extends SceneTree
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ", description)
	else: failures += 1; push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run()
	var focus: Vector3 = game.focus
	var radius: float = game.camera.position.distance_to(focus)
	game.orbit_camera(Vector2(100, 30))
	check(game.focus == focus and is_equal_approx(game.camera.position.distance_to(focus), radius), "orbit preserves focus and camera distance")
	check(absf(game.camera_yaw) > 0.1 and game.camera_pitch > atan2(46.0, 32.0), "mouse orbit adjusts yaw and tilt")
	var centered: Vector2 = game.camera.unproject_position(focus)
	check(centered.distance_to(root.get_visible_rect().size * 0.5) < 0.01, "orbit keeps the focus centered on screen")
	game.orbit_camera(Vector2(0, 10000))
	check(is_equal_approx(game.camera_pitch, deg_to_rad(75)), "tilt is capped before the camera becomes vertical")
	game.orbit_camera(Vector2(0, -10000))
	check(is_equal_approx(game.camera_pitch, deg_to_rad(35)), "tilt stays above the horizon for reliable ground picking")
	var picks := true
	for yaw in [0.0, 0.7, PI / 2, PI, -1.4]:
		for pitch in [35.0, 55.0, 75.0]:
			game.camera_yaw = yaw; game.camera_pitch = deg_to_rad(pitch); game.update_camera()
			# Keep this projection check inside the clear starting clearing;
			# canyon walls should intercept rays aimed behind them at low angles.
			var point := focus + Vector3(-4.23, 0, 2.81)
			var screen: Vector2 = game.camera.unproject_position(point)
			if game.ground_point(screen).distance_to(point) > 0.002: picks = false
	check(picks, "selection and world orders project correctly at different orbit angles and tilts")
	game.camera_yaw = PI / 2; game.camera_pitch = atan2(46.0, 32.0); game.update_camera()
	var right: Vector3 = game.camera_pan_vector(Vector2.RIGHT)
	var forward: Vector3 = game.camera_pan_vector(Vector2.UP)
	var origin: Vector2 = game.camera.unproject_position(focus)
	check(game.camera.unproject_position(focus + right).x > origin.x and absf(right.y) < 0.001, "keyboard right pans right relative to the rotated camera")
	check(game.camera.unproject_position(focus + forward).y < origin.y and absf(forward.y) < 0.001, "keyboard forward pans upward relative to the rotated camera")
	game.dragging = true
	var motion := InputEventMouseMotion.new(); motion.position = origin; motion.relative = Vector2(30, 0)
	game._unhandled_input(motion)
	check((game.focus - focus).normalized().dot(right) < -0.99, "middle drag pans in screen space after rotation")
	var pan_focus: Vector3 = game.focus
	game.paused = true; motion.alt_pressed = true; motion.relative = Vector2(40, 20)
	var before_yaw: float = game.camera_yaw
	game._unhandled_input(motion)
	check(game.focus == pan_focus and not is_equal_approx(game.camera_yaw, before_yaw), "Alt-middle drag orbits while paused without panning")
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_MIDDLE
	game._input(release)
	check(not game.dragging, "releasing middle mouse ends camera drag")
	game.camera_zoom = 30
	var home := InputEventKey.new(); home.keycode = KEY_HOME; home.pressed = true
	game._unhandled_input(home)
	check(is_zero_approx(game.camera_yaw) and is_equal_approx(game.camera_zoom, 48.0) and game.focus == game.HOME + Vector3(7, 0, -2), "Home restores the complete initial camera view")
	print("CAMERA_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
