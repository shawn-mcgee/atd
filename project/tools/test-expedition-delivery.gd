extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")

func scenario(kind: String, mineral_room: int, gas_room: int, minerals: int, gas: int, stop_at_home: bool) -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run(); game.rocks.clear(); game.rebuild_navigation()
	game.economy.minerals = game.economy.mineral_capacity - mineral_room
	game.economy.gas = game.economy.gas_capacity - gas_room
	var initial_m: int = game.economy.minerals; var initial_g: float = game.economy.gas
	var truck: ExpeditionUnit = game.add_unit("jeep", Vector3(0, 0, -12))
	var driver: ExpeditionUnit = game.add_unit("marine", truck.position + Vector3(1, 0, 2))
	var worker: ExpeditionUnit = game.add_unit("engineer", truck.position + Vector3(-1, 0, 2))
	var resource: Dictionary = game.resource_at(game.DEPOSIT if kind == "minerals" else game.GAS_DEPOSIT)
	game.complex_commands.start(game, [truck, driver, worker], resource)
	var group: Dictionary = game.complex_commands.groups[0]
	truck.cargo = minerals; truck.mined_cargo = minerals; truck.gas_cargo = gas
	game.complex_commands.assemble(game, group, "return")
	var receivers: Dictionary = {}
	for i in range(600):
		game.advance_movement(0.1); game.complex_commands.tick(game, 0.1)
		if group.phase == "return" and is_instance_valid(group.receiver): receivers[group.receiver.kind] = true
		if truck.complex_id == 0: break
		if not stop_at_home and group.phase == "outbound": break
		if i % 100 == 0: await process_frame
	check(game.economy.minerals == initial_m + mini(mineral_room, minerals) and is_equal_approx(game.economy.gas, initial_g + mini(gas_room, gas)), "%s expedition independently delivers both cargo types into available storage" % kind)
	check(truck.cargo + worker.cargo == minerals - mini(mineral_room, minerals) and truck.gas_cargo + worker.gas_cargo == gas - mini(gas_room, gas), "undeliverable cargo is conserved rather than dropped")
	if mineral_room > 0 and gas_room > 0: check(receivers.has("depot") and receivers.has("gas_tank"), "mixed return visits both receiving structures even after one resource fills")
	if stop_at_home:
		check(truck.complex_id == 0 and not truck.has_driver() and worker.aboard == null and driver.aboard == null and truck.position.distance_to(game.HOME) < 16, "full expedition resource ends at HQ with the crew safely unloaded")
	else:
		check(truck.complex_id != 0 and group.phase == "outbound" and worker.aboard == truck, "full incidental resource does not block repeat trips for the expedition resource")
	game.queue_free(); await process_frame

func run() -> void:
	await scenario("minerals", 0, 10, 7, 8, true)
	await scenario("gas", 10, 0, 8, 6, true)
	await scenario("minerals", 2, 3, 5, 7, true)
	await scenario("minerals", 100, 0, 5, 5, false)
	print("EXPEDITION_DELIVERY_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
