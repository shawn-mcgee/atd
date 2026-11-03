extends RefCounted
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
	_state_codec()
	_motion_checkpoints()
	_native_equivalence()
	_batch_handlers()
	_automatic_batch_boundaries()
	for bits in 63:
		for offset in [-1, 0, 1]:
			var value: int = (1 << bits) + offset
			var root: int = Sim.integer_sqrt(value)
			_check((root == 0 and value == 0) or (root > 0 and root <= value / root and root + 1 > value / (root + 1)), "integer root remains exact at bit boundaries")
	var top := Sim.integer_sqrt(9223372036854775807)
	_check(top == 3037000499, "integer root handles maximum signed input without overflow")
	for root in [1, 2, 3, 15, 255, 65535, 65536, 1048575, 134217728, 2147483647, 3037000499]:
		for offset in [-1, 0, 1]:
			_check(Sim.integer_sqrt(root * root + offset) == root - (1 if offset == -1 else 0), "native root estimate is corrected exactly around perfect squares")
	_crowd_windows()
	_bulk_crowd()
	_tick_velocity_capture()
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
		if tick % 20 == 0: _check(game.state_hash() == StateCodec.hash_bytes(StateCodec.pack(game.state)), "native state hash matches reference canonical state bytes")
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

func _state_codec() -> void:
	_check(StateCodec.pack({}) == PackedByteArray([65, 84, 68, 1, 8]), "ATD1 empty dictionary has a fixed golden encoding")
	_check(StateCodec.pack({"x": 0}) == PackedByteArray([65, 84, 68, 1, 6, 1, 1, 120, 80]), "ATD1 keyset and small integer have a fixed golden encoding")
	_check(StateCodec.pack({"x": [{"a": true}, {"a": false}]}) == PackedByteArray([65, 84, 68, 1, 6, 1, 1, 120, 5, 2, 6, 1, 1, 97, 2, 7, 1, 1]), "ATD1 schema IDs follow sorted traversal and are local to each snapshot")
	var game = Fixture.new()._game()
	game.packed_rollback = true
	var backend = game._crowd.backend
	var samples: Array = [null, false, true, -9223372036854775807 - 1, 9223372036854775807, -65, -64, 175, 176, 1.25, 1.0, -0.0, "雪 ☃ 😀", "\"\\\n\v", &"named", [], {}, [{"a": 1}, {"a": 2}], {&"z": 2, "a": [false]}, Vector3i.ZERO, Vector3i(-2147483648, 2147483647, -1), {"nested": [Vector3i(176, -65, 1024)]}]
	for value in samples:
		var sample := {"value": value}
		var packed := StateCodec.pack(sample)
		var decoded = StateCodec.unpack(packed)
		_check(decoded is Dictionary and Canonical.text(decoded) == Canonical.text(sample) and StateCodec.pack(decoded) == packed, "ATD1 preserves all scalar boundaries, Unicode, nulls, containers and normalized names/floats")
		if backend != null:
			_check(backend.call("state_pack", sample) == packed, "compiled ATD1 bytes match the independent reference encoder")
			var native_decoded = backend.call("state_unpack", packed)
			_check(native_decoded is Dictionary and StateCodec.pack(native_decoded) == packed, "compiled decoder preserves reference scalar and container encodings")
	for size in [64, 65]:
		var sample: Dictionary = {}
		for i in size: sample["key_%03d" % i] = i - 70
		var packed := StateCodec.pack(sample)
		_check(StateCodec.unpack(packed) == sample, "ATD1 handles both sides of the small-keyset boundary")
		if backend != null:
			_check(backend.call("state_pack", sample) == packed, "compiled large-map encoding matches reference")
			_check(backend.call("state_unpack", packed) == sample, "compiled decoder preserves both sides of the keyset boundary")
	if backend != null:
		var nested: Dictionary = {}
		for i in 65:
			var child: Dictionary = {}
			for j in (65 if i < 6 else 0): child["child_%d_%d" % [i, j]] = i + j
			nested["parent_%d" % i] = child
		for repeat in 2:
			nested.parent_0.child_0_0 = repeat + 7
			_check(backend.call("state_pack", nested) == StateCodec.pack(nested), "nested large-keyset eviction retains parent keys and reads live values without affecting wire bytes")
	var valid := StateCodec.pack({"text": "雪", "array": [1, 2, 3]})
	for length in valid.size():
		var truncated := valid.slice(0, length)
		_check(StateCodec.unpack(truncated) == null, "truncated ATD1 snapshots are rejected")
		if backend != null: _check(backend.call("state_unpack", truncated) == null, "compiled decoder rejects every truncated snapshot prefix")
	for invalid in [PackedByteArray([65, 84, 68, 2, 8]), PackedByteArray([65, 84, 68, 1, 11]), PackedByteArray([65, 84, 68, 1, 7, 0]), PackedByteArray([65, 84, 68, 1, 6, 1, 1, 255, 80]), PackedByteArray([65, 84, 68, 1, 6, 1, 1, 0, 80]), valid + PackedByteArray([0])]:
		_check(StateCodec.unpack(invalid) == null, "invalid versions, tags, schema IDs, UTF-8 and trailing data are rejected")
		if backend != null: _check(backend.call("state_unpack", invalid) == null, "compiled decoder rejects invalid versions, tags, schemas, UTF-8 and trailing data")
	if backend != null:
		var source := StateCodec.pack({"雪": [{"n": -9223372036854775807 - 1, "t": "😀"}, {"n": 176, "t": "café"}], "number": 1.25})
		var seed_value := 12345
		for i in 256:
			seed_value = (seed_value * 1103515245 + 12345) & 0x7fffffff
			var mutated := source.duplicate()
			mutated[seed_value % mutated.size()] = (seed_value >> 16) & 255
			var expected = StateCodec.unpack(mutated)
			var actual = backend.call("state_unpack", mutated)
			_check((expected == null and actual == null) or (expected is Dictionary and actual is Dictionary and StateCodec.pack(actual) == StateCodec.pack(expected)), "compiled decoding matches reference validation on deterministic byte mutations and Unicode keysets")
	for levels in [126, 127]:
		var nested = Vector3i.ZERO
		for level in levels: nested = [nested]
		var packed := StateCodec.pack({"value": nested})
		_check(packed.is_empty() == (levels == 127), "compact vectors preserve the array encoding depth limit")
		if backend != null: _check(backend.call("state_pack", {"value": nested}) == packed, "native compact-vector depth checks match the reference")
	var frame: Dictionary = game.rollback_checkpoint()
	var original: String = game.state_hash()
	game.step([])
	_check(StateCodec.hash_bytes(StateCodec.pack(StateCodec.unpack(frame.packed))) == original, "retained packed snapshots are independent of subsequent native encodes and ticks")
	game.restore_rollback(frame)
	_check(game.state_hash() == original, "packed rollback restores complete state and rebuilds derived caches")
	game.packed_rollback = false
	var plain: Dictionary = game.rollback_checkpoint()
	_check(game.rollback_hash(plain) == game.rollback_hash(frame), "dictionary and packed checkpoint representations have identical canonical hashes")
	var boundary: Dictionary = game.rollback_checkpoint(true)
	_check(boundary.has("packed") and not boundary.has("state") and game.rollback_hash(boundary) == original, "Web hash boundaries retain canonical bytes without also copying the state dictionary")
	game.step([]); game.restore_rollback(plain)
	_check(game.state_hash() == original, "dictionary rollback retains the same complete state as packed rollback")
	var reference = Sim.new(); reference.accelerated = false
	var fixture = Fixture.new(); reference.initialize(fixture._definitions(), fixture._players(), 42)
	reference.restore(game.checkpoint())
	_check(reference.state_hash() == game.state_hash(), "reference and compiled sessions share the ATD1 hash format")

