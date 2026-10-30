extends RefCounted
## Atlas mapping, orientation, hit masks and effects belong exclusively to the view.
const PATH := "res://assets/sprites/"
const FLAT_TOP := [ "turret_base", "laser_turret_base", "flame_turret_base"]
var manifest: Dictionary
var textures: Dictionary = {}
var regions: Dictionary = {}
var images: Dictionary = {}
var headings: Dictionary = {}
var aim_until: Dictionary = {}
var clock := 0.0
var gates: Dictionary = {}
var effects: Array[Dictionary] = []
var initial_resources: Dictionary = {}
var last_event := 0

func _init() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(PATH + "atlas.json"))
	for key in manifest.sheets:
		textures[key] = load(PATH + manifest.sheets[key].file)
	for key in manifest.sprites:
		var entry: Dictionary = manifest.sprites[key]
		var values: Array = entry.region
		var texture := AtlasTexture.new()
		texture.atlas = textures[entry.sheet]
		texture.region = Rect2(values[0], values[1], values[2], values[3])
		texture.filter_clip = true
		regions[key] = texture

func texture(key: String) -> Texture2D:
	if key == "gate": return regions.wall
	if key in ["turret", "laser_turret", "flame_turret"]: key += "_base"
	return regions.get(key)

func rotation(key: String) -> float:
	return deg_to_rad(float(manifest.sprites[key].rotation_degrees)) + (PI / 6 if key in FLAT_TOP else 0.0)

func sprite_rect(key: String, pixels_per_unit: float, size_override: Vector2 = Vector2.ZERO) -> Rect2:
	var entry: Dictionary = manifest.sprites[key]
	var size := Vector2(entry.world_size[0], entry.world_size[1]) if size_override == Vector2.ZERO else size_override
	size *= pixels_per_unit
	return Rect2(-Vector2(entry.pivot[0], entry.pivot[1]) * size, size)

func draw(game, key: String, point: Vector3, angle: float = 0, tint: Color = Color.WHITE, size_override: Vector2 = Vector2.ZERO) -> void:
	if not regions.has(key): return
	game.draw_set_transform(game.world_to_screen(point), angle + game.camera_angle + rotation(key))
	game.draw_texture_rect(regions[key], sprite_rect(key, game.zoom, size_override), false, tint)
	game.draw_set_transform(Vector2.ZERO)

func hit(game, key: String, point: Vector3, angle: float, screen: Vector2) -> bool:
	if not regions.has(key): return false
	var local: Vector2 = (screen - game.world_to_screen(point)).rotated(-angle - game.camera_angle - rotation(key))
	var rect := sprite_rect(key, game.zoom)
	if not rect.has_point(local): return false
	var entry: Dictionary = manifest.sprites[key]
	if not images.has(entry.sheet): images[entry.sheet] = textures[entry.sheet].get_image()
	var uv := (local - rect.position) / rect.size
	var source: Rect2 = regions[key].region
	var pixel := Vector2i(source.position + uv * source.size)
	return images[entry.sheet].get_pixelv(pixel).a > 0.2

func actor_angle(actor: SimEntity) -> float:
	if actor is SimUnit:
		if float(aim_until.get(actor.simulation_id, -1.0)) >= clock: return float(headings[actor.simulation_id])
		return -actor.yaw
	var offset: Vector3 = actor.path[actor.path_index] - actor.position if actor.path_index < actor.path.size() else Vector3.ZERO
	if offset.length_squared() > 0.01: headings[actor.simulation_id] = atan2(offset.x, -offset.z)
	return float(headings.get(actor.simulation_id, 0.0))

func muzzle_point(game, actor: SimEntity, angle: float) -> Vector3:
	var key := actor.kind + "_head" if actor is SimStructure else actor.kind
	var origin: Vector3 = actor.position if actor is SimStructure else game.actor_position(actor)
	if not manifest.sprites.has(key): return origin
	var entry: Dictionary = manifest.sprites[key]
	if not entry.has("muzzle_uv"): return origin
	var offset := (Vector2(entry.muzzle_uv[0], entry.muzzle_uv[1]) - Vector2(entry.pivot[0], entry.pivot[1])) * Vector2(entry.world_size[0], entry.world_size[1])
	offset = offset.rotated(angle + rotation(key))
	return origin + Vector3(offset.x, 0, offset.y)

