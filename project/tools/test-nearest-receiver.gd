extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func scenario(kind: String, on_foot: bool) -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run(); game.audio_enabled = false
	game.rocks.clear(); game.rebuild_navigation()
	var command = game.complex_commands
	var resource: Dictionary = game.resource_at(game.GAS_DEPOSIT if kind == "gas" else game.DEPOSIT)
	resource.discovered = true; resource.remaining = 200
	var local: ExpeditionStructure = game.add_structure("gas_tank" if kind == "gas" else "depot", resource.position + Vector3(7, 0, 0), false)
	var worker: ExpeditionUnit = game.add_unit("engineer", resource.position + Vector3(-1, 0, -2))
	var carrier := worker
	var crew: Array = [worker]
	var truck: ExpeditionUnit
	if not on_foot:
		truck = game.add_unit("jeep", resource.position + Vector3(0, 0, -2)); carrier = truck
		crew.append(truck); crew.append(game.add_unit("marine", truck.position + Vector3(1, 0, 0)))
	check(command.start_expedition(game, crew, resource), "%s expedition starts for %s delivery" % ["on-foot" if on_foot else "vehicle", kind])
	var group: Dictionary = command.foot.groups[-1] if on_foot else command.groups[-1]
	if not on_foot:
		truck.board(group.driver); truck.board(worker)
		group.leg = "return"; group.receiver = game.find_receiver(carrier.position, kind, true)
	group.phase = "return"
	if kind == "gas": carrier.gas_cargo = 5
	else: carrier.cargo = 5; carrier.mined_cargo = 5
	game.economy.minerals = 0; game.economy.gas = 0
	var home: ExpeditionStructure = game.find_receiver(carrier.position, kind, true)
	command.tick(game, 0.1)
	var chosen: ExpeditionStructure = worker.target if on_foot else group.receiver
	check(chosen == home, "unfinished %s receiver is ignored" % kind)
	# Finish the outpost receiver after the expedition has already started home.
	local.complete = true; local.funded = true
	game.rebuild_navigation(); game.economy.recalculate(game.structures)
	command.tick(game, 0.1)
	chosen = worker.target if on_foot else group.receiver
	check(chosen == local, "%s expedition switches to a newly completed nearby %s receiver during its return" % ["on-foot" if on_foot else "vehicle", kind])
	local.hp = 0; command.tick(game, 0.1)
	chosen = worker.target if on_foot else group.receiver
	check(chosen == home, "destroyed %s receiver is skipped in favor of the next suitable receiver" % kind)
	local.hp = game.Rules.STRUCTURES[local.kind].hp; command.tick(game, 0.1)
	var stayed_local := true
	for i in range(100):
		game.advance_movement(0.1); command.tick(game, 0.1)
		if carrier.position.distance_to(resource.position) > 16: stayed_local = false
		if carrier.cargo_total() == 0: break
		if i % 25 == 0: await process_frame
	var deposited: float = game.economy.gas if kind == "gas" else game.economy.minerals
	check(carrier.cargo_total() == 0 and deposited == 5 and stayed_local, "%s expedition deposits %s at the outpost without travelling to HQ" % ["on-foot" if on_foot else "vehicle", kind])
	if not on_foot: check(truck.has_driver() and worker.aboard == truck and truck.complex_id != 0, "local delivery preserves the vehicle crew and repeating expedition")
	if kind == "minerals": check(game.returned_materials == 0, "outpost deposits do not count as a physical HQ return for the mission")
	# Explicit home-return orders retain their intended destination.
	check(game.find_receiver(carrier.position, kind, true) == home and game.find_receiver(carrier.position, kind) == local, "nearest-receiver selection and explicit HQ-return selection remain distinct")
	game.queue_free(); await process_frame

func run() -> void:
	for kind in ["gas", "minerals"]:
		await scenario(kind, true)
		await scenario(kind, false)
	print("NEAREST_RECEIVER_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
