extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.begin_run(); game.audio_enabled = false
	game.rocks.clear(); game.rebuild_navigation(); game.economy.minerals = 0
	var command = game.complex_commands
	var resource: Dictionary = game.resource_at(game.DEPOSIT); resource.discovered = true; resource.remaining = 5000
	var scout: ExpeditionUnit = game.add_unit("scout", resource.position + Vector3(-12, 0, 0))
	var miner: ExpeditionUnit = game.add_unit("engineer", resource.position + Vector3(-3, 0, 0))
	var pilot: ExpeditionUnit = game.add_unit("marine", scout.position + Vector3(0, 0, 1))
	var heavy: ExpeditionUnit = game.add_unit("flamer", scout.position + Vector3(0, 0, 2))
	check(command.start_expedition(game, [scout, miner, heavy, pilot], resource), "a mining expedition accepts a scout alongside on-foot miners")
	check(command.scouts.groups.size() == 1 and command.scouts.groups[0].driver == pilot and command.foot.groups[0].members.has(miner), "scout receives the marine pilot while the engineer remains a miner")
	var goals: Dictionary = {}
	var watching := false
	var stayed_near := true
	var remaining: int = resource.remaining
	for i in range(650):
		game.advance_movement(0.1); command.tick(game, 0.1); game.rebuild_light()
		if scout.order == "convoy_scout_patrol":
			goals[scout.goal] = true
			if scout.position.distance_to(resource.position) < 11: watching = true
			if watching and scout.position.distance_to(resource.position) > 16: stayed_near = false
		if i % 100 == 0: await process_frame
	check(scout.driver == pilot and goals.size() >= 5 and watching and stayed_near, "crewed scout visits stable perimeter points and stays near its mining patch")
	check(resource.remaining < remaining and miner.aboard == null, "perimeter support allows engineers to keep gathering and delivering")
	var enemy: ExpeditionPredator = game.add_creature(scout.position - scout.facing * 18, 99)
	game.rebuild_light(); game.update_scanner_contacts(); game.refresh_ui()
	check(game.sensor_blips.any(func(blip): return game.Hex.to_axial(blip.position, preload("res://scripts/expedition_terrain.gd").CELL) == game.Hex.to_axial(enemy.position, preload("res://scripts/expedition_terrain.gd").CELL)), "scout scanner reports nearby threats as approximate tile contacts")
	check(game.light.sample(enemy.position) < 0.065 and game.visible_target(enemy.position, 0.1) == null, "scanning a hidden threat does not reveal it for combat")
	var expanded: Array = command.expedition_selection([scout])
	check(expanded.has(miner) and expanded.has(heavy) and expanded.has(pilot), "selecting a mining scout can retask its complete mining crew")
	game.set_order(scout, "move", scout.position + Vector3(0, 0, 5))
	check(command.scouts.groups.is_empty() and miner.complex_id != 0 and pilot.aboard == scout, "directly ordering the scout detaches support without interrupting mining or ejecting its pilot")
	# Every mining vehicle needs a separate pilot, in addition to its working engineers.
	var jeep: ExpeditionUnit = game.add_unit("jeep", Vector3(12, 0, -12))
	var second_scout: ExpeditionUnit = game.add_unit("scout", jeep.position + Vector3(0, 0, 3))
	var worker: ExpeditionUnit = game.add_unit("engineer", jeep.position + Vector3(2, 0, 0))
	var spare: ExpeditionUnit = game.add_unit("engineer", jeep.position + Vector3(3, 0, 0))
	var flamer: ExpeditionUnit = game.add_unit("flamer", jeep.position + Vector3(4, 0, 0))
	check(not command.mining_available([jeep, second_scout, worker, flamer]), "insufficient crew is rejected before a scout can take the only working engineer")
	check(command.start_expedition(game, [jeep, second_scout, worker, spare, flamer], resource), "a jeep and scout can share a mining expedition with enough crew")
	var support: Dictionary = command.scouts.groups[-1]
	var convoy: Dictionary = command.groups[-1]
	check(support.driver == flamer and convoy.driver == spare and convoy.members.has(worker), "mining scout prefers a flamer before a surplus engineer while retaining a miner")
	# Test jeep preference with a surplus engineer and a separate miner.
	command.interrupt(jeep); command.scouts.tick(game, 0.1)
	check(command.scouts.groups.is_empty(), "scout support stops when its mining convoy ends")
	check(command.start_expedition(game, [jeep, worker, spare, flamer], resource), "jeep mining restarts with an available crew")
	convoy = command.groups[-1]
	check(convoy.driver == flamer and convoy.riders.has(worker) and convoy.riders.has(spare), "mining jeep prefers a flamer driver and carries both working engineers")
	command.interrupt(jeep)
	# Scanned patches retask the party; exploration requires explicit targeting.
	check(command.start_expedition(game, [jeep, second_scout, worker, spare, flamer], {}, Vector3(20, 0, -18)), "a mixed vehicle party can switch to exploration")
	game.select_actor(jeep); game.focus = game.DEPOSIT; game.update_camera()
	await physics_frame
	game.choose_expedition(true)
	await game.expedition_click(game.camera.unproject_position(game.DEPOSIT))
	check(command.exploration.groups.is_empty() and command.groups.size() == 1 and command.scouts.groups.size() == 1 and command.groups[0].resource == resource, "explicit patch targeting switches the whole exploration party to mining with scout support")
	game.select_actor(second_scout)
	game.choose_expedition()
	await game.expedition_click(game.camera.unproject_position(game.DEPOSIT + Vector3(-6, 0, 6)))
	check(command.groups.is_empty() and command.scouts.groups.is_empty() and command.exploration.groups.size() == 1 and worker.complex_id == second_scout.complex_id, "explicit exploration targeting switches a mining scout's whole crew back to exploration")
	var third_scout: ExpeditionUnit = game.add_unit("scout", jeep.position + Vector3(0, 0, 6))
	var extra_pilot: ExpeditionUnit = game.add_unit("marine", third_scout.position)
	var full_crew: Array = command.expedition_selection([second_scout]) + [third_scout, extra_pilot]
	check(command.start_expedition(game, full_crew, resource) and command.scouts.groups.size() == 2, "a mining expedition can assign multiple scouts without sharing their drivers")
	var later_scout: ExpeditionUnit = command.scouts.groups[-1].vehicle
	var first_scout: ExpeditionUnit = command.scouts.groups[0].vehicle
	expanded = command.expedition_selection([later_scout])
	check(expanded.has(first_scout) and expanded.has(jeep) and expanded.has(worker), "retasking any scout includes earlier scouts and all linked miners regardless of assignment order")
	print("EXPEDITION_SCOUT_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
