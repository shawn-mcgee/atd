extends RefCounted
const Fixture = preload("res://tests/geometry_suite.gd")
const Sim = preload("res://core/simulation.gd")
const Rally = preload("res://core/rally.gd")
const Hex = preload("res://core/hex_cells.gd")
const Geo = preload("res://core/geometry.gd")
const Nav = preload("res://core/navigation.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func _game():
	var fixture = Fixture.new()
	var data: Dictionary = fixture._definitions()
	data.units.engineer.production_ticks = 1
	data.units.hq.collision_radius = 0.4
	data.units.hq.footprint = [[0, 0]]
	var game = Sim.new()
	game.initialize(data, fixture._players(), 42)
	game._spawn("hq", 1, [0, 0, 0])
	return game

func run() -> Dictionary:
	var game = _game()
	var source = game.entity(7)
	_check(source.rally_point == [-1536, 0, 3072], "default rally is directly south in world coordinates")
	var target := Hex.point([5, 0])
	game.step([{"kind": "rally", "player": 1, "actors": [7], "point": target}, {"kind": "train", "player": 1, "actors": [7], "definition": "engineer"}])
	var child = game.entity(8)
	_check(source.rally_point == target and child.position == Hex.point([1, 0]), "paid unit emerges on nearest adjacent tile toward rally")
	_check(child.order.get("kind") == "move" and child.order.point == target, "newborn receives rally move without moving on its birth tick")
	game.step([{"kind": "rally", "player": 9, "actors": [7], "point": [0, 0, 0]}, {"kind": "rally", "player": 1, "actors": [2], "point": target}])
	_check(source.rally_point == target and game.entity(2).rally_point.is_empty(), "rally commands enforce ownership and spawner capability")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	for tick in 100: game.step([])
	_check(child.order.is_empty() and game.distance_squared(child.position, target) <= Hex.SCALE * Hex.SCALE, "offspring navigates to normal rally arrival range")
	var expected: String = game.state_hash()
	game.restore(saved)
	for tick in 100: game.step([])
	_check(game.state_hash() == expected, "JSON restore reproduces rally travel")
	game = _game(); source = game.entity(7)
	game.content.settings.terrain = [[2, 0], [1, 1], [0, 1], [1, -1], [2, -1]]
	source.rally_point = Hex.point([4, 0])
	var chosen := Rally.spawn_position(game, source, "engineer")
	_check(not chosen.is_empty() and chosen != Hex.point([1, 0]), "path ranking avoids geometrically nearest exit trapped in a pocket")
	var ghost := {"definition": "engineer", "position": chosen}
	var data := Nav.actor_field(game, source)
	_check(not Nav._path(game, ghost, [[4, 0]], data).is_empty(), "chosen exit has an actual traversable route to rally")
	# All adjacent exits blocked: production stays ready instead of teleporting out.
	game = _game(); source = game.entity(7)
	game.content.settings.terrain = Hex.NEIGHBORS.duplicate(true)
	game.step([{"kind": "train", "player": 1, "actors": [7], "definition": "engineer"}])
	_check(game.entity(8) == null and not source.production.is_empty(), "sealed source waits for an adjacent exit")
	game.content.settings.terrain = []
	game.step([])
	_check(game.entity(8) != null and source.production.is_empty(), "ready production resumes when exit clears")
	# Passive sources share rally commands, emergence, and dispatch.
	game = _game()
	game.content.units.nest.capabilities.passive_spawner = {"definition": "scavenger", "interval_ticks": 1, "max_alive": 1, "spawn_radius": 2}
	game.entity(4).passive_remaining = 1
	game.step([{"kind": "rally", "player": 9, "actors": [4], "point": Hex.point([13, -5])}])
	game.step([])
	child = game.entity(8)
	_check(child != null and child.spawn_source == 4 and child.order.get("point", []) == Hex.point([13, -5]), "passive offspring inherit source rally")
	var nearest := 1000
	for cell in Geo.cells(game, game.entity(4)): nearest = mini(nearest, Hex.distance(Hex.from_point(child.position), cell))
	_check(nearest == 1, "passive offspring emerge adjacent to whole footprint")
	var a = Rollback.new(); var b = Rollback.new()
	var fixture = _game()
	for session in [a, b]:
		session.initialize(fixture.content, fixture.state.players, 42, 0)
		session.simulation.restore(fixture.checkpoint()); session._save()
	for tick in 50:
		for player in [1, 9]:
			var commands: Array = [{"kind": "rally", "actors": [7], "point": target}, {"kind": "train", "actors": [7], "definition": "engineer"}] if tick == 1 and player == 1 else []
			a.receive(player, tick, commands)
			if tick != 1 or player != 1: b.receive(player, tick, commands)
	for tick in 8: a.advance(); b.advance()
	_check(b.receive(1, 1, [{"kind": "rally", "actors": [7], "point": target}, {"kind": "train", "actors": [7], "definition": "engineer"}]), "rally command survives network sanitization and late input")
	for tick in 42: a.advance(); b.advance()
	_check(b.rollbacks == 1 and a.simulation.state_hash() == b.simulation.state_hash(), "late rally replay reproduces emergence and arrival")
	return {"checks": checks, "failures": failures, "hash": b.simulation.state_hash()}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
