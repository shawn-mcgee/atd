extends RefCounted
const Fixture = preload("res://tests/geometry_suite.gd")
const Sim = preload("res://core/simulation.gd")
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")
const Canonical = preload("res://core/canonical.gd")
const Exploration = preload("res://core/exploration.gd")
const Nav = preload("res://core/navigation.gd")
const Crowd = preload("res://core/crowd.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
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
		if tick % 20 == 0: _check(game.state_hash() == Canonical.hash_of(game.state), "native state hash matches canonical wire hash")
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
	_check(game.state_hash() == expected and expected == Canonical.hash_of(game.state), "JSON restore reproduces local forces, obstacle snapshots and exact hashes")
	return {"checks": checks, "failures": failures}

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
