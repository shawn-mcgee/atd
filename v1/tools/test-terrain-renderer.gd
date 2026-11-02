extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/top_down.tscn").instantiate(); game.initial_seed = 42
	root.add_child(game); game.set_process(false); game.begin_run()
	var renderer = game.terrain_renderer
	var original: String = game.simulation.state_hash()
	renderer.sync()
	var total := 0
	for batch in renderer.batches.values(): total += batch.multimesh.instance_count
	check(total == game.simulation.explored.size(), "each explored cell has exactly one terrain instance")
	check(renderer.coverage_batches.size() == renderer.batches.size(), "fog coverage reuses every terrain batch")
	for key in renderer.batches:
		check(renderer.coverage_batches[key].multimesh == renderer.batches[key].multimesh, "coverage shares retained geometry for " + key)
	var uploads: int = renderer.upload_revision
	game.focus = Vector2(9, -6); game.zoom = 90; game.camera_angle = 1.2
	renderer.sync()
	var point := Vector3(4, 0, -8)
	check((renderer.transform * Vector2(point.x, point.z)).is_equal_approx(game.world_to_screen(point)), "retained terrain follows camera transform")
	check(renderer.upload_revision == uploads, "camera changes reuse GPU terrain buffers")
	game.simulation.light.add_source(Vector3(9, 0, -6), 10); game.darkness.sync(); renderer.sync()
	check(renderer.upload_revision == uploads, "changing illumination does not rebuild terrain geometry")
	game.simulation.light.sources.pop_back()
	check(game.simulation.state_hash() == original, "terrain presentation leaves deterministic gameplay unchanged")
	var cell := Vector2i(30, 20)
	game.simulation.explored[cell] = "ground"; renderer.sync()
	check(renderer.upload_revision == uploads + 1, "new exploration updates retained instances")
	game.simulation.explored[cell] = "cliff"; game.simulation.navigation.revision += 1; renderer.sync()
	check(renderer.known[cell] == "cliff", "terrain edits invalidate existing cells without requiring new exploration")
	game.queue_free(); await process_frame
	print("TERRAIN_RENDERER_TEST_RESULT: ", failures, " failures"); quit(1 if failures else 0)

