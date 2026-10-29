extends SceneTree
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ", description)
	else: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func fixture():
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run()
	return game

func advance(game, seconds: float) -> void:
	for i in range(ceili(seconds / 0.1)):
		game.simulation_tick(0.1)
		if i % 20 == 0: await process_frame
		if game.ended: break

func release(game) -> void:
	game.queue_free(); await process_frame

func run_checks() -> void:
	await crew_checks()
	await economy_checks()
	await infrastructure_checks()
	await mission_checks()
	print("TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)

func crew_checks() -> void:
	var game = await fixture()
	var vehicle: ExpeditionUnit = game.jeep
	check(game.units.size() == 7 and game.structures.size() == 7, "starting expedition includes crew, stores, generation and production buildings")
	var initial := vehicle.position
	check(not game.set_order(vehicle, "move", initial + Vector3(10, 0, 0)), "unpiloted vehicle rejects movement orders")
	vehicle.tick_move(1)
	check(vehicle.position == initial and not vehicle.headlight.visible, "unpiloted vehicle stays still with graphical headlights off")
	vehicle.position = Vector3(35, 0, 26); game.rebuild_light()
	check(game.light.sample(vehicle.position) > 0 and game.light.deterrence(vehicle.position) == 0, "abandoned vehicle has a visible emergency beacon that does not deter creatures")
	check(game.light.sample(vehicle.position + Vector3.FORWARD * 12) == 0, "unpiloted vehicle has no forward gameplay illumination")
	check(vehicle.board(game.units[0]) and vehicle.driver == game.units[0], "first infantry boarder becomes driver")
	for i in range(1, 4): vehicle.board(game.units[i])
	check(vehicle.passengers.size() == 3 and vehicle.occupied_seats() == 4 and not vehicle.board(game.units[4]), "jeep holds one driver plus exactly three passengers")
	game.rebuild_light()
	check(vehicle.headlight.visible and game.light.sample(vehicle.position + Vector3.FORWARD * 12) > 0.5, "driver enables both graphical and gameplay headlights")
	game.select_actor(game.units[0])
	check(game.selected_engineers().is_empty(), "engineer cannot build or repair while driving")
	game.set_order(vehicle, "move", vehicle.position + Vector3(3, 0, 0))
	game.select_actor(vehicle); game.unload()
	check(vehicle.has_driver() and vehicle.passengers.is_empty() and vehicle.headlight.visible, "first U unloads passengers and retains the driver and headlights")
	check(not vehicle.moving(), "unloading stops the vehicle so passengers are not left behind by an active move order")
	check(game.selected.size() == 1 and game.selected[0] == vehicle, "jeep remains selected for a second unload press")
	game.unload()
	check(not vehicle.has_driver() and game.units[0].aboard == null and not vehicle.headlight.visible, "second U unloads driver and switches headlights off")
	check(vehicle.board(game.units[4]), "abandoned vehicle can be recovered by another infantry unit")
	var goal := vehicle.position + Vector3(-3.17, 0, -2.81)
	game.set_order(vehicle, "move", goal); game.accumulator = 0
	var before := vehicle.position; var time_before: float = game.elapsed
	game._process(1.0 / 120.0); var first := vehicle.position
	game._process(1.0 / 120.0)
	check(before.distance_to(first) > 0 and first.distance_to(vehicle.position) > 0 and game.elapsed == time_before, "vehicle movement remains continuous between logic ticks")
	check(absf(vehicle.visual.rotation.y) > 0 and absf(vehicle.visual.rotation.y) < 0.1, "vehicle turns gradually rather than snapping to grid headings")
	var scout: ExpeditionUnit = game.add_unit("scout", Vector3(30, 0, 25))
	check(scout.board(game.units[5]) and scout.seat_capacity() == 1 and not scout.board(game.units[1]), "scout has one pilot seat and no passenger seats")
	game.select_actor(scout); game.unload()
	check(not scout.has_driver(), "single-seat scout unloads its driver on first U")
	game.economy.gas = 0; game.power.tick(game.structures, game.economy, 0); game.rebuild_light()
	check(game.light.sample(game.core.position) > 0 and game.light.deterrence(game.core.position) == 0, "Command Center emergency light survives total grid fuel loss")
	await release(game)
	game = await fixture(); vehicle = game.jeep
	vehicle.board(game.units[0]); vehicle.board(game.units[1]); vehicle.hp = 0
	game.cleanup_dead(); game.rebuild_light()
	check(not game.units.has(vehicle) and game.units[0].aboard == null and game.units[1].aboard == null and game.units[0].hp > 0, "destroyed jeep ejects injured surviving crew")
	check(game.wrecks.size() == 1 and game.light.sample(vehicle.position) > 0, "wreck leaves a temporary fading emergency beacon")
	game.check_mission()
	check(not game.ended, "vehicle loss permits rescue and replacement rather than immediate defeat")
	await release(game)

func economy_checks() -> void:
	var game = await fixture()
	check(game.economy.minerals == 400 and is_equal_approx(game.economy.gas, 140.0), "starting global resources are already deposited")
	check(game.economy.mineral_capacity == 500 and game.economy.gas_capacity == 240, "mineral depot and gas tank add the correct global capacity")
	var worker: ExpeditionUnit = game.units[1]
	worker.cargo = 10; worker.mined_cargo = 10; worker.gas_cargo = 7
	var tank: ExpeditionStructure
	for b in game.structures:
		if b.kind == "gas_tank": tank = b
	game.deposit_cargo(worker, tank)
	check(worker.cargo == 10 and worker.gas_cargo == 0 and is_equal_approx(game.economy.gas, 147.0), "gas tank accepts gas but does not bank carried minerals")
	game.deposit_cargo(worker, game.home_depot)
	check(worker.cargo == 0 and game.economy.minerals == 410 and game.returned_materials == 10, "mineral depot banks minerals and records newly mined home deliveries")
	game.economy.gas = 0; var minerals_before: int = game.economy.minerals
	check(not game.economy.spend({"minerals": 20, "gas": 1}) and game.economy.minerals == minerals_before, "two-resource purchases are atomic when gas is insufficient")
	game.economy.gas = 100
	game.select_actor(worker)
	var point := HexPoint(game, game.HOME + Vector3(7, 0, -7))
	var site: ExpeditionStructure = game.order_build("repeater", point)
	check(site != null and game.economy.minerals == minerals_before - 15 and site.funded, "construction reserves global resources immediately without jeep material delivery")
	check(site != null and not game.navigation.blocked(site.position), "unbuilt blueprints do not act as instant physical blockades")
	await advance(game, 15)
	check(site != null and site.complete, "engineer must physically reach and construct globally funded site")
	check(site != null and game.navigation.blocked(site.position), "completed construction updates obstacle navigation")
	var barracks: ExpeditionStructure
	var garage: ExpeditionStructure
	for b in game.structures:
		if b.kind == "barracks": barracks = b
		if b.kind == "garage": garage = b
	game.select_actor(barracks)
	check(not game.train_unit("jeep"), "barracks cannot manufacture vehicles")
	var before_count: int = game.units.size()
	var paid_m: int = game.economy.minerals
	var paid_g: float = game.economy.gas
	check(game.train_unit("flamer") and game.economy.minerals == paid_m - 65 and is_equal_approx(game.economy.gas, paid_g - 20), "flamer training charges both minerals and gas")
	await advance(game, 12)
	check(game.units.size() == before_count + 1 and game.units.back().kind == "flamer", "barracks produces infantry after its queue timer")
	game.select_actor(garage); game.train_unit("scout")
	await advance(game, 11)
	check(game.units.back().kind == "scout" and not game.units.back().has_driver(), "garage produces an unpiloted scout")
	var refund_m: int = game.economy.minerals
	game.train_unit("scout"); game.cancel_training()
	check(game.economy.minerals == refund_m and garage.queue.is_empty(), "canceling a production order refunds its reservation once")
	game.home_depot.hp = 0; game.cleanup_dead(); game.economy.recalculate(game.structures)
	check(game.economy.mineral_capacity == 100 and game.economy.minerals > 100, "storage destruction reduces capacity while preserving already banked minerals")
	check(game.economy.deposit("minerals", 20) == 0, "over-capacity bank cannot accept further deliveries")
	await release(game)
	game = await fixture(); game.select_actor(game.core); game.scan(); game.select_actor(game.jeep)
	worker = game.units[1]
	worker.position = game.GAS_DEPOSIT
	worker.harvest_kind = "gas"; worker.harvest_origin = game.GAS_DEPOSIT
	game.jeep.position = game.GAS_DEPOSIT + Vector3(3, 0, 0)
	game.set_order(worker, "harvest", game.GAS_DEPOSIT)
	await advance(game, 16)
	check(game.jeep.gas_cargo >= 20 and game.economy.gas < 140, "gas is physically harvested into an unpiloted nearby carrier before being banked")
	game.jeep.board(game.units[4]); game.select_actor(game.jeep)
	var fuel_before: float = game.economy.gas
	game.stock_depot(); await advance(game, 20)
	check(game.jeep.gas_cargo == 0 and game.economy.gas > fuel_before + 17, "piloted gas shipment reaches a Gas Tank and replenishes global fuel reserves")
	await release(game)

func HexPoint(game, point: Vector3) -> Vector3:
	return game.Hex.snap(point, 2)

func infrastructure_checks() -> void:
	var game = await fixture()
	var generator: ExpeditionStructure = game.add_structure("generator", Vector3(-34, 0, -24))
	var relay: ExpeditionStructure = game.add_structure("repeater", Vector3(-6, 0, -24))
	var lamp: ExpeditionStructure = game.add_structure("floodlight", Vector3(22, 0, -24))
	var grid: Array = [generator, relay, lamp]
	game.economy.gas = 20; game.power.tick(grid, game.economy, 1)
	check(lamp.powered and game.power.used == 2 and is_equal_approx(game.economy.gas, 19.95), "repeater distributes generator power with gas consumption proportional to served demand")
	relay.hp = 0; var gas_before: float = game.economy.gas
	game.power.tick(grid, game.economy, 1)
	check(not lamp.powered and is_equal_approx(game.economy.gas, gas_before), "severed repeater disconnects spotlight and idle generation wastes no gas")
	var scanner: ExpeditionStructure = game.add_structure("scanner", generator.position + Vector3(8, 0, 0))
	var predator: ExpeditionPredator = game.add_creature(generator.position + Vector3(18, 0, 0), 8)
	game.power.tick([generator, scanner], game.economy, 0); game.rebuild_light(); game.update_scanner_contacts()
	check(scanner.powered and game.sensor_blips.size() > 0, "powered scanner detects hidden enemies as approximate tile contacts")
	check(game.light.sample(predator.position) == 0 and game.visible_target(predator.position + Vector3(0, 0, 4), 12) == null, "scanner contacts do not illuminate creatures or allow weapon targeting")
	var gate: ExpeditionStructure = game.add_structure("gate", generator.position + Vector3(2, 0, 0))
	game.power.tick([generator, gate], game.economy, 0)
	check(game.set_gate(gate, true) and gate.gate_open and not game.navigation.blocked(gate.position), "powered gate opens and updates walkable navigation")
	gate.powered = false
	check(not game.set_gate(gate, false), "unpowered gate cannot close itself electrically")
	var engineer: ExpeditionUnit = game.units[1]
	engineer.position = gate.position + Vector3(3, 0, 0)
	game.set_order(engineer, "close_gate", gate.position, gate)
	# Keep its local power source disabled so this exercises the manual path.
	generator.enabled = false
	await advance(game, 3)
	check(not gate.gate_open and game.navigation.blocked(gate.position), "engineer manually closes an unpowered gate after reaching it")
	await release(game)

func mission_checks() -> void:
	var game = await fixture()
	game.select_actor(game.core); game.scan(); game.select_actor(game.jeep); game.board_squad()
	await advance(game, 15)
	check(game.jeep.has_driver() and game.jeep.passengers.size() == 3, "expedition crew physically boards one driver and three passengers")
	game.set_order(game.jeep, "move", game.DEPOSIT + Vector3(0, 0, 5))
	await advance(game, 14)
	check(game.jeep.position.distance_to(game.DEPOSIT) < 7, "piloted expedition travels smoothly to the mineral signal")
	# Canyon routing changes the arrival heading. Face the parked headlights
	# toward the work site before testing illuminated construction placement.
	game.jeep.facing = (game.DEPOSIT + Vector3(-3.5, 0, 3) - game.jeep.position).normalized()
	game.jeep.desired_yaw = atan2(-game.jeep.facing.x, -game.jeep.facing.z)
	game.jeep.visual.rotation.y = game.jeep.desired_yaw
	game.rebuild_light()
	game.select_actor(game.jeep); game.unload()
	var engineer: ExpeditionUnit
	for unit in game.units:
		if unit.kind == "engineer" and unit.aboard == null: engineer = unit; break
	check(game.jeep.has_driver() and engineer != null, "ground engineer can work while another crew member remains as driver")
	if engineer == null: await release(game); return
	game.select_actor(engineer)
	var generator: ExpeditionStructure = game.order_build("generator", game.DEPOSIT + Vector3(-3.5, 0, 3))
	check(generator != null, "expedition can fund a remote generator from global resources")
	if generator == null: await release(game); return
	await advance(game, 16)
	var lamp: ExpeditionStructure = game.order_build("floodlight", game.DEPOSIT)
	check(lamp != null, "engineer can place a spotlight within the new generator network")
	if lamp == null: await release(game); return
	# Allow the explicit follow-up job to complete at the mining perimeter.
	await advance(game, 24)
	check(generator.complete and lamp.complete and lamp.powered and game.outpost_established, "generator and spotlight establish an operating mining perimeter")
	engineer.harvest_kind = "minerals"; engineer.harvest_origin = game.DEPOSIT
	game.set_order(engineer, "harvest", game.DEPOSIT)
	# Wait for two physical batches, including any approach to the deposit.
	for i in range(80):
		await advance(game, 1)
		if game.jeep.mined_cargo >= 30 or game.ended: break
	check(game.jeep.mined_cargo >= 30, "engineer harvests physical minerals and transfers batches into the nearby jeep")
	game.select_actor(game.jeep); game.return_home()
	await advance(game, 20)
	check(game.ended and game.victorious and game.returned_materials >= 30, "new two-resource expedition can return fresh minerals and win")
	await release(game)
