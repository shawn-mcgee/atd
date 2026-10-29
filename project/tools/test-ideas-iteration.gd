extends SceneTree
const Layout = preload("res://scripts/scenario_layout.gd")
const Terrain = preload("res://scripts/expedition_terrain.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(ceili(seconds / 0.1)):
		game.advance_movement(0.1); game.tactics.tick(game, 0.1); game.tactical_groups.tick(game, 0.1)
		for unit in game.units: game.process_order(unit, 0.1)

func run() -> void:
	var terrain := Terrain.new()
	var a := Layout.new(); var b := Layout.new(); var different := false
	for seed_value in [1, 42, 819, 2048, 32768]:
		a.generate(terrain, seed_value); b.generate(terrain, seed_value)
		check(a.rock_cells == b.rock_cells and a.fields == b.fields and a.beacon_position == b.beacon_position and a.hive_position == b.hive_position, "seed %d reproduces terrain, resource fields, and objectives" % seed_value)
		if seed_value != 1: different = different or a.rock_cells != first_rocks
		else: first_rocks = a.rock_cells.duplicate()
		check(a.rock_cells.size() > 40 and a.rock_cells.keys().all(func(cell): return not a.reserved(a.Hex.to_world(cell, Terrain.CELL))), "seed %d leaves the landing zone and every objective approach clear" % seed_value)
	check(different, "different mission seeds generate different layouts")
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.scenario_seed = 42
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.audio_enabled = false; game.begin_run()
	check(game.units.size() == 2 and game.units[0].kind == "engineer" and game.units[1].kind == "marine" and game.structures.size() == 2 and game.structures[0] == game.core and game.structures[1] == game.mission.beacon, "real demo starts with HQ, one engineer and one marine; the only other structure is undiscovered extraction")
	check(game.core.powered and game.power.capacity == 4 and game.economy.mineral_capacity == 100 and game.economy.gas_capacity == 100, "HQ provides usable storage and bootstrap power without starting infrastructure")
	check(game.Power.source_range(game.core) > game.Power.GENERATOR_RANGE and game.Power.source_range(game.core) < game.Power.LINK_RANGE and game.light.sample(Vector3(8, 0, 0)) == 0, "HQ acts as a medium relay while illuminating only a small radius")
	check(game.mission.map_objectives().is_empty() and not game.mission.beacon.visible and not game.mission.hive.visible and not game.mission.item.visible, "unscouted objectives expose no world models or minimap labels")
	game.minimap.refresh()
	check(not game.minimap.markers.any(func(marker): return marker.point == game.mission.beacon.position), "generic structure markers cannot leak the extraction location")
	var reachable := true
	for point in [game.mission.beacon.position, game.mission.hive.position] + game.layout.fields.map(func(field): return field.position):
		var route: PackedVector3Array = game.navigation.path(game.units[0].position, point)
		if route.is_empty() or route[-1].distance_to(point) > 1: reachable = false
	check(reachable, "every generated resource field and mission objective is reachable")
	var engineer: ExpeditionUnit = game.units[0]
	engineer.cargo = 7; engineer.gas_cargo = 4
	game.economy.minerals -= 10; game.economy.gas -= 10
	var minerals: int = game.economy.minerals; var gas: float = game.economy.gas
	check(game.find_receiver(engineer.position, "minerals") == game.core and game.find_receiver(engineer.position, "gas") == game.core, "both delivery routes fall back to HQ without depots or tanks")
	game.deposit_cargo(engineer, game.core)
	check(game.economy.minerals == minerals + 7 and game.economy.gas == gas + 4 and engineer.cargo_total() == 0, "HQ physically receives both currencies in one delivery")
	game.economy.gas = 0; game.power.tick(game.structures, game.economy, 10)
	check(game.core.powered and game.power.used == 0 and game.economy.gas == 0, "HQ auxiliary power remains available without methane or resource scan charging")
	game.select_actor(game.core)
	var names_hidden := true
	for building in game.structures:
		for child in building.get_children():
			if child is Label3D and child.visible: names_hidden = false
	# HQ is selected, so exactly its name should now be visible.
	check(not names_hidden, "selecting a structure reveals its name")
	game.select_actor(null)
	check(game.structures.all(func(building): return building.get_children().all(func(child): return not child is Label3D or not child.visible)), "deselecting hides every floating structure name")
	game.light.add_source(game.mission.beacon.position, 8); game.mission.tick(game, 0.1)
	check(game.mission.beacon_discovered and not game.mission.hive_discovered and game.mission.map_objectives().size() == 1, "scouting reveals only the visited objective")
	game.light.sources.clear(); game.mission.tick(game, 0.1)
	check(game.mission.map_objectives().size() == 1 and not game.mission.beacon.visible, "discovered map locations are remembered after illumination is lost")
	check(game.mission.EXTRACTION_TIME == 60, "extraction now requires a full minute")
	for enemy in game.creatures: enemy.hp = 0
	game.cleanup_dead(); game.director.groups.clear()
	# Weapon behavior includes resources, reload downtime, visibility, and splash.
	game.light.sources.clear(); game.light.add_source(Vector3(-12, 0, -12), 35)
	var gun: ExpeditionStructure = game.add_structure("turret", Vector3(-12, 0, -12))
	var laser: ExpeditionStructure = game.add_structure("laser_turret", gun.position + Vector3(2, 0, 0))
	var flame: ExpeditionStructure = game.add_structure("flame_turret", gun.position + Vector3(0, 0, 2))
	game.economy.minerals = 50; game.economy.gas = 20
	for turret in [gun, laser, flame]: turret.powered = true
	var victim: ExpeditionPredator = game.add_creature(gun.position + Vector3(5, 0, 0), 99, "brute")
	var victim2: ExpeditionPredator = game.add_creature(victim.position + Vector3(0, 0, 1), 99, "brute")
	gun.ammo = 0; gun.auto_reload = false; laser.enabled = false; flame.enabled = false
	game.turret_system.tick(game, 0.1)
	check(gun.reload_remaining == 0 and game.economy.minerals == 50, "an empty turret with automatic reload disabled waits without spending")
	check(game.turret_system.reload(game, gun) and game.economy.minerals == 42 and gun.reload_remaining == 4, "manual minigun reload consumes eight materials once and starts downtime")
	var hp: float = victim.hp
	game.turret_system.tick(game, 1)
	check(victim.hp == hp and not game.turret_system.reload(game, gun) and game.economy.minerals == 42, "reloading disables fire and cannot double-charge an overlapping reload")
	game.turret_system.tick(game, 3); game.turret_system.tick(game, 0.1)
	check(gun.ammo == 29 and victim.hp < hp, "a completed reload refills the magazine and allows fire again")
	gun.ammo = 0; gun.cooldown = 0; game.economy.minerals = 7; gun.auto_reload = true
	game.turret_system.tick(game, 0.1)
	check(gun.reload_remaining == 0 and game.economy.minerals == 7, "unaffordable automatic reload is atomic and leaves resources unchanged")
	game.economy.minerals = 8; game.turret_system.tick(game, 0.1)
	check(gun.reload_remaining == 4 and game.economy.minerals == 0, "automatic reload resumes when sufficient materials arrive")
	gun.enabled = false; flame.enabled = true; laser.enabled = true
	hp = victim.hp; var hp2: float = victim2.hp; gas = game.economy.gas
	game.turret_system.tick(game, 0.1)
	check(victim.hp < hp and victim2.hp < hp2 and flame.ammo == 11, "flame turret damages multiple visible enemies in its area")
	check(laser.ammo == 0 and game.economy.gas == gas and not game.turret_system.reload(game, laser) and game.Rules.STRUCTURES.laser_turret.power > game.Rules.STRUCTURES.turret.power, "laser trades higher power for unlimited fire with no reload resources")
	flame.ammo = 0; flame.cooldown = 0; laser.enabled = false
	game.turret_system.tick(game, 0.1)
	check(flame.reload_remaining == 5 and game.economy.gas == gas - 6, "flame reload consumes methane rather than materials")
	game.select_actor(flame); game.toggle_turret_reload(); game.refresh_ui()
	check(not flame.auto_reload and game.context_buttons.auto_reload.visible and game.context_buttons.reload_turret.visible, "turret reload controls are exposed per selection")
	for enemy in game.creatures: enemy.hp = 0
	game.cleanup_dead()
	# A mixed group protects engineers, travels as an escort, and can be interrupted.
	var car: ExpeditionUnit = game.add_unit("jeep", Vector3(0, 0, -18))
	var pilot: ExpeditionUnit = game.add_unit("marine", car.position + Vector3(1, 0, 0))
	var guard: ExpeditionUnit = game.add_unit("marine", car.position + Vector3(2, 0, 0))
	var worker: ExpeditionUnit = game.add_unit("engineer", car.position + Vector3(-1, 0, 0))
	check(game.tactical_groups.start(game, [car, pilot, guard, worker], "attack_move", Vector3(0, 0, -60)), "mixed crew accepts a coordinated tactical command")
	step(game, 1)
	check(car.driver == pilot and worker.aboard == car and guard.aboard == null, "tactical groups reserve a pilot, board the engineer, and keep an armed foot escort")
	game.advance_movement(0.1)
	check(car.escort_speed_limit <= 3.5, "vehicle travel respects its walking escort's speed")
	step(game, 9)
	check(car.position.z < -23 and worker.aboard == car and guard.position.distance_to(car.position) < 7, "mixed attack-move advances together while the engineer stays protected")
	game.issue_order(guard, "move", Vector3(8, 0, -25))
	check(guard.complex_id == 0 and not game.tactical_groups.groups[0].members.has(guard), "a direct order immediately detaches its recipient from coordinated behavior")
	game.select_actor(car); game.unload()
	check(worker.aboard == null and worker.complex_id == 0 and car.complex_id == 0, "manual unload cancels vehicle coordination and never reboards the rescued engineer")
	var rescue_car: ExpeditionUnit = game.add_unit("jeep", Vector3(10, 0, -22))
	var lost_pilot: ExpeditionUnit = game.add_unit("marine", rescue_car.position)
	var survivor: ExpeditionUnit = game.add_unit("engineer", rescue_car.position)
	rescue_car.board(lost_pilot); rescue_car.board(survivor); lost_pilot.hp = 0; game.cleanup_dead()
	check(game.tactical_groups.start(game, [rescue_car], "attack_move", Vector3(10, 0, -30)), "a surviving passenger can accept a recovery mission after losing the pilot")
	step(game, 1)
	check(rescue_car.driver == survivor and survivor.hp > 0, "a recovery mission reseats the surviving passenger as the new driver")
	# Scout contacts are approximate, bounded, and never create combat vision.
	var scout: ExpeditionUnit = game.add_unit("scout", Vector3(-35, 0, -20))
	var scout_pilot: ExpeditionUnit = game.add_unit("marine", scout.position)
	scout.board(scout_pilot)
	game.light.sources.clear()
	var hidden: ExpeditionPredator = game.add_creature(scout.position + Vector3(7, 0, 0), 99)
	game.tactical_groups.start(game, [scout], "patrol", scout.position + Vector3(0, 0, -10))
	game.tactical_groups.tick(game, 0.1)
	var patrol: Dictionary = game.tactical_groups.groups[-1]
	check(patrol.investigate.is_finite() and game.visible_target(scout.position, 20) == null and not hidden.visible, "scout groups investigate approximate signals without revealing or targeting hidden enemies")
	game.tactical_groups.start(game, [scout], "patrol", scout.position + Vector3(8, 0, 0), null, true)
	check(patrol.points.size() == 3, "shift patrol extends a shared route without breaking the existing crew")
	# Exercise shared defense and attack transitions on an isolated navigable field.
	game.rocks.clear(); game.rebuild_navigation()
	var defender: ExpeditionUnit = game.add_unit("marine", Vector3(-10, 0, -30))
	var protected_worker: ExpeditionUnit = game.add_unit("engineer", defender.position + Vector3(0, 0, 2))
	var defense_point: Vector3 = protected_worker.position
	game.tactical_groups.start(game, [defender, protected_worker], "defend", defense_point, protected_worker)
	step(game, 2)
	check(protected_worker.order == "cohort_protected" and not protected_worker.moving() and protected_worker.position.distance_to(defense_point) < 1, "defending a selected engineer holds its order and position while allowing gentle crowd spacing")
	game.light.add_source(defense_point, 25)
	var attacker: ExpeditionPredator = game.add_creature(defense_point + Vector3(6, 0, 0), 99)
	game.tactical_groups.tick(game, 0.1)
	check(defender.combat_target == attacker, "coordinated defenders acquire a visible threat near the protected unit")
	attacker.position = defense_point + Vector3(20, 0, 0); game.tactical_groups.tick(game, 0.1)
	check(defender.combat_target == null and defender.goal.distance_to(defense_point) < 5, "coordinated defenders drop pursuits outside the leash and return to their formation")
	attacker.position = defense_point + Vector3(6, 0, 0)
	game.tactical_groups.start(game, [defender, protected_worker], "attack_move", Vector3(20, 0, -30))
	game.tactical_groups.tick(game, 0.1)
	check(defender.combat_target == attacker, "shared attack-move pursues visible enemies before advancing its original route")
	attacker.hp = 0; hidden.hp = 0; game.cleanup_dead(); game.tactical_groups.tick(game, 0.1)
	check(defender.combat_target == null and defender.goal.distance_to(Vector3(20, 0, -30)) < 1, "shared attack-move resumes its destination after the hostile dies")
	# Queue a group order behind finite direct moves; it must neither interrupt nor get lost.
	game.issue_order(defender, "move", Vector3(-5, 0, -35))
	game.issue_order(protected_worker, "move", Vector3(-6, 0, -35))
	game.tactical_groups.start(game, [defender, protected_worker], "patrol", Vector3(3, 0, -35), null, true)
	check(game.tactical_groups.queued_count(defender) == 1 and defender.order == "move", "a shifted coordinated order waits behind the selected units' current work")
	step(game, 8)
	check(game.tactical_groups.queued_count(defender) == 0 and game.tactical_groups.groups.any(func(group): return group.mode == "patrol" and group.members.has(defender) and group.members.has(protected_worker)), "the queued tactical group starts when both direct moves finish")
	print("IDEAS_ITERATION_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)

var first_rocks: Dictionary = {}
