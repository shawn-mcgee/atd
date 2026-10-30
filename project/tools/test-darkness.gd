extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/top_down.tscn").instantiate(); game.initial_seed = 42
	root.add_child(game); game.set_process(false); game.begin_run()
	var fog = game.darkness; fog.set_process(false)
	var before: String = game.simulation.state_hash()
	check(fog.mouse_filter == Control.MOUSE_FILTER_IGNORE and fog.z_index == 100, "darkness covers world without blocking mouse input or the HUD")
	check(fog.light_stamps.sources == game.simulation.light.sources, "GPU mask receives every authoritative light, without a fixed light count limit")
	game.focus = Vector2(15, -9); game.zoom = 160; game.camera_angle = 0.8
	fog._process(0.25)
	check(fog.clock > 0 and fog.material.get_shader_parameter("camera_focus") == game.focus and is_equal_approx(fog.material.get_shader_parameter("camera_zoom"), 160), "world-anchored noise follows camera rotation, pan, and close zoom")
	game.simulation.paused = true
	var stopped: float = fog.clock; fog._process(1)
	check(fog.clock == stopped, "wisps freeze while paused")
	game.simulation.paused = false
	check(game.simulation.state_hash() == before, "shader animation and camera changes do not affect gameplay")
	var revision: int = fog.field_revision
	game.simulation.light.add_source(Vector3(15, 0, 2), 7, Vector3.FORWARD, 0.6, 0.5)
	fog.sync()
	check(fog.field_revision != revision and fog.light_stamps.sources[-1].cone == 0.6, "moving/added directional lights refresh the cone-aware mask")
	root.size = Vector2i(1600, 1000); await process_frame; fog.sync()
	check(fog.size == game.get_viewport_rect().size, "overlay follows resized windows")
	game.queue_free(); await process_frame
	print("DARKNESS_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