func _motion_checkpoints() -> void:
	var game = Fixture.new()._game()
	game.packed_rollback = false
	game.entity(2).velocity = Vector3i(73, 0, -18)
	game.entity(2).facing = Vector3i(1024, 0, -512)
	var original: String = game.state_hash()
	var internal: Dictionary = game.rollback_checkpoint()
	var public: Dictionary = game.checkpoint()
	_check(internal.state.actors[1].velocity is Vector3i and public.actors[1].velocity == [73, 0, -18] and public.actors[1].facing == [1024, 0, -512], "internal snapshots retain compact motion while public checkpoints expose integer arrays")
	_check(game.packed_state(internal.state) == game.packed_state(public), "compact and public motion have identical canonical bytes")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(public))
	_check(parsed.actors[1].velocity is Array and parsed.actors[1].facing is Array, "ordinary public checkpoint JSON preserves motion arrays")
	game.restore(parsed)
	_check(game.entity(2).velocity is Vector3i and game.entity(2).facing is Vector3i and game.state_hash() == original, "JSON restore rebuilds compact motion without changing state")
	var packed: Dictionary = game.rollback_checkpoint(true)
	game.entity(2).velocity[0] = 99
	game.restore_rollback(packed)
	_check(game.state_hash() == original and game.entity(2).velocity is Vector3i, "packed restore rebuilds independent compact motion")
	var session = Rollback.new(); session.checkpoints[0] = internal
	var debug: Dictionary = session.checkpoint_state(0)
	debug.actors[1].velocity[0] = 123
	public.actors[1].facing[0] = 321
	_check(internal.state.actors[1].velocity == Vector3i(73, 0, -18) and game.state_hash() == original, "editable public and debug motion arrays never mutate live or retained snapshots")
	var wide: Dictionary = game.checkpoint(); wide.actors[1].velocity = [1 << 40, 0, 0]
	game.restore(wide)
	_check(game.entity(2).velocity == [1 << 40, 0, 0] and game.state_hash() == StateCodec.hash_bytes(StateCodec.pack(wide)), "restore preserves legacy int64 motion outside the compact range")

