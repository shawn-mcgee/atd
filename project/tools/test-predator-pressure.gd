extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run(); game.audio_enabled = false
	var first_seen := INF; var last_seen := 0.0; var longest_gap := 0.0
	var contacts := 0; var visible_time := 0.0; var previous := false
	for i in range(1800):
		game.simulation_tick(0.1)
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
	check(game.director.reinforcements_spawned >= 4 and game.creatures.size() <= game.director.MAX_CREATURES, "combat losses are replenished without unbounded population growth")
	check(game.core.hp > 0 and not game.ended, "the guarded starting base can withstand recurring probes while the player prepares an expedition")
	print("PREDATOR_PRESSURE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
