extends RefCounted
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const RADIUS := Terrain.CELL
var terrain := Terrain.new()
var graph := AStar3D.new()
var friendly_graph := AStar3D.new()
var cells: Dictionary = {}
var obstacles: Array[Dictionary] = []
var geometry_obstacles: Array[Dictionary] = []
var solid_cells: Dictionary = {}
var records: Dictionary = {}
var surfaces: Dictionary = {}
var initialized := false
var last_dirty: Dictionary = {}
var revision := 0
var route_cache: Dictionary = {}
var route_cache_revision := -1
var slope_cells: Dictionary = {}
var light_weight_key: Array = []
var light_weight_ids := PackedInt64Array()
var light_weight_values := PackedFloat64Array()

func _init() -> void:
	for r in range(-Terrain.MAP_RADIUS, Terrain.MAP_RADIUS + 1):
		for q in range(-Terrain.MAP_RADIUS, Terrain.MAP_RADIUS + 1):
			var cell := Vector2i(q, r)
			var point := Hex.to_world(cell, RADIUS)
			if not Terrain.contains(point): continue
			var id := graph.get_available_point_id()
			cells[cell] = id
			graph.add_point(id, point)
			friendly_graph.add_point(id, point)

func rebuild(blockers: Array[Dictionary]) -> void:
	var next_records: Dictionary = {}
	for obstacle in blockers: next_records[hash(obstacle)] = obstacle
	var changes: Array = []
	for key in records:
		if not next_records.has(key): changes.append(records[key])
	for key in next_records:
		if not records.has(key): changes.append(next_records[key])
	var next_surfaces: Dictionary = {}
	for cell in terrain.cleared_cells:
		next_surfaces[hash(["cleared", cell])] = {"position": Hex.to_world(cell, Terrain.CELL), "radius": Terrain.CELL * 2}
	for surface in terrain.structures:
		var key := hash([surface.simulation_id, surface.position, surface.complete, surface.hp > 0, surface.build_direction])
		next_surfaces[key] = {"position": surface.position, "radius": 8.0}
	for key in surfaces:
		if not next_surfaces.has(key): changes.append(surfaces[key])
	for key in next_surfaces:
		if not surfaces.has(key): changes.append(next_surfaces[key])
	records = next_records; surfaces = next_surfaces
	obstacles = blockers
	geometry_obstacles.assign(blockers.filter(func(obstacle): return not obstacle.has("cell")))
	solid_cells.clear()
	for obstacle in obstacles:
		if obstacle.has("cell"): solid_cells[obstacle.cell] = obstacle
	last_dirty.clear()
	if initialized and changes.is_empty(): return
	revision += 1
	for cell in cells:
		var point := Hex.to_world(cell, RADIUS)
		if not initialized: last_dirty[cell] = true; continue
		for change in changes:
			var end: Vector3 = change.get("end", change.position)
			if Geometry3D.get_closest_point_to_segment(point, change.position, end).distance_to(point) <= float(change.radius) + RADIUS * 2.5:
				last_dirty[cell] = true; break
	initialized = true
	for cell in last_dirty:
		var id: int = cells[cell]
		graph.set_point_position(id, terrain.surface(Hex.to_world(cell, RADIUS)))
		friendly_graph.set_point_position(id, graph.get_point_position(id))
		for other in graph.get_point_connections(id): graph.disconnect_points(id, other)
		for other in friendly_graph.get_point_connections(id): friendly_graph.disconnect_points(id, other)
		graph.set_point_disabled(id, blocked(graph.get_point_position(id)))
		friendly_graph.set_point_disabled(id, blocked(graph.get_point_position(id), true))
	slope_cells.clear()
	if terrain.natural_enabled:
		mark_slope(Hex.snap(Vector3(43.3, 0, 6), RADIUS), 0)
	for structure in terrain.structures:
		if SimEntity.valid(structure) and structure.kind == "ramp" and structure.complete and structure.hp > 0: mark_slope(structure.position, structure.build_direction)
	var edges: Dictionary = {}
	for cell in last_dirty:
		var id: int = cells[cell]
		for offset in Hex.NEIGHBORS:
			var neighbor: Vector2i = cell + offset
			if not cells.has(neighbor): continue
			var other: int = cells[neighbor]
			var edge := Vector2i(mini(id, other), maxi(id, other))
			if edges.has(edge): continue
			edges[edge] = true
			for nav in [graph, friendly_graph]:
				if nav.is_point_disabled(id) or nav.is_point_disabled(other): continue
				if clear_segment(nav.get_point_position(id), nav.get_point_position(other), nav == friendly_graph): nav.connect_points(id, other)

