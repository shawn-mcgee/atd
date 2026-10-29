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
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.begin_run()
	game.refresh_ui()
	check(not game.construction_panel.visible and game.context_buttons.load.visible and game.context_buttons.board.visible, "jeep selection exposes cargo/transport and hides construction")
	check(not game.context_buttons.unload.visible and not game.context_buttons.escort.visible and not game.context_buttons.repair.visible, "empty jeep hides disembark and infantry-specific commands")
	game.select_actor(game.units[0]); game.refresh_ui()
	check(game.hud.build_tab.visible and game.context_buttons.repair.visible, "engineer selection reveals construction and repair")
	check(not game.context_buttons.load.visible and game.context_buttons.escort.visible and game.context_buttons.board.visible, "engineer hides cargo controls and exposes infantry commands")
	game.choose_build("floodlight")
	check(game.build_kind == "floodlight", "selected engineer can enter construction placement")
	game.select_actor(game.units[2]); game.refresh_ui()
	check(not game.construction_panel.visible and game.build_kind.is_empty(), "changing from engineer to marine hides menu and cancels placement")
	check(not game.context_buttons.repair.visible and game.context_buttons.escort.visible and not game.context_buttons.load.visible, "marine shows infantry commands only")
	game.choose_build("turret")
	check(game.build_kind.is_empty(), "construction hotkeys cannot bypass engineer selection")
	game.select_actor(game.units[0], true); game.refresh_ui()
	check(game.hud.build_tab.visible and game.context_buttons.repair.visible and game.context_buttons.escort.visible, "mixed infantry selection retains applicable engineer and squad commands")
	game.select_actor(game.jeep, true); game.refresh_ui()
	check(game.context_buttons.load.visible and game.hud.build_tab.visible and game.context_buttons.board.visible, "mixed vehicle/infantry selection combines commands without duplicate boarding actions")
	game.select_actor(game.home_depot); game.refresh_ui()
	check(not game.construction_panel.visible and not game.context_buttons.stop.visible and not game.context_buttons.load.visible, "structure inspection hides unit action menus")
	game.select_actor(null); game.refresh_ui()
	check(not game.construction_panel.visible and not game.command_panel.visible, "clearing selection leaves mission controls and selection hint")
	game.select_actor(game.units[0]); game.choose_repair()
	check(game.repair_mode, "repair mode requires and accepts an engineer")
	game.select_actor(game.jeep)
	check(not game.repair_mode, "changing to a non-engineer cancels repair targeting")
	await process_frame
	await process_frame
	var vehicle_height: float = game.command_panel.size.y
	game.select_actor(null); game.refresh_ui()
	await process_frame
	await process_frame
	check(is_equal_approx(game.command_panel.size.y, vehicle_height), "command dock keeps a stable layout while irrelevant actions disappear")
	var barracks: ExpeditionStructure
	var garage: ExpeditionStructure
	for b in game.structures:
		if b.kind == "barracks": barracks = b
		if b.kind == "garage": garage = b
	game.select_actor(barracks); game.refresh_ui()
	check(game.context_buttons.engineer.visible and game.context_buttons.flamer.visible and not game.context_buttons.jeep.visible, "barracks selection exposes only infantry production")
	game.select_actor(garage); game.refresh_ui()
	check(game.context_buttons.scout.visible and game.context_buttons.jeep.visible and not game.context_buttons.marine.visible, "garage selection exposes only vehicle production")
	game.select_actor(game.jeep)
	game.jeep.board(game.units[0]); game.refresh_ui()
	check(game.context_buttons.unload.visible and "driver" in game.context_buttons.unload.text, "vehicle with only a driver offers explicit driver unload command")
	game.jeep.board(game.units[1]); game.refresh_ui()
	check("passengers" in game.context_buttons.unload.text, "vehicle with passengers offers passenger unload before driver")
	print("CONTEXT_HUD_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
