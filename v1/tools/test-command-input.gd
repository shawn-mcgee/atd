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
	check(not game.build_buttons.has("ramp") and not game.build_buttons.has("platform"), "ramps and platforms are absent from construction options")
	check(not game.simulation.valid_site("ramp", Vector3.ZERO) and not game.simulation.valid_site("platform", Vector3.ZERO), "engine placement rejects disabled ramps and platforms")
	game.choose_build("platform"); game.choose_build("ramp")
	check(game.build_kind.is_empty(), "disabled structures cannot activate placement through direct UI calls")
	var structure_count: int = game.structures.size()
	game.simulation.apply_command({"kind": "build", "building": "platform", "actors": [game.simulation.units[0].simulation_id], "point": Vector3.ZERO})
	game.simulation.apply_command({"kind": "build", "building": "ramp", "actors": [game.simulation.units[0].simulation_id], "point": Vector3.ZERO})
	check(game.structures.size() == structure_count, "queued commands cannot construct removed surface structures")
	var anchor := Vector3(25, 0, -20)
	game.simulation.add_resource_patch("minerals", anchor + Vector3(1.7320508075688772, 0, 0), 50)
	game.simulation.resource_nodes[-1].discovered = true
	var extractor = game.simulation.add_structure("extractor", anchor)
	game.mining_mode = true; game.expedition_mode = true
	game.target_click(game.world_to_screen(extractor.position), false)
	check(game.simulation.pending_commands[-1].kind == "expedition" and game.simulation.pending_commands[-1].point.distance_to(game.simulation.resource_nodes[-1].position) < 0.01, "mining can target an extractor whose center tile has no deposit")
	var covered: Dictionary = game.simulation.resource_nodes[-1]
	var unchanged: String = game.simulation.state_hash()
	check(not game.resource_visible(covered) and game.pick_resource(game.world_to_screen(covered.position)) != covered, "covered patches are hidden and cannot be picked")
	game.selected.assign([extractor]); game.refresh_ui()
	check(game.details.text.contains("Materials left: 50") and game.details.text.contains("Methane left: 0"), "selecting an extractor shows remaining materials and methane")
	check(game.hud.grid_panel.visible and game.hud.grid_value.text == "Power: -2\nGrid capacity: —\nGrid demand: —", "disconnected electrical structures show their signed cost with no grid values")
	check(game.simulation.state_hash() == unchanged, "hiding patches and inspecting totals leaves resource data unchanged")
	extractor.hp = 0
	check(game.resource_visible(covered), "remaining patches reappear when their extractor is destroyed")
	extractor.hp = game.Rules.STRUCTURES.extractor.hp
	game.simulation.power.tick(game.structures, game.economy, 0)
	game.selected.assign([game.simulation.core]); game.refresh_ui()
	check(game.hud.grid_panel.visible and game.hud.grid_value.text == "Power: +4\nGrid capacity: 4\nGrid demand: 0" and game.hud.grid_value.tooltip_text.is_empty(), "grid information contains only signed power, capacity and current demand")
	game.selected.assign([game.simulation.units[0]]); game.refresh_ui()
	check(not game.hud.grid_panel.visible, "units do not display power grid status")
	var depot: SimStructure = game.simulation.add_structure("depot", game.simulation.core.position)
	game.selected.assign([depot]); game.refresh_ui()
	check(not game.hud.grid_panel.visible, "structures that do not participate in power do not display grid status")
	game.selected.assign([game.simulation.units[0]]); game.refresh_ui(); game.choose_build("floodlight")
	game.mouse_world = Vector3(60, 0, 60); game.hud.update_power_preview()
	check(game.power_preview_label.visible and game.power_preview_label.text.contains("No power connection"), "construction previews explain missing power connections")
	game.simulation.rocks.clear(); game.simulation.navigation.terrain.natural_enabled = false
	game.simulation.rebuild_navigation(); game.simulation.light.clear(); game.simulation.light.add_source(Vector3.ZERO, 100)
	var occupied: Vector3 = game.Hex.to_world(Vector2i(-15, 15), 1)
	game.simulation.units[0].position = occupied
	game.simulation.add_unit("marine", occupied)
	game.choose_build("wall"); game.target_click(game.world_to_screen(occupied), false)
	var build: Dictionary = game.simulation.pending_commands[-1]
	check(build.kind == "build" and build.point.distance_to(occupied) < 0.01 and game.selected == [game.simulation.units[0]], "placement clicks through units and retains the selected engineer")
	game.simulation.apply_command(build)
	var blueprint: SimStructure = game.simulation.structures[-1]
	check(blueprint.kind == "wall" and not blueprint.complete and not game.simulation.navigation.blocked(occupied), "placing a blueprint over units keeps its tile fully walkable")
	game.queue_free(); await process_frame
	print("COMMAND_INPUT_TEST_RESULT: ", failures, " failures"); quit(1 if failures else 0)
