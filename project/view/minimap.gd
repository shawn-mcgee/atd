extends Control
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
var game: Node2D
var scale_factor := 1.24

func setup(world: Node2D) -> void:
	game = world; mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT); fit()
	tooltip_text = "Click or drag to pan / surveyed terrain and visible contacts"

func fit() -> void:
	offset_left = -268; offset_right = -18; offset_top = -268; offset_bottom = -18

func project(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) * scale_factor + size * 0.5

func _process(_dt: float) -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		game.focus = (event.position - size * 0.5) / scale_factor; accept_event()

func _draw() -> void:
	if game == null: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("0a131e")); draw_rect(Rect2(Vector2.ZERO, size), Color("3a5965"), false)
	for cell in game.simulation.explored:
		var point := Hex.to_world(cell, Terrain.CELL)
		var color := Color("62747e") if game.simulation.explored[cell] == "cliff" else Color("334e56")
		draw_circle(project(point), 1.1, color)
	for patch in game.resource_nodes:
		if patch.discovered and patch.remaining > 0: draw_circle(project(patch.position), 2, Color("79e1c7") if patch.kind == "minerals" else Color("b9cb75"))
	for building in game.structures:
		if building.visible: draw_circle(project(building.position), 2.5, Color("9cb9d4"))
	for actor in game.units:
		if actor.aboard == null: draw_circle(project(actor.position), 2, Color("c6e8ec"))
	for enemy in game.creatures:
		if enemy.visible: draw_circle(project(enemy.position), 2, Color("ec7187"))
	for blip in game.sensor_blips: draw_circle(project(blip.position), 2.5, Color("eec17f"), false)
	if game.mission.beacon_discovered: draw_circle(project(game.mission.beacon.position), 3, Color("ebcf8c"))
	if game.mission.hive_discovered: draw_circle(project(game.mission.hive.position), 3, Color("dc6f8f"))
	var corners := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(game.get_viewport_rect().size.x, 0), game.get_viewport_rect().size, Vector2(0, game.get_viewport_rect().size.y)]: corners.append(project(game.ground_point(corner)))
	corners.append(corners[0]); draw_polyline(corners, Color("9fcec9"), 1, true)
