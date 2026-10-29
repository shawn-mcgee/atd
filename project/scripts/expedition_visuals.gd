extends RefCounted
## Small placeholder mesh helpers; generated Asset Forge building assets are reused.
static func material(color: Color, unlit: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if unlit: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func box(parent: Node3D, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = material(color)
	parent.add_child(node)
	return node

static func sphere(parent: Node3D, radius: float, point: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	node.position = point
	node.material_override = material(color)
	parent.add_child(node)
	return node

static func ring(parent: Node3D, radius: float, color: Color, segments: int = 48) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material(color, true))
	for i in range(segments):
		for angle in [i * TAU / segments, (i + 1) * TAU / segments]:
			mesh.surface_add_vertex(Vector3(cos(angle) * radius, 0.1, sin(angle) * radius))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)
	return node

static func paint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D: node.material_override = mat
	for child in node.get_children(): paint(child, mat)
