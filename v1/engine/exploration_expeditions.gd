extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
## Rally at the chosen starting point, then keep scouting every unknown map cell.
const Hex = preload("res://engine/hex_grid.gd")
static var LEASH: float = float(Config.value("exploration", "leash"))
var groups: Array[Dictionary] = []
var clock := 0.0
var visibility_clock := 0.0
var component_revision := -1
var components: Dictionary = {}
var component_graph: WeakRef
const PLAN_QUERIES := 8
const PLAN_CELLS := 256
const SMALL_SURVEY := 512
var unseen: Dictionary = {}
var known_count := -1

func diagnostic_state() -> Dictionary:
	# Components and the unseen index are derived from navigation/explored state.
	return {"groups": groups, "clock": clock, "visibility_clock": visibility_clock}

func rebuild_unseen(game) -> void:
	unseen.clear()
	for cell in game.navigation.cells:
		if not game.explored.has(cell): unseen[cell] = true
	known_count = game.explored.size()

func reveal(cell: Vector2i) -> void:
	if unseen.erase(cell): known_count += 1

func warm_cache(game) -> void:
	rebuild_unseen(game); refresh_components(game)

func alive(unit) -> bool:
	return SimEntity.valid(unit) and unit.hp > 0

func available(roster: Dictionary) -> bool:
	return not roster.members.is_empty() and roster.members.size() >= roster.vehicles.size() + roster.scouts.size()

func driver_rank(unit: SimUnit, vehicle: SimUnit) -> int:
	return vehicle.DRIVER_RANK[unit.kind]

func seat_plan(members: Array, vehicles: Array) -> Dictionary:
	var pool: Array = members.duplicate()
	var pilots: Dictionary = {}
	var seats: Dictionary = {}
	for vehicle in vehicles:
		pool.sort_custom(func(a, b): return driver_rank(a, vehicle) < driver_rank(b, vehicle) if driver_rank(a, vehicle) != driver_rank(b, vehicle) else a.formation_slot < b.formation_slot)
		pilots[vehicle] = pool.pop_front()
		seats[pilots[vehicle]] = vehicle
	# Keep engineers in available passenger seats; combat infantry walk as guards.
	for vehicle in vehicles:
		var room: int = vehicle.seat_capacity() - 1
		for unit in pool.duplicate():
			if room <= 0: break
			if unit.kind != "engineer": continue
			seats[unit] = vehicle; pool.erase(unit); room -= 1
	return {"pilots": pilots, "seats": seats, "walkers": pool}

func assign_seats(game, group: Dictionary) -> void:
	var plan := seat_plan(group.members, group.vehicles)
	group.pilots = plan.pilots; group.seats = plan.seats
	for unit in group.members:
		if unit.aboard == null: continue
		var vehicle: SimUnit = unit.aboard
		if group.seats.get(unit) != vehicle or (vehicle.driver == unit) != (group.pilots.get(vehicle) == unit):
			vehicle.disembark(unit, game.free_spawn(vehicle.position))
	for unit in group.members + group.vehicles:
		if unit.aboard != null: continue
		unit.path.clear(); unit.target = null; unit.goal = unit.position
		unit.order = "convoy_explore_board" if group.seats.has(unit) else "convoy_explore"
	group.retry = 0.0; group.stalled = 0.0

