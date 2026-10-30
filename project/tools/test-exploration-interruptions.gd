extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		game.advance_movement(0.1)
		for unit in game.units: game.process_order(unit, 0.1)
		game.complex_commands.tick(game, 0.1); game.rebuild_light()
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	await process_frame; await physics_frame

	game.rocks.clear(); game.rebuild_navigation()
	var command = game.complex_commands
	var exploration = command.exploration
	var worker: SimUnit = game.add_unit("engineer", Vector3(-50, 0, -20))
	var guard: SimUnit = game.add_unit("marine", worker.position + Vector3(1, 0, 0))
	check(command.start_expedition(game, [worker, guard], {}, Vector3(-30, 0, -20)), "engineer and guard begin exploring")
	var group: Dictionary = exploration.groups[-1]
	var wall: SimStructure = game.add_structure("wall", worker.position + Vector3(0, 0, 3), false)
	game.rebuild_navigation()
	check(game.set_order(worker, "build", wall.position, wall), "a build order interrupts exploration")
	await step(game, 12)
	check(wall.complete and worker.order == "idle" and worker.complex_id == 0 and not group.members.has(worker), "completed construction leaves the former explorer idle and detached")
	var held := worker.position
	await step(game, 15)
	check(worker.order == "idle" and worker.position.distance_to(held) < 0.01 and guard.complex_id == group.id, "the builder stays put while the remaining expedition continues scouting")
	exploration.finish(group)
	# A real terrain right-click must finish as a normal move, with no auto-resume.
	guard.position = Vector3(-24, 0, -18)
	command.start_expedition(game, [guard], {}, Vector3(-10, 0, -18))
	game.select_actor(guard)
	game.contextual_order(Vector3(-20, 0, -14))
	check(guard.complex_id == 0 and guard.order == "move" and exploration.groups.is_empty(), "ordinary terrain right-click cancels scouting instead of rearming it")
	await step(game, 8)
	held = guard.position
	await step(game, 15)
	check(guard.order == "idle" and guard.complex_id == 0 and guard.position.distance_to(held) < 0.01, "finishing the move never returns the unit to exploration")
	# Defend against stale membership when an order is replaced outside set_order.
	command.start_expedition(game, [guard], {}, Vector3(-10, 0, -18))
	group = exploration.groups[-1]
	guard.order = "move"; guard.travel(guard.position + Vector3(2, 0, 0), game.navigation)
	command.tick(game, 0.1)
	check(guard.order == "move" and guard.complex_id == 0 and not exploration.groups.has(group), "stale group membership cannot overwrite a replacement task")
	await step(game, 8)
	check(guard.order == "idle" and guard.complex_id == 0, "a replacement task completing cannot restore stale exploration")
	# Unloading must detach every assigned passenger, not just the driver.
	var jeep: SimUnit = game.add_unit("jeep", Vector3(12, 0, -18))
	var driver: SimUnit = game.add_unit("engineer", jeep.position + Vector3(1, 0, 0))
	var passenger: SimUnit = game.add_unit("engineer", jeep.position + Vector3(2, 0, 0))
	var escort: SimUnit = game.add_unit("marine", jeep.position + Vector3(0, 0, 2))
	command.start_expedition(game, [jeep, driver, passenger, escort], {}, Vector3(25, 0, -18))
	group = exploration.groups[-1]
	await step(game, 2)
	check(jeep.driver == driver and passenger.aboard == jeep, "exploration boards engineer driver and passenger")
	game.select_actor(jeep); game.unload()
	check(jeep.complex_id == 0 and driver.complex_id == 0 and passenger.complex_id == 0 and passenger.aboard == null and escort.complex_id == group.id, "unloading detaches the vehicle and all its assigned crew while walking escorts keep exploring")
	held = jeep.position
	var repair: SimStructure = game.add_structure("wall", passenger.position + Vector3(0, 0, 3))
	repair.hp -= 8; game.rebuild_navigation()
	game.set_order(passenger, "repair", repair.position, repair)
	await step(game, 15)
	check(repair.hp == game.Rules.STRUCTURES.wall.hp and passenger.order == "idle" and passenger.aboard == null and passenger.complex_id == 0 and jeep.position.distance_to(held) < 0.01, "an unloaded engineer finishes repair without reboarding or restarting the vehicle's exploration")
	# The player can still explicitly opt back into exploration.
	command.start_expedition(game, [passenger], {}, passenger.position + Vector3(6, 0, 0))
	check(passenger.complex_id != 0 and command.is_expedition(passenger), "explicit Expedition targeting can start scouting again")
	game.dispose()
	print("EXPLORATION_INTERRUPTION_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
