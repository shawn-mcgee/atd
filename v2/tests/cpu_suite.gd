extends RefCounted
const Actor = preload("res://core/actor.gd")
const Fixture = preload("res://tests/geometry_suite.gd")
const Sim = preload("res://core/simulation.gd")
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")
const Canonical = preload("res://core/canonical.gd")
const StateCodec = preload("res://core/state_codec.gd")
const Exploration = preload("res://core/exploration.gd")
const Nav = preload("res://core/navigation.gd")
const Crowd = preload("res://core/crowd.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	_typed_actors()
	_entity_lookup()
	_state_codec()
	for bits in 63:
		for offset in [-1, 0, 1]:
			var value: int = (1 << bits) + offset
			var root: int = Sim.integer_sqrt(value)
			_check((root == 0 and value == 0) or (root > 0 and root <= value / root and root + 1 > value / (root + 1)), "integer root remains exact at bit boundaries")
	var top := Sim.integer_sqrt(9223372036854775807)
	_check(top == 3037000499, "integer root handles maximum signed input without overflow")
	for root in [1, 2, 3, 15, 255, 65535, 65536, 1048575, 134217728, 2147483647, 3037000499]:
		for offset in [-1, 0, 1]:
			_check(Sim.integer_sqrt(root * root + offset) == root - (1 if offset == -1 else 0), "Godot root estimate is corrected exactly around perfect squares")
	_crowd_windows()
	_fringe()
	_sweeps()
	_hash_boundaries()
	var game = Fixture.new()._game()
	var movers: Array = []
	for i in 12:
		game._spawn("engineer", 1, Hex.point([-4 - i / 4, i % 4 - 2]))
		movers.append(int(game.state.next_id) - 1)
	for r in range(-4, 5): game._spawn("wall", 1, Hex.point([0, r]))
	game.step([{"kind": "move", "player": 1, "actors": movers, "point": Hex.point([4, 0])}])
	for tick in 220:
		game.step([])
		_check(game._navigation_searches <= 1, "group joins shared static route without per-unit searches")
		if tick % 20 == 0: _check(game.state_hash() == StateCodec.hash_bytes(StateCodec.pack(game.state)), "state hash matches reference canonical state bytes")
	_check(game.entity(movers[0]).order.is_empty() and game.distance_squared(game.entity(movers[0]).position, Hex.point([4, 0])) <= Hex.SCALE * Hex.SCALE, "shared static group route still reaches destination around wall")
	# Interleaved hostile movement exercises incremental obstacle updates.
	game = Fixture.new()._game()
	var humans: Array = []; var foes: Array = []
	for i in 8:
		game._spawn("engineer", 1, Hex.point([-4 - i / 4, i % 4 - 2])); humans.append(int(game.state.next_id) - 1)
		game._spawn("scavenger", 9, Hex.point([4 + i / 4, i % 4 - 2])); foes.append(int(game.state.next_id) - 1)
	game.step([{"kind": "move", "player": 1, "actors": humans, "point": [0, 0, 0]}, {"kind": "move", "player": 9, "actors": foes, "point": [0, 0, 0]}])
	var saved: Dictionary = game.checkpoint()
	for tick in 80:
		game.step([])
		var separated := true
		for a in humans:
			for b in foes:
				var limit := Geo.radius(game, game.entity(a)) + Geo.radius(game, game.entity(b))
				if game.distance_squared(game.entity(a).position, game.entity(b).position) < limit * limit: separated = false
		_check(separated, "interleaved hostile groups never overlap bodies")
	_check(game._navigation_searches == 0, "moving hostile groups do not trigger global path searches")
	var expected: String = game.state_hash()
	game.restore(JSON.parse_string(JSON.stringify(saved))) # Raw JSON includes integral floats.
	for tick in 80: game.step([])
	_check(game.state_hash() == expected and expected == StateCodec.hash_bytes(StateCodec.pack(game.state)), "JSON restore reproduces local forces, obstacle snapshots and exact hashes")
	return {"checks": checks, "failures": failures}

func _typed_actors() -> void:
	var game = Fixture.new()._game()
	var actor: Actor = game.entity(2)
	_check(actor.motion.enabled and actor.has_capability("move") and game.entity(3).combat.enabled, "definitions compose typed actor capability state")
	_check(not game.entity(1).motion.enabled and game.entity(1).production_state.enabled, "structure capabilities compose independently of movement")
	actor.motion.navigation = {"path": [[100, 0, 200]]}
	actor.combat.ready_tick = 7
	actor.cargo.nacre = 3
	var saved: Dictionary = game.checkpoint()
	var expected: String = game.state_hash()
	_check(saved.actors[1] is Dictionary and StateCodec.pack(saved) == StateCodec.pack(game.state), "typed actors flatten to the existing canonical checkpoint schema")
	var copied := actor.duplicate(true)
	copied.motion.navigation.path[0][0] = 900
	_check(actor.motion.navigation.path[0][0] == 100 and copied.motion != actor.motion, "duplicated actors own independent capability objects and nested state")
	actor.motion.navigation.path[0][0] = 500
	actor.cargo.nacre = 99
	_check(saved.actors[1].navigation.path[0][0] == 100 and saved.actors[1].nacre == 3, "retained checkpoints cannot observe later component mutations")
	game.restore(saved)
	var restored: Actor = game.entity(2)
	_check(restored != actor and restored.motion != actor.motion and restored.motion.enabled and game.state_hash() == expected, "restore builds fresh composed actors with the exact saved hash")

func _entity_lookup() -> void:
	var game = Fixture.new()._game()
	var actor: Actor = game.state.actors[1]
	var id := int(actor.id)
	game._inside_step = true
	_check(game.entity(id) == actor and game.entity(-1) == null, "tick-local entity lookup resolves existing and missing IDs")
	actor.hp = 0
	_check(game.entity(id) == actor, "dead actors remain addressable before end-of-tick pruning")
	game._spawn("engineer", 1, Hex.point([-5, 0]))
	var born := int(game.state.next_id) - 1
	_check(game.entity(born) == game.state.actors.back(), "spawning updates an already populated tick-local index")
	var saved: Dictionary = game.checkpoint()
	game.restore(saved)
	_check(not game._inside_step and game._entity_index.is_empty(), "restore discards indexed actor references")
	game.step([])
	_check(game.entity(id) == null and game._entity_index.is_empty(), "tick pruning and completion discard dead/indexed actors")
	# Direct state edits remain supported outside the simulation update interval.
	var replacement: Actor = game.entity(born).duplicate(true)
	replacement.hp = 7
	game.state.actors[game.state.actors.size() - 1] = replacement
	_check(game.entity(born).hp == 7, "outside-tick entity lookup observes replaced actor dictionaries")
	game.state.actors.pop_back()
	_check(game.entity(born) == null, "outside-tick entity lookup observes direct actor removal")

func _state_codec() -> void:
	_check(StateCodec.pack({}) == PackedByteArray([65, 84, 68, 1, 8]), "ATD1 empty dictionary has a fixed golden encoding")
	_check(StateCodec.pack({"x": 0}) == PackedByteArray([65, 84, 68, 1, 6, 1, 1, 120, 80]), "ATD1 keyset and small integer have a fixed golden encoding")
	_check(StateCodec.pack({"x": [{"a": true}, {"a": false}]}) == PackedByteArray([65, 84, 68, 1, 6, 1, 1, 120, 5, 2, 6, 1, 1, 97, 2, 7, 1, 1]), "ATD1 schema IDs follow sorted traversal and are local to each snapshot")
	var layout_sample := {"a": [{"x": 1}, {"x": 2}]}
	var layout_expected := StateCodec.pack(layout_sample)
	for i in 12:
		StateCodec.pack({"different_%d" % i: {"nested_%d" % i: i}})
	_check(StateCodec.pack(layout_sample) == layout_expected, "keyset cache eviction and prior traversals cannot change wire schema IDs")
	layout_sample.a[0].x = 9
	_check(StateCodec.unpack(StateCodec.pack(layout_sample)) == layout_sample, "cached key order never retains mutable state values")
	var game = Fixture.new()._game()
	game.packed_rollback = true
	var samples: Array = [null, false, true, -9223372036854775807 - 1, 9223372036854775807, -65, -64, 175, 176, 1.25, 1.0, -0.0, "雪 ☃ 😀", "\"\\\n\v", &"named", [], {}, [{"a": 1}, {"a": 2}], {&"z": 2, "a": [false]}]
	for value in samples:
		var sample := {"value": value}
		var packed := StateCodec.pack(sample)
		var decoded = StateCodec.unpack(packed)
		_check(decoded is Dictionary and Canonical.text(decoded) == Canonical.text(sample) and StateCodec.pack(decoded) == packed, "ATD1 preserves all scalar boundaries, Unicode, nulls, containers and normalized names/floats")
	for size in [64, 65]:
		var sample: Dictionary = {}
		for i in size: sample["key_%03d" % i] = i - 70
		var packed := StateCodec.pack(sample)
		_check(StateCodec.unpack(packed) == sample, "ATD1 handles both sides of the small-keyset boundary")
	var valid := StateCodec.pack({"text": "雪", "array": [1, 2, 3]})
	for length in valid.size(): _check(StateCodec.unpack(valid.slice(0, length)) == null, "truncated ATD1 snapshots are rejected")
	for invalid in [PackedByteArray([65, 84, 68, 2, 8]), PackedByteArray([65, 84, 68, 1, 11]), PackedByteArray([65, 84, 68, 1, 7, 0]), PackedByteArray([65, 84, 68, 1, 6, 1, 1, 255, 80]), PackedByteArray([65, 84, 68, 1, 6, 1, 1, 0, 80]), valid + PackedByteArray([0])]:
		_check(StateCodec.unpack(invalid) == null, "invalid versions, tags, schema IDs, UTF-8 and trailing data are rejected")
	var frame: Dictionary = game.rollback_checkpoint()
	var original: String = game.state_hash()
	game.step([])
	_check(StateCodec.hash_bytes(StateCodec.pack(StateCodec.unpack(frame.packed))) == original, "retained packed snapshots are independent of subsequent encodes and ticks")
	game.restore_rollback(frame)
	_check(game.state_hash() == original, "packed rollback restores complete state and rebuilds derived caches")
	game.packed_rollback = false
	var plain: Dictionary = game.rollback_checkpoint()
	_check(game.rollback_hash(plain) == game.rollback_hash(frame), "dictionary and packed checkpoint representations have identical canonical hashes")
	game.step([]); game.restore_rollback(plain)
	_check(game.state_hash() == original, "dictionary rollback retains the same complete state as packed rollback")
	var reference = Sim.new()
	var fixture = Fixture.new(); reference.initialize(fixture._definitions(), fixture._players(), 42)
	reference.restore(game.checkpoint())
	_check(reference.state_hash() == game.state_hash(), "independent Godot sessions share the ATD1 hash format")

func _crowd_windows() -> void:
	_crowd_window_case()

func _crowd_window_case() -> void:
	var game = Fixture.new()._game()
	game._spawn("engineer", 1, [0, 0, 0]); var first = game.state.actors.back()
	game._spawn("engineer", 1, [3072, 0, 0]); var second = game.state.actors.back()
	var crowd := Crowd.new()
	crowd.rebuild(game.state.actors, game.content.units, {})
	var found := crowd.query(1, 0, 0, Hex.SCALE)
	_check(found.size() == 1 and found[0].id == int(first.id), "initial cached window excludes distant bodies")
	second.position = [-800, 0, 0]; crowd.moved(second)
	found = crowd.query(1, 0, 0, Hex.SCALE)
	_check(found.size() == 2, "entering an empty bucket invalidates cached windows")
	second.position = [400, 0, 0]; crowd.moved(second)
	found = crowd.query(1, 0, 0, Hex.SCALE)
	_check(found.size() == 2 and found[0].id != found[1].id, "live bucket arrays update without duplicate bodies")
	second.hp = 0
	found = crowd.query(1, 0, 0, Hex.SCALE)
	_check(found.size() == 1 and found[0].id == int(first.id), "dead bodies disappear from cached windows")
	first.position = [100, 0, -200]
	game.content.units.engineer.collision_radius = 0.375
	crowd.rebuild(game.state.actors, game.content.units, {str(first.id): [123, 0, -321]})
	var refreshed := crowd.body_for(int(first.id))
	_check(refreshed.q == 100 and refreshed.r == -200 and refreshed.radius == 384 and refreshed.vq == 123 and refreshed.vr == -321, "rebuilt bodies refresh direct state edits, definition radii and previous velocities")
	_check(crowd.body_for(int(second.id)) == null, "rebuilding drops dead actors and their materialized wrappers")
	first.velocity = [19, 0, -23]
	crowd.rebuild(game.state.actors, game.content.units, {"missing_actor": [0, 0, 0]})
	first.velocity = [99, 0, 99]
	var newborn := crowd.body_for(int(first.id))
	_check(newborn.vq == 19 and newborn.vr == -23, "late body wrappers retain frame-entry velocity for actors absent from previous snapshots")
	for value in [-4097, -4096, -2049, -2048, -1, 0, 2047, 2048, 4096]:
		_check(Crowd.coordinate(value) == floori(float(value) / 2048.0), "bucket coordinates floor both sides of zero")

func _fringe() -> void:
	var fixture = Fixture.new()
	var data: Dictionary = fixture._definitions()
	for definition in data.units.values():
		definition.capabilities.erase("perception"); definition.capabilities.erase("illumination")
	data.units.engineer.capabilities.perception = {"radius": 3.25}
	var game = Sim.new(); game.initialize(data, fixture._players(), 42)
	var cache: Dictionary = {}
	var expected: Dictionary = game.state.revealed["1"].duplicate()
	for tick in 80:
		var point := [-3 * Hex.SCALE + tick * 91, 0, -tick * 47]
		game.entity(2).position = point
		for q in range(-12, 13):
			for r in range(-12, 13):
				if game.distance_squared(point, Hex.point([q, r])) <= 3328 * 3328: expected[Hex.key([q, r])] = true
		Exploration.record(game, cache)
		_check(game.state.revealed["1"] == expected, "unknown-fringe exploration matches exhaustive circle rasterization")

func _sweeps() -> void:
	# Compare allocation-free contact checks with the original geometry oracle,
	# including intersecting starts, tangencies and sub-tile rounding.
	for i in 600:
		var a := [i * 391 % 4096 - 2048, 0, i * 977 % 4096 - 2048]
		var b := [int(a[0]) + i * 73 % 1024 - 512, 0, int(a[2]) + i * 157 % 1024 - 512]
		var center := [i * 811 % 4096 - 2048, i * 619 % 4096 - 2048]
		var start := [a[0], a[2]]; var end := [b[0], b[2]]
		var radius := i * 19 % 768; var other_radius := i * 29 % 768
		var limit := radius + other_radius + 2
		var closest := Geo.segment_distance(center, start, end)
		var start_distance := Geo.metric(Geo.sub(center, start))
		var expected := closest > limit * limit or (start_distance < limit * limit and Geo.metric(Geo.sub(center, end)) > start_distance and closest >= start_distance)
		_check(Nav.enemy_clear(a, b, radius, [{"position": [center[0], 0, center[1]], "radius": other_radius}]) == expected, "scalar swept-circle contact matches geometry oracle")
		var body := Crowd.Body.new(); body.q = int(a[0]); body.r = int(a[2]); body.radius = radius
		var enemy := Crowd.Body.new(); enemy.q = int(center[0]); enemy.r = int(center[1]); enemy.radius = other_radius
		var enemies: Array[Crowd.Body] = [enemy]
		_check(Crowd.contact_clear(body, int(b[0]), int(b[2]), enemies) == expected, "typed crowd contact matches independent swept-circle oracle")
	var game = Fixture.new()._game()
	for r in range(-3, 4): game._spawn("wall", 1, Hex.point([0, r]))
	var data := Nav.static_field(game.navigation_field())
	for q in range(-5, 6):
		for r in range(-5, 6):
			var origin := [q * Hex.SCALE + 241, 0, r * Hex.SCALE - 137]
			var size := 205; var speed := 154
			if not Nav.center_clear(game, Hex.from_point(origin), size + speed + Hex.SCALE + 4, data): continue
			for offset in Hex.NEIGHBORS:
				var target := [int(origin[0]) + int(offset[0]) * speed, 0, int(origin[2]) + int(offset[1]) * speed]
				_check(Nav.segment_clear(game, origin, target, size, data.blocked), "tile certificate preserves static clearance in every direction")

func _hash_boundaries() -> void:
	var fixture = Fixture.new()
	var data: Dictionary = fixture._definitions()
	var full = Rollback.new(); var sparse = Rollback.new()
	full.initialize(data, fixture._players(), 42, 0)
	sparse.initialize(data, fixture._players(), 42, 0, 20)
	var confirmed: Array = []
	sparse.events_confirmed.connect(func(events): confirmed.append(events))
	var commands := [{"kind": "move", "actors": [2], "point": [0, 0, 0]}]
	for tick in 45:
		for player in [1, 9]:
			full.receive(player, tick, commands if tick == 3 and player == 1 else [])
			if tick != 3 or player != 1: sparse.receive(player, tick, [])
	for tick in 10: full.advance(); sparse.advance()
	_check(sparse.receive(1, 3, commands) and sparse.rollbacks == 1, "sparse-hash session replays late commands")
	for tick in 35: full.advance(); sparse.advance()
	_check(full.simulation.state_hash() == sparse.simulation.state_hash(), "hash cadence does not change gameplay")
	_check(sparse.hashes.size() == 3 and sparse.hashes[20] == full.hashes[20] and sparse.hashes[40] == full.hashes[40], "only exchange boundaries are hashed and corrected after replay")
	_check(confirmed.size() == 45 and sparse.checkpoints.size() == full.checkpoints.size(), "sparse hashes retain per-tick checkpoints and event confirmation")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
