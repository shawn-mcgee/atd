extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps = 120
	var loader = load("res://scenes/loading.tscn").instantiate(); loader.initial_seed = 42
	root.add_child(loader); current_scene = loader
	check(loader.status != null and current_scene == loader, "loading console exists before mission initialization")
	var frames := 0; var world_frames := 0
	var started := Time.get_ticks_msec()
	while is_instance_valid(loader) and Time.get_ticks_msec() - started < 60000:
		if loader.stage == "world": world_frames += 1
		if loader.stage == "failed": break
		frames += 1; await process_frame
	check(not is_instance_valid(loader), "loading hands off and removes its overlay")
	if is_instance_valid(loader):
		push_error(loader.status.text); loader.queue_free(); await process_frame; quit(1); return
	var game = current_scene
	game.set_process(false)
	check(game.scene_file_path == "res://scenes/top_down.tscn" and game.overlay.visible and not game.started, "prepared mission opens at its briefing, without running simulation ticks")
	check(frames > 2 and world_frames > 0, "frames continue while the worker generates the world")
	check(game.simulation.scenario_seed == 42 and game.simulation.tick_number == 0, "loading preserves the chosen seed and initial tick")
	var reference = load("res://engine/simulation.gd").new(); reference.initialize(42)
	check(game.simulation.state_hash() == reference.state_hash(), "worker generation matches synchronous deterministic initialization")
	reference.dispose(); game.queue_free(); await process_frame
	print("LOADING_TEST_RESULT: ", failures, " failures"); quit(1 if failures else 0)