func _automatic_batch_boundaries() -> void:
	for scenario in ["neutral", "empty_target", "expired", "stale_order", "active", "manual"]:
		var game = Fixture.new()._game()
		game.entity(5).position = [0, 0, 0]
		game.entity(3).position = [3072, 0, 0]
		game.state.tick = 10
		var actor = game.entity(5)
		actor.veil_stance = {"mode": "offensive", "network": 1, "order": 1, "target": [-4096, 0, 0], "expires": 50}
		actor.order = {"kind": "move", "point": [-6144, 0, 0]}
		match scenario:
			"neutral": actor.veil_stance.mode = "neutral"
			"empty_target": actor.veil_stance.target = []
			"expired": actor.veil_stance.expires = 10
			"stale_order": actor.veil_stance.mode = "neutral"; actor.order.veil_order = true
			"manual": actor.order.manual = true
		var reference = Sim.new(); reference.accelerated = false
		reference.initialize(game.content, game.state.players, 42); reference.restore(game.checkpoint())
		game.step([]); reference.step([])
		_check(game.state_hash() == reference.state_hash(), "automatic batch boundary matches reference for %s stance/order" % scenario)
		if scenario == "active": _check(actor.order.get("kind") == "attack", "active mobile stance still performs due automatic targeting")
		if scenario == "stale_order": _check(actor.order.is_empty(), "inactive old Veil order is still cleared on the due tick")

func _batch_handlers() -> void:
	if not ClassDB.class_exists("ATDMovementKernel"): return
	var fixture = Fixture.new(); var data: Dictionary = fixture._definitions()
	data.units.engineer.capabilities.illumination = {"radius": 2}
	data.units.engineer.capabilities.factory = {"produces": ["engineer"]}
	data.units.scavenger.capabilities.passive_spawner = {"definition": "scavenger", "interval_ticks": 5, "max_alive": 1, "spawn_radius": 1}
	var game = Sim.new(); game.initialize(data, fixture._players(), 42)
	var humans: Array = []; var foes: Array = []
	for i in 3:
		game._spawn("engineer", 1, [-4096 - i * 512, 0, -2048]); humans.append(int(game.state.next_id) - 1)
		game._spawn("scavenger", 9, [4096 + i * 512, 0, 2048]); foes.append(int(game.state.next_id) - 1)
	game.entity(humans[1]).production = [{"definition": "engineer", "remaining": 2}]
	var reference = Sim.new(); reference.accelerated = false
	reference.initialize(data, fixture._players(), 42); reference.restore(game.checkpoint())
	for tick in 25:
		var commands: Array = []
		if tick == 0: commands = [{"kind": "move", "player": 1, "actors": humans, "point": [4096, 0, -1024]}, {"kind": "move", "player": 9, "actors": foes, "point": [-4096, 0, 1024]}]
		game.step(commands); reference.step(commands)
		_check(game.state_hash() == reference.state_hash(), "point batches preserve interleaved production, passive mobile sources, light invalidation, foreign obstacle caches and actor order")

