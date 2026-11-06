extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	const Simulation = preload("res://engine/simulation.gd")
	for seed_value in [1, 42, 819]:
		var sim = Simulation.new(); sim.initialize(seed_value)
		var outer := 0
		for rock in sim.rocks:
			if rock.position.length() > 90: outer += 1
		check(sim.Terrain.MAP_RADIUS == 84 and sim.navigation.cells.size() == 21421, "map is 50 percent wider with 21,421 hexes")
		check(sim.rocks.size() > 1200 and outer > 100, "seed %d has dense cliffs extending into the expanded world: %d" % [seed_value, sim.rocks.size()])
		var reachable := true
		for point in [sim.mission.beacon.position, sim.mission.hive.position]:
			var path: PackedVector3Array = sim.navigation.path(Vector3(3, 0, -2), point)
			if path.is_empty() or path[-1].distance_to(point) > 2: reachable = false
		check(reachable, "objectives remain reachable")
		check(sim.resource_nodes.any(func(patch): return patch.kind == "minerals" and patch.discovered) and sim.resource_nodes.any(func(patch): return patch.kind == "gas" and patch.discovered), "both starter resources remain visible")
		sim.dispose()
		await process_frame
	print("MAP_GENERATION_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
