extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		game.advance_movement(0.1); game.complex_commands.tick(game, 0.1)
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.begin_run(); game.select_actor(game.core); game.scan(); game.select_actor(game.jeep)
	game.rocks.clear(); game.rebuild_navigation()
	var worker: ExpeditionUnit = game.add_unit("engineer", game.DEPOSIT + Vector3(-3, 0, 0))
	var guard: ExpeditionUnit = game.add_unit("marine", worker.position + Vector3(0, 0, 3))
	worker.capacity = 3
	var resource: Dictionary = game.resource_at(game.DEPOSIT)
	resource.remaining = 30
	check(game.complex_commands.expedition_available([worker]), "one engineer can run an expedition without a jeep")
	check(game.complex_commands.expedition_available([guard]) and not game.complex_commands.mining_available([guard]), "combat infantry can explore but still need an engineer to gather")
	game.select_actor(worker); game.select_actor(guard, true)
	game.choose_expedition(true); await game.expedition_click(game.camera.unproject_position(game.DEPOSIT))
	check(game.complex_commands.foot.groups.size() == 1 and not game.expedition_mode, "explicit expedition targeting starts an on-foot expedition")
	await step(game, 1)
	check(guard.order == "convoy_foot_patrol", "on-foot infantry patrol while engineers gather")
	var before: int = game.returned_materials
	await step(game, 100)
	check(game.returned_materials >= before + 6, "on-foot engineers carry multiple loads home and repeat gathering")
	game.set_order(worker, "move", Vector3(5, 0, -20))
	await step(game, 2)
	check(worker.complex_id == 0 and game.complex_commands.foot.groups.is_empty() and guard.complex_id == 0, "interrupting the final foot engineer releases its guard and never re-enlists the worker")
	var a: ExpeditionUnit = game.add_unit("jeep", Vector3(7, 0, -8))
	var b: ExpeditionUnit = game.add_unit("jeep", Vector3(8, 0, -3))
	a.capacity = 4; b.capacity = 4
	check(not game.complex_commands.mining_available([a, b, worker, guard]), "multiple jeeps require a working engineer for each mining convoy")
	for kind in ["marine", "engineer"]:
		var u: ExpeditionUnit = game.add_unit(kind, a.position); a.board(u)
		var v: ExpeditionUnit = game.add_unit(kind, b.position); b.board(v)
	var extra: Array = []
	for i in range(6): extra.append(game.add_unit("flamer", Vector3(9 + i, 0, -5)))
	check(game.complex_commands.expedition_available([a, b]), "multiple packed jeeps can use their existing onboard crews")
	game.selected.assign([a, b] + extra)
	resource.remaining = 200
	game.choose_expedition(true); await game.expedition_click(game.camera.unproject_position(game.DEPOSIT))
	check(game.complex_commands.groups.size() == 2, "one expedition command creates two independent jeep convoys")
	var ids: Dictionary = {}
	var valid := true
	for group in game.complex_commands.groups:
		valid = valid and group.driver.kind == "marine" and group.riders.any(func(unit): return unit.kind == "engineer") and group.members.size() == 5
		for unit in group.members:
			if ids.has(unit.get_instance_id()): valid = false
			ids[unit.get_instance_id()] = true
	check(valid and ids.size() == 10, "every convoy gets a light infantry driver, engineer passenger and its own overflow escort without duplicate assignments")
	before = game.returned_materials
	await step(game, 110)
	check(game.returned_materials >= before + 8, "multiple jeeps collect and deliver cargo from the same deposit")
	game.select_actor(a); game.stop_selected()
	check(game.complex_commands.groups.size() == 1 and b.complex_id != 0, "stopping one convoy leaves the other expedition active")
	before = game.returned_materials
	await step(game, 80)
	check(game.returned_materials > before and a.complex_id == 0, "remaining convoy continues its loop without reclaiming the interrupted jeep")
	print("EXPEDITION_ROSTER_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
