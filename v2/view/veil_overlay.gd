extends Node3D
const Actor = preload("res://core/actor.gd")
## Read-only presentation of membrane and selected-unit connections to its global network.
const Hex = preload("res://core/hex_cells.gd")
const COLORS := {"neutral": Color("76588c"), "defensive": Color("4e9caa"), "offensive": Color("be6859")}
var show_veil := true
var show_links := true
var show_illumination := false
var show_perception := false
var _signature: Array = []
var _surfaces: Dictionary = {}

func refresh(game, owner: int, selected: Array, view_owners: Array = []) -> void:
	var observers: Array = [owner] if view_owners.is_empty() else view_owners
	var actors: Array = []
	for actor: Actor in game.state.actors:
		if int(actor.hp) > 0: actors.append([int(actor.id), int(actor.owner), actor.definition, actor.position, int(actor.rotation)])
	var signature: Array = [int(game.state.veil.revision), observers.duplicate(), selected.duplicate(), show_veil, show_links, show_illumination, show_perception, actors]
	if signature == _signature: return
	_signature = signature.duplicate(true)
	var veil: Dictionary = game.state.veil
	var visible: Dictionary = {}
	var triangles: Array = []
	var colors: Array = []
	var lines: Array = []
	for key in veil.cells:
		var cell: Dictionary = veil.cells[key]
		var point := Hex.point([cell.q, cell.r])
		if not observers.has(int(cell.owner)):
			var seen := false
			for observer in observers:
				if game.visibility_at(int(observer), point) == 2:
					seen = true
					break
			if not seen: continue
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
			if actor == null or not observers.has(int(actor.owner)): continue
			var near := Hex.from_point(actor.position)
			var nearest := ""
			var distance := 0x7fffffffffffffff
			for offset in [[0, 0]] + Hex.NEIGHBORS:
				var key := Hex.key([int(near[0]) + int(offset[0]), int(near[1]) + int(offset[1])])
				if not visible.has(key) or int(veil.cells[key].owner) != int(actor.owner): continue
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
	if show_perception:
		for cell in veil.cells.values():
			if not observers.has(int(cell.owner)) or int(cell.hp) <= 0: continue
			var center := _world(Hex.point([cell.q, cell.r])) + Vector3(0, 0.025, 0)
			for edge in 6:
				perception.append(center + _corner(edge))
				perception.append(center + _corner(edge + 1))
	if show_illumination or show_perception:
		var lit: Dictionary = {}
		for observer in observers: lit.merge(game.illumination_cells(int(observer)))
		for cell in lit.values():
			var center := _world(Hex.point(cell)) + Vector3(0, 0.025, 0)
			for edge in 6:
				if show_illumination:
					illumination.append(center + _corner(edge))
					illumination.append(center + _corner(edge + 1))
				if show_perception:
					perception.append(center + _corner(edge))
					perception.append(center + _corner(edge + 1))
	for actor: Actor in game.state.actors:
		if not observers.has(int(actor.owner)) or int(actor.hp) <= 0: continue
		var caps: Dictionary = game.content.units[actor.definition].capabilities
		if not show_perception or not caps.has("perception"): continue
		var radius := float(caps.perception.radius) * sqrt(3.0)
		var center := _world(actor.position) + Vector3(0, 0.025, 0)
		for edge in 64:
			for index in [edge, edge + 1]:
				var angle := float(index) * TAU / 64.0
				perception.append(center + Vector3(cos(angle), 0, sin(angle)) * radius)
	_surface("Illumination", Mesh.PRIMITIVE_LINES, illumination, [], Color("e6cf75"))
	_surface("Perception", Mesh.PRIMITIVE_LINES, perception, [], Color("6ab5d9"))

func clear() -> void:
	_signature.clear()
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
		if name == "Membrane":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.35
		instance.material_override = material
		add_child(instance)
		_surfaces[name] = instance
	var instance: MeshInstance3D = _surfaces[name]
	instance.visible = not vertices.is_empty()
	if vertices.is_empty(): return
	var mesh := ArrayMesh.new()
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	mesh.add_surface_from_arrays(primitive, arrays)
	instance.mesh = mesh

func _corner(index: int) -> Vector3:
	var angle := float(index) * TAU / 6.0 + PI / 6.0
	return Vector3(cos(angle), 0, sin(angle)) * 0.94

func _world(position: Array) -> Vector3:
	var q := float(position[0]) / Hex.SCALE
	var r := float(position[2]) / Hex.SCALE
	return Vector3(sqrt(3.0) * (q + r * 0.5), float(position[1]) / Hex.SCALE, 1.5 * r)
