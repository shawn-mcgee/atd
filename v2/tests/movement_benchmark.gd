extends RefCounted
## Manual timing probe; timings are diagnostic, never simulation inputs or assertions.
const Fixture = preload("res://tests/geometry_suite.gd")
const Sim = preload("res://core/simulation.gd")
const Geo = preload("res://core/geometry.gd")
const Canonical = preload("res://core/canonical.gd")

func run(args: PackedStringArray) -> Dictionary:
	var reports: Array = []
	var verified := "--verify" in args
	var valid := true
	for count in ([64] if "--large" in args else [16, 32, 64]):
		var fixture = Fixture.new()
		var game = Sim.new()
		game.accelerated = not "--reference" in args
		game.initialize(fixture._definitions(), fixture._players(), 42)
		if "--require-native" in args and game._crowd.backend == null:
			return {"ok": false, "reports": [], "error": "Compiled movement kernel is unavailable"}
		var movers: Array = []
		var opponents: Array = []
		var opposing := "--opposing" in args
		for i in count:
			game._spawn("engineer", 1, [-(i % 8 + 2) * 1024, 0, -(i / 8 + 2) * 1024])
			movers.append(int(game.state.next_id) - 1)
			game._spawn("scavenger", 9, [(i % 8 + 2) * 1024, 0, (i / 8 + 2) * 1024])
			opponents.append(int(game.state.next_id) - 1)
		var max_searches := 0; var max_expansions := 0
		var samples: Array = []
		var steps: Array = []; var copies: Array = []; var hashes: Array = []
		var history: Array = []
		var history_limit := int(game.content.settings.rollback_ticks) + 2
		var initial: Dictionary = game.checkpoint() if verified else {}
		var orders: Array = [{"kind": "move", "player": 1, "actors": movers, "point": [0, 0, 0]}]
		if opposing: orders.append({"kind": "move", "player": 9, "actors": opponents, "point": [0, 0, 0]})
		var humans: Array = []; var foes: Array = []
		if verified:
			for id in movers: humans.append(game.entity(id))
			for id in opponents: foes.append(game.entity(id))
		for tick in 60:
			var started := Time.get_ticks_usec()
			game.step(orders if tick == 0 else [])
			var stepped := Time.get_ticks_usec()
			history.append(game.rollback_checkpoint(int(game.state.tick) % 20 == 0))
			if history.size() > history_limit: history.pop_front()
			var copied := Time.get_ticks_usec()
			if int(game.state.tick) % 20 == 0: game.rollback_hash(history.back())
			var finished := Time.get_ticks_usec()
			steps.append(stepped - started); copies.append(copied - stepped)
			if int(game.state.tick) % 20 == 0: hashes.append(finished - copied)
			max_searches = maxi(max_searches, game._navigation_searches); max_expansions = maxi(max_expansions, game._navigation_expansions)
			samples.append(finished - started)
			# Verification is deliberately outside every timed interval.
			if verified:
				for human in humans:
					for foe in foes:
						var limit := Geo.radius(game, human) + Geo.radius(game, foe)
						if game.distance_squared(human.position, foe.position) < limit * limit: valid = false
		var cold := 0; var steady := 0
		for i in samples.size():
			if i < 10: cold += int(samples[i])
			else: steady += int(samples[i])
		var sorted := samples.duplicate(); sorted.sort()
		var final_hash: String = game.state_hash()
		var state_json_hash := Canonical.hash_of(game.state)
		if verified:
			game.restore_rollback(history[30])
			for tick in 29: game.step([])
			valid = valid and game.state_hash() == final_hash and Canonical.hash_of(game.state) == state_json_hash
			if not game.packed_rollback:
				game.restore_rollback(history[39]) # A packed hash boundary in mixed Web history.
				for tick in 20: game.step([])
				valid = valid and game.state_hash() == final_hash and Canonical.hash_of(game.state) == state_json_hash
			game.restore(JSON.parse_string(JSON.stringify(initial)))
			for tick in 60: game.step(orders if tick == 0 else [])
			valid = valid and game.state_hash() == final_hash
		var report := {"movers": count, "opposing": opposing, "max_searches": max_searches, "max_expansions": max_expansions, "actors": game.state.actors.size(),
			"backend": "native" if game._crowd.backend != null else "gdscript",
			"platform": OS.get_name(), "debug_build": OS.has_feature("debug"),
			"mean_us": _mean(samples), "first_10_mean_us": cold / 10, "next_50_mean_us": steady / 50, "p95_us": sorted[56], "peak_us": sorted.back(),
			"step_mean_us": _mean(steps), "checkpoint_mean_us": _mean(copies), "hash_mean_us": _mean(hashes), "final_hash": final_hash,
			"state_json_hash": state_json_hash, "snapshot_bytes": history.back().get("packed", PackedByteArray()).size(), "checkpoint_format": "packed" if game.packed_rollback else "mixed",
			"verification": ("passed" if valid else "failed") if verified else "not_requested"}
		reports.append(report)
		print("ATD_MOVEMENT_BENCHMARK " + JSON.stringify(report))
	return {"ok": valid, "reports": reports}

static func _mean(samples: Array) -> int:
	var total := 0
	for value in samples: total += int(value)
	return total / maxi(1, samples.size())