func _tick_velocity_capture() -> void:
	var game = Fixture.new()._game()
	if game._crowd.backend == null: return
	game.entity(2).velocity = [73, 0, -18]
	game.entity(5).velocity = [-31, 0, 97]
	var positions: Array = game.state.actors.map(func(actor): return actor.position.duplicate())
	var previous: Dictionary = game._crowd.backend.call("begin_tick", game.state.actors)
	_check(previous.size() == game.state.actors.size() and previous[2] == [73, 0, -18] and previous[5] == [-31, 0, 97], "native tick capture retains previous velocities using actor IDs")
	_check(game.state.actors.all(func(actor): return actor.velocity == Vector3i.ZERO) and game.state.actors.map(func(actor): return actor.position) == positions, "native tick capture clears every velocity without changing position")
	game.entity(2).velocity[0] = 99
	_check(game.entity(5).velocity == Vector3i.ZERO and previous[2] == [73, 0, -18], "velocity resets leave actor and retained arrays independent")
	game.entity(2).velocity = [25, 0, 13]
	var next: Dictionary = game._crowd.backend.call("begin_tick", game.state.actors)
	_check(next[2] == [25, 0, 13] and previous[2] == [73, 0, -18], "successive native captures never alias earlier snapshot values")

func _bulk_crowd() -> void:
	var game = Fixture.new()._game()
	if game._crowd.backend == null: return
	var native = Crowd.new(); var reference = Crowd.new(false)
	var velocities := {2: [73, 0, -18], 5: [-31, 0, 97]}
	for phase in 3:
		if phase == 1:
			game.content.units.engineer.collision_radius = 1 # Integer content values are valid.
			game.entity(5).owner = 1
			game._spawn("engineer", 9, [1024, 0, -512]); game.entity(7).velocity = [19, 0, 37]
		if phase == 2:
			game.entity(2).hp = 0
			game.entity(5).definition = "maw" # Membership changes on transformation.
		native.rebuild(game.state.actors, game.content.units, velocities)
		reference.rebuild(game.state.actors, game.content.units, velocities)
		_check(native.owners == reference.owners, "bulk index preserves sorted owners after spawn, death, ownership and definition changes")
		for actor in game.state.actors:
			var actual = native.body(int(actor.id)); var expected = reference.body(int(actor.id))
			_check((actual == null and expected == null) or (actual != null and expected != null and actual.actor == expected.actor and [actual.owner, actual.radius, actual.q, actual.r, actual.vq, actual.vr] == [expected.owner, expected.radius, expected.q, expected.r, expected.vq, expected.vr]), "lazy body metadata matches reference including previous velocity and current content")
		for owner in [1, 9]:
			for point in [Vector2i(-12288, 0), Vector2i(0, 0), Vector2i(12288, 0)]:
				_check(native.query(owner, point.x, point.y, 16384).map(func(row): return row.id) == reference.query(owner, point.x, point.y, 16384).map(func(row): return row.id), "bulk queries retain exact reference bucket order and membership")
		var moving = game.entity(6)
		moving.position = [phase * 2048 - 2049, 0, -2049]
		native.moved(moving); reference.moved(moving)
		_check(native.body(6).q == int(moving.position[0]) and native.query(int(moving.owner), -2048, -2048, 4096).map(func(row): return row.id) == reference.query(int(moving.owner), -2048, -2048, 4096).map(func(row): return row.id), "incremental updates keep native index and existing lazy wrappers synchronized")
		moving.hp = 0
		_check(native.query(int(moving.owner), -2048, -2048, 4096).map(func(row): return row.id) == reference.query(int(moving.owner), -2048, -2048, 4096).map(func(row): return row.id), "lazy wrappers retain live actor references for death filtering")
		moving.hp = 15

