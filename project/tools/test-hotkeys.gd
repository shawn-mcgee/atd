extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func key_event(code: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	return event
func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await process_frame
	game.begin_run(); game.set_process(false); game.paused = true
	var soldier: ExpeditionUnit = game.units.filter(func(unit): return unit.kind == "marine")[0]
	game.select_actor(soldier)
	var directions := {KEY_W: Vector3.FORWARD, KEY_A: Vector3.LEFT, KEY_S: Vector3.BACK, KEY_D: Vector3.RIGHT}
	for code in directions:
		game.focus = Vector3.ZERO; game.camera_yaw = 0; game.update_camera()
		Input.parse_input_event(key_event(code, true)); await process_frame
		game._process(0.1)
		Input.parse_input_event(key_event(code, false)); await process_frame
		check(game.focus.dot(directions[code]) > 0.1 and game.tactical_mode.is_empty(), "camera pan key %s moves without arming a tactical command" % OS.get_keycode_string(code))
	Input.parse_input_event(key_event(KEY_Q, true)); await process_frame
	Input.parse_input_event(key_event(KEY_Q, false))
	check(game.tactical_mode == "attack_move" and game.context_buttons.attack.text.contains("[Q]"), "Q arms attack-move and its command caption advertises Q")
	game.refresh_context_commands(); game.refresh_context_commands()
	check(game.context_buttons.attack.text.count("[Q]") == 1, "repeated HUD refreshes retain a single hotkey label")
	game.select_actor(game.units.filter(func(unit): return unit.kind == "engineer")[0]); game.hud.show_tab("build")
	var labels := true
	for i in range(game.BUILD_KINDS.size()):
		var button: Button = game.build_buttons[game.BUILD_KINDS[i]]
		var badge: Label = button.get_meta("key_label")
		if badge.text != ("[%s]" % str((i + 1) % 10) if i < 10 else "Click"): labels = false
	check(labels, "build cards show numeric keys or explicitly identify mouse-only choices")
	game.select_actor(game.core); game.refresh_ui()
	check(game.context_buttons.engineer.get_meta("key_label").text == "[1]" and game.context_buttons.scout.get_meta("key_label").text == "[2]", "production cards display the active factory's actual keys")
	print("HOTKEY_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
