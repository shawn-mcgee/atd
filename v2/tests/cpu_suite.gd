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
	_native_equivalence()
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
	var samples: Array = [null, false, true, -9223372036854775807 - 1, 9223372036854775807, -65, -64, 175, 176, 1.25, 1.0, -0.0, "雪 ☃ 😀", "\"\\\n\v", &"named", [], {}, [{"a": 1}, {"a": 2}], {&"z": 2, "a": [false]}]
	for value in samples:
		var sample := {"value": value}
		var packed := StateCodec.pack(sample)
		var decoded = StateCodec.unpack(packed)
		_check(decoded is Dictionary and Canonical.text(decoded) == Canonical.text(sample) and StateCodec.pack(decoded) == packed, "ATD1 preserves all scalar boundaries, Unicode, nulls, containers and normalized names/floats")
		if backend != null:
			_check(backend.call("state_pack", sample) == packed, "compiled ATD1 bytes match the independent reference encoder")
	for size in [64, 65]:
		var sample: Dictionary = {}
		for i in size: sample["key_%03d" % i] = i - 70
		var packed := StateCodec.pack(sample)
		_check(StateCodec.unpack(packed) == sample, "ATD1 handles both sides of the small-keyset boundary")
		if backend != null: _check(backend.call("state_pack", sample) == packed, "compiled large-map encoding matches reference")
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
	for length in valid.size(): _check(StateCodec.unpack(valid.slice(0, length)) == null, "truncated ATD1 snapshots are rejected")
	for invalid in [PackedByteArray([65, 84, 68, 2, 8]), PackedByteArray([65, 84, 68, 1, 11]), PackedByteArray([65, 84, 68, 1, 7, 0]), PackedByteArray([65, 84, 68, 1, 6, 1, 1, 255, 80]), PackedByteArray([65, 84, 68, 1, 6, 1, 1, 0, 80]), valid + PackedByteArray([0])]:
		_check(StateCodec.unpack(invalid) == null, "invalid versions, tags, schema IDs, UTF-8 and trailing data are rejected")
	var frame: Dictionary = game.rollback_checkpoint()
	var original: String = game.state_hash()
	game.step([])
	_check(StateCodec.hash_bytes(StateCodec.pack(StateCodec.unpack(frame.packed))) == original, "retained packed snapshots are independent of subsequent native encodes and ticks")
	game.restore_rollback(frame)
	_check(game.state_hash() == original, "packed rollback restores complete state and rebuilds derived caches")
	game.packed_rollback = false
	var plain: Dictionary = game.rollback_checkpoint()
	_check(game.rollback_hash(plain) == game.rollback_hash(frame), "dictionary and packed checkpoint representations have identical canonical hashes")
	game.step([]); game.restore_rollback(plain)
	_check(game.state_hash() == original, "dictionary rollback retains the same complete state as packed rollback")
	var reference = Sim.new(); reference.accelerated = false
	var fixture = Fixture.new(); reference.initialize(fixture._definitions(), fixture._players(), 42)
	reference.restore(game.checkpoint())
	_check(reference.state_hash() == game.state_hash(), "reference and compiled sessions share the ATD1 hash format")

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
	_native_clearance()
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