func mark_slope(anchor: Vector3, direction_index: int) -> void:
	slope_cells[Hex.to_axial(anchor, RADIUS)] = true
	slope_cells[Hex.to_axial(anchor - Terrain.direction(direction_index) * Terrain.SPACING, RADIUS)] = true

func blocked(point: Vector3, friendly: bool = false) -> bool:
	if not Terrain.contains(point): return true
	if solid_at(point): return true
	for obstacle in geometry_obstacles:
		if obstacle.has("cell"): continue
		if friendly and obstacle.get("auto_gate", false): continue
		if absf(point.y - obstacle.position.y) > float(obstacle.get("height", 2.4)): continue
		var origin: Vector3 = obstacle.position
		var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(point, origin, obstacle.end) if obstacle.has("end") else origin
		nearest.y = point.y
		if point.distance_to(nearest) < float(obstacle.radius) + 0.35: return true
	return false

func solid_at(point: Vector3) -> bool:
	var cell := Hex.to_axial(point, Terrain.CELL)
	if not solid_cells.has(cell): return false
	var obstacle: Dictionary = solid_cells[cell]
	return point.y >= obstacle.position.y - 0.1 and point.y < obstacle.position.y + obstacle.height + 0.2

func clear_segment(a: Vector3, b: Vector3, friendly: bool = false) -> bool:
	var horizontal := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(1, ceili(horizontal / 0.15))
	# Check the slope as well as cell connectivity: a short ramp must not let
	# string-pulling cut diagonally over its raised side wall.
	var maximum_rise := horizontal / steps * 1.0 + 0.005
	var previous := terrain.height(a)
	var last_cell := Vector2i(2147483647, 2147483647)
	var flat_height := 0.0
	for i in range(steps + 1):
		var sample := a.lerp(b, float(i) / steps)
		# Share one axial conversion for bounds, solids and elevation. Flat cells
		# use the graph's authoritative height; only ramp samples need interpolation.
		var cell := Hex.to_axial(sample, RADIUS)
		if not cells.has(cell): return false
		if cell != last_cell:
			last_cell = cell; flat_height = graph.get_point_position(cells[cell]).y
		var height: float = terrain.height(sample) if slope_cells.has(cell) or not initialized else flat_height
		if solid_cells.has(cell):
			var obstacle: Dictionary = solid_cells[cell]
			if sample.y >= obstacle.position.y - 0.1 and sample.y < obstacle.position.y + obstacle.height + 0.2: return false
		if absf(height - previous) > maximum_rise: return false
		previous = height
	for obstacle in geometry_obstacles:
		if obstacle.has("cell"): continue
		if friendly and obstacle.get("auto_gate", false): continue
		if absf((a.y + b.y) * 0.5 - obstacle.position.y) > float(obstacle.get("height", 2.4)): continue
		var origin: Vector3 = obstacle.position
		if obstacle.has("end"):
			var closest := Geometry3D.get_closest_points_between_segments(a, b, origin, obstacle.end)
			if closest[0].distance_to(closest[1]) < float(obstacle.radius) + 0.25: return false
		else:
			var nearest := Geometry3D.get_closest_point_to_segment(origin, a, b)
			nearest.y = origin.y
			if nearest.distance_to(origin) < float(obstacle.radius) + 0.25: return false
	return true

func path(a: Vector3, b: Vector3, illumination: RefCounted = null, friendly: bool = true) -> PackedVector3Array:
	# Probe planning and creature navigation often request the same exact route.
	# Packed arrays are copy-on-write, so callers cannot mutate the cached result.
	if route_cache_revision != revision or route_cache.size() >= 256:
		route_cache.clear(); route_cache_revision = revision
	var key := [a, b, friendly, hash(illumination.sources) if illumination != null else 0]
	if route_cache.has(key): return route_cache[key]
	var result := find_path(a, b, illumination, friendly)
	route_cache[key] = result
	return result

