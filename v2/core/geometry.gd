extends RefCounted
const Actor = preload("res://core/actor.gd")
## Shared fixed-point axial footprints and circle/hex clearance.
const Hex = preload("res://core/hex_cells.gd")
const S := 1024
const CORNERS := [[1, 1], [-1, 2], [-2, 1], [-1, -1], [1, -2], [2, -1]]

static func definition(game, actor: Actor) -> Dictionary:
	return game.content.units[actor.construction.get("definition", actor.definition)]

static func structure(game, actor: Actor) -> bool:
	return not game.content.units[actor.definition].capabilities.has("move")

static func offsets(def: Dictionary, rotation: int = 0) -> Array:
	var result: Array = []
	for offset in def.get("footprint", [[0, 0]]):
		var q := int(offset[0]); var r := int(offset[1])
		for turn in posmod(rotation, 6):
			var next := -r
			r = q + r
			q = next
		result.append([q, r])
	return result

static func cells(game, actor: Actor) -> Array:
	return at(definition(game, actor), actor.position, int(actor.rotation))

static func at(def: Dictionary, point: Array, rotation: int = 0) -> Array:
	var origin := Hex.from_point(point)
	var result: Array = []
	for offset in offsets(def, rotation): result.append([int(origin[0]) + int(offset[0]), int(origin[1]) + int(offset[1])])
	return result

@warning_ignore("integer_division")
static func center(game, actor: Actor) -> Array:
	if not structure(game, actor): return actor.position.duplicate()
	var occupied := cells(game, actor)
	var q := 0; var r := 0
	for cell in occupied:
		q += int(cell[0]) * S
		r += int(cell[1]) * S
	return [q / occupied.size(), int(actor.position[1]), r / occupied.size()]

static func radius(game, actor: Actor) -> int:
	return int(round(float(game.content.units[actor.definition].get("collision_radius", 0.2)) * S))

static func collision_shape(game, actor: Actor) -> String:
	return str(definition(game, actor).get("collision_shape", "footprint" if structure(game, actor) else "circle"))

static func collision_circle(game, actor: Actor) -> Dictionary:
	return {"id": int(actor.id), "position": center(game, actor), "radius": int(round(float(definition(game, actor).get("collision_radius", 0.2)) * S))}

static func intersects_collision(game, unit: Actor, target: Actor) -> bool:
	if collision_shape(game, target) == "footprint": return intersects_unit(game, unit, cells(game, target))
	var circle := collision_circle(game, target)
	var combined := radius(game, unit) + int(circle.radius) + 2
	return game.distance_squared(unit.position, circle.position) <= combined * combined

static func metric(a: Array) -> int:
	return int(a[0]) * int(a[0]) + int(a[0]) * int(a[1]) + int(a[1]) * int(a[1])

static func sub(a: Array, b: Array) -> Array:
	return [int(a[0]) - int(b[0]), int(a[1]) - int(b[1])]

static func cross(a: Array, b: Array) -> int:
	return int(a[0]) * int(b[1]) - int(a[1]) * int(b[0])

@warning_ignore("integer_division")
static func segment_distance(point: Array, a: Array, b: Array) -> int:
	var v := sub(b, a); var w := sub(point, a)
	var length := metric(v)
	if length == 0: return metric(w)
	var dot2 := 2 * int(w[0]) * int(v[0]) + int(w[0]) * int(v[1]) + int(w[1]) * int(v[0]) + 2 * int(w[1]) * int(v[1])
	var t := clampi(dot2 * 1048576 / (2 * length), 0, 1048576)
	return metric([int(w[0]) - int(v[0]) * t / 1048576, int(w[1]) - int(v[1]) * t / 1048576])

static func hex_corners(cell: Array) -> Array:
	var result: Array = []
	for offset in CORNERS: result.append([int(cell[0]) * 3 * S + int(offset[0]) * S, int(cell[1]) * 3 * S + int(offset[1]) * S])
	return result

static func inside(point: Array, cell: Array) -> bool:
	var q := int(point[0]) - int(cell[0]) * 3 * S
	var r := int(point[1]) - int(cell[1]) * 3 * S
	return absi(2 * q + r) <= 3 * S and absi(q + 2 * r) <= 3 * S and absi(q - r) <= 3 * S

@warning_ignore("integer_division")
static func distance_to_cells(point: Array, occupied: Array) -> int:
	var p := [int(point[0]) * 3, int(point[2]) * 3]
	var best := 9223372036854775807
	for cell in occupied:
		if inside(p, cell): return 0
		var corners := hex_corners(cell)
		for index in 6: best = mini(best, segment_distance(p, corners[index], corners[(index + 1) % 6]))
	return best / 9

static func distance_to_actor(game, point: Array, target: Actor) -> int:
	return distance_to_cells(point, cells(game, target)) if structure(game, target) else game.distance_squared(point, target.position)

static func interaction_distance(game, point: Array, target: Actor) -> int:
	# Interaction radii are center-to-center, including for multi-tile targets.
	if not structure(game, target): return game.distance_squared(point, target.position)
	var best := 9223372036854775807
	for cell in cells(game, target): best = mini(best, game.distance_squared(point, Hex.point(cell)))
	return best

@warning_ignore("integer_division")
static func adjacent_radius(game, actor: Actor, target: Actor) -> int:
	var bodies := radius(game, actor) + (S / 2 if structure(game, target) else radius(game, target))
	return maxi(3 * S / 2, (bodies + S - 1) / S * S)

static func intersects_unit(game, unit: Actor, occupied: Array) -> bool:
	var size := radius(game, unit)
	return distance_to_cells(unit.position, occupied) < size * size

static func intersects(a: Array, b: Array, c: Array, d: Array) -> bool:
	var ab := sub(b, a); var cd := sub(d, c)
	var ac := cross(ab, sub(c, a)); var ad := cross(ab, sub(d, a))
	var ca := cross(cd, sub(a, c)); var cb := cross(cd, sub(b, c))
	if (ac > 0 and ad > 0) or (ac < 0 and ad < 0) or (ca > 0 and cb > 0) or (ca < 0 and cb < 0): return false
	return maxi(int(a[0]), int(b[0])) >= mini(int(c[0]), int(d[0])) and maxi(int(c[0]), int(d[0])) >= mini(int(a[0]), int(b[0])) and maxi(int(a[1]), int(b[1])) >= mini(int(c[1]), int(d[1])) and maxi(int(c[1]), int(d[1])) >= mini(int(a[1]), int(b[1]))

static func clear_hex(a: Array, b: Array, size: int, cell: Array) -> bool:
	var start := [int(a[0]) * 3, int(a[2]) * 3]
	var end := [int(b[0]) * 3, int(b[2]) * 3]
	if inside(start, cell) or inside(end, cell): return false
	var corners := hex_corners(cell)
	var limit := (size * 3 + 2) * (size * 3 + 2)
	for index in 6:
		var c: Array = corners[index]; var d: Array = corners[(index + 1) % 6]
		if intersects(start, end, c, d): return false
		if segment_distance(start, c, d) <= limit or segment_distance(end, c, d) <= limit or segment_distance(c, start, end) <= limit: return false
	return true
