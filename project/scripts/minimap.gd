extends Control
const Hex = preload("res://scripts/hex_grid.gd")
const Terrain = preload("res://scripts/expedition_terrain.gd")
const MINT := Color("7bf4d0")
var terrain_mesh: MultiMesh
var terrain_indices: Dictionary = {}
var terrain_colors := {"ground": Color("2d454c"), "cliff": Color("849399"), "raised": Color("58756c"), "ramp": Color("827950")}
var terrain_cached: Dictionary = {}
var game: Node3D
var explored: Dictionary = {}
var cells: Array[Vector2i] = []
var markers: Array[Dictionary] = []
var camera_polygon := PackedVector2Array()
var dragging := false
var elapsed := 0.0
var frame_style: StyleBoxFlat
var survey_revision := -1
var survey_hash := -1
var survey_count := -1
var survey_points: Dictionary = {}
var survey_types: Dictionary = {}

func setup(world: Node3D) -> void:
	game = world; name = "Minimap"
	frame_style = game.style(Color(0.025, 0.05, 0.068, 0.96))
	mouse_filter = Control.MOUSE_FILTER_STOP; clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "North-up / click or drag to pan\nMint: friendly · Amber: minerals · Green: gas · Red: visible enemies"
	visible = game.started and not game.ended
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	for cell in game.navigation.cells: cells.append(cell)
	setup_terrain_mesh()
	fit()
	refresh()

func setup_terrain_mesh() -> void:
	var vertices := PackedVector3Array()
	for i in range(6):
		vertices.append(Vector3.ZERO)
		for edge in [i, i + 1]:
			var angle: float = PI / 6 + edge * TAU / 6
			vertices.append(Vector3(cos(angle), sin(angle), 0) * Terrain.CELL)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mesh = MultiMesh.new(); terrain_mesh.transform_format = MultiMesh.TRANSFORM_2D
	terrain_mesh.use_colors = true; terrain_mesh.mesh = mesh; terrain_mesh.instance_count = cells.size()
	for i in range(cells.size()):
		var point := Hex.to_world(cells[i], Terrain.CELL)
		terrain_indices[cells[i]] = i
		terrain_mesh.set_instance_transform_2d(i, Transform2D(0, Vector2(point.x, point.z)))
		terrain_mesh.set_instance_color(i, Color.TRANSPARENT)

func cache_terrain() -> void:
	# Geometry is shared and uploaded once. Only newly charted or changed cells update.
	if terrain_cached.size() > explored.size():
		for cell in terrain_cached:
			if not explored.has(cell): terrain_mesh.set_instance_color(terrain_indices[cell], Color.TRANSPARENT)
		terrain_cached.clear()
	for cell in explored:
		if terrain_cached.get(cell) == explored[cell]: continue
		terrain_mesh.set_instance_color(terrain_indices[cell], terrain_colors[explored[cell]])
		terrain_cached[cell] = explored[cell]

func map_rect() -> Rect2:
	return Rect2(10, 27, size.x - 20, size.y - 49)

func map_scale() -> float:
	var radius := (Terrain.MAP_RADIUS + 0.5) * Terrain.SPACING
	return minf(map_rect().size.x / (radius * 2), map_rect().size.y / (radius * sqrt(3.0)))

func world_to_map(point: Vector3) -> Vector2:
	return map_rect().get_center() + Vector2(point.x, point.z) * map_scale()

func map_to_world(point: Vector2) -> Vector3:
	var flat := (point - map_rect().get_center()) / map_scale()
	return Vector3(flat.x, 0, flat.y)

func hex_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	var radius := (Terrain.MAP_RADIUS + 0.5) * Terrain.SPACING
	for i in range(6): result.append(world_to_map(Vector3(cos(i * TAU / 6), 0, sin(i * TAU / 6)) * radius))
	return result

func fit() -> void:
	# Stable companion to the command dock, independent of selection or command count.
	var height := minf(250, get_viewport_rect().size.y * 0.34)
	offset_left = -268; offset_right = -18; offset_top = -18 - height; offset_bottom = -18

func _process(dt: float) -> void:
	visible = game.started and not game.ended
	fit()
	elapsed += dt
	if elapsed >= 0.2: elapsed = 0; refresh()
	update_camera_polygon()
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): dragging = false

func refresh() -> void:
	record_exploration()
	cache_terrain()
	markers.clear()
	for resource in game.resource_nodes:
		if resource.discovered and resource.remaining > 0: markers.append({"kind": resource.kind, "point": resource.position, "selected": false})
	for structure in game.structures:
		if structure == game.mission.beacon and not game.mission.beacon_discovered: continue
		if structure.hp > 0: markers.append({"kind": "hq" if structure.kind == "core" else "structure", "point": structure.position, "selected": game.selected.has(structure)})
	for unit in game.units:
		if unit.hp > 0 and unit.aboard == null: markers.append({"kind": "vehicle" if unit.is_vehicle() else "unit", "point": unit.position, "selected": game.selected.has(unit)})
	for creature in game.creatures:
		if creature.hp > 0 and creature.visible and game.light.sample(creature.position) > 0.065: markers.append({"kind": "enemy", "point": creature.position, "selected": false})
	queue_redraw()