func find_path(a: Vector3, b: Vector3, illumination: RefCounted = null, friendly: bool = true) -> PackedVector3Array:
	# The hex graph is only a search scaffold. Units keep continuous world positions
	# and receive exact free-space destinations, with line-of-sight string pulling.
	if not Terrain.contains(b): return PackedVector3Array()
	a = terrain.surface(a); b = terrain.surface(b)
	var nav := friendly_graph if friendly else graph
	if not blocked(b, friendly) and traversable_segment(a, b, illumination, friendly):
		return PackedVector3Array([a, b])
	var start := nav.get_closest_point(a)
	var finish := nav.get_closest_point(b)
	if start < 0 or finish < 0: return PackedVector3Array()
	if illumination != null:
		cache_light_weights(illumination)
		for i in range(light_weight_ids.size()): nav.set_point_weight_scale(light_weight_ids[i], light_weight_values[i])
	var result := nav.get_point_path(start, finish)
	if illumination != null:
		for id in light_weight_ids: nav.set_point_weight_scale(id, 1.0)
	if result.is_empty(): return result
	if not blocked(b, friendly) and traversable_segment(result[result.size() - 1], b, illumination, friendly): result.append(b)
	var smooth := PackedVector3Array([a])
	var cursor := 0
	while cursor < result.size():
		var furthest := cursor
		for candidate in range(result.size() - 1, cursor - 1, -1):
			if traversable_segment(smooth[smooth.size() - 1], result[candidate], illumination, friendly):
				furthest = candidate
				break
		if smooth[smooth.size() - 1].distance_to(result[furthest]) > 0.05: smooth.append(result[furthest])
		cursor = furthest + 1
	return smooth

func cache_light_weights(illumination: RefCounted) -> void:
	# All cells outside deterrent light radii have weight 1. Cache only deviations;
	# this preserves exact costs while avoiding two full-map sweeps per AI route.
	var key := [revision, hash(illumination.sources)]
	if key == light_weight_key: return
	light_weight_key = key; light_weight_ids.clear(); light_weight_values.clear()
	var candidates: Dictionary = {}
	for source in illumination.sources:
		if not source.deters: continue
		var center := Hex.to_axial(source.position, RADIUS)
		var reach := ceili(float(source.radius) / (RADIUS * 1.5)) + 1
		for q in range(-reach, reach + 1):
			for r in range(maxi(-reach, -q - reach), mini(reach, -q + reach) + 1):
				var cell := center + Vector2i(q, r)
				if cells.has(cell): candidates[cells[cell]] = true
	for id in candidates:
		var strength: float = illumination.deterrence(graph.get_point_position(id))
		if strength > 0:
			light_weight_ids.append(id); light_weight_values.append(1.0 + strength * 18.0)

func traversable_segment(a: Vector3, b: Vector3, illumination: RefCounted = null, friendly: bool = false) -> bool:
	if not clear_segment(a, b, friendly): return false
	if illumination != null:
		var samples := maxi(1, ceili(a.distance_to(b) / 1.5))
		for i in range(samples + 1):
			if illumination.deterrence(a.lerp(b, float(i) / samples)) > 0.2: return false
	return true

func affects_path(position: Vector3, path_points: PackedVector3Array, index: int) -> bool:
	var previous := position
	for i in range(index, path_points.size()):
		var point := path_points[i]
		var steps := maxi(1, ceili(previous.distance_to(point)))
		for step in range(steps + 1):
			if last_dirty.has(Hex.to_axial(previous.lerp(point, float(step) / steps), RADIUS)): return true
		previous = point
	return false

func can_see(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.4))
	for i in range(steps + 1):
		var sample := a.lerp(b, float(i) / steps) + Vector3.UP * 1.5
		if solid_at(sample) or terrain.height(sample) > sample.y: return false
	for obstacle in geometry_obstacles:
		if obstacle.has("cell"): continue
		if obstacle.has("end"):
			var closest := Geometry3D.get_closest_points_between_segments(a, b, obstacle.position, obstacle.end)
			if closest[0].distance_to(closest[1]) < float(obstacle.radius): return false
			continue
		var owner = obstacle.get("owner")
		if SimEntity.valid(owner) and (preload("res://engine/structure_footprints.gd").reach(owner, a) < 1.5 or preload("res://engine/structure_footprints.gd").reach(owner, b) < 1.5): continue
		if a.distance_to(obstacle.position) < float(obstacle.radius) + 1 or b.distance_to(obstacle.position) < float(obstacle.radius) + 1: continue
		if Geometry3D.get_closest_point_to_segment(obstacle.position, a, b).distance_to(obstacle.position) < float(obstacle.radius): return false
	return true
