extends SceneTree
const Hex = preload("res://engine/hex_grid.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/top_down.tscn").instantiate(); game.initial_seed = 42
	root.add_child(game); game.set_process(false); game.begin_run()
	var sim = game.simulation
	sim.rocks.clear(); sim.rebuild_navigation()
	var patch: Dictionary = sim.resource_nodes[-1]; patch.discovered = true
	var worker: SimUnit = sim.units[0]
	worker.position = patch.position + Hex.to_world(Vector2i(0, 2), 1)
	worker.harvest_origin = patch.position
	var initial: int = patch.remaining
	check(sim.resource_fields.harvest(sim, worker, patch) == 0 and patch.remaining == initial, "harvest API rejects mining from two hexes away")
	sim.process_harvest(worker, 1)
	check(worker.cargo_total() == 0 and worker.moving(), "manual mining approaches the deposit instead of extracting remotely")
	var adjacent := true
	for offset in Hex.NEIGHBORS:
		worker.position = patch.position + Hex.to_world(offset, 1)
		adjacent = adjacent and sim.resource_fields.within_reach(worker, patch.position)
	check(adjacent, "all six adjacent tile centers are within mining reach")
	worker.position = patch.position
	check(sim.resource_fields.harvest(sim, worker, patch) == 1, "engineers can mine while on top of a deposit")
	worker.position.y += 3
	check(not sim.resource_fields.within_reach(worker, patch.position), "mining cannot reach another elevation")
	worker.position = patch.position + Hex.to_world(Vector2i(0, 2), 1)
	initial = patch.remaining
	sim.complex_commands.start_expedition(sim, [worker], patch)
	sim.complex_commands.foot.tick(sim, 1)
	check(patch.remaining == initial and worker.moving(), "on-foot mining expeditions use the same adjacency rule")
	sim.complex_commands.interrupt(worker)
	var jeep: SimUnit = sim.add_unit("jeep", patch.position + Vector3(4, 0, 0))
	var pilot: SimUnit = sim.add_unit("marine", jeep.position)
	sim.complex_commands.start_expedition(sim, [jeep, pilot, worker], patch)
	var convoy: Dictionary = sim.complex_commands.groups[-1]
	jeep.board(convoy.driver); convoy.phase = "work"
	sim.complex_commands.tick(sim, 1)
	check(patch.remaining == initial, "vehicle expedition workers cannot mine from a distance")
	sim.complex_commands.interrupt(jeep)
	var marine: SimUnit = sim.units[1]
	marine.position = Vector3(-10, 0, -5); marine.yaw = 0; marine.cooldown = 0
	var enemy: SimPredator = sim.add_creature(Vector3(-4, 0, -5), 999)
	sim.light.add_source(enemy.position, 20); sim.events.clear()
	sim.combat_tick(0.1)
	var shot: Dictionary = {}
	for event in sim.events:
		if event.type == "shot" and event.shooter == marine.simulation_id: shot = event
	check(not shot.is_empty() and shot.weapon == "marine", "shots identify their actual shooter and weapon")
	var before: String = sim.state_hash()
	game.sprites.tick(game, 0)
	check(is_equal_approx(game.sprites.actor_angle(marine), PI / 2), "a north-facing marine visually aims east at its shooting target")
	var muzzle: Vector3 = game.sprites.muzzle_point(game, marine, PI / 2)
	check(muzzle.x > marine.position.x + 0.75 and absf(muzzle.z - marine.position.z) < 0.03, "marine muzzle lies at the rotated rifle tip rather than the torso")
	for kind in ["flamer", "turret", "laser_turret", "flame_turret"]:
		var actor: SimEntity = sim.add_unit(kind, Vector3(12, 0, -10)) if kind == "flamer" else sim.add_structure(kind, Vector3(12, 0, -10))
		var tip: Vector3 = game.sprites.muzzle_point(game, actor, 0)
		check(tip.z < actor.position.z - 0.75, kind + " uses its nozzle/barrel attachment")
	# Check visual isolation after the actors above have been added to the core.
	before = sim.state_hash(); game.sprites.tick(game, 0.05)
	check(before == sim.state_hash(), "combat aiming and effect attachments never change authoritative state")
	check(not game.has_method("play_cue") and not sim.has_method("play_cue"), "synthetic beeping has been removed from both view and core")
	game.queue_free(); await process_frame
	print("COMBAT_AND_MINING_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
