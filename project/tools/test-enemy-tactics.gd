extends SceneTree
const Tactics = preload("res://engine/predator_tactics.gd")
var failures := 0
var serial := 100

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func clear_packs(game) -> void:
	for creature in game.creatures: creature.hp = 0
	game.cleanup_dead(); game.director.groups.clear()

func pack(game, center: Vector3, kinds: Array, phase: String = "staging") -> Dictionary:
	serial += 1
	game.director.add_group(center, serial, 0)
	for i in range(kinds.size()): game.add_creature(center + Vector3(3 + i, 0, 0), serial, kinds[i])
	var group: Dictionary = game.director.groups[-1]
	game.director.change(group, phase, game)
	return group

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	game.rocks.clear(); game.navigation.terrain.natural_enabled = false; game.rebuild_navigation()
	clear_packs(game); game.elapsed = 200
	var director = game.director
	var worker: SimUnit = game.add_unit("engineer", Vector3(-42, 0, -12))
	game.rebuild_light()
	var group := pack(game, worker.position, ["runner", "stalker", "brute"])
	group.intent = "probe"
	director.tick(game, 0.4)
	check(game.creatures.all(func(c): return c.state == "staging" and c.target == null), "a probe group gathers before attacking even when a target is exposed")
	game.creatures[0].hurt(1); director.tick(game, 0.4)
	check(group.phase == "retreating" and game.creatures.all(func(c): return c.target == null and c.state == "retreating"), "one hit during probe preparation withdraws the pack without a hunting override")
	clear_packs(game)
	group = pack(game, worker.position, ["runner", "stalker", "brute"])
	group.intent = "assault"
	game.creatures[0].hurt(1); director.tick(game, 0.4)
	check(group.phase == "assault" and game.creatures.all(func(c): return c.state == "assault"), "shooting an assault gathering starts its attack early")
	clear_packs(game)
	group = pack(game, worker.position, ["runner", "stalker"], "probing")
	director.tick(game, 0.4)
	var runner: SimPredator = game.creatures[0]
	check(runner.probe_active and runner.target == worker and not game.creatures[1].probe_active and game.creatures[1].target == null, "only the runner probes while the larger alien waits at the boundary")
	runner.hurt(1)
	check(runner.target == null and runner.state == "retreating", "a damaged probe stops attacking immediately")
	director.tick(game, 0.4)
	check(group.phase == "retreating", "resisted probes do not summon an assault")
	clear_packs(game)
	group = pack(game, worker.position, ["runner", "stalker"], "probing")
	runner = game.creatures[0]; runner.position = worker.position + Vector3(2, 0, 0)
	var health := worker.hp
	for i in range(12):
		game.elapsed += 0.4; director.tick(game, 0.4); game.combat_tick(0.4); runner.cooldown = 0
	check(worker.hp < health and group.phase == "assault", "a runner that reaches and damages an unresisting target calls the waiting pack forward")
	worker.hp = 80
	clear_packs(game)
	group = pack(game, worker.position, ["runner", "stalker"], "probing")
	for i in range(12):
		game.creatures[0].position = worker.position + Vector3(10, 0, 0)
		game.elapsed += 0.4; director.tick(game, 0.4)
	check(group.phase == "probing" and group.probe_success == 0, "time spent approaching a target is not mistaken for a successful probe")
	clear_packs(game)
	group = pack(game, worker.position, ["runner", "stalker"])
	group.intent = "probe"; game.creatures[0].hurt(1000); game.cleanup_dead(); director.tick(game, 0.4)
	check(group.phase == "retreating", "a probe killed before the next AI tick still warns the surviving group")
	clear_packs(game)
	group = pack(game, worker.position, ["runner", "stalker", "brute"], "assault")
	var generator: SimStructure = game.add_structure("generator", worker.position + Vector3(0, 0, 5))
	var turret: SimStructure = game.add_structure("turret", worker.position + Vector3(0, 0, -5)); turret.powered = true
	Tactics.observe(game, group, game.creatures)
	var choices: Array[String] = []
	for creature in game.creatures:
		choices.append(Tactics.choose(game, director, group, creature).kind)
	check(choices == ["engineer", "generator", "turret"], "runners prefer workers, stalkers support buildings, and brutes defensive weapons")
	group.memory.clear()
	var other: SimUnit = game.add_unit("engineer", worker.position + Vector3(0, 0, 8))
	group.memory.append({"actor": worker, "position": worker.position, "time": game.elapsed, "kind": worker.kind, "hp": worker.hp, "operational": false})
	group.memory.append({"actor": other, "position": other.position, "time": game.elapsed, "kind": other.kind, "hp": other.hp, "operational": false})
	check(Tactics.choose(game, director, group, game.creatures[0]).actor == worker, "equal target priorities choose the closer target")
	group.memory[1].hp = 1
	check(Tactics.choose(game, director, group, game.creatures[0]).actor == other, "a more vulnerable valuable target takes priority over proximity")
	group.memory.clear()
	game.creatures[1].position = generator.position + Vector3(12, 0, 0)
	director.tick(game, 0.4)
	check(game.creatures[1].target == generator and game.creatures[1].goal.distance_to(generator.position) > 4, "assaulting stalkers approach support targets from a flank before closing")
	var wall: SimStructure = game.add_structure("wall", Vector3(-42, 0, -35))
	game.rebuild_navigation()
	var brute: SimPredator = game.creatures[2]; brute.position = wall.position + Vector3(0, 0, -5)
	group.memory.append({"actor": wall, "position": wall.position, "time": game.elapsed, "kind": "wall", "hp": wall.hp, "operational": false})
	check(director.breach(game, group, brute, wall.position + Vector3(0, 0, 5)) == wall, "brutes identify observed barriers blocking an assault route")
	check(director.breach(game, group, brute, wall.position + Vector3(0, 2, 5)) == wall, "the elevated core signal cannot hide a blocking wall from retrieval assaults")
	clear_packs(game)
	runner = game.add_creature(Vector3(-12, 0, -42), 999, "runner")
	game.light.sources.clear(); game.light.add_source(Vector3(0, 0, -42), 6)
	runner.state = "probing"; runner.navigate(Vector3(12, 0, -42), game.navigation, game.light)
	var length := 0.0
	for i in range(1, runner.path.size()): length += runner.path[i - 1].distance_to(runner.path[i])
	check(length > 26, "noncommitted probes take a dark detour instead of crossing a protective light")
	runner.state = "assault"; runner.navigate(Vector3(12, 0, -42), game.navigation, game.light)
	check(runner.path.size() == 2, "committing to an assault immediately replaces the light-avoiding route")
	clear_packs(game); game.elapsed = 1
	game.mission.hive.position = Vector3(0, 0, -30)
	var center: Vector2i = game.Hex.to_axial(game.mission.hive.position, 1)
	var inside := pack(game, game.Hex.to_world(center + Vector2i(55, 0), 1), ["brute"], "retreating")
	var outside := pack(game, game.Hex.to_world(center + Vector2i(56, 0), 1), ["stalker"], "lurking")
	director.last_hive_hp = game.mission.hive.hp
	game.mission.hive.hp -= 1; game.shot(worker.position, game.mission.hive.position, Color.WHITE, worker)
	check(inside.phase == "assault" and outside.phase == "lurking", "hive damage immediately alerts exactly the inclusive 55-hex radius, even during setup grace")
	check(inside.alarm_point == worker.position and game.creatures[0].state == "assault", "alerted groups receive the attack location and abandon retreat")
	game.elapsed = 2; game.mission.hive.hp -= 1; director.check_hive_alarm(game)
	check(inside.defend_until == game.elapsed + 45, "continued hive damage refreshes local defense")
	inside.memory.append({"actor": worker, "position": worker.position, "time": game.elapsed, "kind": worker.kind, "hp": worker.hp, "operational": false})
	game.creatures[0].target = worker; game.creatures[0].target_until = game.elapsed + 3
	check(Tactics.choose(game, director, inside, game.creatures[0]).is_empty(), "hive defenders abandon unrelated targets instead of being diverted from the alarm")
	game.elapsed = 120; var early_cap: int = director.population_limit(game)
	game.elapsed = 600
	check(director.escalation(game) == 1 and director.population_limit(game) > early_cap, "normal late-game pressure grows independently of core theft")
	director.change(outside, "staging", game)
	check(outside.intent == "assault", "late-game gatherings choose assaults instead of repeatedly testing defenses")
	game.elapsed = 2; game.mission.stolen = true; game.mission.carrier = worker
	for creature in game.creatures: creature.hp = 1; creature.retreat_remaining = 100
	for entry in director.groups: entry.clock = 500; entry.pending_loss = 1000
	director.tick(game, 0.4)
	check(game.creatures.all(func(c): return c.state == "assault" and c.retreat_remaining == 0) and director.groups.all(func(g): return g.phase == "assault"), "core theft forces every group into permanent aggression despite damage, low health, grace, or distance")
	game.dispose()
	print("ENEMY_TACTICS_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
