extends RefCounted
const Hex = preload("res://scripts/hex_grid.gd")
const MAP_RADIUS := 56
const LEVEL := 3.0
const CELL := 1.0
const SPACING := 1.7320508075688772
const NATURAL_RAMP_HIGH := Vector3(45.033320997, 0, 6)
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
	if natural_mesa_cell(center) and not cleared_cells.has(Hex.to_axial(point, CELL)): result = LEVEL
	else:
		var natural_anchor := Hex.snap(Vector3(43.3, 0, 6), CELL)
		var ramp_height := ramp_sample(point, natural_anchor, 0)
		if ramp_height >= 0: result = ramp_height
	for structure in structures:
		if not is_instance_valid(structure) or not structure.complete or structure.hp <= 0: continue
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

static func ramp_mesh() -> ArrayMesh:
	var a := SPACING / 2
	var points := PackedVector2Array([Vector2(a, CELL / 2), Vector2(0, CELL), Vector2(-a, CELL / 2), Vector2(-SPACING, CELL), Vector2(-SPACING - a, CELL / 2), Vector2(-SPACING - a, -CELL / 2), Vector2(-SPACING, -CELL), Vector2(-a, -CELL / 2), Vector2(0, -CELL), Vector2(a, -CELL / 2)])
	var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := PackedVector3Array()
	for point in points: vertices.append(Vector3(point.x, (point.x + SPACING * 1.5) / (SPACING * 2) * LEVEL, point.y))
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0, indices.size(), 3): triangle(tool, vertices[indices[i]], vertices[indices[i + 2]], vertices[indices[i + 1]])
	for i in range(vertices.size()):
		var top_a := vertices[i]; var top_b := vertices[(i + 1) % vertices.size()]
		var low_a := Vector3(top_a.x, 0, top_a.z); var low_b := Vector3(top_b.x, 0, top_b.z)
		triangle(tool, top_a, top_b, low_a); triangle(tool, low_a, top_b, low_b)
	tool.generate_normals(); return tool.commit()

func surface(point: Vector3) -> Vector3:
	return Vector3(point.x, height(point), point.z)

static func polygon_prism(points: PackedVector2Array, top: float, bottom: float = 0.0) -> ArrayMesh:
	var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()):
		var a := Vector3(points[i].x, top, points[i].y)
		var b := Vector3(points[(i + 1) % points.size()].x, top, points[(i + 1) % points.size()].y)
		triangle(tool, Vector3(0, top, 0), b, a)
		var low_a := Vector3(a.x, bottom, a.z); var low_b := Vector3(b.x, bottom, b.z)
		triangle(tool, a, b, low_a); triangle(tool, low_a, b, low_b)
	tool.generate_normals(); return tool.commit()

static func hex_mesh(top: float, bottom: float = 0.0, radius: float = CELL) -> ArrayMesh:
	var points := PackedVector2Array()
	for i in range(6): points.append(Vector2(cos(PI / 6 + i * TAU / 6), sin(PI / 6 + i * TAU / 6)) * radius)
	return polygon_prism(points, top, bottom)

static func triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces use clockwise winding.
	tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(b)