func start(game, roster: Dictionary, destination: Vector3) -> bool:
	if not available(roster): game.notify("Exploration needs infantry and a driver for every vehicle"); return false
	var vehicles: Array = roster.vehicles + roster.scouts
	var plan := seat_plan(roster.members, vehicles)
	var pool: Array = plan.walkers
	var pilots: Dictionary = plan.pilots
	var seats: Dictionary = plan.seats
	var leader: SimUnit = pool[0] if not pool.is_empty() else vehicles[0]
	var path: PackedVector3Array = game.navigation.path(leader.position, destination)
	if not valid_path(game, path, destination):
		game.notify("No reachable exploration route"); return false
	var route := PackedVector3Array([path[0]])
	for i in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 4.0))
		for step in range(1, steps + 1): route.append(game.navigation.terrain.surface(path[i - 1].lerp(path[i], float(step) / steps)))
	for unit in roster.members + vehicles: game.complex_commands.interrupt(unit)
	for unit in roster.members:
		if unit.aboard != null: unit.aboard.disembark(unit, game.free_spawn(unit.aboard.position))
	var group := {"id": game.complex_commands.next_id, "members": roster.members.duplicate(), "vehicles": vehicles, "pilots": pilots,
		"seats": seats,
		"route": route, "index": 1 if route.size() > 1 else 0, "start": destination, "start_reached": false, "destination": destination,
		"phase": "boarding", "waypoint": route[1] if route.size() > 1 else destination, "clock": 0.0, "retry": 0.0,
		"survey_cell": Hex.to_axial(destination, Terrain.CELL), "plan_queue": [], "plan_index": 0,
		"plan_revision": -1, "deferred": {}, "wait_until": 0.0, "last_position": leader.position, "stalled": 0.0, "scouted_percent": 0.0}
	game.complex_commands.next_id += 1; groups.append(group)
	for unit in roster.members + vehicles:
		unit.complex_id = group.id; unit.path.clear(); unit.target = null
		unit.order = "convoy_explore_board" if seats.has(unit) else "convoy_explore"
	game.notify("Exploration expedition / rally at the target, then auto-scout the entire map")
	return true

func finish(group: Dictionary) -> void:
	for unit in group.members + group.vehicles:
		if not SimEntity.valid(unit) or unit.complex_id != group.id: continue
		unit.complex_id = 0
		if unit.aboard == null: unit.order = "idle"; unit.path.clear(); unit.target = null; unit.goal = unit.position
	groups.erase(group)

func detach_member(group: Dictionary, unit) -> void:
	group.members.erase(unit); group.seats.erase(unit)
	if not SimEntity.valid(unit) or unit.complex_id != group.id: return
	unit.complex_id = 0
	if unit.aboard == null and unit.order.begins_with("convoy_explore"):
		unit.order = "idle"; unit.path.clear(); unit.target = null; unit.goal = unit.position

func detach_vehicle(group: Dictionary, vehicle) -> void:
	for member in group.members.duplicate():
		if group.seats.get(member) == vehicle or (SimEntity.valid(member) and member.aboard == vehicle): detach_member(group, member)
	group.vehicles.erase(vehicle); group.pilots.erase(vehicle)
	if not SimEntity.valid(vehicle) or vehicle.complex_id != group.id: return
	vehicle.complex_id = 0
	if vehicle.order.begins_with("convoy_explore"):
		vehicle.order = "idle"; vehicle.path.clear(); vehicle.target = null; vehicle.goal = vehicle.position

func interrupt(unit: SimUnit) -> void:
	for group in groups.duplicate():
		if group.vehicles.has(unit): detach_vehicle(group, unit)
		if group.members.has(unit): detach_member(group, unit)
		if group.members.is_empty(): finish(group)

func distance_to_route(point: Vector3, route: PackedVector3Array) -> float:
	var distance := point.distance_to(route[0])
	for i in range(1, route.size()): distance = minf(distance, point.distance_to(Geometry3D.get_closest_point_to_segment(point, route[i - 1], route[i])))
	return distance

func bounded_path(game, unit: SimUnit, point: Vector3, route: PackedVector3Array) -> PackedVector3Array:
	var path: PackedVector3Array = game.navigation.path(unit.position, point)
	if not valid_path(game, path, point): return PackedVector3Array()
	# Members initially outside the corridor may join it, then stay inside it.
	if distance_to_route(unit.position, route) > LEASH: return path
	for i in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 1.5))
		for step in range(steps + 1):
			if distance_to_route(path[i - 1].lerp(path[i], float(step) / steps), route) > LEASH: return PackedVector3Array()
	return path

func refresh_components(game) -> void:
	var graph: AStar3D = game.navigation.friendly_graph
	if component_revision == game.navigation.revision and component_graph != null and component_graph.get_ref() == graph: return
	component_revision = game.navigation.revision; components.clear(); component_graph = weakref(graph)
	var component := 0
	for id in graph.get_point_ids():
		if graph.is_point_disabled(id) or components.has(id): continue
		var queue: Array[int] = [id]; var cursor := 0
		components[id] = component
		while cursor < queue.size():
			var current := queue[cursor]; cursor += 1
			for neighbor in graph.get_point_connections(current):
				if graph.is_point_disabled(neighbor) or components.has(neighbor): continue
				components[neighbor] = component; queue.append(neighbor)
		component += 1

