extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Hex = preload("res://core/hex_cells.gd")
const Geo = preload("res://core/geometry.gd")
const Nav = preload("res://core/navigation.gd")
const Construction = preload("res://core/construction.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var data: Dictionary = content.data.duplicate(true)
	data.settings.mission.enabled = false
	data.settings.input_delay = 0
	for definition in data.units.values():
		for cap in ["passive_spawner", "veil_source", "chyme_source"]: definition.capabilities.erase(cap)
	return data

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game():
	var game = Sim.new()
	game.initialize(_definitions(), _players(), 42)
	for item in [[1, -12, 0], [2, -3, 0], [3, -12, 3], [4, 12, 0], [5, 12, 3], [6, 13, 3]]:
		game.entity(item[0]).position = Hex.point([item[1], item[2]])
	for q in range(-10, 11):
		for r in range(-10, 11): game.state.revealed["1"][Hex.key([q, r])] = true
	return game

func run() -> Dictionary:
	var content = Content.new()
	_check(content.load_text(Canonical.text(_definitions())), "footprints, collision radii and footprint visuals validate")
	for footprint in [[], [[1, 0]], [[0, 0], [0, 0]], [[0, 0], [3, 0]], [[0, 0], [0.5, 0]], [[0, 0], [20, 0]]]:
		var data := _definitions()
		data.units.wall.footprint = footprint
		_check(not content.load_text(Canonical.text(data)) and "units.wall.footprint" in " ".join(content.errors), "invalid footprint has field path")
	var bad := _definitions()
	bad.units.engineer.collision_radius = -1
	_check(not content.load_text(Canonical.text(bad)), "invalid collision radius rejected")
	bad = _definitions(); bad.settings.terrain = [[100, 0]]
	_check(not content.load_text(Canonical.text(bad)), "terrain outside arena rejected")
	var shape := {"footprint": [[0, 0], [1, 0], [2, 0]]}
	_check(Geo.offsets(shape, 1) == [[0, 0], [0, 1], [0, 2]] and Geo.offsets(shape, 6) == shape.footprint, "six axial rotations preserve footprint")
	var game = _game()
	game.content.units.maw.footprint = shape.footprint
	game._spawn("maw", 1, Hex.point([0, 0]))
	_check(Geo.center(game, game.entity(7)) == Hex.point([1, 0]), "asymmetric footprint body is centered at centroid")
	_check(not Construction.site_error(game, game.entity(2), "wall", Hex.point([2, 0])).is_empty(), "placement rejects overlap away from structure anchor")
	game.state.revealed["1"].erase("2,2")
	game.content.units.wall.footprint = shape.footprint
	_check("Reveal" in Construction.site_error(game, game.entity(2), "wall", Hex.point([0, 2])), "all footprint tiles must be revealed")
	_check("outside" in Construction.site_error(game, game.entity(2), "wall", Hex.point([32, 0])), "entire footprint must fit arena")
	_structure_collision()
	_routes()
	_diagonal_routes()
	_construction()
	_interaction_ranges()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _routes() -> void:
	var game = _game()
	for r in range(-4, 5): game._spawn("wall", 1, Hex.point([0, r]))
	var unit = game.entity(2)
	var goal := Hex.point([3, 0])
	_check(not Nav.segment_clear(game, unit.position, goal, Geo.radius(game, unit), game.navigation_field().blocked), "wall barrier blocks straight movement")
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": goal}])
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	var detoured := false
	for tick in 300:
		var previous: Array = unit.position.duplicate()
		game.step([])
		if absi(int(unit.position[2])) > Hex.SCALE: detoured = true
		_check(Nav.segment_clear(game, previous, unit.position, Geo.radius(game, unit), game.navigation_field().blocked), "movement sweeps circle without clipping wall corners")
	_check(game.distance_squared(unit.position, goal) <= Hex.SCALE * Hex.SCALE and detoured, "A* routes around wall and reaches destination")
	var expected: String = game.state_hash()
	game.restore(saved)
	for tick in 300: game.step([])
	_check(game.state_hash() == expected, "JSON restore reproduces path progress")
	game = _game()
	game.content.settings.terrain = []
	for r in range(-32, 33):
		if r != 0: game.content.settings.terrain.append([0, r])
	unit = game.entity(2)
	var small: Array = Nav.next(game, unit, goal)
	_check(not small.is_empty(), "small body fits one-tile gap")
	game.content.units.engineer.collision_radius = 0.6
	unit.navigation = {}
	_check(Nav.next(game, unit, goal).is_empty(), "large body cannot pass small gap or clip arena edge")
	game.content.settings.terrain.clear()
	_check(not Nav.next(game, unit, goal).is_empty(), "terrain removal invalidates blocked route")
	game._spawn("wall", 1, Hex.point([0, 0]))
	var wall = game.entity(int(game.state.next_id) - 1)
	_check(not Nav.segment_clear(game, unit.position, goal, Geo.radius(game, unit), game.navigation_field().blocked), "new structure invalidates open route")
	wall.hp = 0
	_check(Nav.next(game, unit, goal) == goal, "destroyed wall opens direct route immediately")
	_check(Nav.center_clear(game, [32, 0], 205, game.navigation_field()), "small bodies can occupy arena edge tiles")
	_check(not Nav.center_clear(game, [32, 0], 615, game.navigation_field()), "large bodies cannot extend beyond arena footprint")
	game = _game()
	game.content.units.nest.capabilities.passive_spawner = {"definition": "scavenger", "interval_ticks": 1, "max_alive": 1, "spawn_radius": 1}
	for tick in 2: game.step([])
	_check(game.entity(7) != null and not Hex.from_point(game.entity(7).position) in Geo.cells(game, game.entity(4)) and Nav.clear(game, game.entity(7).position, Geo.radius(game, game.entity(7)), game.navigation_field().blocked), "passive offspring spawn outside whole source footprint with body clearance")
	game.content.units.mother.production_ticks = 1
	game.step([{"kind": "train", "player": 9, "actors": [4], "definition": "mother"}])
	_check(game.entity(8) != null and Nav.clear(game, game.entity(8).position, Geo.radius(game, game.entity(8)), game.navigation_field().blocked), "paid production spawns clear of multi-tile factory")
	game = _game()
	game.content.units.mother.production_ticks = 1
	game.content.settings.terrain = []
	for q in range(10, 15):
		for r in range(-2, 3):
			if Hex.distance([q, r], [12, 0]) == 2: game.content.settings.terrain.append([q, r])
	var rng := int(game.state.rng)
	game.step([{"kind": "train", "player": 9, "actors": [4], "definition": "mother"}])
	_check(game.entity(7) == null and not game.entity(4).production.is_empty() and int(game.state.rng) == rng, "blocked production waits without teleporting beyond obstacles or spending RNG")
	game.content.settings.terrain.clear()
	game.step([])
	_check(game.entity(7) != null and game.entity(4).production.is_empty(), "opening emergence space resumes ready production")

func _diagonal_routes() -> void:
	var game = _game()
	var unit = game.entity(2)
	var destination := [5 * Hex.SCALE + 123, 0, -2 * Hex.SCALE + 57]
	_check(Nav.next(game, unit, destination) == destination, "open movement uses exact arbitrary-angle destination without grid snapping")
	for r in range(-4, 5): game._spawn("wall", 1, Hex.point([0, r]))
	destination = Hex.point([3, 0])
	var data: Dictionary = game.navigation_field()
	for size in [0.2, 0.6]:
		game.content.units.engineer.collision_radius = size
		var radius := Geo.radius(game, unit)
		var coarse := Nav._path(game, unit, [Hex.from_point(destination)], data)
		var smooth := Nav._smooth(game, unit.position, coarse, radius, data.blocked)
		_check(not smooth.is_empty() and smooth.size() < coarse.size() and smooth.back() == destination, "smoothing removes grid steps while preserving destination")
		var previous: Array = unit.position
		var diagonal := false
		var smooth_length := 0
		for point in smooth:
			_check(Nav.segment_clear(game, previous, point, radius, data.blocked), "long shortcuts preserve swept body clearance")
			var q := int(point[0]) - int(previous[0]); var r := int(point[2]) - int(previous[2])
			if q != 0 and r != 0 and q + r != 0 and game.distance_squared(previous, point) > 4 * Hex.SCALE * Hex.SCALE: diagonal = true
			smooth_length += game.integer_sqrt(game.distance_squared(previous, point))
			previous = point
		var coarse_length := 0
		previous = unit.position
		for point in coarse:
			coarse_length += game.integer_sqrt(game.distance_squared(previous, point))
			previous = point
		_check(diagonal and smooth_length < coarse_length, "wall detours contain large non-hex-axis diagonals and are shorter than grid route")
		_check(Nav._smooth(game, unit.position, coarse, radius, data.blocked) == smooth, "shortcut choices are deterministic")

func _construction() -> void:
	var game = _game()
	game.content.units.wall.footprint = [[0, 0], [1, 0], [2, 0]]
	game.content.units.wall.construction_ticks = 2
	game.entity(2).position = Hex.point([-3, 3])
	var command := {"kind": "build", "player": 1, "actors": [2], "definition": "wall", "point": Hex.point([-2, 2]), "rotation": 0}
	game.step([command])
	var site = game.entity(7)
	_check(site != null and Geo.cells(game, site).size() == 3 and not game.navigation_field().blocked.hexes.has("0,2"), "blueprint reserves full footprint while remaining walkable")
	_check(not Construction.site_error(game, game.entity(2), "turret", Hex.point([0, 2])).is_empty(), "blueprint reserves cells away from anchor")
	game.entity(3).position = Hex.point([0, 2])
	for tick in 20: game.step([])
	_check(site.construction.get("blocked", false), "completion waits for units anywhere in footprint")
	game.entity(3).position = Hex.point([3, 3])
	game.step([])
	_check(site.definition == "wall" and game.navigation_field().blocked.hexes.has("0,2"), "completion activates whole movement footprint")
	game = _game()
	game.entity(2).position = Hex.point([-3, 3])
	for offset in Hex.NEIGHBORS: game._spawn("wall", 1, Hex.point([-3 + int(offset[0]), 3 + int(offset[1])]))
	game.step([{"kind": "build", "player": 1, "actors": [2], "definition": "turret", "point": Hex.point([3, 0])}])
	_check(int(game.state.banks["1"]) == 100 and game.entity(13) == null, "unreachable engineer blueprint cancels with full refund")
	game = _game()
	game.content.units.engineer.collision_radius = 0.6
	game.content.units.engineer.capabilities.builder.work_range = 2
	game.content.units.wall.construction_ticks = 2
	game.entity(2).position = [614, 0, 0]
	game.step([{"kind": "build", "player": 1, "actors": [2], "definition": "wall", "point": [0, 0, 0]}])
	for tick in 80: game.step([])
	_check(game.entity(7).definition == "wall" and not Geo.intersects_unit(game, game.entity(2), Geo.cells(game, game.entity(7))), "large engineer steps fully outside blueprint before completing work")
	_check(game.entity(2).navigation.is_empty(), "finished work discards remaining approach waypoints")

func _interaction_ranges() -> void:
	var game = _game()
	game.content.units.wall.footprint = [[0, 0], [1, 0], [2, 0]]
	game.content.units.wall.construction_ticks = 3
	game.entity(2).position = Hex.point([4, 0])
	game.step([{"kind": "build", "player": 1, "actors": [2], "definition": "wall", "point": [0, 0, 0]}])
	var site = game.entity(7)
	_check(site != null and int(site.construction.remaining) == 3, "engineer cannot build from two tiles beyond footprint perimeter")
	for tick in 80: game.step([])
	_check(site.definition == "wall" and game.interaction_distance(game.entity(2).position, site) <= 1536 * 1536, "builder approaches nearest footprint tile center before working")
	_check(game.distance_squared(game.entity(2).position, Geo.center(game, site)) > 1536 * 1536, "interaction uses nearest footprint tile rather than whole structure centroid")
	var data := _definitions()
	data.settings.mission.enabled = true
	data.units.extraction_point.collision_radius = 0.4
	data.units.extraction_point.footprint = [[0, 0]] # Keep range fixture independent of authored demo footprint.
	game = Sim.new()
	game.initialize(data, _players(), 42)
	var receiver = game.entity(7)
	game.entity(2).position = receiver.position.duplicate()
	game.entity(2).position[0] += 2 * Hex.SCALE
	var remaining := int(game.state.mission.humans["1"].repair_remaining)
	game.step([{"kind": "repair_point", "player": 1, "actors": [2], "target": 7}])
	_check(int(game.state.mission.humans["1"].repair_remaining) == remaining, "repair cannot start two tile centers from target")
	for tick in 80: game.step([])
	_check(int(game.state.mission.humans["1"].repair_remaining) == 0 and game.interaction_distance(game.entity(2).position, receiver) <= 1536 * 1536, "repair approaches center-based interaction radius")
	game = _game()
	game.entity(5).position = Hex.point([15, 0]) # Nest center 12; nearest footprint tile 13.
	game.entity(5).chyme = 3
	game.step([{"kind": "deliver_chyme", "player": 9, "actors": [5], "target": 4}])
	_check(int(game.entity(5).chyme) == 3 and int(game.state.banks["9"]) == 100, "delivery cannot occur at old footprint-edge range")
	for tick in 80: game.step([])
	_check(int(game.entity(5).chyme) == 0 and int(game.state.banks["9"]) == 103 and game.interaction_distance(game.entity(5).position, game.entity(4)) <= 1536 * 1536, "delivery uses nearest tile center of large receiver")

func _rollback() -> String:
	var fixture = _game()
	for r in range(-3, 4): fixture._spawn("wall", 1, Hex.point([0, r]))
	var a = Rollback.new(); var b = Rollback.new()
	for session in [a, b]:
		session.initialize(fixture.content, _players(), 42, 0)
		session.simulation.restore(fixture.checkpoint())
		session._save()
	var move := [{"kind": "move", "actors": [2], "point": Hex.point([3, 0])}]
	for tick in 80:
		for player in [1, 9]:
			var commands: Array = move if player == 1 and tick == 2 else []
			a.receive(player, tick, commands)
			if tick != 2 or player != 1: b.receive(player, tick, commands)
	for tick in 30: a.advance(); b.advance()
	_check(b.receive(1, 2, move) and b.rollbacks == 1, "late movement command triggers route rollback")
	for tick in 50: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "late pathfinding matches reference state and route")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _structure_collision() -> void:
	var game = _game()
	game.content.units.hq.collision_radius = 0.4
	game._spawn("hq", 1, [0, 0, 0])
	var building = game.entity(7)
	var size := Geo.radius(game, game.entity(2))
	var field: Dictionary = game.navigation_field()
	_check(Nav.center_clear(game, [1, 0], size, field), "round building leaves unused build-footprint cells walkable")
	_check(not Nav.center_clear(game, [0, 0], size, field), "round building still blocks its physical body")
	_check(not Construction.site_error(game, game.entity(2), "wall", Hex.point([1, 0])).is_empty(), "walkable building corners remain reserved for placement")
	var start := Hex.point([-3, 1]); var goal := Hex.point([3, 1])
	_check(Nav.segment_clear(game, start, goal, size, field.blocked), "swept path passes through build footprint outside circular body")
	game.entity(2).position = start
	game.step([{"kind": "move", "player": 1, "actors": [2], "point": goal}])
	for tick in 80: game.step([])
	_check(game.entity(2).order.is_empty() and game.distance_squared(game.entity(2).position, goal) <= Hex.SCALE * Hex.SCALE, "unit traverses free space within building footprint")
	var old_hash: String = field.hash
	game.content.units.hq.collision_radius = 1.1
	field = game.navigation_field()
	_check(field.hash != old_hash and not Nav.segment_clear(game, start, goal, size, field.blocked), "circle radius changes invalidate routes and swept clearance")
	game.content.units.hq.collision_shape = "footprint"
	field = game.navigation_field()
	_check(not Nav.center_clear(game, [1, 0], size, field), "footprint collision fills every occupied hex")
	game.content.units.hq.collision_shape = "circle"
	game.content.units.hq.collision_radius = 0.4
	game.content.units.hq.footprint = [[0, 0], [1, 0], [2, 0]]
	_check(Geo.collision_circle(game, building).position == Hex.point([1, 0]), "asymmetric round body uses footprint centroid")
	building.rotation = 1
	_check(Geo.collision_circle(game, building).position == Hex.point([0, 1]) and Nav.center_clear(game, [1, 0], size, game.navigation_field()), "rotating asymmetric footprint rotates its circular body center")
	game.entity(3).position = Hex.point([0, 2])
	_check(Construction.completion_clear(game, building), "completion permits units in footprint outside final body")
	game.entity(3).position = Hex.point([0, 1])
	_check(not Construction.completion_clear(game, building), "completion waits for units intersecting final circle")
	game.entity(3).position = Hex.point([-12, 3])
	building.definition = "womb"
	building.construction = {"definition": "hq"}
	_check(Nav.center_clear(game, [0, 2], size, game.navigation_field()) and not Nav.center_clear(game, [0, 1], size, game.navigation_field()), "Womb inherits target circle rather than reserving footprint as solid terrain")
	var data := _definitions()
	var content = Content.new()
	data.units.hq.collision_shape = "sphere"
	_check(not content.load_text(Canonical.text(data)) and "collision_shape" in " ".join(content.errors), "unsupported collision shape is rejected with field path")
	data.units.hq.collision_shape = "circle"
	data.units.hq.erase("collision_radius")
	_check(not content.load_text(Canonical.text(data)) and "collision_radius" in " ".join(content.errors), "circle collision requires authored radius")