func _native_equivalence() -> void:
	var loaded := ClassDB.class_exists("ATDMovementKernel")
	_check(loaded or not "--require-native" in OS.get_cmdline_user_args(), "required compiled movement kernel is loaded")
	if not loaded: return
	var encoder = Fixture.new()._game()._crowd.backend
	if encoder == null:
		_check(false, "loaded movement kernel ABI matches the current core")
		return
	var controls := ""
	for code in range(1, 32): controls += String.chr(code)
	var samples: Array = [null, false, true, 0, -1, -9223372036854775807 - 1, 9223372036854775807, "\"\\/\n\r\t\v", controls, "Café ☃ 😀", [], {}, {&"named": &"value", "a": [1, false, "text"]}]
	for value in samples:
		var sample := {"value": value}
		var bytes: PackedByteArray = encoder.call("state_bytes", sample)
		_check(bytes == JSON.stringify(sample, "", true, true).to_utf8_buffer(), "compiled serializer preserves exact sorted JSON bytes, escapes, Unicode and int64 values")
	var unsupported: PackedByteArray = encoder.call("state_bytes", {"float": 0.5})
	_check(unsupported.is_empty(), "unsupported scalar types retain Godot's full serializer")
	unsupported = encoder.call("state_bytes", {"雪": 1})
	_check(unsupported.is_empty(), "arbitrary Unicode keys retain Godot's full serializer")
	for tick in 16:
		var changed := {&"named": tick, "a": [tick % 2 == 0, "changed %d" % tick], "extra_%d" % (tick % 3): tick * -3}
		var bytes: PackedByteArray = encoder.call("state_bytes", changed)
		_check(bytes == JSON.stringify(changed, "", true, true).to_utf8_buffer(), "cached keysets validate changing layouts and read current values")
		var normalized: Dictionary = Canonical.normalize(changed)
		bytes = encoder.call("state_bytes", normalized)
		_check(bytes == JSON.stringify(normalized, "", true, true).to_utf8_buffer(), "cached keysets support mixed interned and ordinary keys after normalization")
	for i in 20:
		var nested := {"a_%d" % (i % 7): i, "b": {"a_%d" % ((i + 1) % 7): i + 1, "b": false, "c": []}, "c": true}
		var bytes: PackedByteArray = encoder.call("state_bytes", nested)
		_check(bytes == JSON.stringify(nested, "", true, true).to_utf8_buffer(), "nested and changing keysets preserve exact output beyond the schema-cache cap")
	_native_discovery()
	_native_observer_changes()
	_native_clearance()
	_native_route_keys()
	_native_spatial_queries()
	for walls in [false, true]:
		var game = Fixture.new()._game()
		var humans: Array = []; var foes: Array = []
		for i in 8:
			game._spawn("engineer", 1, [-4096 - i / 4 * 1024, 0, i % 4 * 384 - 768]); humans.append(int(game.state.next_id) - 1)
			game._spawn("scavenger", 9, [4096 + i / 4 * 1024, 0, i % 4 * 384 - 768]); foes.append(int(game.state.next_id) - 1)
		game._spawn("mother", 9, [4096, 0, -3072]); foes.append(int(game.state.next_id) - 1)
		if walls:
			for r in range(-2, 3): game._spawn("wall", 1, Hex.point([0, r]))
		var reference = Sim.new(); reference.accelerated = false
		reference.initialize(game.content, game.state.players, 42); reference.restore(game.checkpoint())
		_check(game._crowd.backend != null and reference._crowd.backend == null, "native/reference equivalence uses distinct movement implementations")
		var saved: Dictionary
		for tick in 140:
			var commands: Array = []
			if tick == 0:
				commands = [{"kind": "move", "player": 1, "actors": humans, "point": [4096, 0, 0]}, {"kind": "move", "player": 9, "actors": foes, "point": [-4096, 0, 0]}, {"kind": "train", "player": 1, "actors": [1], "definition": "engineer"}]
			if tick == 30: commands = [{"kind": "attack", "player": 1, "actors": [2], "target": foes[0]}]
			game.step(commands); reference.step(commands)
			_check(game.state_hash() == reference.state_hash(), "compiled movement matches reference tick, including hard contact, large bodies, routes, production and death")
			if tick == 40: saved = game.checkpoint()
		var expected: String = game.state_hash()
		game.restore(JSON.parse_string(JSON.stringify(saved)))
		for tick in 99: game.step([])
		_check(game.state_hash() == expected, "compiled movement rebuilds derived bodies after JSON restore")

