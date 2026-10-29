extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func advance(game, worker: ExpeditionUnit, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		game.advance_movement(0.1); game.process_order(worker, 0.1)

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run(); game.audio_enabled = false
	game.rocks.clear(); game.rebuild_navigation()
	var site: ExpeditionStructure = game.add_structure("wall", Vector3(-50, 0, -20), false)
	var worker: ExpeditionUnit = game.add_unit("engineer", site.position)
	game.set_order(worker, "build", site.position, site)
	advance(game, worker, 8)
	check(site.complete, "engineer starting at the blueprint center finishes instead of remaining at 99 percent")
	check(not game.navigation.blocked(worker.position) and worker.order == "idle" and not worker.moving(), "completed construction leaves its engineer safely outside the obstacle and idle")
	var crowded: ExpeditionStructure = game.add_structure("generator", Vector3(-30, 0, -20), false)
	worker.position = crowded.position + Vector3(0, 0, 3)
	var idle: ExpeditionUnit = game.add_unit("marine", crowded.position)
	var parked: ExpeditionUnit = game.add_unit("jeep", crowded.position + Vector3(0.8, 0, 0))
	var passenger: ExpeditionUnit = game.add_unit("marine", parked.position)
	parked.board(passenger)
	var dead: ExpeditionUnit = game.add_unit("marine", crowded.position); dead.hp = 0
	crowded.progress = 0.99; game.set_order(worker, "build", crowded.position, crowded)
	advance(game, worker, 3)
	check(crowded.complete, "idle infantry and a parked vehicle cannot permanently block a ready building")
	check(not game.navigation.blocked(idle.position) and not game.navigation.blocked(parked.position), "nearby occupants are moved onto reachable free ground before the building becomes solid")
	check(passenger.aboard == parked and passenger.position == parked.position and idle.order == "idle", "clearance preserves crew and idle unit orders")
	var convoy_site: ExpeditionStructure = game.add_structure("wall", Vector3(-10, 0, -30), false)
	var vehicle: ExpeditionUnit = game.add_unit("jeep", convoy_site.position + Vector3(0, 0, 3.5))
	var driver: ExpeditionUnit = game.add_unit("marine", vehicle.position); vehicle.board(driver)
	var builder: ExpeditionUnit = game.add_unit("engineer", convoy_site.position)
	game.complex_commands.start(game, [vehicle, builder], {}, convoy_site)
	var group: Dictionary = game.complex_commands.groups[-1]
	group.phase = "work"; convoy_site.progress = 0.99
	for i in range(20):
		game.advance_movement(0.1); game.complex_commands.tick(game, 0.1)
	check(convoy_site.complete and not game.navigation.blocked(builder.position), "convoy builders also finish from inside a blueprint without trapping their engineer")
	# Surface construction must clear the whole footprint, not only its center.
	var platform: ExpeditionStructure = game.add_structure("platform", Vector3(-50, 0, 6), false)
	worker.position = platform.position; game.set_order(worker, "build", platform.position, platform)
	platform.progress = 0.99; advance(game, worker, 3)
	check(platform.complete and is_zero_approx(worker.position.y) and game.navigation.terrain.height(worker.position) == 0, "platform completion moves the builder off its raised footprint")
	var ramp: ExpeditionStructure = game.add_structure("ramp", Vector3(-30, 0, 6), false, 0)
	game.add_structure("platform", ramp.position + game.Terrain.direction(0) * game.Terrain.SPACING)
	game.rebuild_navigation()
	worker.position = ramp.position - game.Terrain.direction(0) * game.Terrain.SPACING
	game.set_order(worker, "build", ramp.position, ramp); ramp.progress = 0.99
	advance(game, worker, 3)
	check(ramp.complete and is_zero_approx(worker.position.y) and is_zero_approx(game.navigation.terrain.height(worker.position)), "ramp completion clears occupants from its second cell as well as its center")
	var moving_site: ExpeditionStructure = game.add_structure("wall", Vector3(-10, 0, 6), false)
	var walker: ExpeditionUnit = game.add_unit("marine", moving_site.position)
	var goal := moving_site.position + Vector3(0, 0, 8)
	game.set_order(walker, "move", goal)
	check(game.complete_construction(moving_site) and walker.order == "move" and walker.goal == goal and walker.moving(), "clearing a moving unit preserves its order and replans its original destination")
	for i in range(100): game.advance_movement(0.1); game.process_order(walker, 0.1)
	check(walker.position.distance_to(goal) < 0.2, "a displaced moving unit continues to its destination after construction")
	var dead_site: ExpeditionStructure = game.add_structure("wall", Vector3(10, 0, -30), false)
	var casualty: ExpeditionUnit = game.add_unit("marine", dead_site.position); casualty.hp = 0
	check(game.complete_construction(dead_site), "dead units do not block construction completion")
	# If surrounding terrain truly prevents clearance, never force a unit through it.
	var blocked_site: ExpeditionStructure = game.add_structure("wall", Vector3(30, 0, -30), false)
	worker.position = blocked_site.position
	game.rocks.append({"position": blocked_site.position, "radius": 3.0})
	game.rebuild_navigation(); game.set_order(worker, "build", blocked_site.position, blocked_site)
	blocked_site.progress = 0.99
	var original := worker.position
	game.process_order(worker, 0.1)
	game.select_actor(blocked_site); game.refresh_ui()
	check(not blocked_site.complete and worker.position == original and blocked_site.waiting_for_clearance and game.details.text.contains("Waiting for clear space"), "a genuinely blocked site keeps units safe and explicitly reports why completion is waiting")
	game.rocks.clear(); game.rebuild_navigation(); advance(game, worker, 1)
	check(blocked_site.complete and not blocked_site.waiting_for_clearance, "waiting construction automatically completes once safe space becomes available")
	print("CONSTRUCTION_CLEARANCE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
