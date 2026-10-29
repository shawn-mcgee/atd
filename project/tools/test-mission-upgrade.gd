extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.audio_enabled = false; game.begin_run()
	for enemy in game.creatures: enemy.hp = 0
	game.cleanup_dead(); game.director.groups.clear()
	check(game.Terrain.CELL == 1 and game.Terrain.MAP_RADIUS == 56, "half-size cells preserve world extent")
	check(game.Footprints.cells("core", Vector3.ZERO).size() == 7 and game.Footprints.cells("generator", Vector3.ZERO).size() == 3 and game.Footprints.cells("barracks", Vector3.ZERO).size() == 3 and game.Footprints.cells("garage", Vector3.ZERO).size() == 4, "structure footprints reserve requested tile counts")
	check(game.Footprints.offsets("garage") == [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "garage footprint is a diamond")
	check(game.core.powered and game.structures.filter(func(b): return b.kind == "floodlight")[0].powered, "starting base has a working short-range generator/repeater network")
	var routes_ok := true
	for destination in [game.mission.beacon.position, game.mission.hive.position]:
		var route: PackedVector3Array = game.navigation.path(game.jeep.position, destination)
		if route.is_empty() or route[-1].distance_to(destination) > 1: routes_ok = false
	check(routes_ok, "both mission objectives are reachable through the real canyon map")
	var total := 0
	for patch in game.resource_nodes: total += int(patch.remaining)
	check(total == 8000 and game.resource_nodes.size() > 30, "single-cell patches preserve all six field yields")
	game.select_actor(game.core); game.scan()
	var patch: Dictionary = game.resource_at(game.DEPOSIT)
	check(patch.discovered and game.resource_fields.field_remaining(game, patch) == 1200, "scan reveals a whole field and inspection sums its patches")
	var worker: ExpeditionUnit = game.units[0]
	worker.cargo = 0; worker.mined_cargo = 0
	var extractor: ExpeditionStructure = game.add_structure("extractor", patch.position)
	extractor.powered = true
	check(game.resource_fields.harvest(game, worker, patch) == 3 and worker.cargo == 3, "powered extractor triples gathering for the same deposit")
	extractor.powered = false
	check(game.resource_fields.harvest(game, worker, patch) == 1, "unpowered extractor falls back to hand gathering")
	var boundary: Dictionary = game.rocks.filter(func(rock): return rock.position.length() < 50)[0]
	var neighbor: Vector3 = boundary.position + game.Terrain.direction(0) * game.Terrain.SPACING
	game.light.add_source(neighbor, 10)
	check(game.valid_site("wall", neighbor), "walls can be placed in the free cell beside natural terrain")
	check(not game.valid_site("wall", boundary.position), "terrain's own cell remains unbuildable")
	var generator: ExpeditionStructure = game.add_structure("generator", Vector3(-12, 0, -12))
	var relay: ExpeditionStructure = game.add_structure("repeater", generator.position + Vector3(3, 0, 0))
	var relay2: ExpeditionStructure = game.add_structure("repeater", relay.position + Vector3(8, 0, 0))
	game.power.tick(game.structures, game.economy, 0)
	check(relay.powered and relay2.powered and not game.Power.covers(generator, relay2.position), "repeaters extend beyond the two-tile generator range")
	game.select_actor(relay); game.toggle_repeater()
	check(not relay.powered and not relay.enabled, "turning a repeater off disconnects it")
	game.toggle_repeater()
	var jeep: ExpeditionUnit = game.jeep
	jeep.board(game.units[2]); jeep.position = Vector3(-10, 0, -20); jeep.battery = 50
	game.issue_order(jeep, "move", Vector3(-10, 0, -25)); game.advance_movement(1); game.vehicles.tick(game, 1)
	check(jeep.battery < 50, "driving drains vehicle batteries")
	jeep.position = relay.position; jeep.motion_velocity = Vector3.ZERO; game.vehicles.tick(game, 1)
	check(jeep.battery > 50, "a powered repeater recharges nearby vehicles")
	jeep.battery = 0; var before: Vector3 = jeep.position; jeep.tick_move(1)
	check(jeep.position == before and not jeep.headlight.visible, "an empty battery stops propulsion and headlights")
	var soldier: ExpeditionUnit = game.units[3]
	soldier.position = Vector3(-8, 0, -18)
	game.issue_order(soldier, "move", Vector3(-8, 0, -22))
	game.issue_order(soldier, "move", Vector3(-4, 0, -22), null, true)
	for i in range(90): game.advance_movement(0.05); game.process_order(soldier, 0.05); game.tactics.tick(game, 0.05)
	check(soldier.position.distance_to(Vector3(-4, 0, -22)) < 0.5 and soldier.order_queue.is_empty(), "shift orders execute in sequence")
	game.issue_order(soldier, "move", Vector3(-4, 0, -25), null, true)
	game.issue_order(soldier, "move", Vector3(-8, 0, -18))
	check(soldier.order_queue.is_empty(), "an immediate order clears the unit queue")
	game.issue_order(soldier, "patrol", Vector3(-12, 0, -18))
	game.issue_order(soldier, "patrol", Vector3(-12, 0, -24), null, true)
	check(soldier.patrol_points.size() == 3, "shift patrol adds points to a closed patrol route")
	game.issue_order(soldier, "defend", Vector3(-8, 0, -18))
	var enemy: ExpeditionPredator = game.add_creature(Vector3(-9, 0, -18), 99)
	game.light.add_source(enemy.position, 20)
	game.tactics.tick(game, 0.1)
	check(soldier.combat_target == enemy, "defenders acquire nearby visible threats")
	enemy.position = Vector3(-22, 0, -18); game.tactics.tick(game, 0.1)
	check(soldier.combat_target == null and soldier.goal.distance_to(soldier.defense_point) < 4, "defenders abandon pursuits beyond their leash and return")
	enemy.position = Vector3(-9, 0, -18)
	game.issue_order(soldier, "attack", enemy.position, enemy)
	var hp: float = enemy.hp; soldier.cooldown = 0
	game.tactics.tick(game, 0.1); game.combat_tick(0.1)
	check(enemy.hp < hp, "explicit infantry attack damages the selected visible enemy")
	enemy.hp = 0; game.cleanup_dead(); game.tactics.tick(game, 0.1)
	check(soldier.order == "idle", "destroyed attack targets safely complete their order")
	var drill: ExpeditionUnit = game.add_unit("drill", boundary.position + game.Terrain.direction(2) * 2.5)
	drill.board(game.add_unit("engineer", drill.position)); game.issue_order(drill, "drill", boundary.position)
	var fuel: float = game.economy.gas
	game.economy.gas = 4
	for i in range(31): game.vehicles.tick(game, 0.1)
	check(game.economy.gas == 4 and game.rocks.has(boundary), "drilling waits without charging partial methane when reserves are insufficient")
	game.economy.gas = fuel
	for i in range(31): game.vehicles.tick(game, 0.1)
	check(game.economy.gas == fuel - 5 and not game.rocks.has(boundary), "drilling consumes exactly five methane and removes one terrain cell")
	# Exercise actual construction/repair, carrying, timer resets, and victory.
	check(not game.mission.take(game, soldier), "the Hive Core cannot be stolen before extraction is repaired")
	worker.position = game.mission.beacon.position + Vector3(2, 0, 0)
	game.issue_order(worker, "build", game.mission.beacon.position, game.mission.beacon)
	for i in range(125): game.process_order(worker, 0.1)
	check(game.mission.beacon.complete, "an engineer repairs the ruined extraction beacon")
	soldier.position = game.mission.hive.position
	game.issue_order(soldier, "take_core", game.mission.item.position)
	game.mission.tick(game, 0.1)
	check(game.mission.stolen and game.mission.carrier == soldier, "infantry steal and carry the Hive Core after beacon repair")
	var retriever: ExpeditionPredator = game.add_creature(soldier.position + Vector3(6, 0, 0), 99)
	game.director.add_group(game.mission.hive.position, 99, 1)
	game.elapsed = 80; game.director.tick(game, 0.4)
	check(retriever.state == "assault" and retriever.target == soldier, "theft overrides probing and sends Lightless directly after the carrier")
	retriever.hp = 0; game.cleanup_dead(); game.director.groups.clear()
	soldier.position = game.mission.beacon.position; game.mission.tick(game, 4)
	check(game.mission.extraction == 4, "extraction advances while the carrier stays inside the radius")
	soldier.position += Vector3(12, 0, 0); game.mission.tick(game, 0.1)
	check(game.mission.extraction == 0, "leaving extraction resets its timer")
	soldier.position = game.mission.beacon.position; game.mission.tick(game, 4)
	game.mission.beacon.hp = 0; game.mission.tick(game, 0.1)
	check(not game.mission.beacon.complete and game.mission.extraction == 0 and game.structures.has(game.mission.beacon), "destroyed extraction beacon becomes repairable ruins and resets the timer")
	game.mission.beacon.complete = true; game.mission.beacon.hp = 280
	game.mission.tick(game, 30)
	check(game.ended and game.victorious, "holding the repaired beacon for a complete timer extracts the Hive Core")
	game.ended = false; game.victorious = false
	soldier.hp = 0; game.cleanup_dead()
	check(game.mission.dropped and not is_instance_valid(game.mission.carrier), "a dead carrier drops the core without leaving a dangling owner")
	enemy = game.add_creature(game.mission.item.position, 99)
	game.mission.tick(game, 0.1)
	check(game.ended and not game.victorious, "Lightless recovery of the dropped core ends the mission in defeat")
	print("MISSION_UPGRADE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
