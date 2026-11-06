class_name HexGrid
extends RefCounted

const STEP := 0.8660254037844386
const RADIUS := 0.5773502691896258
const DIRECTIONS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + cell.y * 0.5, cell.y * STEP)

static func cell(point: Vector2) -> Vector2i:
	var r := point.y / STEP
	var q := point.x - r * 0.5
	var x := roundi(q)
	var y := roundi(-q - r)
	var z := roundi(r)
	var dx := absf(x - q)
	var dy := absf(y + q + r)
	var dz := absf(z - r)
	if dx > dy and dx > dz:
		x = -y - z
	elif dy > dz:
		y = -x - z
	else:
		z = -x - y
	return Vector2i(x, z)

static func distance(a: Vector2i, b: Vector2i = Vector2i.ZERO) -> int:
	var d := a - b
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.x + d.y)))

static func disk(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			result.append(center + Vector2i(q, r))
	return result

static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

static func unkey(value: String) -> Vector2i:
	var parts := value.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var steps := distance(a, b)
	for i in range(steps + 1):
		result.append(cell(world(a).lerp(world(b), float(i) / maxi(1, steps))))
	return result