func _native_route_keys() -> void:
	var game = Fixture.new()._game()
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": Hex.point([6, 0])}])
	var reference = Sim.new(); reference.accelerated = false
	reference.initialize(game.content, game.state.players, 42); reference.restore(game.checkpoint())
	for phase in 11:
		for engine in [game, reference]:
			var actor = engine.entity(2)
			match phase:
				0: actor.navigation.key[0][0] += 1
				1: actor.navigation.key[1] = 99
				2: actor.navigation.key[2] = 512
				3: actor.navigation.key[3] = "changed"
				4: actor.navigation.key[4] += 1
				5: actor.navigation.key[5] = true
				6: actor.avoidance.progress_for[2] += 1
				7: actor.navigation.direct = false
				8: engine.content.units.engineer.collision_radius = 0.33
				9: engine._spawn("wall", 1, Hex.point([0, 7]))
				10: engine.restore(engine.checkpoint())
			engine.step([])
		_check(game.state_hash() == reference.state_hash(), "private route expectations follow live key, goal, radius, geometry and restore changes (%d)" % phase)
	game = Fixture.new()._game(); game.entity(2).position = Hex.point([0, 3])
	reference.initialize(game.content, game.state.players, 42); reference.restore(game.checkpoint())
	for phase in 141:
		var index := phase if phase < 140 else 0
		var goal := [(-6144 if index % 2 == 0 else 6144), 0, 3072 + index * 13]
		var commands := [{"kind": "move", "player": 1, "actors": [2], "point": goal}]
		game.step(commands); reference.step(commands)
		_check(game.state_hash() == reference.state_hash(), "bounded route expectations preserve reference state across eviction and destination reuse (%d)" % phase)

@warning_ignore("integer_division")
func _native_spatial_queries() -> void:
	var game = Fixture.new()._game()
	game.content.units.mother.collision_radius = 2.25
	for index in 90:
		game._spawn("mother" if index % 13 == 0 else "engineer", [1, 9, 17][index % 3], [(index % 10 - 5) * 512, 0, (index / 10 - 4) * 512])
	var native := Crowd.new(); var reference := Crowd.new(false)
	native.rebuild(game.state.actors, game.content.units, {})
	reference.rebuild(game.state.actors, game.content.units, {})
	for phase in 2:
		if phase == 1:
			game.entity(7).position = [-2049, 0, 2048]
			native.moved(game.entity(7)); reference.moved(game.entity(7))
		for owner in [1, 9, 17]:
			for point in [Vector2i(-2049, 0), Vector2i.ZERO, Vector2i(2048, -2048)]:
				for cap in [0, 1, 7, 24]:
					for offset in [0, 5, 37]:
						_check(native.query(owner, point.x, point.y, 2300, cap, offset).map(func(body): return body.id) == reference.query(owner, point.x, point.y, 2300, cap, offset).map(func(body): return body.id), "streamed queries preserve three-owner scan limits, bucket order, offsets and moved large bodies")
		for id in [2, 7, 42, 95]:
			var body: Crowd.Body = reference.body(id)
			var enemies: Array[Crowd.Body] = []
			for other in reference.bodies.values():
				if other.owner != body.owner: enemies.append(other)
			for offset in [Vector2i.ZERO, Vector2i(2050, -1600), Vector2i(-1000, 512), Vector2i(7000, 7000)]:
				var point: Vector2i = Vector2i(body.q, body.r) + offset
				var expected := 0
				for other in reference.bodies.values():
					if other.id == id or other.owner != body.owner: continue
					var limit: int = body.radius + other.radius
					expected += maxi(0, limit * limit - Geo.metric([point.x - other.q, point.y - other.r])) * 4096 / (limit * limit)
				_check(int(native.backend.call("pressure", id, point)) == expected, "spatial pressure equals the exhaustive all-body sum")
				var reach := body.radius + Sim.integer_sqrt(Geo.metric([offset.x, offset.y])) + 2
				_check(bool(native.backend.call("contact", id, point, reach)) == Crowd.contact_clear(body, point.x, point.y, enemies), "streamed hard contact matches all hostile bodies without a prediction scan limit")

func _native_discovery() -> void:
	for radius in [0.0, 0.75, 9.25]:
		var fixture = Fixture.new()
		var data: Dictionary = fixture._definitions(); data.settings.map_radius = 4
		for definition in data.units.values():
			definition.capabilities.erase("perception"); definition.capabilities.erase("illumination")
		data.units.engineer.capabilities.perception = {"radius": radius}
		var game = Sim.new(); game.initialize(data, fixture._players(), 42)
		var expected: Dictionary = game.state.revealed.duplicate(true)
		var reach := int(round(radius * Hex.SCALE))
		for tick in 40:
			var actor = game.entity(2)
			actor.owner = 1 if tick % 7 < 3 else 9
			actor.position = [(tick * 359 % 8193) - 4096, 0, (tick * 733 % 8193) - 4096]
			for q in range(-4, 5):
				for r in range(-4, 5):
					if absi(q + r) <= 4 and game.distance_squared(actor.position, Hex.point([q, r])) <= reach * reach: expected[str(actor.owner)][Hex.key([q, r])] = true
			Exploration.record(game, game._exploration_cache)
			_check(game.state.revealed == expected, "compiled discovery matches exhaustive map edges, zero/fractional/large radii and ownership changes")
			if tick == 20: game.restore(game.checkpoint())

