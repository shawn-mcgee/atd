extends RefCounted
const GeometrySuite = preload("res://tests/geometry_suite.gd")
const Hex = preload("res://core/hex_cells.gd")
const Geo = preload("res://core/geometry.gd")
const Nav = preload("res://core/navigation.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func _game():
	return GeometrySuite.new()._game()

func run() -> Dictionary:
	_friendly_pass()
	_dense_friendly_traffic()
	_arrival_and_settling()
	_approach_and_group()
	_enemy_obstacles()
	_tight_passage()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _friendly_pass() -> void:
	var game = _game()
	game.entity(3).position = [0, 0, 0]
	var goal := Hex.point([3, 0])
	var minimum := 9223372036854775807
	var bent := false
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": goal}])
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	for tick in 160:
		game.step([])
		minimum = mini(minimum, game.distance_squared(game.entity(2).position, game.entity(3).position))
		if absi(int(game.entity(2).position[2])) > 64: bent = true
	var combined := Geo.radius(game, game.entity(2)) + Geo.radius(game, game.entity(3))
	_check(game.distance_squared(game.entity(2).position, goal) <= Hex.SCALE * Hex.SCALE and bent, "unit steers around stationary ally and reaches free destination range")
	_check(minimum >= (combined - 16) * (combined - 16), "open-ground allied avoidance keeps bodies separated")
	var expected: String = game.state_hash()
	game.restore(saved)
	for tick in 160: game.step([])
	_check(game.state_hash() == expected, "JSON restore reproduces steering, velocity and passing state")
	game = _game()
	game.entity(3).position = Hex.point([3, 0])
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": Hex.point([3, 0])}, {"kind": "move", "player": 1, "actors": [3], "point": Hex.point([-3, 0])}])
	for tick in 180: game.step([])
	_check(game.entity(2).order.is_empty() and game.entity(3).order.is_empty() and int(game.entity(2).position[0]) > 0 and int(game.entity(3).position[0]) < 0, "opposing allied traffic passes without deadlocking")

func _dense_friendly_traffic() -> void:
	for crossing in [false, true]:
		var game = _game()
		var left: Array = []; var right: Array = []
		for i in 16:
			game._spawn("engineer", 1, [-5120 + (i % 4) * 320, 0, -3072 + (i / 4) * 320])
			left.append(int(game.state.next_id) - 1)
			if crossing:
				game._spawn("engineer", 1, [5120 - (i % 4) * 320, 0, -3072 + (i / 4) * 320])
				right.append(int(game.state.next_id) - 1)
		var commands: Array = [{"kind": "move", "player": 1, "actors": left, "point": [6144, 0, -3072]}]
		if crossing: commands.append({"kind": "move", "player": 1, "actors": right, "point": [-6144, 0, -3072]})
		var travel := 0; var backwards := false
		for tick in 120:
			var previous: Dictionary = {}
			for id in left + right:
				var actor = game.entity(id)
				if tick == 0 or not actor.order.is_empty(): previous[id] = actor.position.duplicate()
			game.step(commands if tick == 0 else [])
			for id in previous:
				var actor = game.entity(id)
				var origin: Array = previous[id]
				var q := int(actor.position[0]) - int(origin[0]); var r := int(actor.position[2]) - int(origin[2])
				travel += game.integer_sqrt(q * q + q * r + r * r)
				var goal_q := (6144 if id in left else -6144) - int(origin[0]); var goal_r := -3072 - int(origin[2])
				if 2 * goal_q * q + goal_q * r + goal_r * q + 2 * goal_r * r < 0: backwards = true
		var arrived := true
		for id in left + right:
			if not game.entity(id).order.is_empty(): arrived = false
		_check(arrived, "packed allied traffic reaches its destination without persistent mutual avoidance")
		_check(not backwards, "friendly separation preserves forward progress instead of reversing traffic")
		_check(travel / (left.size() + right.size()) < 14000, "packed and crossing allies avoid orbiting detours")
		var settled: Array = []
		for id in left + right: settled.append(game.entity(id).position.duplicate())
		for tick in 40: game.step([])
		var stable := true; var index := 0
		for id in left + right:
			if game.entity(id).position != settled[index]: stable = false
			index += 1
		_check(stable, "dense friendly arrivals settle without neighbor-selection jitter")

func _arrival_and_settling() -> void:
	var game = _game()
	game.entity(3).position = [0, 0, 0]
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": [0, 0, 0]}])
	for tick in 160: game.step([])
	var distance: int = game.distance_squared(game.entity(2).position, game.entity(3).position)
	_check(game.entity(2).order.is_empty() and distance >= 410 * 410 and distance <= Hex.SCALE * Hex.SCALE, "shared destination chooses a nearby free slot rather than stacking units")
	var settled: Array = [game.entity(2).position.duplicate(), game.entity(3).position.duplicate()]
	for tick in 40: game.step([])
	_check([game.entity(2).position, game.entity(3).position] == settled, "arrived units stay still instead of chasing exact marker")
	game.entity(2).position = [0, 0, 0]
	game.entity(3).position = [0, 0, 0]
	for tick in 80: game.step([])
	_check(game.distance_squared(game.entity(2).position, game.entity(3).position) >= 410 * 410, "idle overlapping allies gently settle apart")
	_check(Hex.from_point(game.entity(2).position) == Hex.from_point(game.entity(3).position), "separated bodies may still share a hex tile")

func _enemy_obstacles() -> void:
	var game = _game()
	game.entity(5).position = [0, 0, 0]
	var unit = game.entity(2)
	var goal := Hex.point([3, 0])
	var field: Dictionary = Nav.actor_field(game, unit)
	_check(not Nav.segment_clear(game, unit.position, goal, Geo.radius(game, unit), field.blocked, field.enemies), "hostile body blocks direct shortcut")
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": goal}])
	for tick in 160:
		var previous: Array = unit.position.duplicate()
		game.step([])
		field = Nav.actor_field(game, unit)
		_check(Nav.segment_clear(game, previous, unit.position, Geo.radius(game, unit), field.blocked, field.enemies), "movement never sweeps through enemy body")
	_check(game.distance_squared(unit.position, goal) <= Hex.SCALE * Hex.SCALE, "route goes around hard enemy obstacle")
	game = _game()
	unit = game.entity(2)
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": goal}])
	game.entity(5).position = [-Hex.SCALE, 0, 0]
	var previous: Array = unit.position.duplicate()
	game.step([])
	field = Nav.actor_field(game, unit)
	_check(unit.navigation.get("direct", false) and Nav.segment_clear(game, previous, unit.position, Geo.radius(game, unit), field.blocked, field.enemies), "newly blocking enemy changes local movement while static route remains direct")
	game.entity(5).hp = 0
	_check(Nav.next(game, unit, goal) == goal, "dead hostile no longer blocks shortcut")
	game = _game()
	game._spawn("engineer", 9, [0, 0, 0])
	field = Nav.actor_field(game, game.entity(2))
	_check(not Nav.segment_clear(game, game.entity(2).position, goal, Geo.radius(game, game.entity(2)), field.blocked, field.enemies), "foreign ownership is hostile even for same-faction definition")
	# Static clearance stays reusable while hostile occupancy changes independently.
	game = _game()
	unit = game.entity(2)
	field = Nav.actor_field(game, unit)
	_check(Nav.center_clear(game, [0, 0], Geo.radius(game, unit), field), "static clearance cache accepts initially empty center")
	game.entity(5).position = [0, 0, 0]
	field = Nav.actor_field(game, unit)
	_check(not Nav.center_clear(game, [0, 0], Geo.radius(game, unit), field), "enemy occupancy is checked independently of cached terrain clearance")
	game.entity(5).position = Hex.point([3, 0])
	field = Nav.actor_field(game, unit)
	_check(Nav.center_clear(game, [0, 0], Geo.radius(game, unit), field), "moving enemy frees cached center again")

func _approach_and_group() -> void:
	var game = _game()
	# Seven-tile HQ; approach its nearest footprint cell rather than its anchor.
	game.entity(2).position = Hex.point([-6, 0])
	game.step([{"kind": "approach", "player": 1, "actors": [2], "target": 1}])
	for tick in 100: game.step([])
	var adjacent := Geo.adjacent_radius(game, game.entity(2), game.entity(1))
	_check(game.entity(2).order.is_empty() and game.interaction_distance(game.entity(2).position, game.entity(1)) <= adjacent * adjacent, "approach stops adjacent to larger structure footprint")
	_check(game.distance_squared(game.entity(2).position, game.entity(1).position) > adjacent * adjacent, "approach need not touch large structure anchor")
	game = _game()
	game.entity(3).position = Hex.point([3, 0])
	game.step([{"kind": "approach", "player": 1, "actors": [2], "target": 3}, {"kind": "move", "player": 1, "actors": [3], "point": Hex.point([5, 0])}])
	for tick in 120: game.step([])
	adjacent = Geo.adjacent_radius(game, game.entity(2), game.entity(3))
	_check(game.entity(2).order.is_empty() and game.distance_squared(game.entity(2).position, game.entity(3).position) <= adjacent * adjacent, "approach tracks moving unit until adjacent")
	game = _game()
	var group: Array = [2, 3]
	game.entity(3).position = Hex.point([3, 0])
	for cell in [[0, -3], [0, 3]]:
		game._spawn("engineer", 1, Hex.point(cell))
		group.append(int(game.state.next_id) - 1)
	game.step([{"kind": "move", "player": 1, "actors": group, "point": [0, 0, 0]}])
	for tick in 200: game.step([])
	var positions: Array = []
	for id in group:
		var actor = game.entity(id)
		_check(actor.order.is_empty() and game.distance_squared(actor.position, [0, 0, 0]) <= Hex.SCALE * Hex.SCALE, "group member finishes inside point arrival radius")
		positions.append(actor.position.duplicate())
	for tick in 40: game.step([])
	for i in group.size(): _check(game.entity(group[i]).position == positions[i], "group stays settled after reaching shared destination")

func _corridor(game) -> void:
	game.content.settings.terrain = []
	for q in range(-32, 33):
		for r in [-1, 1]:
			if Hex.inside([q, r], 32): game.content.settings.terrain.append([q, r])
	game.content.units.engineer.collision_radius = 0.25
	game.content.units.marine.collision_radius = 0.25
	game.content.units.scavenger.collision_radius = 0.25

func _tight_passage() -> void:
	var game = _game()
	_corridor(game)
	game.entity(3).position = [0, 0, 0]
	game.entity(3).order = {"kind": "hold"} # Stationary local-avoidance fixture.
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": Hex.point([3, 0])}])
	var overlapped := false
	for tick in 240:
		game.step([])
		if game.distance_squared(game.entity(2).position, game.entity(3).position) < 512 * 512: overlapped = true
	_check(game.entity(2).order.is_empty() and int(game.entity(2).position[0]) >= 2 * Hex.SCALE and overlapped, "friendly overlap remains available to pass an unavoidable bottleneck")
	game = _game()
	_corridor(game)
	game.entity(5).position = [0, 0, 0]
	_check(Nav.next(game, game.entity(2), Hex.point([3, 0])) == Hex.point([3, 0]), "hostile unit does not enter global routing graph")
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": Hex.point([3, 0])}])
	for tick in 120: game.step([])
	_check(int(game.entity(2).position[0]) < 0 and game.distance_squared(game.entity(2).position, game.entity(5).position) >= 512 * 512, "local hard contact prevents crossing hostile bottleneck")

func _rollback() -> String:
	var fixture = _game()
	fixture.entity(3).position = [0, 0, 0]
	var a = Rollback.new(); var b = Rollback.new()
	for session in [a, b]:
		session.initialize(fixture.content, fixture.state.players, 42, 0)
		session.simulation.restore(fixture.checkpoint())
		session._save()
	var move := [{"kind": "move", "actors": [2], "point": Hex.point([3, 0])}]
	for tick in 90:
		for player in [1, 9]:
			var commands: Array = move if player == 1 and tick == 2 else []
			a.receive(player, tick, commands)
			if tick != 2 or player != 1: b.receive(player, tick, commands)
	for tick in 30: a.advance(); b.advance()
	_check(b.receive(1, 2, move) and b.rollbacks == 1, "late steering command triggers rollback")
	for tick in 60: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "late input reproduces local avoidance and arrival state")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