func reset_plan(group: Dictionary) -> void:
	group.plan_revision = -1; group.plan_queue = []; group.plan_index = 0
	group.plan_ring = 0; group.plan_cursor = 0

func hold(group: Dictionary, units: Array) -> void:
	for unit in units:
		unit.order = "convoy_explore"; unit.target = null; unit.path.clear(); unit.goal = unit.position

func set_route(game, group: Dictionary, path: PackedVector3Array) -> void:
	var route := PackedVector3Array([path[0]])
	for i in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 4.0))
		for step in range(1, steps + 1): route.append(game.navigation.terrain.surface(path[i - 1].lerp(path[i], float(step) / steps)))
	group.route = route; group.index = 1 if route.size() > 1 else 0
	group.destination = path[-1]; group.waypoint = route[group.index]
	group.clock = 0.0; group.stalled = 0.0; group.last_position = path[0]; group.retry = 0.0

func valid_path(game, path: PackedVector3Array, endpoint: Vector3) -> bool:
	if path.is_empty() or path[-1].distance_to(endpoint) > 0.3: return false
	for i in range(1, path.size()):
		if not game.navigation.clear_segment(path[i - 1], path[i], true): return false
	return true

func reserved(group: Dictionary, cell: Vector2i) -> bool:
	for other in groups:
		if other != group and other.phase == "exploring" and other.survey_cell == cell: return true
	return false

func prepare_plan(game, group: Dictionary, leader: SimUnit) -> void:
	refresh_components(game)
	if known_count != game.explored.size(): rebuild_unseen(game)
	group.plan_queue = []; group.plan_index = 0
	group.plan_revision = game.navigation.revision
	group.plan_origin = leader.position; group.plan_center = Hex.to_axial(leader.position, Terrain.CELL)
	group.plan_ring = 0; group.plan_cursor = 0
	group.plan_offset = Vector2(leader.position.x - Hex.to_world(group.plan_center, Terrain.CELL).x, leader.position.z - Hex.to_world(group.plan_center, Terrain.CELL).z).length()
	var center: Vector2i = group.plan_center
	group.plan_limit = Terrain.MAP_RADIUS + maxi(absi(center.x), maxi(absi(center.y), absi(center.x + center.y)))
	var graph: AStar3D = game.navigation.friendly_graph
	group.plan_component = int(components.get(graph.get_closest_point(leader.position), -1))
	# A nearly finished survey searches only the few remaining cells.
	if unseen.size() <= SMALL_SURVEY:
		group.plan_ring = -1
		for cell in unseen: add_candidate(game, group, cell)
		sort_candidates(group)

func add_candidate(game, group: Dictionary, cell: Vector2i) -> void:
	if not unseen.has(cell) or game.explored.has(cell) or reserved(group, cell) or float(group.deferred.get(cell, 0.0)) > clock: return
	var id: int = game.navigation.cells[cell]
	var graph: AStar3D = game.navigation.friendly_graph
	if graph.is_point_disabled(id) or int(components.get(id, -2)) != int(group.plan_component): return
	var point := graph.get_point_position(id)
	# Disabled graph nodes already encode blocked(point, true).
	var distance := roundi(Vector2(point.x - group.plan_origin.x, point.z - group.plan_origin.z).length_squared() * 1000.0)
	group.plan_queue.append({"cell": cell, "point": point, "distance": distance, "center": cell.x * cell.x + cell.x * cell.y + cell.y * cell.y})

func sort_candidates(group: Dictionary) -> void:
	group.plan_queue.sort_custom(func(a, b):
		if a.distance != b.distance: return a.distance < b.distance
		if a.center != b.center: return a.center < b.center
		return a.cell.x < b.cell.x if a.cell.x != b.cell.x else a.cell.y < b.cell.y)

