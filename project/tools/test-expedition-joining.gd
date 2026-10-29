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
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.minimap.set_process(false); game.begin_run(); game.audio_enabled = false
	game.rocks.clear(); game.rebuild_navigation()
	var command = game.complex_commands
	var resource: Dictionary = game.resource_at(game.DEPOSIT)
	resource.discovered = true; resource.remaining = 10000
	# Compare the whole batch once; do not distribute selected friends one at a time.
	var first: Array = []
	for kind in ["engineer", "marine", "flamer"]: first.append(game.add_unit(kind, resource.position + Vector3(0, 0, 8 + first.size() * 2)))
	command.start_expedition(game, first, resource)
	var larger: Dictionary = command.foot.groups[-1]
	var worker: ExpeditionUnit = game.add_unit("engineer", resource.position + Vector3(8, 0, 8))
	command.start_expedition(game, [worker], resource)
	var smaller: Dictionary = command.foot.groups[-1]
	var engineer: ExpeditionUnit = game.add_unit("engineer", resource.position + Vector3(-8, 0, 8))
	var marine: ExpeditionUnit = game.add_unit("marine", engineer.position + Vector3(2, 0, 0))
	game.selected.assign([engineer, marine]); game.focus = resource.position; game.update_camera()
	await game.contextual_order(game.camera.unproject_position(resource.position))
	check(smaller.members.has(engineer) and smaller.members.has(marine) and larger.members.size() == 3 and command.foot.groups.size() == 2, "right-clicking a patch puts the entire selected batch in the smallest attached expedition")
	check(engineer.complex_id == smaller.id and marine.complex_id == smaller.id, "reinforcements share existing membership rather than creating a separate expedition")
	await step(game, 3)
	check(engineer.order == "convoy_foot_gather" and marine.order.begins_with("convoy_foot_"), "joined engineers gather and infantry guard through the normal expedition controller")
	# A member click selects that expedition even if another is smaller.
	var heavy: ExpeditionUnit = game.add_unit("flamer", resource.position + Vector3(-12, 0, 8))
	game.select_actor(heavy); game.focus = worker.position; game.update_camera()
	await game.contextual_order(game.camera.unproject_position(worker.position + Vector3(0, 1.9, 0)))
	check(heavy.complex_id == smaller.id and smaller.members.has(heavy), "right-clicking an expedition member joins its specific expedition")
	var size: int = smaller.members.size()
	command.join_member(game, [heavy], worker)
	check(smaller.members.size() == size, "joining the same expedition again does not duplicate members or restart it")
	# Transfer selected units only, leaving the rest of the original party running.
	var old_id: int = larger.id
	command.join_member(game, [first[1]], worker)
	check(first[1].complex_id == smaller.id and not larger.members.has(first[1]) and first[0].complex_id == old_id and first[2].complex_id == old_id, "transferring one expedition member leaves its unselected companions in their original expedition")
	# Do not reset an active delivery when a worker joins.
	smaller.phase = "return"; worker.cargo = 2
	var later: ExpeditionUnit = game.add_unit("engineer", worker.position + Vector3(4, 0, 0))
	command.join_member(game, [later], worker)
	check(smaller.phase == "return" and worker.cargo == 2 and later.complex_id == smaller.id, "joining a delivery expedition preserves its phase and existing cargo")
	for group in command.foot.groups.duplicate(): command.foot.finish(group)
	# Preserve exploration progress and prefer new engineers for empty seats.
	var jeep: ExpeditionUnit = game.add_unit("jeep", Vector3(8, 0, -20))
	var pilot: ExpeditionUnit = game.add_unit("marine", jeep.position + Vector3(1, 0, 0))
	command.start_expedition(game, [jeep, pilot], {}, Vector3(25, 0, -20))
	await step(game, 2)
	var exploration: Dictionary = command.exploration.groups[-1]
	var route: PackedVector3Array = exploration.route.duplicate()
	var index: int = exploration.index
	var recruit: ExpeditionUnit = game.add_unit("engineer", jeep.position + Vector3(2, 0, 0))
	var passenger: ExpeditionUnit = game.add_unit("engineer", jeep.position + Vector3(3, 0, 0))
	game.selected.assign([recruit, passenger]); game.focus = jeep.position; game.update_camera()
	var hood: Vector2 = game.camera.unproject_position(jeep.visual.to_global(Vector3(0, 1.1, -1)))
	check(await game.pick(hood) == jeep, "reinforcement click hits the exploring jeep's visible model")
	await game.contextual_order(hood)
	check(recruit.complex_id == exploration.id and passenger.complex_id == exploration.id and exploration.route == route and exploration.index == index, "right-clicking an exploring vehicle joins its expedition without resetting the route")
	await step(game, 3)
	check(jeep.driver == recruit and passenger.aboard == jeep and pilot.aboard == null, "joining exploration applies engineer driver and passenger priorities")
	var scout: ExpeditionUnit = game.add_unit("scout", jeep.position + Vector3(0, 0, 4))
	var scout_driver: ExpeditionUnit = game.add_unit("engineer", scout.position + Vector3(1, 0, 0))
	command.join_member(game, [scout, scout_driver], jeep)
	await step(game, 3)
	check(scout.complex_id == exploration.id and scout.has_driver() and exploration.vehicles.has(scout), "a vehicle and crew can reinforce an exploration expedition")
	var released: Array = exploration.members.filter(func(unit): return exploration.seats.get(unit) == jeep)
	game.set_order(jeep, "move", jeep.position + Vector3(5, 0, 0))
	check(released.all(func(unit): return unit.complex_id == 0) and scout.complex_id == exploration.id, "later direct orders still permanently detach reinforced vehicle crews")
	for group in command.exploration.groups.duplicate(): command.exploration.finish(group)
	# Mining convoy member joins must keep its existing work phase and pilot.
	var truck: ExpeditionUnit = game.add_unit("jeep", Vector3(12, 0, -10))
	var driver: ExpeditionUnit = game.add_unit("marine", truck.position)
	var miner: ExpeditionUnit = game.add_unit("engineer", truck.position + Vector3(1, 0, 0))
	command.start_expedition(game, [truck, driver, miner], resource)
	var convoy: Dictionary = command.groups[-1]
	await step(game, 1)
	var phase: String = convoy.phase
	var builder: ExpeditionUnit = game.add_unit("engineer", truck.position + Vector3(1, 0, 0))
	command.join_member(game, [builder], truck)
	check(convoy.members.has(builder) and builder.complex_id == convoy.id and convoy.phase == phase and convoy.driver == driver, "a new worker joins the existing mining convoy without restarting its work cycle")
	# New haulers remain one logical expedition for subsequent member/patch joins.
	var extra: ExpeditionUnit = game.add_unit("jeep", truck.position + Vector3(0, 0, 5))
	var extra_driver: ExpeditionUnit = game.add_unit("marine", extra.position)
	var extra_worker: ExpeditionUnit = game.add_unit("engineer", extra.position + Vector3(1, 0, 0))
	command.join_member(game, [extra, extra_driver, extra_worker], truck)
	var whole: Array = command.expedition_selection([truck])
	check(whole.has(extra) and whole.has(extra_driver) and whole.has(extra_worker) and whole.has(builder), "an added hauler and selected crew belong to the same logical mining expedition")
	var support: ExpeditionUnit = game.add_unit("scout", truck.position + Vector3(0, 0, -5))
	var support_driver: ExpeditionUnit = game.add_unit("marine", support.position)
	command.join_member(game, [support, support_driver], truck)
	check(command.scouts.groups.size() == 1 and command.expedition_selection([support]).has(extra), "a mining scout and pilot join and link to the existing haulers")
	var support_guard: ExpeditionUnit = game.add_unit("flamer", support.position + Vector3(3, 0, 0))
	command.join_member(game, [support_guard], support)
	check(command.expedition_selection([support]).has(support_guard) and support_guard.complex_id != 0, "right-clicking a mining perimeter scout joins its associated expedition")
	await step(game, 15)
	check(truck.has_driver() and extra.has_driver() and support.has_driver() and command.expedition_selection([support]).has(support_guard), "reinforced haulers and perimeter support board their crews and remain active together")
	var small_worker: ExpeditionUnit = game.add_unit("engineer", resource.position + Vector3(-12, 0, -4))
	command.start_expedition(game, [small_worker], resource)
	var small_party: Dictionary = command.foot.groups[-1]
	var batch: Array = []
	for i in range(3): batch.append(game.add_unit("marine", resource.position + Vector3(-12 - i * 2, 0, -8)))
	command.join_resource(game, batch, resource)
	check(batch.all(func(unit): return unit.complex_id == small_party.id) and not command.expedition_selection([truck]).has(batch[0]), "patch balancing counts the linked haulers and perimeter crew together and keeps a selected batch in the smaller expedition")
	# Reject insufficient vehicle crew before touching either expedition.
	var empty: ExpeditionUnit = game.add_unit("scout", Vector3(40, 0, -30))
	var lone: ExpeditionUnit = game.add_unit("engineer", empty.position + Vector3(1, 0, 0))
	command.start_expedition(game, [lone], game.resource_at(game.GAS_DEPOSIT).merged({"discovered": true}))
	var gas_id: int = lone.complex_id
	command.join_member(game, [empty], lone)
	check(lone.complex_id == gas_id and empty.complex_id == 0 and empty.order == "idle", "an undercrewed vehicle cannot consume the expedition's only miner")
	check(not command.join_resource(game, [empty], {}) and not command.join_resource(game, [empty], {"discovered": false, "remaining": 10}), "empty or unscanned patches do not capture normal right-click orders")
	print("EXPEDITION_JOINING_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
