extends Node3D
## Read-only presentation of membrane and selected-unit connections to its global network.
const Hex = preload("res://core/hex_cells.gd")
const COLORS := {"neutral": Color("76588c"), "defensive": Color("4e9caa"), "offensive": Color("be6859")}
var show_veil := true
var show_links := true
var show_illumination := false
var show_perception := false
var _signature := ""
var _surfaces: Dictionary = {}

func refresh(game, owner: int, selected: Array) -> void:
	var signature := "%d:%d:%s:%s:%s:%s:%s" % [game.state.tick, owner, selected, show_veil, show_links, show_illumination, show_perception]
	if signature == _signature: return
	_signature = signature
	var veil: Dictionary = game.state.veil
	var visible: Dictionary = {}
	var triangles: Array = []
	var colors: Array = []
	var lines: Array = []
	for key in veil.cells:
		var cell: Dictionary = veil.cells[key]
		var point := Hex.point([cell.q, cell.r])
		if int(cell.owner) != owner and game.visibility_at(owner, point) != 2: continue
		visible[key] = true
		if not show_veil: continue
		var mode: String = veil.networks[str(cell.network)].stance
		var color: Color = COLORS[mode]
		if cell.sources.is_empty(): color = Color("82755d")
		color *= 0.45 + 0.55 * float(cell.hp) / float(game.Veil.settings(game).tile_hp)
		var center := _world(point) + Vector3(0, 0.005, 0)
		for edge in 6:
			triangles.append(center)
			triangles.append(center + _corner(edge))
			triangles.append(center + _corner(edge + 1))
			for vertex in 3: colors.append(color)
	if show_links:
		for id in selected:
			var actor = game.entity(int(id))
			if actor == null or int(actor.owner) != owner: continue
			var near := Hex.from_point(actor.position)
			var nearest := ""
			var distance := 0x7fffffffffffffff
			for offset in [[0, 0]] + Hex.NEIGHBORS:
				var key := Hex.key([int(near[0]) + int(offset[0]), int(near[1]) + int(offset[1])])
				if not visible.has(key) or int(veil.cells[key].owner) != owner: continue
				var point := Hex.point([veil.cells[key].q, veil.cells[key].r])
				var next: int = game.distance_squared(point, actor.position)
				if next < distance: distance = next; nearest = key
			if not nearest.is_empty():
				lines.append(_world(actor.position) + Vector3(0, 0.1, 0))
				lines.append(_world(Hex.point([veil.cells[nearest].q, veil.cells[nearest].r])) + Vector3(0, 0.04, 0))
	_surface("Membrane", Mesh.PRIMITIVE_TRIANGLES, triangles, colors, Color.WHITE)
	_surface("Links", Mesh.PRIMITIVE_LINES, lines, [], Color("cfaddf"))
	var illumination: Array = []
	var perception: Array = []
	for actor in game.state.actors:
		if int(actor.owner) != owner: continue
		var caps: Dictionary = game.content.units[actor.definition].capabilities
		for spec in [["illumination", show_illumination, illumination], ["perception", show_perception, perception]]:
			if not spec[1] or not caps.has(spec[0]): continue
			var radius := float(caps[spec[0]].radius) * sqrt(3.0)
			var center := _world(actor.position) + Vector3(0, 0.025, 0)
			for edge in 64:
				for index in [edge, edge + 1]:
					var angle := float(index) * TAU / 64.0
					spec[2].append(center + Vector3(cos(angle), 0, sin(angle)) * radius)
	_surface("Illumination", Mesh.PRIMITIVE_LINES, illumination, [], Color("e6cf75"))
	_surface("Perception", Mesh.PRIMITIVE_LINES, perception, [], Color("6ab5d9"))

func clear() -> void:
	_signature = ""
	for surface in _surfaces.values(): surface.visible = false

func _surface(name: String, primitive: int, vertices: Array, colors: Array, color: Color) -> void:
	if not _surfaces.has(name):
		var instance := MeshInstance3D.new()
		instance.name = name
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = color
		instance.material_override = material
		add_child(instance)
		_surfaces[name] = instance
	var instance: MeshInstance3D = _surfaces[name]
	instance.visible = not vertices.is_empty()
	if vertices.is_empty(): return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(primitive)
	for index in vertices.size():
		if not colors.is_empty(): mesh.surface_set_color(colors[index])
		mesh.surface_add_vertex(vertices[index])
	mesh.surface_end()
	instance.mesh = mesh

func _corner(index: int) -> Vector3:
	var angle := float(index) * TAU / 6.0 + PI / 6.0
	return Vector3(cos(angle), 0, sin(angle)) * 0.94

func _world(position: Array) -> Vector3:
	var q := float(position[0]) / Hex.SCALE
	var r := float(position[2]) / Hex.SCALE
	return Vector3(sqrt(3.0) * (q + r * 0.5), float(position[1]) / Hex.SCALE, 1.5 * r)