func next_cell(group: Dictionary) -> Vector2i:
	var ring: int = group.plan_ring
	if ring == 0:
		group.plan_ring = 1
		return group.plan_center
	var cursor: int = group.plan_cursor
	var side := cursor / ring
	var cell: Vector2i = group.plan_center + Hex.NEIGHBORS[4] * ring
	for i in range(side): cell += Hex.NEIGHBORS[i] * ring
	cell += Hex.NEIGHBORS[side] * (cursor % ring)
	group.plan_cursor += 1
	if int(group.plan_cursor) >= ring * 6:
		group.plan_ring += 1; group.plan_cursor = 0
	return cell

func choose_destination(game, group: Dictionary, leader: SimUnit) -> int:
	if group.plan_revision != game.navigation.revision: prepare_plan(game, group, leader)
	var queries := 0; var inspected := 0; var scanned := 0
	while queries < PLAN_QUERIES and inspected < 24:
		var complete: bool = int(group.plan_ring) < 0 or int(group.plan_ring) > int(group.plan_limit)
		# Outside axial ring r, world distance is at least 1.5*r minus the
		# leader's offset from its cell center. Preserve exact Euclidean ordering.
		var bound := maxf(0, float(group.plan_ring) * 1.5 - float(group.plan_offset))
		while not complete and (group.plan_queue.is_empty() or bound * bound * 1000 <= float(group.plan_queue[0].distance) + 1):
			if scanned >= PLAN_CELLS: return 0
			var cell := next_cell(group); scanned += 1
			add_candidate(game, group, cell)
			if int(group.plan_cursor) == 0 or scanned == PLAN_CELLS: sort_candidates(group)
			complete = int(group.plan_ring) > int(group.plan_limit)
			bound = maxf(0, float(group.plan_ring) * 1.5 - float(group.plan_offset))
		if group.plan_queue.is_empty(): return -1 if complete else 0
		var candidate: Dictionary = group.plan_queue.pop_front(); inspected += 1
		if game.explored.has(candidate.cell) or reserved(group, candidate.cell): continue
		queries += 1
		var path: PackedVector3Array = game.navigation.path(leader.position, candidate.point)
		if not valid_path(game, path, candidate.point): continue
		set_route(game, group, path); group.survey_cell = candidate.cell; group.phase = "exploring"
		return 1
	return 0

