extends Control
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
var game: Node2D
var scale_factor := 1.0
var redraw_clock := 0.0
var survey_key: Array = []
var survey_texture: ImageTexture

func setup(world: Node2D) -> void:
	game = world; mouse_filter = Control.MOUSE_FILTER_STOP; clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT); fit()
	tooltip_text = "Click or drag to pan / surveyed terrain and visible contacts"

func fit() -> void:
	offset_left = -240; offset_right = -8; offset_top = -240; offset_bottom = -8
	scale_factor = minf((232.0 - 16) / (2 * Terrain.MAP_RADIUS * sqrt(3.0)), (232.0 - 44) / (3 * Terrain.MAP_RADIUS)) * 0.96

func map_area() -> Rect2:
	return Rect2(Vector2(8, 26), size - Vector2(16, 44))

func project(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) * scale_factor + map_area().get_center()

func _process(dt: float) -> void:
	redraw_clock += dt
	if redraw_clock >= 0.1:
		redraw_clock = 0.0
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if map_area().has_point(event.position):
			game.focus = (event.position - map_area().get_center()) / scale_factor; accept_event()

func _draw() -> void:
	if game == null: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("1c2527")); draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color("626b65"), false, 2)
	draw_line(Vector2(2, 2), Vector2(size.x - 2, 2), Color("7b8276"))
	draw_rect(map_area(), Color("090f11"))
	draw_circle(Vector2(12, 14), 2, Color("79aa8c"))
	draw_string(ThemeDB.fallback_font, Vector2(20, 18), "TACTICAL / NADIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("d5ad68"))
	draw_string(ThemeDB.fallback_font, Vector2(10, size.y - 5), "LOCAL SECTOR / LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("92998c"))
	for fraction in [0.25, 0.5, 0.75]:
		var area := map_area()
		draw_line(area.position + Vector2(area.size.x * fraction, 0), area.position + Vector2(area.size.x * fraction, area.size.y), Color(0.3, 0.4, 0.3, 0.12))
		draw_line(area.position + Vector2(0, area.size.y * fraction), area.position + Vector2(area.size.x, area.size.y * fraction), Color(0.3, 0.4, 0.3, 0.12))
	var key := [game.simulation.explored.size(), game.simulation.navigation.revision, size]
	if key != survey_key:
		survey_key = key
		var image := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
		for cell in game.simulation.explored:
			var pixel := Vector2i(project(Hex.to_world(cell, Terrain.CELL)))
			var color := Color("62747e") if game.simulation.explored[cell] == "cliff" else Color("334e56")
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var at := pixel + Vector2i(dx, dy)
					if at.x >= 0 and at.y >= 0 and at.x < image.get_width() and at.y < image.get_height(): image.set_pixelv(at, color)
		survey_texture = ImageTexture.create_from_image(image)
	if survey_texture != null: draw_texture(survey_texture, Vector2.ZERO)
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
