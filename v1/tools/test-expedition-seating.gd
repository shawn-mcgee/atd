extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		game.advance_movement(0.1); game.complex_commands.tick(game, 0.1); game.rebuild_light()
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	await process_frame

	game.rocks.clear(); game.rebuild_navigation()
	var command = game.complex_commands
	var resource: Dictionary = game.resource_at(game.DEPOSIT); resource.discovered = true
	var jeep: SimUnit = game.add_unit("jeep", Vector3(8, 0, -16))
	var marine: SimUnit = game.add_unit("marine", jeep.position)
	var flamer: SimUnit = game.add_unit("flamer", jeep.position + Vector3(0, 0, 1))
	var engineers: Array = []
	for i in range(3): engineers.append(game.add_unit("engineer", jeep.position + Vector3(i + 1, 0, 0)))
	var crew: Array = [jeep, marine, flamer] + engineers
	jeep.board(marine)
	check(command.start_expedition(game, crew, {}, Vector3(25, 0, -16)), "a crewed mining-style jeep can switch to exploration")
	var group: Dictionary = command.exploration.groups[-1]
	check(group.pilots[jeep] == engineers[0] and group.seats.has(engineers[1]) and group.seats.has(engineers[2]) and not group.seats.has(marine) and not group.seats.has(flamer), "exploration replaces the marine driver and prioritizes engineers for passenger seats")
	await step(game, 4)
	check(jeep.driver == engineers[0] and engineers.all(func(unit): return unit.aboard == jeep) and marine.aboard == null and flamer.aboard == null, "all selected engineers ride while combat infantry escort on foot")
	check(command.start_expedition(game, crew, resource), "the exploring crew can switch to mining")
	group = command.groups[-1]
	check(group.driver == marine and engineers.all(func(unit): return group.riders.has(unit)), "mining reassigns the marine as driver and engineers as workers")
	for i in range(600):
		await step(game, 0.1)
		if group.phase == "work": break
	check(group.phase == "work" and jeep.driver == marine and engineers.all(func(unit): return unit.aboard == null), "mining keeps the marine aboard with lights while engineers dismount to dig")
	command.interrupt(jeep)
	jeep.disembark(marine, jeep.position + Vector3(4, 0, 0))
	check(command.start_expedition(game, [jeep, flamer] + engineers, resource), "mining accepts a flamer and surplus engineers")
	check(command.groups[-1].driver == flamer, "a flamer drives before surplus engineers during mining")
	command.interrupt(jeep)
	check(command.start_expedition(game, [jeep] + engineers.slice(0, 2), resource), "engineers-only mining has a driver fallback")
	group = command.groups[-1]
	check(group.driver.kind == "engineer" and group.members.any(func(unit): return unit.kind == "engineer" and unit != group.driver), "engineer fallback retains a separate mining engineer")
	command.interrupt(jeep)
	# Multiple vehicles assign their pilots before using spare seats for engineers.
	var scout: SimUnit = game.add_unit("scout", jeep.position + Vector3(0, 0, 3))
	var extra: SimUnit = game.add_unit("engineer", jeep.position + Vector3(1, 0, 3))
	crew = [jeep, scout, marine, flamer, extra] + engineers
	check(command.start_expedition(game, crew, {}, Vector3(25, 0, -20)), "a jeep and scout can explore with a pooled crew")
	group = command.exploration.groups[-1]
	check(group.pilots[jeep].kind == "engineer" and group.pilots[scout].kind == "engineer" and group.seats.size() == 4, "both pilots and all remaining engineers receive seats before combat infantry")
	await step(game, 5)
	check((engineers + [extra]).all(func(unit): return unit.aboard != null) and marine.aboard == null and flamer.aboard == null, "multi-vehicle exploration boards all assigned engineers without stranding a pilot")
	# Directly moving one vehicle also releases its passengers, not the other car.
	var detached: Array = group.members.filter(func(unit): return unit.aboard == jeep)
	game.set_order(jeep, "move", jeep.position + Vector3(0, 0, -5))
	await step(game, 12)
	check(jeep.complex_id == 0 and not jeep.order.begins_with("convoy_explore") and detached.all(func(unit): return unit.complex_id == 0) and scout.complex_id == group.id, "a direct vehicle order permanently detaches its entire crew while the other scout continues")
	game.dispose()
	print("EXPEDITION_SEATING_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
