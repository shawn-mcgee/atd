extends RefCounted
## Shared paid/passive emergence and rally orders.
const Hex = preload("res://core/hex_cells.gd")
const Geo = preload("res://core/geometry.gd")
const Nav = preload("res://core/navigation.gd")

static func capable(game, actor: Dictionary) -> bool:
	var caps: Dictionary = game.content.units[actor.definition].capabilities
	return Geo.structure(game, actor) and (caps.has("factory") or caps.has("passive_spawner"))

@warning_ignore("integer_division")
static func default_point(game, source: Dictionary) -> Array:
	var center := Geo.center(game, source)
	var south := int(center[2])
	for cell in Geo.cells(game, source): south = maxi(south, int(cell[1]) * Hex.SCALE)
	var offset := south + 3 * Hex.SCALE - int(center[2])
	# World south is +z with unchanged x: q decreases by half the r offset.
	while offset > 0:
		var point := [int(center[0]) - offset / 2, 0, int(center[2]) + offset]
		if game.valid_point(point): return point
		offset = maxi(0, offset - Hex.SCALE / 2)
	return center

static func reset(game, source: Dictionary) -> void:
	source.rally_point = default_point(game, source) if capable(game, source) else []

static func dispatch(game, source: Dictionary, child: Dictionary) -> void:
	if not game.content.units[child.definition].capabilities.has("move"): return
	var target: Array = source.rally_point if not source.rally_point.is_empty() else default_point(game, source)
	child.order = {"kind": "move", "point": target.duplicate(), "manual": true, "start_tick": int(game.state.tick) + 1}
	game._face(child, target)

static func _emergence_ring(game, source: Dictionary, footprint: Array, size: int) -> int:
	if Geo.collision_shape(game, source) != "circle": return maxi(1, ceili(float(size + 2) / Hex.SCALE + 0.5))
	var circle := Geo.collision_circle(game, source)
	var combined := size + int(circle.radius) + 2
	var limit := ceili(float(combined) / Hex.SCALE) + 1
	# Pick the nearest ring that fits the source body before considering other
	# blockers. A crowded or walled-in exit must wait rather than teleport outward.
	for ring in range(1, limit + 1):
		for origin in footprint:
			for q in range(int(origin[0]) - ring, int(origin[0]) + ring + 1):
				for r in range(int(origin[1]) - ring, int(origin[1]) + ring + 1):
					var cell := [q, r]
					if not Hex.inside(cell, int(game.content.settings.map_radius)): continue
					var nearest := 2147483647
					for covered in footprint: nearest = mini(nearest, Hex.distance(cell, covered))
					if nearest == ring and game.distance_squared(Hex.point(cell), circle.position) > combined * combined: return ring
	return limit

static func spawn_position(game, source: Dictionary, product: String, destination: Array = []) -> Array:
	var target: Array = source.rally_point if destination.is_empty() else destination
	if target.is_empty(): target = default_point(game, source)
	var footprint := Geo.cells(game, source)
	var size := int(round(float(game.content.units[product].get("collision_radius", 0.2)) * Hex.SCALE))
	var data := Nav.actor_field(game, source)
	var exiting: Dictionary = {"hexes": data.blocked.hexes.duplicate(), "circles": []}
	for circle in data.blocked.circles:
		if int(circle.id) != int(source.id): exiting.circles.append(circle)
	for cell in footprint: exiting.hexes.erase(Hex.key(cell))
	var occupied: Dictionary = {}
	for actor in game.state.actors:
		if int(actor.hp) <= 0: continue
		if not Geo.structure(game, actor): occupied[Hex.key(Hex.from_point(actor.position))] = true
		if actor.order.get("kind") == "build":
			for cell in Geo.at(game.content.units[actor.order.definition], actor.order.point, int(actor.order.get("rotation", 0))): occupied[Hex.key(cell)] = true
	# Larger bodies need a wider ring to clear the solid source footprint.
	var ring := _emergence_ring(game, source, footprint, size)
	var candidates: Dictionary = {}
	for origin in footprint:
		for q in range(int(origin[0]) - ring, int(origin[0]) + ring + 1):
			for r in range(int(origin[1]) - ring, int(origin[1]) + ring + 1):
				var cell := [q, r]; var key := Hex.key(cell)
				if candidates.has(key) or occupied.has(key): continue
				var nearest := 2147483647
				for covered in footprint: nearest = mini(nearest, Hex.distance(cell, covered))
				if nearest != ring or not Nav.center_clear(game, cell, size, data): continue
				for covered in footprint:
					if Nav.segment_clear(game, Hex.point(covered), Hex.point(cell), size, exiting, data.enemies):
						candidates[key] = cell
						break
	var cells: Array = candidates.values()
	if cells.is_empty(): return []
	cells.sort_custom(Hex.compare)
	var goal := Hex.from_point(target)
	var routes := Nav.static_field(data)
	var goals: Array = [goal] if Nav.center_clear(game, goal, size, routes) else Nav._goals(game, {"definition": product, "position": target}, target, null, Hex.SCALE, routes)
	var best := Nav.closest_reachable(game, goals, cells, size, data)
	if not best.is_empty(): return Hex.point(best)
	# An unreachable rally must not freeze production; ordinary movement reports it.
	cells.sort_custom(func(a, b):
		var da: int = game.distance_squared(Hex.point(a), target); var db: int = game.distance_squared(Hex.point(b), target)
		return da < db or (da == db and Hex.compare(a, b)))
	return Hex.point(cells[0])
