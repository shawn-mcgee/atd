extends RefCounted
const Hex = preload("res://core/hex_cells.gd")

static func world(cell: Array) -> Vector3:
	return Vector3(sqrt(3.0) * (float(cell[0]) + float(cell[1]) * 0.5), 0, 1.5 * float(cell[1]))

static func corner(index: int) -> Vector3:
	var angle := float(index) * TAU / 6.0 + PI / 6.0
	return Vector3(cos(angle), 0, sin(angle))

static func outline(cells: Array, center: Vector3 = Vector3.ZERO) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for cell in cells:
		for edge in 6:
			var offset: Array = Hex.NEIGHBORS[(edge + 1) % 6]
			if [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])] in cells: continue
			mesh.surface_add_vertex(world(cell) - center + corner(edge))
			mesh.surface_add_vertex(world(cell) - center + corner(edge + 1))
	mesh.surface_end()
	return mesh

static func body(cells: Array, height: float, center: Vector3 = Vector3.ZERO) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var base := world(cell) - center
		for edge in 6:
			var a := base + corner(edge); var b := base + corner(edge + 1)
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(base + Vector3.UP * height)
			mesh.surface_add_vertex(b + Vector3.UP * height)
			mesh.surface_add_vertex(a + Vector3.UP * height)
			var offset: Array = Hex.NEIGHBORS[(edge + 1) % 6]
			if [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])] in cells: continue
			mesh.surface_set_normal((corner(edge) + corner(edge + 1)).normalized())
			for vertex in [a, b + Vector3.UP * height, b, a, a + Vector3.UP * height, b + Vector3.UP * height]: mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	return mesh

static func rim(cells: Array, height: float, center: Vector3 = Vector3.ZERO) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var base := world(cell) - center + Vector3.UP * (height + 0.015)
		for edge in 6:
			var offset: Array = Hex.NEIGHBORS[(edge + 1) % 6]
			if [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])] in cells: continue
			var a := base + corner(edge); var b := base + corner(edge + 1)
			var inner_a := base + corner(edge) * 0.88; var inner_b := base + corner(edge + 1) * 0.88
			for vertex in [a, b, inner_b, a, inner_b, inner_a]: mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	return mesh
