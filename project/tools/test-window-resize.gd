extends SceneTree
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ", description)
	else: failures += 1; push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	game.set_process(false)
	game.update_camera()
	var initial_size: float = game.camera.size
	var initial_scale: float = game.camera.unproject_position(game.HOME).distance_to(game.camera.unproject_position(game.HOME + Vector3.RIGHT))
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "viewport follows native window size")
	root.size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	var grown_scale: float = game.camera.unproject_position(game.HOME).distance_to(game.camera.unproject_position(game.HOME + Vector3.RIGHT))
	check(game.ui.size.is_equal_approx(Vector2(1920, 1080)), "HUD root expands to resized window")
	check(game.camera.size > initial_size, "larger window reveals more terrain vertically")
	check(absf(initial_scale - grown_scale) < 0.01, "units preserve their screen scale when window grows")
	game.camera_zoom = 36
	game.update_camera()
	check(is_equal_approx(game.camera.size, 36.0 * 1080.0 / 800.0), "mouse-wheel zoom remains independent of resizing")
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	check(is_equal_approx(game.camera.size, 36.0), "shrinking window preserves the chosen zoom")
	print("RESIZE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