func polygon(game, key: String, vertices: PackedVector2Array, anchor: Vector3, angle: float = 0, tint: Color = Color.WHITE) -> void:
	if not regions.has(key) or vertices.size() < 3: return
	var local := PackedVector2Array()
	var origin: Vector2 = game.world_to_screen(anchor)
	for point in vertices: local.append((point - origin).rotated(-game.camera_angle - angle) / game.zoom)
	var bounds := Rect2(local[0], Vector2.ZERO)
	for point in local: bounds = bounds.expand(point)
	var entry: Dictionary = manifest.sprites[key]
	var source: Rect2 = regions[key].region
	var atlas_size: Vector2 = textures[entry.sheet].get_size()
	var uvs := PackedVector2Array()
	for point in local:
		var uv := (point - bounds.position) / bounds.size
		if key in FLAT_TOP:
			# Rotate flat-top art, not the pointy-top grid or its gameplay footprint.
			var radius := bounds.size.y / 2
			uv = (point - bounds.get_center()).rotated(-PI / 6) / Vector2(radius * 2, radius * sqrt(3)) + Vector2.ONE * 0.5
		if key.begins_with("ground_"):
			# Use the continuous interior instead of repeating rocky island borders.
			uv = (uv - Vector2.ONE * 0.5) * 0.55 + Vector2.ONE * 0.5
		uvs.append((source.position + uv * source.size) / atlas_size)
	game.draw_polygon(vertices, PackedColorArray([tint]), uvs, textures[entry.sheet])

func building_key(building: SimStructure, stolen: bool = false) -> String:
	if building.kind == "beacon" and not building.complete: return "beacon_ruined"
	if building.kind == "hive" and (stolen or building.hp < 400): return "hive_breached"
	return building.kind + "_base" if building.kind in ["turret", "laser_turret", "flame_turret"] else building.kind

func building_layout(game, building: SimStructure, vertices: PackedVector2Array) -> Dictionary:
	var angle := building.build_direction * PI / 3
	if building.kind == "platform":
		var data: Dictionary = manifest.sprites.platform
		return {"point": building.position, "angle": angle, "size": Vector2(data.world_size[0], data.world_size[1])}
	var origin: Vector2 = game.world_to_screen(building.position)
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for point in vertices: bounds = bounds.expand((point - origin).rotated(-game.camera_angle - angle) / game.zoom)
	var center := bounds.get_center().rotated(angle)
	return {"point": building.position + Vector3(center.x, 0, center.y), "angle": angle, "size": bounds.size}

func draw_building(game, building: SimStructure, vertices: PackedVector2Array, tint: Color) -> void:
	var layout := building_layout(game, building, vertices)
	var key := building_key(building, game.mission.stolen)
	var size: Vector2 = layout.size
	if key in FLAT_TOP:
		# Flat-top source rectangle rotates into the pointy-top footprint bounds.
		size = Vector2(size.y, size.x)
	draw(game, key, layout.point, layout.angle, tint, size)

func hit_building(game, building: SimStructure, vertices: PackedVector2Array, screen: Vector2) -> bool:
	var key := building_key(building, game.mission.stolen)
	if not regions.has(key): return false
	var layout := building_layout(game, building, vertices)
	var size: Vector2 = layout.size
	if key in FLAT_TOP: size = Vector2(size.y, size.x)
	var rect := sprite_rect(key, game.zoom, size)
	var local: Vector2 = (screen - game.world_to_screen(layout.point)).rotated(-game.camera_angle - layout.angle - rotation(key))
	if not rect.has_point(local): return false
	var entry: Dictionary = manifest.sprites[key]
	if not images.has(entry.sheet): images[entry.sheet] = textures[entry.sheet].get_image()
	var region: Rect2 = regions[key].region
	var pixel := Vector2i(region.position + (local - rect.position) / rect.size * region.size)
	return images[entry.sheet].get_pixelv(pixel).a > 0.2

