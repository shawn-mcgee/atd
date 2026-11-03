extends RefCounted
## Deterministic axial A*. Paths belong to actors; obstacle caches are derived.
const Hex = preload("res://core/hex_cells.gd")
const Geo = preload("res://core/geometry.gd")
const Canonical = preload("res://core/canonical.gd")

static func field(game, cache: Dictionary) -> Dictionary:
	var signature: Array = [game.content.settings.get("terrain", [])]
	var blocked: Dictionary = {}
	var circles: Array = []
	for cell in game.content.settings.get("terrain", []): blocked[Hex.key(cell)] = cell
	for actor in game.actor_group("structures"):
		if int(actor.hp) <= 0 or not Geo.structure(game, actor) or actor.construction.get("kind") == "blueprint": continue
		if not game.content.units[actor.definition].get("blocks_movement", true): continue
		if Geo.collision_shape(game, actor) == "circle":
			var circle := Geo.collision_circle(game, actor)
			signature.append(circle)
			circles.append(circle)
		else:
			var occupied := Geo.cells(game, actor)
			signature.append(occupied)
			for cell in occupied: blocked[Hex.key(cell)] = cell
	if cache.get("signature", []) == signature: return cache.field
	var keys: Array = blocked.keys(); keys.sort()
	var result := {"blocked": {"hexes": blocked, "circles": circles}, "hash": Canonical.hash_of([keys, circles]), "clearance": {}}
	if game._crowd.backend != null:
		var shapes := PackedInt64Array([blocked.size()])
		for cell in blocked.values(): shapes.append(int(cell[0])); shapes.append(int(cell[1]))
		shapes.append(circles.size())
		for circle in circles: shapes.append(int(circle.position[0])); shapes.append(int(circle.position[2])); shapes.append(int(circle.radius))
		result.blocked.native_backend = game._crowd.backend
		result.blocked.native_revision = int(game._crowd.backend.call("world", shapes, int(game.content.settings.map_radius), result.hash))
	cache.signature = signature.duplicate(true)
	cache.field = result
	return result

static func actor_field(game, actor: Dictionary) -> Dictionary:
	var base: Dictionary = game.navigation_field()
	var circles: Dictionary = game.enemy_circles(int(actor.owner))
	var enemies: Array = circles.enemies
	return {"blocked": base.blocked, "hash": base.hash, "clearance": base.clearance, "enemies": enemies, "enemy_bounds": circles.bounds}

static func clear(game, point: Array, size: int, obstacles: Dictionary) -> bool:
	return segment_clear(game, point, point, size, obstacles)

@warning_ignore("integer_division")
static func segment_clear(game, a: Array, b: Array, size: int, obstacles: Dictionary, enemies: Array = []) -> bool:
	var hexes: Dictionary = obstacles.get("hexes", obstacles)
	var map_radius := int(game.content.settings.map_radius)
	if int(a[1]) != 0 or int(b[1]) != 0: return false
	var backend: RefCounted = obstacles.get("native_backend")
	if backend != null:
		var valid := int(backend.call("static_clear", int(obstacles.native_revision), Vector2i(int(a[0]), int(a[2])), Vector2i(int(b[0]), int(b[2])), size))
		if valid >= 0: return valid == 1 and enemy_clear(a, b, size, enemies)
	var pad := (size + Hex.SCALE - 1) / Hex.SCALE + 1
	var interior := true
	var inner_limit := (map_radius - pad) * Hex.SCALE
	for point in [a, b]:
		if absi(int(point[0])) > inner_limit or absi(int(point[2])) > inner_limit or absi(int(point[0]) + int(point[2])) > inner_limit: interior = false
	if interior and hexes.is_empty():
		return enemy_clear(a, b, size, obstacles.get("circles", [])) and enemy_clear(a, b, size, enemies)
	var start := Hex.from_point(a); var end := Hex.from_point(b)
	if not interior and (not Hex.inside(start, map_radius) or not Hex.inside(end, map_radius)): return false
	var min_q := mini(int(start[0]), int(end[0])) - pad; var max_q := maxi(int(start[0]), int(end[0])) + pad
	var min_r := mini(int(start[1]), int(end[1])) - pad; var max_r := maxi(int(start[1]), int(end[1])) + pad
	if interior and hexes.size() < (max_q - min_q + 1) * (max_r - min_r + 1):
		# Sparse arenas need checks only against actual occupied hexes.
		for cell in hexes.values():
			if int(cell[0]) >= min_q and int(cell[0]) <= max_q and int(cell[1]) >= min_r and int(cell[1]) <= max_r and not Geo.clear_hex(a, b, size, cell): return false
	else:
		for q in range(mini(int(start[0]), int(end[0])) - pad, maxi(int(start[0]), int(end[0])) + pad + 1):
			for r in range(mini(int(start[1]), int(end[1])) - pad, maxi(int(start[1]), int(end[1])) + pad + 1):
				var cell := [q, r]
				if (not Hex.inside(cell, map_radius) or hexes.has(Hex.key(cell))) and not Geo.clear_hex(a, b, size, cell): return false
	return enemy_clear(a, b, size, obstacles.get("circles", [])) and enemy_clear(a, b, size, enemies)

