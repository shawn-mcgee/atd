extends Control
## Screen-space bars follow visible geometry and never participate in world picking.
const Rules = preload("res://scripts/expedition_rules.gd")
var game: Node3D
var health_entries: Array[Dictionary] = []
var battery_entries: Array[Dictionary] = []
var bounds_cache: Dictionary = {}

func setup(world: Node3D) -> void:
	game = world; mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_dt: float) -> void:
	refresh()

func bounds(actor: Node3D) -> AABB:
	var key := hash([actor.get_instance_id(), actor.progress if actor is ExpeditionStructure else snappedf(actor.visual.rotation.y, 0.15), actor.complete if actor is ExpeditionStructure else true])
	var id := actor.get_instance_id()
	if bounds_cache.has(id) and bounds_cache[id].key == key: return bounds_cache[id].box
	var box := AABB(); var have := false
	var pending: Array[Node] = [actor]
	var inverse := actor.global_transform.affine_inverse()
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D or node.mesh == null or node.mesh is ImmediateMesh: continue
		var local: AABB = inverse * node.global_transform * node.get_aabb()
		box = box.merge(local) if have else local; have = true
	if not have: box = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	bounds_cache[id] = {"key": key, "box": box}
	return box

func screen_box(actor: Node3D) -> Rect2:
	var box := bounds(actor)
	var result := Rect2(); var first := true
	for i in range(8):
		var point: Vector3 = actor.global_transform * box.get_endpoint(i)
		var projected: Vector2 = game.camera.unproject_position(point)
		if first: result = Rect2(projected, Vector2.ZERO); first = false
		else: result = result.expand(projected)
	return result

func refresh() -> void:
	health_entries.clear(); battery_entries.clear()
	if game == null or not game.started or game.ended: queue_redraw(); return
	var actors: Array = game.units + game.structures + game.creatures
	if is_instance_valid(game.mission.hive): actors.append(game.mission.hive)
	var live: Dictionary = {}
	for actor in actors:
		if not is_instance_valid(actor) or actor.hp <= 0 or not actor.is_visible_in_tree() or game.camera.is_position_behind(actor.global_position): continue
		live[actor.get_instance_id()] = true
		if actor is ExpeditionUnit and actor.aboard != null: continue
		if actor is ExpeditionPredator and game.light.sample(actor.position) < 0.065: continue
		var maximum: float = actor.max_hp if actor is ExpeditionPredator else Rules.UNITS[actor.kind].hp if actor is ExpeditionUnit else Rules.STRUCTURES[actor.kind].hp
		var vehicle: bool = actor is ExpeditionUnit and actor.is_vehicle()
		if actor.hp >= maximum and not vehicle: continue
		var rect := screen_box(actor)
		if not get_viewport_rect().grow(50).intersects(rect): continue
		var width := 54.0 if vehicle or actor is ExpeditionStructure else 36.0
		if actor.hp < maximum:
			health_entries.append({"actor": actor, "rect": Rect2(Vector2(rect.get_center().x - width / 2, rect.position.y - 10), Vector2(width, 5)), "value": clampf(actor.hp / maximum, 0, 1), "enemy": actor is ExpeditionPredator or actor == game.mission.hive})
		if vehicle:
			battery_entries.append({"actor": actor, "rect": Rect2(Vector2(rect.get_center().x - 26, rect.end.y + 5), Vector2(52, 4)), "value": clampf(actor.battery / 100, 0, 1), "charging": actor.charging})
	for id in bounds_cache.keys():
		if not live.has(id): bounds_cache.erase(id)
	queue_redraw()

func bar(rect: Rect2, value: float, color: Color) -> void:
	draw_rect(rect.grow(2), Color(0.015, 0.025, 0.035, 0.9))
	draw_rect(rect, Color("26353e"))
	if value > 0: draw_rect(Rect2(rect.position, Vector2(rect.size.x * value, rect.size.y)), color)

func _draw() -> void:
	for entry in health_entries: bar(entry.rect, entry.value, Color("ee8693") if entry.enemy else Color("7bf4d0") if entry.value > 0.3 else Color("efbd77"))
	for entry in battery_entries: bar(entry.rect, entry.value, Color("8cc7ff") if entry.charging else Color("7bf4d0") if entry.value > 0.5 else Color("efbd77") if entry.value > 0.2 else Color("ee8693"))
