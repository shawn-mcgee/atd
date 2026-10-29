extends RefCounted
## Pointy-top axial coordinates, with cube rounding at cell boundaries.
const SQRT_3 := 1.7320508075688772
const NEIGHBORS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func to_axial(point: Vector3, radius: float) -> Vector2i:
	var q := (SQRT_3 / 3.0 * point.x - point.z / 3.0) / radius
	var r := point.z * 2.0 / 3.0 / radius
	var s := -q - r
	var rq := roundi(q)
	var rr := roundi(r)
	var rs := roundi(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)

static func to_world(axial: Vector2i, radius: float) -> Vector3:
	return Vector3(radius * SQRT_3 * (axial.x + axial.y * 0.5), 0, radius * 1.5 * axial.y)

static func snap(point: Vector3, radius: float) -> Vector3:
	return to_world(to_axial(point, radius), radius)
