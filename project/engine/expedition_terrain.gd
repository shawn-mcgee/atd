extends RefCounted
const Hex = preload("res://engine/hex_grid.gd")
const MAP_RADIUS := 56
const LEVEL := 3.0
const CELL := 1.0
const SPACING := 1.7320508075688772
const NATURAL_RAMP_HIGH := Vector3(45.033320997, 0, 6)
var natural_enabled := false
var structures: Array = []
var cleared_cells: Dictionary = {}

static func contains(point: Vector3, margin: int = 0) -> bool:
	var cell := Hex.to_axial(point, CELL)
	return maxi(absi(cell.x), maxi(absi(cell.y), absi(cell.x + cell.y))) <= MAP_RADIUS - margin

static func direction(index: int) -> Vector3:
	return Hex.to_world(Hex.NEIGHBORS[posmod(index, 6)], CELL).normalized()

func height(point: Vector3) -> float:
	var result := 0.0
	# The walkable mesa is also a cluster of full hex cells.
	var center := Hex.snap(point, CELL)
	if natural_enabled and natural_mesa_cell(center) and not cleared_cells.has(Hex.to_axial(point, CELL)): result = LEVEL
	elif natural_enabled:
		var natural_anchor := Hex.snap(Vector3(43.3, 0, 6), CELL)
		var ramp_height := ramp_sample(point, natural_anchor, 0)
		if ramp_height >= 0: result = ramp_height
	for structure in structures:
		if not SimEntity.valid(structure) or not structure.complete or structure.hp <= 0: continue
		if structure.kind == "platform" and Hex.to_axial(point, CELL) == Hex.to_axial(structure.position, CELL): result = maxf(result, LEVEL)
		elif structure.kind == "ramp":
			var ramp_height := ramp_sample(point, structure.position, structure.build_direction)
			if ramp_height >= 0: result = maxf(result, ramp_height)
	return result

static func natural_mesa_cell(center: Vector3) -> bool:
	return center.x >= 45 and center.x <= 65 and center.z >= 0 and center.z <= 18

static func ramp_sample(point: Vector3, anchor: Vector3, direction_index: int) -> float:
	var forward := direction(direction_index)
	var cell := Hex.to_axial(point, CELL)
	if cell != Hex.to_axial(anchor, CELL) and cell != Hex.to_axial(anchor - forward * SPACING, CELL): return -1.0
	return clampf(((point - anchor).dot(forward) + SPACING * 1.5) / (SPACING * 2) * LEVEL, 0, LEVEL)

func surface(point: Vector3) -> Vector3:
	return Vector3(point.x, height(point), point.z)