func _native_observer_changes() -> void:
	var fixture = Fixture.new()
	var data: Dictionary = fixture._definitions(); data.settings.map_radius = 5
	for definition in data.units.values():
		definition.capabilities.erase("perception"); definition.capabilities.erase("illumination")
	data.units.engineer.capabilities.perception = {"radius": 0.75}
	data.units.hq.capabilities.perception = {"radius": 1}
	data.units.womb.capabilities.perception = {"radius": 2.25}
	data.units.maw.footprint = [[0, 0], [1, 0], [2, 0]]
	var game = Sim.new(); game.initialize(data, fixture._players(), 42)
	game._spawn("womb", 9, [0, 0, 0])
	game.entity(7).construction = {"definition": "maw"}
	var expected: Dictionary = game.state.revealed.duplicate(true)
	for tick in 48:
		game.entity(2).owner = 1 if tick % 3 else 9
		game.entity(2).position = [tick * 359 % 10241 - 5120, 0, tick * 733 % 10241 - 5120]
		game.entity(2).hp = 0 if tick % 7 == 0 else 10
		game.entity(1).position = [tick * 161 % 8193 - 4096, 0, tick * 317 % 8193 - 4096]
		game.entity(7).rotation = tick % 6
		game.content.units.engineer.capabilities.perception.radius = tick % 4 if tick % 2 else 1.25
		if tick == 24: game.content.units.engineer.capabilities.erase("move")
		if tick == 36: game.content.units.engineer.capabilities.move = {"speed": 3}
		for actor in game.state.actors:
			var caps: Dictionary = game.content.units[actor.definition].capabilities
			if int(actor.hp) <= 0 or not caps.has("perception"): continue
			var center := Geo.center(game, actor)
			var reach := int(round(float(caps.perception.radius) * Hex.SCALE))
			for q in range(-5, 6):
				for r in range(-5, 6):
					if absi(q + r) <= 5 and game.distance_squared(center, Hex.point([q, r])) <= reach * reach: expected[str(actor.owner)][Hex.key([q, r])] = true
		Exploration.record(game, game._exploration_cache)
		_check(game.state.revealed == expected, "bulk discovery follows live capability, owner, life, radius, rotated footprint and Womb center changes")
		if tick == 20: game.restore(game.checkpoint())

func _native_clearance() -> void:
	for mode in 4:
		var fixture = Fixture.new()
		var data: Dictionary = fixture._definitions()
		data.settings.map_radius = 12 if mode < 3 else 3
		data.settings.terrain = []
		if mode == 1:
			for q in range(-3, 4):
				for r in range(-3, 4): data.settings.terrain.append([q, r])
		var game = Sim.new(); game.initialize(data, fixture._players(), 42)
		if mode == 0: game._spawn("wall", 1, [0, 0, 0])
		var field: Dictionary = game.navigation_field()
		var oracle := {"hexes": field.blocked.hexes, "circles": field.blocked.circles}
		for i in 240:
			var extent := 14336 if mode < 3 else 4096
			var a := [i * 391 % (extent * 2) - extent, 0, i * 977 % (extent * 2) - extent]
			var b := [int(a[0]) + i * 73 % 8192 - 4096, 0, int(a[2]) + i * 157 % 8192 - 4096]
			if i % 5 == 0: b = a
			var size := i * 19 % 2048
			_check(Nav.segment_clear(game, a, b, size, field.blocked) == Nav.segment_clear(game, a, b, size, oracle), "compiled static clearance matches independent GDScript circle/hex/map-edge oracle")
		game._spawn("wall", 1, [3072, 0, 0])
		game.navigation_field()
		_check(int(game._crowd.backend.call("static_clear", int(field.blocked.native_revision), Vector2i(2048, 0), Vector2i(4096, 0), 205)) == -1, "stale native world revisions decline rather than query changed geometry")
		_check(Nav.segment_clear(game, [2048, 0, 0], [4096, 0, 0], 205, field.blocked) == Nav.segment_clear(game, [2048, 0, 0], [4096, 0, 0], 205, oracle), "retained static fields preserve their original clearance after world changes")

func _crowd_windows() -> void:
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
