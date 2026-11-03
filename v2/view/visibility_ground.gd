extends Node3D
const Actor = preload("res://core/actor.gd")
## Read-only tile visibility. Detection alone never clears ground fog.
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")
enum State { DARK, FOG, PERCEIVED, ILLUMINATED }
const COLORS := [Color("0b1119"), Color("1c2a38"), Color("304f65"), Color("71633d")]
var cells: Dictionary = {}
var _signature: Array = []
var _tile_keys: Array = []
var _vertices := PackedVector3Array()
var _color_blocks: Array = []
var surface: MeshInstance3D

func refresh(game, observers: Array) -> void:
	var known: Dictionary = {}
	var lit: Dictionary = {}
	var perceived: Dictionary = {}
	var sources: Array = []
	for owner in observers:
		known.merge(game.state.revealed.get(str(owner), {}))
		lit.merge(game.illumination_cells(int(owner)))
	for actor: Actor in game.state.actors:
		if int(actor.hp) <= 0 or not observers.has(int(actor.owner)): continue
		var caps: Dictionary = game.content.units[actor.definition].capabilities
		if caps.has("perception"): sources.append([Geo.center(game, actor), int(round(float(caps.perception.radius) * Hex.SCALE))])
	for key in lit: known[key] = true
	for key in game.state.veil.cells:
		var tissue: Dictionary = game.state.veil.cells[key]
		if observers.has(int(tissue.owner)) and int(tissue.hp) > 0:
			known[key] = true
			perceived[key] = true
	var signature: Array = [observers.duplicate(), known.hash(), lit.hash(), perceived.hash(), sources]
	if signature == _signature: return
	_signature = signature.duplicate(true)
	var next_cells: Dictionary = {}
	for key in known:
		if lit.has(key): next_cells[key] = State.ILLUMINATED; continue
		if perceived.has(key): next_cells[key] = State.PERCEIVED; continue
		var parts: PackedStringArray = str(key).split(",")
		var q := int(parts[0]) * Hex.SCALE; var r := int(parts[1]) * Hex.SCALE
		var state := State.FOG
		# Sources and light were prepared once; never call simulation visibility
		# or recompute illumination per tile. Stop at the first covering source.
		for source in sources:
			var center: Array = source[0]; var radius := int(source[1])
			var dq := q - int(center[0]); var dr := r - int(center[2])
			if dq * dq + dq * dr + dr * dr <= radius * radius:
				state = State.PERCEIVED
				break
		next_cells[key] = state
	if next_cells == cells: return
	cells = next_cells
	var keys: Array = cells.keys()
	if keys != _tile_keys:
		_tile_keys = keys
		_vertices.clear()
		var corners: Array = []
		for edge in 6: corners.append(_corner(edge))
		for key in keys:
			var parts: PackedStringArray = str(key).split(",")
			var center := _world([int(parts[0]), int(parts[1])])
			for edge in 6:
				_vertices.append(center)
				_vertices.append(center + corners[edge])
				_vertices.append(center + corners[(edge + 1) % 6])
	if _color_blocks.is_empty():
		for color in COLORS:
			var block := PackedColorArray(); block.resize(18); block.fill(color)
			_color_blocks.append(block)
	var colors := PackedColorArray()
	for key in keys: colors.append_array(_color_blocks[int(cells[key])])
	var mesh := ArrayMesh.new()
	if not keys.is_empty():
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices; arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if surface == null:
		surface = MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		surface.material_override = material
		add_child(surface)
	surface.mesh = mesh
	surface.visible = not known.is_empty()

func tile_state(game, observers: Array, cell: Array, lit = null) -> int:
	var key := Hex.key(cell)
	for owner in observers:
		if (game.illumination_cells(int(owner)) if lit == null else lit).has(key): return State.ILLUMINATED
	for owner in observers:
		if game.visibility_at(int(owner), Hex.point(cell)) == 2: return State.PERCEIVED
	for owner in observers:
		if game.state.revealed.get(str(owner), {}).has(key): return State.FOG
	return State.DARK

func clear() -> void:
	_signature.clear()
	cells.clear()
	_tile_keys.clear()
	_vertices.clear()
	if surface != null: surface.hide()

func _world(cell: Array) -> Vector3:
	return Vector3(sqrt(3.0) * (float(cell[0]) + float(cell[1]) * 0.5), -0.025, 1.5 * float(cell[1]))

func _corner(index: int) -> Vector3:
	var angle := float(index) * TAU / 6.0 + PI / 6.0
	return Vector3(cos(angle), 0, sin(angle)) * 0.96