func record_exploration() -> void:
	# The HUD and expeditions can ask during the same tick. Survey an unchanged
	# light field only once, and never resample already charted cells.
	var field_hash := hash(game.light.sources)
	if survey_revision == game.navigation.revision and survey_hash == field_hash and survey_count == explored.size(): return
	if survey_revision != game.navigation.revision:
		survey_revision = game.navigation.revision
		for cell in cells:
			var point: Vector3 = game.navigation.friendly_graph.get_point_position(game.navigation.cells[cell])
			survey_points[cell] = point
			survey_types[cell] = "cliff" if game.navigation.solid_cells.has(cell) else "raised" if point.y > 2.9 else "ramp" if point.y > 0.1 else "ground"
			if explored.has(cell): explored[cell] = survey_types[cell]
	var exposure: Dictionary = {}
	for source in game.light.sources:
		var center := Hex.to_axial(source.position, Terrain.CELL)
		var reach := ceili(float(source.radius) / (Terrain.CELL * 1.5)) + 1
		for q in range(-reach, reach + 1):
			for r in range(maxi(-reach, -q - reach), mini(reach, -q + reach) + 1):
				var cell := center + Vector2i(q, r)
				if explored.has(cell) or not survey_points.has(cell): continue
				var strength: float = game.light.source_strength(survey_points[cell], source)
				if strength <= 0: continue
				var total: float = float(exposure.get(cell, 0.0)) + strength
				if total > 0.05: explored[cell] = survey_types[cell]
				else: exposure[cell] = total
	survey_hash = field_hash; survey_count = explored.size()

func scouting_percent() -> float:
	return 100.0 * explored.size() / maxi(1, cells.size())

func update_camera_polygon() -> void:
	var next := PackedVector2Array()
	var view_size: Vector2 = game.get_viewport().get_visible_rect().size
	for corner in [Vector2.ZERO, Vector2(view_size.x, 0), view_size, Vector2(0, view_size.y)]:
		var origin: Vector3 = game.camera.project_ray_origin(corner)
		var direction: Vector3 = game.camera.project_ray_normal(corner)
		if absf(direction.y) < 0.001: return
		next.append(world_to_map(origin + direction * (-origin.y / direction.y)))
	if next != camera_polygon: camera_polygon = next; queue_redraw()

func pan_to(point: Vector2, clamp_edge: bool = false) -> bool:
	if not game.started or game.ended: return false
	var world := map_to_world(point)
	if not Geometry2D.is_point_in_polygon(point, hex_outline()) or not Terrain.contains(world):
		if not clamp_edge: return false
		var low := 0.0; var high := 1.0
		for i in range(18):
			var middle := (low + high) * 0.5
			if Terrain.contains(world * middle): low = middle
			else: high = middle
		world *= low
	game.focus = game.navigation.terrain.surface(world)
	game.update_camera(); update_camera_polygon(); queue_redraw()
	return true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: dragging = pan_to(event.position)
		else: dragging = false
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		pan_to(event.position, true); accept_event()
	elif event is InputEventMouseButton: accept_event()

func _draw() -> void:
	if game == null or size.y < 50: return
	draw_style_box(frame_style, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12, 19), "MINIMAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MINT)
	draw_string(font, Vector2(size.x - 23, 19), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("93aeb8"))

	var outline := hex_outline()
	draw_colored_polygon(outline, Color("080f14"))
	draw_set_transform(map_rect().get_center(), 0, Vector2.ONE * map_scale())
	draw_multimesh(terrain_mesh, null)
	draw_set_transform(Vector2.ZERO)
	var edge := outline.duplicate(); edge.append(edge[0]); draw_polyline(edge, Color("49646d"), 1, true)
	for marker in markers:
		var point := world_to_map(marker.point)
		var kind: String = marker.kind
		var color := Color("ed7c89") if kind == "enemy" else Color("efbd77") if kind == "minerals" else Color("a9c97b") if kind == "gas" else MINT
		var radius := 4.0 if kind in ["hq", "minerals", "gas"] else 3.0 if kind == "vehicle" else 2.0
		if marker.selected: draw_circle(point, radius + 2, Color.WHITE, false, 1, true)
		if kind in ["hq", "structure"]: draw_rect(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2), color)
		else: draw_circle(point, radius, color, true, -1, true)
		if kind == "hq": draw_circle(point, radius + 2, color, false, 1, true)
	for objective in game.mission.map_objectives():
		var point := world_to_map(objective.point)
		draw_circle(point, 4, objective.color, false, 1, true)
		draw_string(font, point + Vector2(5, -3), objective.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, objective.color)
	if camera_polygon.size() == 4:
		for polygon in Geometry2D.intersect_polygons(camera_polygon, outline):
			var line: PackedVector2Array = polygon.duplicate(); line.append(line[0]); draw_polyline(line, Color(0.9, 0.96, 1, 0.8), 1, true)

