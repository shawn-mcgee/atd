extends SceneTree
const Primitives = preload("res://view/primitives.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error("FAIL: " + text)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/top_down.tscn").instantiate()
	game.initial_seed = 42
	root.add_child(game); current_scene = game
	game.set_process(false)
	await process_frame
	game.begin_run()
	var engine = game.simulation
	var untouched: String = engine.state_hash()
	game.selected.assign([engine.units[0]]); game.refresh_ui(); game.choose_build("generator")
	check(game.hud.build_tab.visible and game.build_kind == "generator", "engineer selection exposes contextual construction")
	game.camera_angle = 0.7; game.focus = Vector2(4, -7)
	var point := Vector3(-3, 0, -5)
	check(game.ground_point(game.world_to_screen(point)).distance_to(point) < 0.00001, "terrain picking inverts rotated camera projection")
	game.focus = Vector2.ZERO; game.camera_angle = 0
	check(game.pick(game.world_to_screen(engine.units[0].position)) == engine.units[0], "unit circles are picked directly")
	var jeep: SimUnit = engine.add_unit("jeep", Vector3(9, 0, -3))
	check(game.pick(game.world_to_screen(jeep.position)) == jeep, "vehicle selection covers its entire circle")
	check(game.pick(game.world_to_screen(engine.core.position)) == engine.core, "structure polygons participate in picking")
	check(game.pick(game.world_to_screen(Vector3(70, 0, 60))) == null, "empty geometry falls through to terrain")
	var polygon := Primitives.structure_polygon(game, engine.core)
	check(polygon.size() == 6, "HQ hull uses the six outer occupied tile centers")
	var generator: SimStructure = engine.add_structure("generator", Vector3(-8, 0, 0))
	check(Primitives.structure_polygon(game, generator).size() == 3, "generator footprint draws a triangle")
	var depot: SimStructure = engine.add_structure("depot", Vector3(-12, 0, 0))
	var small := Primitives.structure_polygon(game, depot)
	check(small.size() == 6 and absf(small[0].distance_to(game.world_to_screen(depot.position)) / game.zoom - 0.8) < 0.00001, "one-cell structures use an 80 percent hexagon")
	untouched = engine.state_hash()
	await process_frame; await process_frame
	check(engine.state_hash() == untouched, "drawing and HUD refresh do not change authoritative state")
	game.selected.assign([engine.units[1]]); game.refresh_ui()
	check(not game.hud.build_tab.visible and game.build_kind == "", "non-engineer selection hides construction and cancels placement")
	var hotkey := InputEventKey.new(); hotkey.keycode = KEY_Q; hotkey.pressed = true
	game._unhandled_input(hotkey)
	check(game.tactical_mode == "attack_move", "Q arms attack-move")
	game.tactical_mode = ""; hotkey.keycode = KEY_A; game._unhandled_input(hotkey)
	check(game.tactical_mode == "", "A remains available for WASD panning")
	game.selected.assign([engine.core]); game.train_unit("engineer")
	check(engine.core.queue.is_empty(), "HUD production submits a command without mutating gameplay")
	engine.step(); check(engine.core.queue == ["engineer"], "production command executes on the next fixed tick")
	var before_scale: float = game.world_to_screen(Vector3.RIGHT).distance_to(game.world_to_screen(Vector3.ZERO))
	root.size = Vector2i(1600, 1000); await process_frame
	check(is_equal_approx(before_scale, game.world_to_screen(Vector3.RIGHT).distance_to(game.world_to_screen(Vector3.ZERO))), "resizing reveals more terrain at the same world scale")
	game.queue_free(); await process_frame
	# Different render schedules run the same tick-stamped commands.
	var hashes: Array[String] = []
	for fps in [30, 60, 144]:
		var view = load("res://scenes/top_down.tscn").instantiate(); view.initial_seed = 819
		root.add_child(view); view.set_process(false); view.begin_run()
		view.simulation.enqueue({"kind": "context", "actors": [view.simulation.units[0].simulation_id], "point": Vector3(-8, 0, -6)})
		for i in range(fps * 3): view._process(1.0 / fps)
		check(view.simulation.tick_number == 30, "%d FPS advances exactly 30 ticks in three seconds" % fps)
		hashes.append(view.simulation.state_hash()); view.queue_free(); await process_frame
	check(hashes[0] == hashes[1] and hashes[1] == hashes[2], "simulation outcome is independent of render frame rate")
	print("TOP_DOWN_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