@warning_ignore("integer_division")
static func enemy_clear(a: Array, b: Array, size: int, enemies: Array, bounds: Array = []) -> bool:
	if enemies.is_empty(): return true
	var min_q := mini(int(a[0]), int(b[0])); var max_q := maxi(int(a[0]), int(b[0]))
	var min_r := mini(int(a[2]), int(b[2])); var max_r := maxi(int(a[2]), int(b[2]))
	var vq := int(b[0]) - int(a[0]); var vr := int(b[2]) - int(a[2])
	var length := vq * vq + vq * vr + vr * vr
	if not bounds.is_empty():
		var margin := (size * 1183 + 1023) / 1024 + 4
		if maxi(int(a[0]), int(b[0])) + margin < int(bounds[0]) or mini(int(a[0]), int(b[0])) - margin > int(bounds[1]) or maxi(int(a[2]), int(b[2])) + margin < int(bounds[2]) or mini(int(a[2]), int(b[2])) - margin > int(bounds[3]): return true
	for enemy in enemies:
		var extent := (size + int(enemy.radius) + 2) * 1183 / 1024 + 2
		if int(enemy.position[0]) < min_q - extent or int(enemy.position[0]) > max_q + extent or int(enemy.position[2]) < min_r - extent or int(enemy.position[2]) > max_r + extent: continue
		var q := int(enemy.position[0]) - int(a[0]); var r := int(enemy.position[2]) - int(a[2])
		var limit := size + int(enemy.radius) + 2
		var start_distance := q * q + q * r + r * r
		var closest := start_distance
		if length > 0:
			var dot2 := 2 * q * vq + q * vr + r * vq + 2 * r * vr
			var t := clampi(dot2 * 1048576 / (2 * length), 0, 1048576)
			var dq := q - vq * t / 1048576; var dr := r - vr * t / 1048576
			closest = dq * dq + dq * dr + dr * dr
		if closest > limit * limit: continue
		# Allow an already intersecting body to move outward, never further through it.
		var eq := q - vq; var er := r - vr
		if start_distance < limit * limit and eq * eq + eq * er + er * er > start_distance and closest >= start_distance: continue
		return false
	return true

static func center_clear(game, cell: Array, size: int, field_data: Dictionary) -> bool:
	var bucket := str(size)
	if not field_data.clearance.has(bucket): field_data.clearance[bucket] = {}
	var values: Dictionary = field_data.clearance[bucket]
	var key := Hex.key(cell)
	if not values.has(key): values[key] = segment_clear(game, Hex.point(cell), Hex.point(cell), size, field_data.blocked)
	if not values[key]: return false
	if field_data.get("enemies", []).is_empty(): return true
	var point := Hex.point(cell)
	return enemy_clear(point, point, size, field_data.get("enemies", []), field_data.get("enemy_bounds", []))

static func static_field(data: Dictionary) -> Dictionary:
	return {"blocked": data.blocked, "hash": data.hash, "clearance": data.clearance, "enemies": []}