func tick(game, dt: float) -> void:
	clock += dt; visibility_clock += dt
	if not groups.is_empty() and visibility_clock >= 0.2:
		game.record_exploration(); visibility_clock = 0.0
	for group in groups.duplicate():
		# Direct tasks and later task completion must never reclaim old members.
		for unit in group.members.duplicate():
			if not alive(unit) or unit.complex_id != group.id or (unit.aboard == null and not unit.order.begins_with("convoy_explore")): detach_member(group, unit)
		for vehicle in group.vehicles.duplicate():
			if not alive(vehicle): detach_vehicle(group, vehicle); continue
			var pilot = group.pilots.get(vehicle)
			if vehicle.complex_id != group.id or not vehicle.order.begins_with("convoy_explore") or not alive(pilot) or not group.members.has(pilot): detach_vehicle(group, vehicle)
		if group.members.is_empty(): finish(group); continue
		var boarding := false
		for vehicle in group.vehicles:
			var pilot: SimUnit = group.pilots[vehicle]
			if pilot.aboard == vehicle: continue
			boarding = true
			game.complex_commands.issue(game, pilot, "explore_board", vehicle.position, vehicle)
			if pilot.position.distance_to(vehicle.position) < 3.8: vehicle.board(pilot)
		for passenger in group.seats:
			var vehicle: SimUnit = group.seats[passenger]
			if group.pilots[vehicle] == passenger or passenger.aboard == vehicle: continue
			boarding = true
			game.complex_commands.issue(game, passenger, "explore_board", vehicle.position, vehicle)
			if vehicle.has_driver() and passenger.position.distance_to(vehicle.position) < 3.8: vehicle.board(passenger)
		if boarding: continue
		var walkers: Array = group.members.filter(func(unit): return unit.aboard == null)
		var leaders: Array = walkers if not walkers.is_empty() else group.vehicles
		if leaders.is_empty(): finish(group); continue
		leaders.sort_custom(func(a, b): return float(game.Rules.UNITS[a.kind].speed) < float(game.Rules.UNITS[b.kind].speed))
		var leader: SimUnit = leaders[0]
		if group.phase == "boarding":
			group.phase = "travel"
		group.scouted_percent = game.scouting_percent()
		var movers: Array = walkers + group.vehicles
		if group.start_reached and game.explored.size() == game.navigation.cells.size():
			if group.phase != "complete": game.notify("Exploration complete / map 100% scouted")
			group.phase = "complete"; hold(group, movers); continue
		if group.phase in ["complete", "waiting"]:
			hold(group, movers)
			if clock < float(group.wait_until) and group.plan_revision == game.navigation.revision: continue
			if group.plan_revision != game.navigation.revision: group.deferred.clear()
			if not group.start_reached:
				var path: PackedVector3Array = game.navigation.path(leader.position, group.start)
				if valid_path(game, path, group.start): set_route(game, group, path); group.phase = "travel"
				else: group.wait_until = clock + 5; group.plan_revision = game.navigation.revision; continue
			else: group.phase = "planning"; reset_plan(group)
		if group.phase == "planning":
			hold(group, movers)
			var result := choose_destination(game, group, leader)
			if result <= 0:
				if result < 0: group.phase = "waiting"; group.wait_until = clock + 5
				continue
		group.clock += dt; group.retry -= dt
		var final_leg: bool = group.index >= group.route.size() - 1
		if leader.position.distance_to(group.waypoint) < (0.25 if final_leg else 0.6):
			if not final_leg:
				group.index += 1; group.waypoint = group.route[group.index]; group.clock = 0.0
			elif group.phase == "travel":
				group.start_reached = true; group.phase = "planning"; reset_plan(group); hold(group, movers); continue
			else:
				if not game.explored.has(group.survey_cell): group.deferred[group.survey_cell] = clock + 20
				group.phase = "planning"; reset_plan(group); hold(group, movers); continue
		if leader.position.distance_to(group.last_position) < dt * 0.1: group.stalled += dt
		else: group.stalled = 0.0
		group.last_position = leader.position
		if group.stalled > 4:
			hold(group, movers)
			if group.start_reached:
				group.deferred[group.survey_cell] = clock + 20; group.phase = "planning"; reset_plan(group)
			else: group.phase = "waiting"; group.wait_until = clock; group.plan_revision = -1
			continue
		for unit in movers:
			unit.order = "convoy_explore"; unit.target = null
			# Auto-fire handles nearby visible enemies; no enemy position becomes a goal.
			var angle: float = unit.formation_slot * 2.4
			var point: Vector3 = group.waypoint if unit == leader else game.navigation.terrain.surface(group.waypoint + Vector3(cos(angle), 0, sin(angle)) * 1.5)
			if distance_to_route(point, group.route) > LEASH: point = group.waypoint
			if unit.goal.distance_to(point) < 0.5 and unit.moving(): continue
			if unit.position.distance_to(point) < (0.15 if unit == leader and final_leg else 0.5): unit.path.clear(); continue
			if group.retry > 0: continue
			var path := bounded_path(game, unit, point, group.route)
			if path.is_empty(): path = bounded_path(game, unit, group.waypoint, group.route); point = group.waypoint
			if not path.is_empty(): unit.goal = point; unit.path = path; unit.path_index = 0
		if group.retry <= 0: group.retry = 0.5

func describe(unit: SimUnit) -> String:
	for group in groups:
		if group.id != unit.complex_id: continue
		var phase: String = {"boarding": "boarding drivers", "travel": "moving to sweep start", "planning": "finding unscouted territory", "exploring": "auto-scouting", "waiting": "waiting for access", "complete": "map fully scouted"}[group.phase]
		return "Exploration / %s / %d%% scouted" % [phase, floori(group.scouted_percent)]
	return ""

func apply_speed_limits(game) -> void:
	for group in groups:
		var speed := INF
		for unit in group.members:
			if alive(unit) and unit.aboard == null: speed = minf(speed, float(game.Rules.UNITS[unit.kind].speed))
		for vehicle in group.vehicles:
			if alive(vehicle): vehicle.escort_speed_limit = minf(vehicle.escort_speed_limit, speed)
