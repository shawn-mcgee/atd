extends SceneTree
var failures := 0
const Hex = preload("res://scripts/hex_grid.gd")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func mouse(button: MouseButton, pressed: bool, point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button; event.pressed = pressed; event.position = point
	return event

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var directions_ok := true
	for direction in Hex.NEIGHBORS:
		var endpoint := Hex.to_world(direction * 8, preload("res://scripts/expedition_terrain.gd").CELL)
		var line := Hex.line(Vector3.ZERO, endpoint, preload("res://scripts/expedition_terrain.gd").CELL)
		directions_ok = directions_ok and line.size() == 9 and line[0] == Vector3.ZERO and line[-1] == endpoint
		for i in range(1, line.size()):
			directions_ok = directions_ok and is_equal_approx(line[i].distance_to(line[i - 1]), preload("res://scripts/expedition_terrain.gd").SPACING)
	check(directions_ok, "wall lines include both endpoints and every neighboring cell in all six directions")
	var oblique := Hex.line(Vector3.ZERO, Hex.to_world(Vector2i(7, -3), preload("res://scripts/expedition_terrain.gd").CELL), preload("res://scripts/expedition_terrain.gd").CELL)
	var reversed := Hex.line(oblique[-1], oblique[0], preload("res://scripts/expedition_terrain.gd").CELL); reversed.reverse()
	check(oblique == reversed and oblique.size() == 8, "oblique lines are contiguous and independent of drag direction")
	check(Hex.line(Vector3.ZERO, Vector3.ZERO, preload("res://scripts/expedition_terrain.gd").CELL).size() == 1, "a stationary click produces one unique cell")
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run(); game.audio_enabled = false
	# Remove the rendered occluders too: this fixture is an empty building field.
	for rock in game.rocks:
		if not rock.has("node"): continue
		game.picker.remove_owner(rock.node); game.occluded_units.remove_occluder(rock.node); rock.node.queue_free()
	game.rocks.clear(); game.rebuild_navigation()
	game.light.sources.clear(); game.light.add_source(Vector3.ZERO, 150)
	var worker: ExpeditionUnit = game.units[0]; game.select_actor(worker)
	# Find a flat, empty line away from the base and visible terrain cliffs.
	var points: Array[Vector3] = []
	for r in range(-15, 15):
		for q in range(-15, 10):
			var candidate := Hex.line(Hex.to_world(Vector2i(q, r), preload("res://scripts/expedition_terrain.gd").CELL), Hex.to_world(Vector2i(q + 5, r), preload("res://scripts/expedition_terrain.gd").CELL), preload("res://scripts/expedition_terrain.gd").CELL)
			if candidate.all(func(p): return game.valid_site("wall", p) and p.length() > 20 and game.navigation.terrain.height(p) == 0):
				points = candidate; break
		if not points.is_empty(): break
	check(points.size() == 6, "test has a clear six-cell construction line")
	if points.is_empty(): quit(1); return
	worker.position = points[0] + Vector3(0, 0, 3)
	game.focus = points[2]; game.camera_zoom = 36; game.update_camera()
	await physics_frame
	var start: Vector2 = game.camera.unproject_position(points[0])
	var endpoint: Vector2 = game.camera.unproject_position(points[-1])
	var bank: int = game.economy.minerals
	var before: int = game.structures.size()
	game.choose_build("wall")
	game._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true, start))
	game.wall_placement.update_preview(game, points[-1]); game.update_power_placement()
	check(game.wall_placement.active and not game.selecting and game.structures.size() == before and game.economy.minerals == bank, "pressing and dragging walls previews without spending, placing, or selecting")
	check(game.wall_placement.count == 6 and game.wall_placement.markers.size() == 6 and game.power_preview_label.text.begins_with("6 walls / 60 materials"), "preview displays every cell and the total affordable cost")
	game._input(mouse(MOUSE_BUTTON_LEFT, false, endpoint))
	check(not game.wall_placement.active and game.build_kind.is_empty() and game.structures.size() == before + 6 and game.economy.minerals == bank - 60, "releasing a world drag commits the complete line and charges each segment once")
	var sites: Array = game.structures.slice(before)
	check(sites.all(func(site): return site.kind == "wall" and site.funded and not site.complete) and worker.target == sites[0], "drag creates funded blueprints and assigns the first segment to the engineer")
	check(sites[0].connections.size() == 1 and sites[2].connections.size() == 2, "new wall segments connect to their hex neighbors")
	for i in range(900):
		game.advance_movement(0.1); game.process_order(worker, 0.1)
		if i % 100 == 0: await process_frame
		if sites.all(func(site): return site.complete): break
	check(sites.all(func(site): return site.complete), "engineer completes the dragged wall line through existing maintenance chaining")
	game.light.sources.clear(); game.light.add_source(Vector3.ZERO, 150)
	bank = game.economy.minerals
	check(game.order_wall_line(points[0], points[-1]) == 0 and game.economy.minerals == bank, "dragging over existing walls never duplicates or charges them")
	var extension := points[-1] + (points[1] - points[0]) * 3
	game.economy.minerals = 25; game.choose_build("wall")
	game.wall_placement.begin(endpoint, points[-1]); game.wall_placement.update_preview(game, extension)
	check(game.wall_placement.count == 2 and game.wall_placement.buildable == [false, true, true, false], "preview skips occupied starts and marks the unaffordable end of a line")
	var planned: int = game.wall_placement.count
	game.wall_placement.cancel()
	check(game.order_wall_line(points[-1], extension) == planned and game.economy.minerals == 5, "commit matches the affordable preview and cannot overspend")
	before = game.structures.size(); bank = game.economy.minerals
	game.build_kind = ""; game.choose_build("wall")
	game._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true, start))
	game._input(mouse(MOUSE_BUTTON_RIGHT, true, endpoint))
	game._input(mouse(MOUSE_BUTTON_LEFT, false, endpoint))
	check(not game.wall_placement.active and game.build_kind.is_empty() and game.structures.size() == before and game.economy.minerals == bank, "right-click cancels the drag and subsequent release places nothing")
	game.choose_build("wall"); game.wall_placement.begin(start, points[0])
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	game._unhandled_input(escape)
	check(not game.wall_placement.active and game.structures.size() == before, "Escape immediately discards the preview")
	game.select_actor(worker); game.choose_build("wall"); game.wall_placement.begin(start, points[0])
	game.select_actor(game.jeep)
	check(not game.wall_placement.active and game.build_kind.is_empty(), "changing selection cancels pending wall placement")
	game.select_actor(worker); game.choose_build("wall"); game.wall_placement.begin(start, points[0])
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.wall_placement.active, "losing application focus discards the drag")
	game.economy.minerals = 100
	game.wall_placement.begin(start, points[0])
	var motion := InputEventMouseMotion.new(); motion.position = Vector2(50, 50)
	root.push_input(motion, true)
	await process_frame
	check(root.gui_get_hovered_control() != null, "HUD release test targets an actual blocking control")
	game._input(mouse(MOUSE_BUTTON_LEFT, false, motion.position))
	check(not game.wall_placement.active and game.structures.size() == before and game.economy.minerals == 100, "releasing over the HUD discards the line without spending")
	motion = InputEventMouseMotion.new(); motion.position = Vector2(700, 400)
	root.push_input(motion, true)
	game.wall_placement.begin(start, points[0])
	game._input(mouse(MOUSE_BUTTON_LEFT, false, Vector2(-100000, -100000)))
	check(not game.wall_placement.active and game.structures.size() == before, "releasing outside the map discards the line")
	# Single clicks retain the actor picker and normal one-wall placement behavior.
	var single := extension + (points[1] - points[0])
	game.focus = single; game.update_camera()
	await physics_frame
	var screen: Vector2 = game.camera.unproject_position(single)
	game._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true, screen))
	game._input(mouse(MOUSE_BUTTON_LEFT, false, screen))
	await process_frame
	check(game.structures.size() == before + 1 and game.economy.minerals == 90 and game.build_kind.is_empty(), "a click without dragging still places exactly one wall")
	game.choose_build("wall")
	screen = game.camera.unproject_position(game.structures[-1].position + Vector3.UP * 0.4)
	game._unhandled_input(mouse(MOUSE_BUTTON_LEFT, true, screen))
	game._input(mouse(MOUSE_BUTTON_LEFT, false, screen))
	await process_frame
	check(game.selected == [game.structures[-1]] and game.structures.size() == before + 1, "clicking an existing wall still selects it instead of creating a duplicate")
	game.select_actor(worker)
	game.economy.minerals = 100; game.light.sources.clear()
	check(game.order_wall_line(extension, extension + (points[1] - points[0]) * 2) == 0 and game.economy.minerals == 100, "unlit terrain cannot be funded through wall dragging")
	print("WALL_PLACEMENT_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