static func next(game, actor: Dictionary, destination: Array, target = null, reach: int = 0, interaction: bool = false, supplied_field = null) -> Array:
	# Routes depend only on terrain and immobile collision shapes. Mobile bodies
	# belong to local steering/contact checks, never the global search graph.
	var data := static_field(game.navigation_field() if supplied_field == null else supplied_field)
	var size := Geo.radius(game, actor)
	var key: Array = [destination, int(target.id) if target != null else 0, reach, data.hash, size, interaction]
	var old: Dictionary = actor.get("navigation", {})
	if old.get("key", []) == key and old.get("direct", false):
		if not old.get("deviated", false) or segment_clear(game, actor.position, destination, size + 2, data.blocked):
			old.deviated = false
			return destination
	if target == null and segment_clear(game, actor.position, destination, size + 2, data.blocked):
		actor.navigation = {"key": key.duplicate(true), "path": [], "direct": true, "blocked": false}
		return destination
	if old.get("key", []) != key or (old.get("deviated", false) and not _route_clear(game, actor.position, old.get("path", []).slice(0, 1), size, data)):
		for other in game.state.actors:
			if int(other.id) == int(actor.id) or int(other.owner) != int(actor.owner) or int(other.hp) <= 0: continue
			var route: Dictionary = other.get("navigation", {})
			if route.get("key", []) == key and not route.get("path", []).is_empty() and segment_clear(game, actor.position, route.path[0], size + 2, data.blocked):
				actor.navigation = {"key": key.duplicate(true), "path": route.path.duplicate(true), "blocked": false}
				return actor.navigation.path[0]
		var goals := _goals(game, actor, destination, target, reach, data, interaction)
		data.search_expansions = 0
		var coarse := _path(game, actor, goals, data)
		if game._inside_step:
			game._navigation_searches += 1
			game._navigation_expansions += int(data.search_expansions)
		actor.navigation = {"key": key.duplicate(true), "path": _smooth(game, actor.position, coarse, size, data.blocked), "blocked": coarse.is_empty()}
	actor.navigation.deviated = false
	var path: Array = actor.navigation.path
	while not path.is_empty() and actor.position == path[0]: path.pop_front()
	if path.is_empty(): return []
	for index in range(path.size() - 1, 0, -1):
		if segment_clear(game, actor.position, path[index], size + 2, data.blocked):
			path = path.slice(index)
			actor.navigation.path = path
			break
	return path[0]

static func _route_clear(game, origin: Array, path: Array, size: int, data: Dictionary) -> bool:
	if path.is_empty(): return false
	var previous: Array = origin
	for point in path:
		if not segment_clear(game, previous, point, size, data.blocked): return false
		previous = point
	return true

static func _smooth(game, start: Array, path: Array, size: int, obstacles: Dictionary, enemies: Array = []) -> Array:
	var result: Array = []
	var origin: Array = start
	var first := 0
	while first < path.size():
		var last := first
		for index in range(path.size() - 1, first, -1):
			# A tiny fixed-point safety margin avoids corner grazing after rounding.
			if segment_clear(game, origin, path[index], size + 2, obstacles, enemies):
				last = index
				break
		result.append(path[last])
		origin = path[last]
		first = last + 1
	return result

static func _goals(game, actor: Dictionary, destination: Array, target, reach: int, data: Dictionary, interaction: bool = false) -> Array:
	var goals: Array = []
	var size := Geo.radius(game, actor)
	var center := Hex.from_point(destination)
	if target == null and reach == 0 and segment_clear(game, destination, destination, size, data.blocked, data.get("enemies", [])): return [center]
	var occupied: Array = Geo.cells(game, target) if target != null and Geo.structure(game, target) else [center]
	var seen: Dictionary = {}
	var span := ceili(float(reach + size) / Hex.SCALE) + 2 if target != null or reach > 0 else 4
	for origin in occupied:
		for q in range(int(origin[0]) - span, int(origin[0]) + span + 1):
			for r in range(int(origin[1]) - span, int(origin[1]) + span + 1):
				var cell := [q, r]; var key := Hex.key(cell)
				if seen.has(key): continue
				seen[key] = true
				if interaction and target != null and Geo.structure(game, target) and cell in occupied: continue
				if not center_clear(game, cell, size, data): continue
				if interaction and target != null and Geo.structure(game, target) and Geo.intersects_collision(game, {"definition": actor.definition, "position": Hex.point(cell)}, target): continue
				var distance: int = (Geo.interaction_distance(game, Hex.point(cell), target) if interaction else Geo.distance_to_actor(game, Hex.point(cell), target)) if target != null else game.distance_squared(Hex.point(cell), destination)
				if (target != null or reach > 0) and distance > reach * reach: continue
				goals.append(cell)
	if target == null and reach == 0 and not goals.is_empty():
		goals.sort_custom(func(a, b):
			var da: int = game.distance_squared(Hex.point(a), destination); var db: int = game.distance_squared(Hex.point(b), destination)
			return da < db or (da == db and Hex.compare(a, b)))
		var nearest: int = game.distance_squared(Hex.point(goals[0]), destination)
		goals = goals.filter(func(cell): return game.distance_squared(Hex.point(cell), destination) == nearest)
	goals.sort_custom(Hex.compare)
	return goals

