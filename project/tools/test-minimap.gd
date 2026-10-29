extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func count_kind(map, kind: String) -> int:
	var count := 0
	for marker in map.markers:
		if marker.kind == kind: count += 1
	return count

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame; await process_frame
	game.set_process(false); game.begin_run()
	var map = game.minimap
	map.refresh()
	check(count_kind(map, "hq") == 1 and count_kind(map, "vehicle") == 1 and count_kind(map, "unit") == 6, "minimap shows headquarters and friendly units")
	check(count_kind(map, "minerals") == 0 and count_kind(map, "gas") == 0, "unscouted resource patches stay off the minimap")
	check(map.explored.size() > 0 and map.explored.size() < map.cells.size() / 4, "terrain begins explored only around friendly illumination")
	game.select_actor(game.core); game.light.add_source(game.DEPOSIT, 8); game.light.add_source(game.GAS_DEPOSIT, 8); game.resource_fields.discover(game); map.refresh()
	check(count_kind(map, "minerals") == 7 and count_kind(map, "gas") == 7, "scouted resource patches appear without revealing farther deposits")
	check(map.terrain_mesh.instance_count == map.cells.size() and map.terrain_mesh.mesh.get_surface_count() == 1, "minimap shares one cached hex mesh for every terrain cell")
	var cached_cell: Vector2i = map.explored.keys()[0]
	check(map.terrain_cached[cached_cell] == map.explored[cached_cell], "revealed terrain uploads its remembered color")
	var unknown_cell: Vector2i
	for cell in map.cells:
		if not map.explored.has(cell): unknown_cell = cell; break
	check(not map.terrain_cached.has(unknown_cell), "unexplored cells stay transparent in the GPU cache")
	var enemy: ExpeditionPredator = game.add_creature(game.HOME + Vector3(3, 0, 0), 77)
	enemy.visible = false; map.refresh()
	check(count_kind(map, "enemy") == 0, "hidden creatures never appear as minimap contacts")
	enemy.visible = true; map.refresh()
	check(count_kind(map, "enemy") == 1, "already visible creatures appear as enemy contacts")
	game.light.sources.clear(); map.refresh()
	check(count_kind(map, "enemy") == 0, "enemy contacts disappear when illumination is lost")
	var explored: int = map.explored.size()
	map.refresh()
	check(map.explored.size() == explored, "previously explored terrain remains on the minimap")
	game.rebuild_light()
	var point := Vector3(-52, 0, 26)
	check(map.map_to_world(map.world_to_map(point)).distance_to(point) < 0.001, "world/minimap coordinates round-trip accurately")
	await process_frame; await process_frame
	var before: Array[Node3D] = game.selected.duplicate()
	var target: Vector2 = map.world_to_map(point)
	var global_target: Vector2 = map.get_global_transform() * target
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = global_target; down.global_position = global_target
	Input.parse_input_event(down)
	await process_frame; await process_frame
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.position = global_target; up.global_position = global_target
	Input.parse_input_event(up)
	await process_frame; await process_frame
	check(game.focus.distance_to(game.navigation.terrain.surface(point)) < 0.01 and game.selected == before and not game.selecting, "actual minimap click pans the camera without selecting or ordering world actors")
	game.select_actor(game.units[1]); game.choose_build("wall")
	var buildings: int = game.structures.size()
	global_target = map.get_global_transform() * map.world_to_map(Vector3(-30, 0, 12))
	down.position = global_target; down.global_position = global_target; Input.parse_input_event(down)
	await process_frame
	var drag_world := Vector3(-35, 0, 32)
	var drag_global: Vector2 = map.get_global_transform() * map.world_to_map(drag_world)
	var motion := InputEventMouseMotion.new(); motion.position = drag_global; motion.global_position = drag_global
	motion.relative = drag_global - global_target; motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame
	up.position = drag_global; up.global_position = drag_global; Input.parse_input_event(up)
	await process_frame
	check(game.focus.distance_to(game.navigation.terrain.surface(drag_world)) < 0.01 and not map.dragging, "real minimap drag pans continuously and releases cleanly")
	check(game.structures.size() == buildings and game.build_kind == "wall", "minimap input does not place a structure or cancel construction targeting")
	game.build_kind = ""
	var yaw: float = game.camera_yaw
	game.orbit_camera(Vector2(120, 10)); map.update_camera_polygon()
	check(map.camera_polygon.size() == 4 and game.camera_yaw != yaw and map.map_to_world(map.world_to_map(point)).distance_to(point) < 0.001, "camera footprint follows orbit while the minimap remains north-up")
	map.pan_to(map.world_to_map(Vector3(200, 0, 200)), true)
	check(game.Terrain.contains(game.focus), "dragging past the map boundary clamps the camera inside the hexagon")
	game.jeep.board(game.units[0]); map.refresh()
	check(count_kind(map, "unit") == 5, "boarded infantry are represented by their vehicle rather than duplicate markers")
	root.size = Vector2i(1100, 720); game.select_actor(game.jeep); game.refresh_ui()
	await process_frame; await process_frame; await process_frame
	check(map.get_global_rect().end.x <= 1100 and map.get_global_rect().end.y <= 720 and not map.get_global_rect().intersects(game.command_panel.get_global_rect()), "minimap fits beside contextual commands at the minimum window size")
	root.size = Vector2i(1600, 1000)
	await process_frame; await process_frame
	check(absf(map.get_global_rect().end.x - 1582) < 1 and absf(map.get_global_rect().end.y - 982) < 1, "minimap stays anchored to the bottom-right when the window grows")
	# Compare the localized visibility recorder with the original whole-map query.
	game.rebuild_light()
	var history: Dictionary = map.explored.duplicate()
	map.explored.clear(); map.record_exploration()
	var expected: Dictionary = {}
	for cell in map.cells:
		var sample: Vector3 = game.navigation.terrain.surface(game.Hex.to_world(cell, game.Terrain.CELL))
		if game.light.sample(sample) > 0.05: expected[cell] = true
	check(map.explored.size() == expected.size() and expected.keys().all(func(cell): return map.explored.has(cell)), "localized scouting records exactly the cells revealed by authoritative lighting, including headlights")
	map.explored.merge(history)
	print("MINIMAP_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
