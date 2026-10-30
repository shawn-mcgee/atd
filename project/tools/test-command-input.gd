extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/top_down.tscn").instantiate(); game.initial_seed = 42
	root.add_child(game); game.set_process(false); game.begin_run(); game.selected.assign([game.simulation.units[1]])
	game.choose_tactical("patrol")
	game.command_click(game.world_to_screen(Vector3(-5, 0, -7)), false, MOUSE_BUTTON_RIGHT)
	check(game.tactical_mode == "" and game.simulation.pending_commands[-1].mode == "patrol", "plain right-click defines a patrol and exits targeting")
	game.choose_tactical("patrol")
	game.command_click(game.world_to_screen(Vector3(-5, 0, -7)), false, MOUSE_BUTTON_LEFT)
	check(game.tactical_mode == "", "plain left-click defines a patrol and exits targeting")
	game.choose_tactical("patrol")
	game.command_click(game.world_to_screen(Vector3(-5, 0, -7)), true, MOUSE_BUTTON_LEFT)
	game.command_click(game.world_to_screen(Vector3(-8, 0, -7)), true, MOUSE_BUTTON_RIGHT)
	var count: int = game.simulation.pending_commands.size()
	check(game.tactical_mode == "patrol" and game.patrol_queuing and game.simulation.pending_commands[-1].append, "Shift left/right clicks queue patrol points without ending input")
	game.command_click(game.world_to_screen(Vector3(-9, 0, -7)), false, MOUSE_BUTTON_LEFT)
	check(game.tactical_mode == "" and game.simulation.pending_commands.size() == count, "plain left-click finishes queued patrol input without adding an unwanted point")
	game.choose_tactical("patrol")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; game._unhandled_input(escape)
	check(game.tactical_mode == "" and not game.selected.is_empty(), "Escape exits targeting while retaining the selection")
	var point := Vector3(35, 0, -20)
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_RIGHT; click.pressed = true
	click.position = game.minimap.project(point); click.shift_pressed = true
	var focus: Vector2 = game.focus; game.minimap._gui_input(click)
	var command: Dictionary = game.simulation.pending_commands[-1]
	check(command.kind == "context" and command.append and command.point.distance_to(point) < 0.01 and game.focus == focus, "minimap right-click issues a queued world order without moving the camera")
	game.choose_tactical("patrol"); click.button_index = MOUSE_BUTTON_LEFT
	game.minimap._gui_input(click)
	check(game.tactical_mode == "patrol" and game.simulation.pending_commands[-1].mode == "patrol", "minimap supports Shift patrol targeting")
	click.shift_pressed = false; count = game.simulation.pending_commands.size(); game.minimap._gui_input(click)
	check(game.tactical_mode == "" and game.simulation.pending_commands.size() == count, "minimap plain left-click finishes queued patrol input")
	check(not game.context_buttons.has("recharge"), "removed charging controls are absent from the HUD")
	game.selected.assign([game.simulation.units[0]])
	var anchor := Vector3(25, 0, -20)
	game.simulation.add_resource_patch("minerals", anchor + Vector3(1.7320508075688772, 0, 0), 50)
	game.simulation.resource_nodes[-1].discovered = true
	var extractor = game.simulation.add_structure("extractor", anchor)
	game.mining_mode = true; game.expedition_mode = true
	game.target_click(game.world_to_screen(extractor.position), false)
	check(game.simulation.pending_commands[-1].kind == "expedition" and game.simulation.pending_commands[-1].point.distance_to(game.simulation.resource_nodes[-1].position) < 0.01, "mining can target an extractor whose center tile has no deposit")
	game.queue_free(); await process_frame
	print("COMMAND_INPUT_TEST_RESULT: ", failures, " failures"); quit(1 if failures else 0)
