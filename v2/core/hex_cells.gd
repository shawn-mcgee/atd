extends RefCounted
## Integer axial cells shared by the membrane simulation and its view adapter.
const SCALE := 1024
const NEIGHBORS := [[1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1]]

static func key(cell: Array) -> String:
	return "%d,%d" % [cell[0], cell[1]]

static func point(cell: Array) -> Array:
	return [int(cell[0]) * SCALE, 0, int(cell[1]) * SCALE]

static func from_point(position: Array) -> Array:
	var q := _round(int(position[0]))
	var r := _round(int(position[2]))
	var s := _round(-int(position[0]) - int(position[2]))
	var q_error := absi(q * SCALE - int(position[0]))
	var r_error := absi(r * SCALE - int(position[2]))
	var s_error := absi(s * SCALE + int(position[0]) + int(position[2]))
	if q_error > r_error and q_error > s_error: q = -r - s
	elif r_error > s_error: r = -q - s
	return [q, r]

static func distance(a: Array, b: Array) -> int:
	return maxi(absi(int(a[0]) - int(b[0])), maxi(absi(int(a[1]) - int(b[1])), absi(int(a[0]) + int(a[1]) - int(b[0]) - int(b[1]))))

static func inside(cell: Array, radius: int) -> bool:
	return distance(cell, [0, 0]) <= radius

static func compare(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1]))

static func _round(value: int) -> int:
	@warning_ignore("integer_division")
	var rounded := (absi(value) + SCALE / 2) / SCALE
	return -rounded if value < 0 else rounded
