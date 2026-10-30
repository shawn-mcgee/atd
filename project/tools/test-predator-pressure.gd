extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	await process_frame

	var first_seen := INF; var last_seen := 0.0; var longest_gap := 0.0
	var contacts := 0; var visible_time := 0.0; var previous := false
	var setup_safe := true
	var initial_hp: float = game.core.hp
	for i in range(1800):
		game.simulation_tick(0.1)
		if game.elapsed < game.director.BASE_GRACE and game.core.hp < initial_hp: setup_safe = false
		var visible: bool = game.creatures.any(func(creature): return creature.hp > 0 and creature.visible and creature.position.distance_to(game.HOME) < 23)
		if visible:
			if not previous: contacts += 1
			first_seen = minf(first_seen, game.elapsed); last_seen = game.elapsed; visible_time += 0.1
		elif first_seen < INF: longest_gap = maxf(longest_gap, game.elapsed - last_seen)
		previous = visible
		if i % 100 == 0: await process_frame
		if game.ended: break
	print("LIVE_PRESSURE first=", first_seen, " last=", last_seen, " contacts=", contacts, " visible_seconds=", visible_time, " longest_gap=", longest_gap, " replacements=", game.director.reinforcements_spawned)
	check(first_seen < 40 and contacts >= 6 and last_seen > 140 and longest_gap < 35, "normal combat and casualties still produce recurring visible encounters instead of an empty world")
	# First-hit withdrawal lets early probes survive; casualties are no longer required.
	# Wiped-pack replacement timing is checked independently in test-predators.
	check(game.director.reinforcements_spawned > 0 and game.creatures.size() <= game.director.population_limit(game), "encounter population is maintained within its rising pressure cap")
	check(setup_safe, "early probing leaves the guarded HQ unharmed throughout setup grace")
	check(game.core.hp > 0 and not game.ended, "the guarded starting base can withstand recurring probes while the player prepares an expedition")
	game.dispose()
	print("PREDATOR_PRESSURE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