static func closest_reachable(game, origins: Array, goals: Array, size: int, data: Dictionary) -> Array:
	data = static_field(data)
	# One reverse multi-source A* ranks emergence tiles by navigable distance.
	var heap: Array = []; var costs: Dictionary = {}; var targets: Dictionary = {}
	for cell in goals: targets[Hex.key(cell)] = true
	for cell in origins:
		var key := Hex.key(cell)
		if costs.has(key): continue
		costs[key] = 0
		var h := _heuristic(cell, goals)
		_push(heap, [h, h, int(cell[0]), int(cell[1]), 0])
	while not heap.is_empty():
		var item := _pop(heap); var cell := [item[2], item[3]]; var key := Hex.key(cell); var work := int(item[4])
		if work != int(costs[key]): continue
		if targets.has(key): return cell
		for offset in Hex.NEIGHBORS:
			var neighbor := [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])]; var next_key := Hex.key(neighbor)
			if costs.has(next_key) and int(costs[next_key]) <= work + 1: continue
			if not center_clear(game, neighbor, size, data) or not segment_clear(game, Hex.point(cell), Hex.point(neighbor), size, data.blocked, data.get("enemies", [])): continue
			costs[next_key] = work + 1
			var h := _heuristic(neighbor, goals)
			_push(heap, [work + 1 + h, h, int(neighbor[0]), int(neighbor[1]), work + 1])
	return []

static func _heuristic(cell: Array, goals: Array) -> int:
	var best := 2147483647
	for goal in goals: best = mini(best, Hex.distance(cell, goal))
	return best

static func _less(a: Array, b: Array) -> bool:
	for index in 4:
		if a[index] != b[index]: return a[index] < b[index]
	return false

static func _push(heap: Array, value: Array) -> void:
	heap.append(value)
	var index := heap.size() - 1
	while index > 0:
		@warning_ignore("integer_division")
		var parent := (index - 1) / 2
		if not _less(heap[index], heap[parent]): break
		var old: Array = heap[parent]; heap[parent] = heap[index]; heap[index] = old
		index = parent

static func _pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return result
	heap[0] = last
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and _less(heap[child + 1], heap[child]): child += 1
		if not _less(heap[child], heap[index]): break
		var old: Array = heap[index]; heap[index] = heap[child]; heap[child] = old
		index = child
	return result

static func _path(game, actor: Dictionary, goals: Array, data: Dictionary) -> Array:
	if goals.is_empty(): return []
	var start := Hex.from_point(actor.position); var start_key := Hex.key(start)
	var heap: Array = []; var cost: Dictionary = {start_key: 0}; var previous: Dictionary = {}; var goal_keys: Dictionary = {}
	for goal in goals: goal_keys[Hex.key(goal)] = true
	var h := _heuristic(start, goals)
	_push(heap, [h, h, int(start[0]), int(start[1]), 0])
	var size := Geo.radius(game, actor)
	var anchor := Hex.point(start)
	var anchored: bool = actor.position != anchor and segment_clear(game, actor.position, anchor, size, data.blocked, data.get("enemies", []))
	while not heap.is_empty():
		var item := _pop(heap); var cell := [item[2], item[3]]; var key := Hex.key(cell); var work := int(item[4])
		if work != int(cost[key]): continue
		if goal_keys.has(key):
			var result: Array = [Hex.point(cell)]
			while key != start_key:
				cell = previous[key]; key = Hex.key(cell)
				if key != start_key: result.push_front(Hex.point(cell))
			if anchored and result[0] != anchor: result.push_front(anchor)
			return result
		data.search_expansions = int(data.get("search_expansions", 0)) + 1
		var from: Array = actor.position if key == start_key and not anchored else Hex.point(cell)
		for offset in Hex.NEIGHBORS:
			var neighbor := [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])]; var next_key := Hex.key(neighbor)
			if cost.has(next_key) and int(cost[next_key]) <= work + 1: continue
			if not center_clear(game, neighbor, size, data) or not segment_clear(game, from, Hex.point(neighbor), size, data.blocked, data.get("enemies", [])): continue
			cost[next_key] = work + 1; previous[next_key] = cell
			h = _heuristic(neighbor, goals)
			_push(heap, [work + 1 + h, h, int(neighbor[0]), int(neighbor[1]), work + 1])
	return []
