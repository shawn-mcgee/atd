extends SceneTree
var failures := 0
var depot_checks := 0
var crew_stayed_aboard := true

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		var depot_crews: Array = []
		for group in game.complex_commands.groups:
			if group.phase == "return":
				depot_crews.append({"vehicle": group.vehicle, "crew": group.vehicle.passengers.duplicate() + [group.vehicle.driver]})
		game.advance_movement(0.1)
		game.complex_commands.tick(game, 0.1)
		for snapshot in depot_crews:
			depot_checks += 1
			for unit in snapshot.crew:
				if is_instance_valid(unit) and unit.aboard != snapshot.vehicle: crew_stayed_aboard = false
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.begin_run(); game.select_actor(game.core); game.light.add_source(game.DEPOSIT, 8); game.light.add_source(game.GAS_DEPOSIT, 8); game.resource_fields.discover(game); game.select_actor(game.jeep)
	game.rocks.clear(); game.rebuild_navigation()
	var jeep: ExpeditionUnit = game.add_unit("jeep", Vector3(7, 0, -8))
	jeep.capacity = 6
	var crew: Array = []
	for kind in ["engineer", "flamer", "marine", "engineer", "marine", "flamer", "engineer"]:
		crew.append(game.add_unit(kind, jeep.position + Vector3(crew.size() * 0.6, 0, 3)))
	var selection: Array[Node3D] = [jeep]
	selection.append_array(crew)
	game.selected = selection
	await game.contextual_order(game.camera.unproject_position(game.DEPOSIT))
	check(game.complex_commands.groups.size() == 1 and game.complex_commands.groups[0].mode == "travel", "ordinary mixed-selection resource click transports without starting gathering")
	game.complex_commands.interrupt(jeep)
	game.choose_expedition(true)
	await game.expedition_click(game.camera.unproject_position(game.DEPOSIT))
	check(game.complex_commands.groups.size() == 1 and game.complex_commands.groups[0].mode == "gather", "explicit expedition targeting starts a gathering mission")
	if game.complex_commands.groups.is_empty(): quit(1); return
	var group: Dictionary = game.complex_commands.groups[0]
	check(group.driver == crew[2], "a marine drives before surplus engineers and flamers on mining expeditions")
	check(group.riders.has(crew[0]) and group.riders.has(crew[3]) and group.riders.has(crew[6]), "working engineers take passenger seats before remaining marines")
	check(not group.riders.has(crew[1]) and not group.riders.has(crew[5]), "flamers become walking escorts first")
	for i in range(300):
		await step(game, 0.1)
		if group.phase == "work": break
	check(group.phase == "work", "crew boards, travels and begins gathering")
	await step(game, 0.1)
	check(jeep.driver == crew[2] and crew[0].aboard == null and crew[3].aboard == null, "marine driver remains aboard while working engineers dismount")
	check(crew[1].order == "convoy_patrol", "dismounted infantry patrol the resource patch")
	game.set_order(crew[6], "move", Vector3(3, 0, -20))
	check(crew[6].complex_id == 0 and not group.members.has(crew[6]), "direct unit orders immediately detach that unit")
	var before: int = game.returned_materials
	await step(game, 170)
	check(game.returned_materials > before + jeep.capacity, "convoy repeats trips and returns multiple loads of real mined cargo")
	check(depot_checks > 0 and crew_stayed_aboard, "driver and passengers stay aboard throughout deposits and departure on repeat trips")
	check(game.complex_commands.groups.size() == 1, "expedition remains active for repeat trips")
	check(crew[6].order == "move" and crew[6].aboard == null and crew[6].complex_id == 0, "detached engineer never rejoins subsequent boarding cycles")
	game.select_actor(jeep); game.stop_selected()
	check(game.complex_commands.groups.is_empty() and jeep.complex_id == 0, "stopping the jeep cancels its expedition")
	for unit in crew: check(unit.complex_id == 0, "cancelled expedition releases crew membership")
	# Driver fallback and passenger/escort ranking without marines.
	var other: ExpeditionUnit = game.add_unit("jeep", Vector3(4, 0, -8))
	var second: Array = [other, game.add_unit("engineer", other.position + Vector3.RIGHT * 3), game.add_unit("flamer", other.position + Vector3.RIGHT * 4)]
	check(game.complex_commands.start(game, second, game.resource_at(game.DEPOSIT)), "expedition can start with a flamer driver")
	group = game.complex_commands.groups[0]
	check(group.driver.kind == "flamer", "the sole engineer stays available to mine while the heavy flamer drives")
	game.select_actor(other); game.unload()
	check(game.complex_commands.groups.is_empty(), "manual unloading cancels automation")
	var task_jeep: ExpeditionUnit = game.add_unit("jeep", Vector3(10, 0, 15))
	var builder: ExpeditionUnit = game.add_unit("engineer", Vector3(12, 0, 15))
	var soldier: ExpeditionUnit = game.add_unit("marine", Vector3(13, 0, 15))
	var defender: ExpeditionUnit = game.add_unit("flamer", Vector3(14, 0, 15))
	var wall: ExpeditionStructure = game.add_structure("wall", Vector3(23, 0, 15))
	wall.hp -= 30
	var health := wall.hp
	game.complex_commands.start(game, [task_jeep, builder, soldier, defender], {}, wall)
	group = game.complex_commands.groups[0]
	for i in range(300):
		await step(game, 0.1)
		if group.phase == "work": break
	await step(game, 2)
	check(wall.hp > health, "structure task transports engineers and repairs damage using minerals")
	check(defender.order == "convoy_defend" and builder.aboard == null and task_jeep.has_driver(), "structure task unloads workers and assigns infantry to defend")
	var nearby: ExpeditionStructure = game.add_structure("wall", Vector3(29, 0, 15))
	nearby.hp -= 16
	var blueprint: ExpeditionStructure = game.add_structure("wall", Vector3(29, 0, 21))
	blueprint.complete = false; blueprint.progress = 0
	game.rebuild_navigation()
	var distant: ExpeditionStructure = game.add_structure("wall", Vector3(43, 0, -25))
	distant.hp -= 20
	await step(game, 140)
	check(nearby.hp == game.Rules.STRUCTURES.wall.hp and blueprint.complete, "maintenance crew chains nearby repairs and unfinished construction")
	check(distant.hp == game.Rules.STRUCTURES.wall.hp - 20, "maintenance search respects its local range")
	check(game.complex_commands.groups.is_empty() and task_jeep.position.distance_to(blueprint.position) < 5 and builder.order == "idle" and not builder.moving(), "crew holds at the final maintenance site when nearby work is finished")
	# A terrain command preserves the existing driver and passengers throughout.
	game.complex_commands.interrupt(task_jeep)
	task_jeep.board(builder); task_jeep.board(defender)
	var driver: ExpeditionUnit = task_jeep.driver
	game.complex_commands.start(game, [task_jeep, crew[1]], {}, null, Vector3(30, 0, 23))
	var remained_aboard := true
	for i in range(300):
		await step(game, 0.1)
		if builder.aboard != task_jeep or defender.aboard != task_jeep or task_jeep.driver != driver: remained_aboard = false
	check(remained_aboard, "terrain command never unloads existing passengers or swaps the driver")
	check(task_jeep.position.distance_to(Vector3(30, 0, 23)) < 1.0, "terrain convoy navigates to its destination")
	game.complex_commands.interrupt(task_jeep)
	var escort: ExpeditionUnit = game.add_unit("engineer", task_jeep.position + Vector3(0, 0, 4))
	game.set_order(escort, "escort", task_jeep.position, task_jeep)
	game.set_order(task_jeep, "move", Vector3(37, 0, 23))
	game.advance_movement(0.1)
	check(is_equal_approx(task_jeep.escort_speed_limit, 3.1) and task_jeep.motion_velocity.length() <= 3.1001, "ordinary jeep escort limits vehicle motion to the slowest escort speed")
	game.set_order(escort, "move", escort.position + Vector3(0, 0, 5))
	game.advance_movement(0.1)
	check(is_inf(task_jeep.escort_speed_limit) and task_jeep.motion_velocity.length() > 3.1, "vehicle regains normal speed when its escort is reassigned")
	var lone: ExpeditionUnit = game.add_unit("engineer", Vector3(28, 0, 15))
	nearby.hp -= 8; blueprint.hp -= 8
	game.continue_maintenance(lone, wall)
	check(lone.order == "repair" and lone.target == nearby, "standalone engineers also seek nearby maintenance after finishing a task")
	var gas_truck: ExpeditionUnit = game.add_unit("jeep", game.GAS_DEPOSIT + Vector3(-5, 0, 0))
	var gas_worker: ExpeditionUnit = game.add_unit("engineer", gas_truck.position + Vector3(0, 0, 3))
	var gas_driver: ExpeditionUnit = game.add_unit("marine", gas_truck.position + Vector3(1, 0, 3))
	var gas: Dictionary = game.resource_at(game.GAS_DEPOSIT)
	gas.remaining = 3; game.economy.gas = game.economy.gas_capacity
	game.complex_commands.start(game, [gas_truck, gas_worker, gas_driver], gas)
	await step(game, 100)
	check(gas.remaining == 0 and gas_truck.gas_cargo + gas_worker.gas_cargo == 3 and gas_truck.complex_id == 0 and not gas_truck.has_driver() and gas_worker.aboard == null, "full target storage ends the expedition at HQ, unloading crew and retaining undeliverable gas")
	game.economy.gas -= 3
	gas_truck.board(gas_driver)
	var tank: ExpeditionStructure = game.find_receiver(gas_truck.position, "gas", true)
	game.set_order(gas_truck, "deliver", tank.position, tank)
	game.set_order(gas_worker, "stock", tank.position, tank)
	for i in range(200):
		game.advance_movement(0.1); game.process_order(gas_truck, 0.1); game.process_order(gas_worker, 0.1)
	check(gas_truck.gas_cargo == 0 and gas_worker.gas_cargo == 0, "retained cargo can be delivered manually after storage becomes available")
	var packed: ExpeditionUnit = game.add_unit("jeep", Vector3(7, 0, -8))
	var pilot: ExpeditionUnit = game.add_unit("marine", packed.position)
	var worker: ExpeditionUnit = game.add_unit("engineer", packed.position)
	packed.board(pilot); packed.board(worker)
	game.select_actor(packed)
	check(game.context_buttons.mining.visible, "packed jeep alone exposes the expedition button using its existing crew")
	await game.contextual_order(game.camera.unproject_position(game.DEPOSIT))
	check(packed.complex_id == 0 and packed.order == "move" and worker.aboard == packed, "ordinary packed-jeep right-click remains a move with passengers aboard")
	game.context_buttons.mining.pressed.emit()
	check(game.expedition_mode and packed.complex_id == 0, "expedition button arms targeting without issuing a command")
	await game.expedition_click(Vector2(-100000, -100000))
	check(game.expedition_mode and packed.complex_id == 0, "invalid expedition target keeps targeting active without changing existing orders")
	var cancel := InputEventKey.new(); cancel.keycode = KEY_ESCAPE; cancel.pressed = true
	game._unhandled_input(cancel)
	check(not game.expedition_mode and packed.order == "move", "Escape cancels expedition targeting without redirecting the jeep")
	var key := InputEventKey.new(); key.keycode = KEY_M; key.pressed = true
	game._unhandled_input(key)
	check(game.expedition_mode, "M hotkey arms expedition targeting for a selected packed jeep")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	game._unhandled_input(escape)
	check(not game.expedition_mode and game.selected.size() == 1 and game.selected[0] == packed, "Escape cancels expedition targeting while preserving selection")
	game._unhandled_input(key)
	await game.expedition_click(game.camera.unproject_position(game.DEPOSIT))
	check(not game.expedition_mode and packed.complex_id != 0 and game.complex_commands.groups[-1].members.has(worker), "packed jeep expedition includes its onboard engineer without selecting hidden passengers")
	game.choose_expedition(true); game.select_actor(pilot)
	check(not game.expedition_mode, "changing selection cancels expedition targeting")
	print("COMPLEX_COMMAND_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
