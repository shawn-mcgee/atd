extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		game.advance_movement(0.1); game.complex_commands.tick(game, 0.1); game.rebuild_light()
		if i % 10 == 0: game.minimap.refresh()
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.begin_run(); game.audio_enabled = false
	var command = game.complex_commands
	var exploration = command.exploration
	var canyon_guard: ExpeditionUnit = game.add_unit("marine", Vector3(4, 0, -3))
	check(command.start_expedition(game, [canyon_guard], {}, game.DEPOSIT), "exploration can plan through the real canyon terrain")
	var canyon: Dictionary = exploration.groups[-1]
	var clear_route := true
	for i in range(1600):
		game.advance_movement(0.1); command.tick(game, 0.1); game.rebuild_light()
		if game.navigation.blocked(canyon_guard.position) or exploration.distance_to_route(canyon_guard.position, canyon.route) > exploration.LEASH + 0.1: clear_route = false
		if i % 100 == 0: await process_frame
		if canyon.start_reached: break
	check(clear_route and canyon.start_reached and canyon_guard.position.distance_to(game.DEPOSIT) < 0.8, "explorers navigate actual cliffs and reach their sweep start while staying within their current route corridor")
	exploration.finish(canyon)
	game.rocks.clear(); game.rebuild_navigation()
	var marine: ExpeditionUnit = game.add_unit("marine", Vector3(-40, 0, -12))
	var flamer: ExpeditionUnit = game.add_unit("flamer", marine.position + Vector3(0, 0, 1))
	var destination := Vector3(-12, 0, -12)
	check(command.expedition_available([marine, flamer]), "infantry can start exploration without an engineer")
	check(command.start_expedition(game, [marine, flamer], {}, destination), "a terrain expedition creates an exploration task")
	var group: Dictionary = exploration.groups[-1]
	game.rebuild_light(); exploration.tick(game, 0.1)
	check(game.light.sample(group.waypoint) < 0.05 and exploration.distance_to_route(group.waypoint, group.route) <= exploration.LEASH, "exploration prefers unseen ground near its route")
	var explored_before: int = game.minimap.explored.size()
	var stayed_close := true
	for i in range(1000):
		game.advance_movement(0.1); command.tick(game, 0.1); game.rebuild_light()
		for unit in [marine, flamer]:
			if exploration.distance_to_route(unit.position, group.route) > exploration.LEASH + 0.1: stayed_close = false
		if i % 10 == 0: game.minimap.refresh()
		if i % 100 == 0: await process_frame
		if group.start_reached and marine.position.distance_to(destination) > 12: break
	check(stayed_close and group.start_reached and group.phase != "complete" and marine.position.distance_to(destination) > 12, "explorers keep sweeping beyond the chosen starting area while following their current route")
	check(game.minimap.explored.size() > explored_before, "exploration records newly illuminated terrain on the minimap")
	var enemy: ExpeditionPredator = game.add_creature(marine.position + Vector3(0, 0, 2), 99)
	game.light.add_source(enemy.position, 3)
	var goal := marine.goal
	game.combat_tick(0.1)
	check(enemy.hp < enemy.max_hp and marine.goal == goal, "explorers fire at visible enemies in range without chasing them")
	game.set_order(marine, "move", marine.position + Vector3(0, 0, 4))
	check(marine.complex_id == 0 and not group.members.has(marine) and group.members.has(flamer), "a direct order detaches one explorer while the others continue")
	command.interrupt(flamer)
	check(exploration.groups.is_empty(), "removing the final explorer cleans up the task")
	# Both vehicle kinds share the requested driver priority.
	for kind in ["scout", "jeep"]:
		var vehicle: ExpeditionUnit = game.add_unit(kind, Vector3(-25, 0, 12))
		var engineer: ExpeditionUnit = game.add_unit("engineer", vehicle.position)
		var heavy: ExpeditionUnit = game.add_unit("flamer", vehicle.position + Vector3(0, 0, 1))
		check(command.start_expedition(game, [vehicle, heavy, engineer], {}, Vector3(-15, 0, 12)), kind + " accepts exploration with available infantry")
		var task: Dictionary = exploration.groups[-1]
		check(task.pilots[vehicle] == engineer, kind + " prefers an engineer driver over a heavy flamer")
		await step(game, 2)
		check(vehicle.driver == engineer and heavy.aboard == null, kind + " boards its chosen driver and keeps combat infantry on foot")
		exploration.finish(task)
		vehicle.disembark(engineer, vehicle.position + Vector3(0, 0, 3))
		check(command.start_expedition(game, [vehicle, heavy, engineer, marine], {}, Vector3(-10, 0, 12)), kind + " can accept a new crew")
		task = exploration.groups[-1]
		check(task.pilots[vehicle] == engineer, kind + " prefers an engineer over marine and heavy flamer")
		exploration.finish(task)
		check(command.start_expedition(game, [vehicle, heavy, marine], {}, Vector3(-10, 0, 12)), kind + " accepts a crew without engineers")
		task = exploration.groups[-1]
		check(task.pilots[vehicle] == marine, kind + " prefers a marine over a heavy flamer when no engineer is available")
		exploration.finish(task)
	# Explicit exploration targeting starts scouting; ordinary right-click detaches.
	marine.position = Vector3(5, 0, -16); flamer.position = marine.position + Vector3(1, 0, 0)
	game.select_actor(marine); game.select_actor(flamer, true); game.choose_expedition()
	game.focus = Vector3(8, 0, -17); game.update_camera()
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_RIGHT; click.pressed = true
	click.position = game.camera.unproject_position(Vector3(12, 0, -17))
	game._unhandled_input(click); await process_frame
	check(not game.expedition_mode and exploration.groups.size() == 1, "right-click confirms an armed exploration order")
	var id: int = marine.complex_id
	game.select_actor(marine)
	await game.contextual_order(game.camera.unproject_position(Vector3(14, 0, -13)))
	check(marine.complex_id == 0 and marine.order == "move" and flamer.complex_id == id and exploration.groups.size() == 1, "right-clicking terrain detaches the selected explorer and leaves its companions exploring")
	game.select_actor(flamer); game.choose_expedition()
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	game._unhandled_input(escape)
	check(not game.expedition_mode and flamer.complex_id != 0, "Escape cancels targeting without cancelling the current exploration")
	var scouts: Array[ExpeditionUnit] = []
	for i in range(2):
		var vehicle: ExpeditionUnit = game.add_unit("scout", Vector3(-15, 0, -8 - i * 5))
		var pilot: ExpeditionUnit = game.add_unit("engineer", vehicle.position + Vector3(1, 0, 0))
		check(command.start_expedition(game, [vehicle, pilot], {}, Vector3(-15, 0, -15)), "independent scout expedition accepts the common sweep start")
		scouts.append(vehicle)
	var shared_before: int = game.minimap.explored.size()
	var claimed := 0; var separate := true
	for i in range(300):
		game.advance_movement(0.1); game.rebuild_light(); command.tick(game, 0.1)
		var tasks: Array = exploration.groups.filter(func(task): return task.vehicles.has(scouts[0]) or task.vehicles.has(scouts[1]))
		if tasks.size() == 2 and tasks.all(func(task): return task.phase in ["exploring", "scanning"]):
			claimed += 1
			if tasks[0].survey_cell == tasks[1].survey_cell: separate = false
		if i % 100 == 0: await process_frame
	check(claimed > 0 and separate and game.minimap.explored.size() > shared_before, "multiple expeditions share scouting progress and reserve different unknown targets")
	game.select_actor(scouts[1]); game.stop_selected()
	check(scouts[1].complex_id == 0 and scouts[0].complex_id != 0, "stopping one automatic scout leaves the other expedition exploring")
	print("EXPEDITION_EXPLORATION_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
