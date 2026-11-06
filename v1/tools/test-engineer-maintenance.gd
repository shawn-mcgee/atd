extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func advance(game, worker: SimUnit, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		game.advance_movement(0.1); game.process_order(worker, 0.1)
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	await process_frame

	game.rocks.clear(); game.rebuild_navigation()
	var first: SimStructure = game.add_structure("wall", Vector3(-50, 0, -20), false)
	var worker: SimUnit = game.add_unit("engineer", first.position + Vector3(0, 0, 3))
	game.set_order(worker, "build", first.position, first)
	await advance(game, worker, 6)
	var finished_at := worker.position
	check(first.complete and worker.order == "idle" and worker.target == null and not worker.moving(), "finishing an isolated build clears the engineer's order and path")
	await advance(game, worker, 10)
	check(worker.position.distance_to(finished_at) < 0.01 and worker.goal == finished_at, "engineer remains exactly where the completed build finished")
	var repair: SimStructure = game.add_structure("wall", first.position + Vector3(7, 0, 0))
	repair.hp -= 16
	var blueprint: SimStructure = game.add_structure("wall", repair.position + Vector3(7, 0, 0), false)
	var distant: SimStructure = game.add_structure("wall", blueprint.position + Vector3(22, 0, 0))
	distant.hp -= 16
	game.rebuild_navigation()
	game.continue_maintenance(worker, first)
	check(worker.order == "repair" and worker.target == repair, "completed work immediately chains to the nearest reachable damaged structure")
	await advance(game, worker, 20)
	check(repair.hp == game.Rules.STRUCTURES.wall.hp and blueprint.complete, "engineer repairs nearby damage and then completes the nearby blueprint")
	finished_at = worker.position
	await advance(game, worker, 10)
	check(worker.order == "idle" and not worker.moving() and worker.position.distance_to(finished_at) < 0.01, "engineer holds at the last chained job without wandering toward HQ")
	check(distant.hp == game.Rules.STRUCTURES.wall.hp - 16, "jobs beyond the nearby search radius do not pull the engineer away")
	# A disconnected elevated job must not strand the engineer or suppress holding.
	var deck: SimStructure = game.add_structure("platform", blueprint.position + Vector3(7, 0, 0))
	game.rebuild_navigation()
	var inaccessible: SimStructure = game.add_structure("turret", deck.position)
	inaccessible.hp -= 8
	game.rebuild_navigation()
	game.continue_maintenance(worker, blueprint)
	check(worker.order == "idle" and not worker.moving(), "unreachable nearby work is skipped instead of creating a bogus move order")
	game.dispose()
	print("ENGINEER_MAINTENANCE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
