extends RefCounted
## Authoritative visibility, shared by combat, creatures and the terrain shader.
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
var sources: Array[Dictionary] = []
var navigation_ref: WeakRef
var reachable: Array[Dictionary] = []
var field: Dictionary = {}
var reach_cache: Dictionary = {}
var field_key: Array = []
var geometry_revision := -1
var heights: Dictionary = {}
var walls: Dictionary = {}
var dirty := true

func configure(navigation: RefCounted) -> void:
	navigation_ref = weakref(navigation); dirty = true

func clear() -> void:
	sources.clear(); dirty = true

func cell_height(cell: Vector2i, navigation: RefCounted) -> float:
	if not heights.has(cell):
		var height: float = navigation.graph.get_point_position(navigation.cells[cell]).y
		if navigation.solid_cells.has(cell):
			var obstacle: Dictionary = navigation.solid_cells[cell]
			height = maxf(height, float(obstacle.position.y) + float(obstacle.height))
		heights[cell] = height
	return float(heights[cell])

func flood(source: Dictionary, navigation: RefCounted) -> Dictionary:
	var start := Hex.to_axial(source.position, Terrain.CELL)
	if not navigation.cells.has(start): return {}
	var reached := {start: maxf(float(source.position.y), navigation.terrain.height(source.position))}; var walked := {start: true}
	var queue: Array = [[start, 0]]; var cursor := 0
	var max_steps := ceili(float(source.radius) / Terrain.SPACING) + 1
	while cursor < queue.size():
		var entry: Array = queue[cursor]; cursor += 1
		var cell: Vector2i = entry[0]; var depth: int = entry[1]
		if depth >= max_steps: continue
		var height: float = maxf(maxf(float(source.position.y), navigation.terrain.height(source.position)), cell_height(cell, navigation))
		for offset in Hex.NEIGHBORS:
			var next: Vector2i = cell + offset
			if walked.has(next) or not navigation.cells.has(next): continue
			var point := Hex.to_world(next, Terrain.CELL)
			if source_strength(point, source) <= 0: continue
			var next_height := cell_height(next, navigation)
			# The near face can be seen, but visibility does not rise onto its top.
			reached[next] = maxf(float(reached.get(next, -INF)), minf(height, next_height))
			var rise := next_height - height
			var ramp: bool = navigation.slope_cells.has(cell) or navigation.slope_cells.has(next)
			if (walls.has(next) and height < float(walls[next]) - 0.2) or (rise > 0.2 and not (ramp and rise <= Terrain.LEVEL * 0.55)): continue
			reached[next] = next_height; walked[next] = true; queue.append([next, depth + 1])
	return reached

func ensure_field() -> void:
	var navigation = navigation_ref.get_ref() if navigation_ref != null else null
	if navigation == null: return
	var key := [navigation.revision, hash(sources)]
	if key == field_key: dirty = false; return
	if geometry_revision != navigation.revision:
		geometry_revision = navigation.revision; heights.clear(); walls.clear(); reach_cache.clear()
		for obstacle in navigation.geometry_obstacles:
			var owner = obstacle.get("owner")
			if SimEntity.valid(owner) and owner.kind in ["wall", "gate"]: walls[Hex.to_axial(obstacle.position, Terrain.CELL)] = float(owner.position.y) + Terrain.LEVEL
	if reach_cache.size() > 128: reach_cache.clear()
	reachable.clear(); field.clear()
	for source in sources:
		var source_key := hash(source)
		if not reach_cache.has(source_key): reach_cache[source_key] = flood(source, navigation)
		var cells: Dictionary = reach_cache[source_key]; reachable.append(cells)
		for cell in cells:
			var point: Vector3 = navigation.graph.get_point_position(navigation.cells[cell])
			var strength := source_strength(point, source) if point.y <= float(cells[cell]) + 0.2 else 0.0
			if strength > 0: field[cell] = minf(1.0, float(field.get(cell, 0.0)) + strength)
	field_key = key; dirty = false

func sample_source(point: Vector3, source: Dictionary) -> float:
	if navigation_ref != null:
		if dirty or (navigation_ref != null and navigation_ref.get_ref().revision != geometry_revision): ensure_field()
		var index := sources.find(source)
		if index >= 0 and index < reachable.size():
			var cell := Hex.to_axial(point, Terrain.CELL)
			if not reachable[index].has(cell) or point.y > float(reachable[index][cell]) + 0.2: return 0.0
	return source_strength(point, source)


func add_source(point: Vector3, radius: float, direction: Vector3 = Vector3.ZERO, cone_cos: float = -1.0, intensity: float = 1.0, deters: bool = true) -> void:
	dirty = true
	sources.append({"position": point, "radius": radius, "direction": direction, "cone": cone_cos, "intensity": intensity, "deters": deters})

func sample(point: Vector3, deterrence_only: bool = false) -> float:
	if dirty or (navigation_ref != null and navigation_ref.get_ref().revision != geometry_revision): ensure_field()
	var cell := Hex.to_axial(point, Terrain.CELL)
	var total := 0.0
	for i in range(sources.size()):
		var source: Dictionary = sources[i]
		if deterrence_only and not source.deters: continue
		if navigation_ref != null and i < reachable.size():
			if not reachable[i].has(cell) or point.y > float(reachable[i][cell]) + 0.2: continue
		total += source_strength(point, source)
		if total >= 1.0: return 1.0
	return minf(1.0, total)

static func source_strength(point: Vector3, source: Dictionary) -> float:
	var offset: Vector3 = point - source.position
	offset.y = 0
	var radius: float = source.radius
	var squared := offset.length_squared()
	if squared >= radius * radius: return 0.0
	var distance := sqrt(squared)
	var strength := 1.0 - smoothstep(radius * 0.55, radius, distance)
	if float(source.cone) > -0.5 and distance > 0.01:
		var alignment := (offset / distance).dot(source.direction)
		strength *= smoothstep(float(source.cone), float(source.cone) + 0.12, alignment)
	return strength * float(source.intensity)

func deterrence(point: Vector3) -> float:
	return sample(point, true)
