extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func clear_pack(game) -> void:
	for creature in game.creatures: creature.hp = 0
	game.cleanup_dead(); game.director.groups.clear()

func observe(game, seconds: float, combat: bool = false) -> void:
	for i in range(int(seconds * 10)):
		game.elapsed += 0.1; game.advance_movement(0.1)
		if i % 4 == 0: game.director.tick(game, 0.4)
		if combat: game.combat_tick(0.1)
		if i % 100 == 0: await process_frame

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	await process_frame

	var director = game.director
	var kinds: Dictionary = {}
	for creature in game.creatures: kinds[creature.kind] = true
	check(game.creatures.size() >= 8 and kinds.size() == 3 and director.groups.size() == 6, "the world starts with mixed creature packs around HQ and distant resource habitats")
	var first_seen := INF; var visible_time := 0.0; var quiet := 0.0; var longest_quiet := 0.0
	for i in range(1000):
		game.elapsed += 0.1; game.advance_movement(0.1)
		if i % 4 == 0: director.tick(game, 0.4)
		var seen: bool = game.creatures.any(func(creature): return creature.position.distance_to(game.HOME) < 23 and game.light.sample(creature.position) > 0.065)
		if seen:
			first_seen = minf(first_seen, game.elapsed); visible_time += 0.1; quiet = 0
		elif first_seen < INF: quiet += 0.1; longest_quiet = maxf(longest_quiet, quiet)
		if i % 100 == 0: await process_frame
	print("PROBE_VISIBILITY first=", first_seen, " visible_seconds=", visible_time, " longest_gap=", longest_quiet)
	check(first_seen < director.BASE_GRACE and visible_time > 15 and longest_quiet < 30, "repeated multi-creature probes enter actual player illumination during setup and throughout the encounter")
	clear_pack(game); game.rocks.clear(); game.rebuild_navigation()
	var runner: SimPredator = game.add_creature(Vector3(-50, 0, -20), 90, "runner")
	var stalker: SimPredator = game.add_creature(Vector3(-50, 0, -23), 90, "stalker")
	var brute: SimPredator = game.add_creature(Vector3(-50, 0, -26), 90, "brute")
	check(runner.max_hp < stalker.max_hp and stalker.max_hp < brute.max_hp, "runner, stalker and brute have distinct durability")
	for creature in [runner, brute]:
		creature.state = "probing"; creature.path = PackedVector3Array([creature.position + Vector3(10, 0, 0)]); creature.path_index = 0
	var runner_start := runner.position; var brute_start := brute.position
	runner.move_tick(0.1); brute.move_tick(0.1)
	check(runner.position.distance_to(runner_start) > brute.position.distance_to(brute_start), "runners actually move faster than brutes")
	clear_pack(game)
	var building: SimStructure = game.add_structure("generator", Vector3(-40, 0, -12))
	game.rebuild_navigation()
	var hunter: SimPredator = game.add_creature(building.position + Vector3(8, 0, 0), 90)
	director.add_group(building.position, 90, 1); director.groups[-1].phase = "probing"
	game.elapsed = 80; game.rebuild_light(); director.tick(game, 0.4)
	check(hunter.target == building and hunter.state == "hunting", "a probe that observes an undefended structure commits to attacking it")
	var hp := building.hp
	await observe(game, 8, true)
	check(building.hp < hp and hunter.position.distance_to(building.position) < 3 and not game.navigation.blocked(hunter.position), "creatures approach a solid structure closely enough to bite and damage it")
	var guard: SimUnit = game.add_unit("marine", building.position + Vector3(0, 0, 4))
	game.light.sources.clear(); game.light.add_source(building.position, 20)
	director.groups[-1].memory.clear(); director.groups[-1].phase = "probing"; hunter.hp = hunter.max_hp; hunter.loss = 0
	director.tick(game, 0.4)
	check(hunter.target == null and hunter.state == "probing", "a guarded, illuminated structure does not trigger an opportunistic probe attack")
	game.rebuild_light(); director.tick(game, 0.4)
	check(hunter.target == building and hunter.state == "hunting", "darkness makes a discovered structure a hunting target even when an infantry guard is nearby")
	game.light.sources.clear(); game.light.add_source(building.position, 20)
	game.jeep.board(guard); director.tick(game, 0.4)
	check(hunter.target == building and hunter.state == "hunting", "boarding the guard exposes an undefended structure even when its surroundings remain lit")
	clear_pack(game)
	var worker: SimUnit = game.add_unit("engineer", Vector3(-30, 0, -35))
	hunter = game.add_creature(worker.position + Vector3(10, 0, 0), 90, "runner")
	director.add_group(worker.position, 90, 1); game.elapsed = 25; game.rebuild_light()
	director.tick(game, 0.4)
	check(hunter.target == worker and hunter.state == "hunting" and game.light.deterrence(worker.position) == 0, "creatures hunt locally observed infantry in the dark despite personal emergency lamps")
	game.light.add_source(worker.position, 12); director.tick(game, 0.4)
	check(hunter.target == null, "operational illumination removes the opportunistic hunting trigger for a lone ground unit")
	game.rebuild_light(); director.tick(game, 0.4)
	hp = worker.hp; await observe(game, 4, true)
	check(worker.hp < hp, "leaving the base for unprotected darkness is dangerous even during the HQ setup grace")
	worker.position = Vector3(0, 0, -2); hunter.position = worker.position + Vector3(2.4, 0, 0)
	hunter.target = worker; hunter.state = "hunting"; hunter.cooldown = 0; game.elapsed = 25
	hp = worker.hp; game.combat_tick(0.1)
	check(worker.hp == hp and not director.attack_allowed(game, worker), "the initial HQ setup grace still prevents damage near the base")
	# Terrain occlusion and last-known positions must constrain the new hunting behavior.
	worker.position = Vector3(-30, 0, -40); hunter.position = worker.position + Vector3(10, 0, 0)
	hunter.hp = hunter.max_hp; hunter.loss = 0; director.groups[-1].loss = 0
	game.rocks.append({"position": worker.position + Vector3(5, 0, 0), "radius": 1.8})
	game.rebuild_navigation(); director.groups[-1].anchor = worker.position; director.groups[-1].memory.clear(); director.groups[-1].phase = "probing"
	game.elapsed = 80; director.tick(game, 0.4)
	check(not director.groups[-1].memory.any(func(memory): return memory.actor == worker) and hunter.target == null, "creatures cannot acquire dark prey through an unseen terrain barrier")
	game.rocks.clear(); game.rebuild_navigation(); director.tick(game, 0.4)
	check(hunter.target == worker, "an exposed unit is acquired once the creature can actually see it")
	var last_seen := worker.position
	worker.position = Vector3(50, 0, 40); game.elapsed += 1; director.tick(game, 0.4)
	check(hunter.target == null and director.groups[-1].memory.any(func(memory): return memory.actor == worker and memory.position == last_seen) and hunter.goal.distance_to(worker.position) > 20, "losing sight investigates a last-known position rather than tracking the unit across the map")
	game.elapsed += 36; director.tick(game, 0.4)
	check(not director.groups[-1].memory.any(func(memory): return memory.actor == worker), "unseen prey is forgotten after the existing memory timeout")
	clear_pack(game); game.elapsed = 100; game.rebuild_light()
	director.add_group(game.HOME, 0, 4)
	director.tick(game, director.REINFORCEMENT_INTERVAL - 1)
	check(game.creatures.is_empty(), "a wiped-out pack is not replaced immediately")
	director.tick(game, 1)
	check(game.creatures.size() == 1 and director.reinforcements_spawned > 0, "a wiped-out pack receives delayed reinforcements instead of leaving the world permanently empty")
	var replacement: SimPredator = game.creatures[0]
	var safe: bool = game.light.sample(replacement.position) <= 0.035 and not game.navigation.blocked(replacement.position)
	for actor in game.units + game.structures:
		if actor.hp > 0 and not (actor is SimUnit and actor.aboard != null) and replacement.position.distance_to(actor.position) < 18: safe = false
	check(safe and not replacement.visible, "reinforcements arrive on hidden, navigable ground away from friendly units and structures")
	for i in range(director.MAX_CREATURES - 1): game.add_creature(Vector3(-60, 0, 30), 999)
	director.tick(game, director.REINFORCEMENT_INTERVAL)
	check(game.creatures.size() == director.MAX_CREATURES, "reinforcements respect the global population cap")
	clear_pack(game); director.add_group(game.HOME, 0)
	game.light.sources.clear(); game.light.add_source(Vector3.ZERO, 300)
	check(director.spawn_member(game, director.groups[-1]) == null and game.creatures.is_empty(), "reinforcements wait when no hidden arrival point exists")
	game.dispose()
	print("PREDATOR_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