func tick(game, dt: float) -> void:
	clock += dt
	for event in game.simulation.events:
		if event.serial <= last_event: continue
		last_event = int(event.serial)
		if event.type != "shot": continue
		var effect: Dictionary = event.duplicate(); effect.age = 0.0
		effects.append(effect)
		var shooter: SimEntity = game.simulation.entities.get(int(event.get("shooter", 0)))
		if SimEntity.valid(shooter):
			var offset: Vector3 = event.b - event.a
			headings[shooter.simulation_id] = atan2(offset.x, -offset.z)
			aim_until[shooter.simulation_id] = clock + (1.0 if shooter.kind == "flamer" else 0.8)
	for effect in effects: effect.age += dt
	effects = effects.filter(func(effect): return effect.age < 0.32)
	for building in game.structures:
		if building.kind == "gate":
			var value: float = gates.get(building.simulation_id, 1.0 if building.gate_open else 0.0)
			gates[building.simulation_id] = move_toward(value, 1.0 if building.gate_open else 0.0, dt * 5)

func draw_effects(game) -> void:
	for effect in effects:
		var age: float = effect.age
		var alpha := 1.0 - age / 0.32
		var source: Vector3 = effect.a
		var shooter: SimEntity = game.simulation.entities.get(int(effect.get("shooter", 0)))
		if SimEntity.valid(shooter): source = muzzle_point(game, shooter, float(headings.get(shooter.simulation_id, 0.0)))
		var offset: Vector3 = effect.b - source
		var angle := atan2(offset.z, offset.x)
		var color: Color = effect.color
		if effect.get("weapon", "") in ["runner", "stalker", "brute"]:
			draw(game, "alien_hit_00", effect.b, 0, Color(1, 1, 1, alpha), Vector2.ONE * 0.5)
			continue
		if color.r > color.g * 1.7 and color.b < 0.4:
			var frame := mini(2, int(age * 12))
			draw(game, "flame_0%d" % frame, source, angle, Color(1, 1, 1, alpha), Vector2(minf(4, offset.length()), 1.2))
		else:
			var laser := color.b > 0.65 and color.r > 0.6
			if age < 0.12: game.draw_line(game.world_to_screen(source), game.world_to_screen(effect.b), Color(color, alpha), 1.5, true)
			draw(game, "impact_laser" if laser else "impact_kinetic", effect.b, 0, Color(1, 1, 1, alpha), Vector2.ONE * (0.4 + age))
			if not laser and age < 0.12: draw(game, "muzzle_00", source, angle, Color(1, 1, 1, alpha), Vector2(0.65, 0.4))

func draw_gate(game, building: SimStructure) -> void:
	# Two posts and sliding leaves; no generated gate pixels are used.
	var angle: float = building.build_direction * PI / 3 + game.camera_angle
	var opening: float = gates.get(building.simulation_id, 1.0 if building.gate_open else 0.0)
	game.draw_set_transform(game.world_to_screen(building.position), angle, Vector2.ONE * game.zoom)
	for side in [-1, 1]:
		game.draw_rect(Rect2(Vector2(-0.28, side * 0.69 - 0.14), Vector2(0.56, 0.28)), Color("a1aaa9"))
		game.draw_rect(Rect2(Vector2(-0.20, side * 0.69 - 0.07), Vector2(0.4, 0.14)), Color("384954"))
		var length := 0.62 * (1.0 - opening)
		var top := 0.06 if side == 1 else -0.06 - length
		if length > 0.01:
			game.draw_rect(Rect2(-0.12, top, 0.24, length), Color("667984"))
			game.draw_line(Vector2(0, top), Vector2(0, top + length), Color("d1a65c"), 0.055)
		var status := Color("d9826a") if building.gate_locked else Color("70c8bd") if building.powered else Color("d5a45c")
		game.draw_circle(Vector2(0, side * 0.69), 0.055, status)
	game.draw_set_transform(Vector2.ZERO)

