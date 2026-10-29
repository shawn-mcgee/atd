extends RefCounted
const Hex = preload("res://scripts/hex_grid.gd")
const Terrain = preload("res://scripts/expedition_terrain.gd")
const RADIUS := 2.0
var terrain := Terrain.new()
var graph := AStar3D.new()
var cells: Dictionary = {}
var obstacles: Array[Dictionary] = []
var solid_cells: Dictionary = {}

func _init() -> void:
	for r in range(-Terrain.MAP_RADIUS, Terrain.MAP_RADIUS + 1):
		for q in range(-Terrain.MAP_RADIUS, Terrain.MAP_RADIUS + 1):
			var cell := Vector2i(q, r)
			var point := Hex.to_world(cell, RADIUS)
			if not Terrain.contains(point): continue
			var id := graph.get_available_point_id()
			cells[cell] = id
			graph.add_point(id, point)

func rebuild(blockers: Array[Dictionary]) -> void:
	obstacles = blockers
	solid_cells.clear()
	for obstacle in obstacles:
		if obstacle.has("cell"): solid_cells[obstacle.cell] = obstacle
	for cell in cells:
		var id: int = cells[cell]
		graph.set_point_position(id, terrain.surface(Hex.to_world(cell, RADIUS)))
		for other in graph.get_point_connections(id): graph.disconnect_points(id, other)
		graph.set_point_disabled(id, blocked(graph.get_point_position(id)))
	for cell in cells:
		var id: int = cells[cell]
		if graph.is_point_disabled(id): continue
		for offset in Hex.NEIGHBORS:
			var neighbor: Vector2i = cell + offset
			if not cells.has(neighbor): continue
			var other: int = cells[neighbor]
			if other <= id or graph.is_point_disabled(other): continue
			if clear_segment(graph.get_point_position(id), graph.get_point_position(other)):
				graph.connect_points(id, other)

func blocked(point: Vector3) -> bool:
	if not Terrain.contains(point): return true
	if solid_at(point): return true
	for obstacle in obstacles:
		if obstacle.has("cell"): continue
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

func clear_segment(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / 0.4))
	var previous := terrain.height(a)
	for i in range(steps + 1):
		var sample := a.lerp(b, float(i) / steps)
		var height := terrain.height(sample)
		if not Terrain.contains(sample) or solid_at(sample) or absf(height - previous) > 0.55: return false
		previous = height
	for obstacle in obstacles:
		if obstacle.has("cell"): continue
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

func path(a: Vector3, b: Vector3, illumination: RefCounted = null) -> PackedVector3Array:
	# The hex graph is only a search scaffold. Units keep continuous world positions
	# and receive exact free-space destinations, with line-of-sight string pulling.
	if not Terrain.contains(b): return PackedVector3Array()
	a = terrain.surface(a); b = terrain.surface(b)
	if not blocked(b) and traversable_segment(a, b, illumination):
		return PackedVector3Array([a, b])
	var start := graph.get_closest_point(a)
	var finish := graph.get_closest_point(b)
	if start < 0 or finish < 0: return PackedVector3Array()
	if illumination != null:
		for id in graph.get_point_ids(): graph.set_point_weight_scale(id, 1.0 + illumination.deterrence(graph.get_point_position(id)) * 18.0)
	var result := graph.get_point_path(start, finish)
	if illumination != null:
		for id in graph.get_point_ids(): graph.set_point_weight_scale(id, 1.0)
	if result.is_empty(): return result
	if not blocked(b) and traversable_segment(result[result.size() - 1], b, illumination): result.append(b)
	var smooth := PackedVector3Array([a])
	var cursor := 0
	while cursor < result.size():
		var furthest := cursor
		for candidate in range(result.size() - 1, cursor - 1, -1):
			if traversable_segment(smooth[smooth.size() - 1], result[candidate], illumination):
				furthest = candidate
				break
		if smooth[smooth.size() - 1].distance_to(result[furthest]) > 0.05: smooth.append(result[furthest])
		cursor = furthest + 1
	return smooth

func traversable_segment(a: Vector3, b: Vector3, illumination: RefCounted = null) -> bool:
	if not clear_segment(a, b): return false
	if illumination != null:
		var samples := maxi(1, ceili(a.distance_to(b) / 1.5))
		for i in range(samples + 1):
			if illumination.deterrence(a.lerp(b, float(i) / samples)) > 0.2: return false
	return true

func can_see(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.4))
	for i in range(steps + 1):
		var sample := a.lerp(b, float(i) / steps) + Vector3.UP * 1.5
		if solid_at(sample) or terrain.height(sample) > sample.y: return false
	for obstacle in obstacles:
		if obstacle.has("cell"): continue
		if obstacle.has("end"):
			var closest := Geometry3D.get_closest_points_between_segments(a, b, obstacle.position, obstacle.end)
			if closest[0].distance_to(closest[1]) < float(obstacle.radius): return false
			continue
		if a.distance_to(obstacle.position) < float(obstacle.radius) + 1 or b.distance_to(obstacle.position) < float(obstacle.radius) + 1: continue
		if Geometry3D.get_closest_point_to_segment(obstacle.position, a, b).distance_to(obstacle.position) < float(obstacle.radius): return false
	return true
