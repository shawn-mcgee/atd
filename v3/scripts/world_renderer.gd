class_name WorldRenderer
extends Node3D

var state: WorldState
var viewer_owner := 0
var memory_overlay := StandardMaterial3D.new()
var terrain := MultiMeshInstance3D.new()
var rocks := MultiMeshInstance3D.new()
var deposits := MultiMeshInstance3D.new()
var scree := MultiMeshInstance3D.new()
var gas_vents := MultiMeshInstance3D.new()
var gas_vapor := MultiMeshInstance3D.new()
var vapor_material := ShaderMaterial.new()
var footing_material := ShaderMaterial.new()
var light_wash_material := ShaderMaterial.new()
var bodies: Dictionary = {}
var body_views: Dictionary = {}
var terrain_stamp: Array = []

class BodyView:
	extends RefCounted
	var root: Node3D
	var model: Node3D
	var ring: Node3D
	var parts: Dictionary
	var bounds: AABB
	var last_position: Vector2
	var structure_signature: Array = []

var view_camera: Camera3D
var friendly_silhouette := ShaderMaterial.new()
var hostile_silhouette := ShaderMaterial.new()
var selection: Array = []
var terrain_cells: Array = []
var tile_cache: Dictionary = {}
var tile_indices: Dictionary = {}
var previous_edge: Dictionary = {}
var visibility_splats: Dictionary = {}
var preview := MeshInstance3D.new()
var shot_mesh := MeshInstance3D.new()
var preview_tiles: Array[MeshInstance3D] = []
var wall_previews: Array[MeshInstance3D] = []
var display_time := 0.0
var visual_shots: Array = []
var feedback_cursor := 0
var impact_rings: Array = []
var destroyed_ids: Dictionary = {}
var hit_overlay: StandardMaterial3D
var shield_overlay: StandardMaterial3D
var preview_valid: StandardMaterial3D
var preview_invalid: StandardMaterial3D
var ghost_model: Node3D
var ghost_kind := ""
var ghost_valid: StandardMaterial3D
var ghost_invalid: StandardMaterial3D
var art := SceneArt.new()
var ground_material := ShaderMaterial.new()
var visibility_texture: ImageTexture
var fog_sheet := MeshInstance3D.new()
var fog_material := ShaderMaterial.new()
var death_effects: Array = []
var particles: Array = []
var occlusion_scene: Array = []
var occluders: Array = []
var occlusion_revision := 0
var particle_mesh := MeshInstance3D.new()
const COLORS := [Color("4aa9ed"), Color("8ad66b"), Color("ef636c"), Color("efb44d"), Color("b68ef0")]

func _ready() -> void:
	for overlay in [friendly_silhouette, hostile_silhouette]: overlay.shader = preload("res://shaders/occluded-unit.gdshader")
	friendly_silhouette.set_shader_parameter("silhouette_color", Color(0.52, 0.76, 0.85, 0.65))
	hostile_silhouette.set_shader_parameter("silhouette_color", Color(0.9, 0.49, 0.34, 0.65))
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.BLACK
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("718998")
	settings.ambient_light_energy = float(Settings.data.presentation.lighting.ambientEnergy)
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_color = Color("91a8bd")
	sun.light_energy = float(Settings.data.presentation.lighting.keyLightEnergy)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	for instance in [terrain, rocks, deposits, scree, gas_vents, gas_vapor]: add_child(instance)
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deposits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tile := CylinderMesh.new()
	tile.top_radius = HexGrid.RADIUS
	tile.bottom_radius = tile.top_radius
	tile.height = 0.08
	tile.radial_segments = 6
	terrain.multimesh = _multi(tile)
	ground_material.shader = preload("res://shaders/regolith.gdshader")
	ground_material.set_shader_parameter("ground_brightness", float(Settings.data.presentation.lighting.groundBrightness))
	ground_material.set_shader_parameter("ground_texture", preload("res://assets/textures/regolith-albedo.png"))
	ground_material.set_shader_parameter("normal_strength", float(Settings.data.presentation.terrain.groundNormalStrength))
	fog_material.shader = preload("res://shaders/black-fog.gdshader")
	var fog_settings: Dictionary = Settings.data.presentation.fog
	for pair in [["memory_opacity", "memoryOpacity"], ["edge_opacity", "edgeOpacity"], ["edge_reach", "edgeReachTiles"], ["drift_speed", "driftSpeed"], ["noise_scale", "noiseScale"]]:
		fog_material.set_shader_parameter(pair[0], float(fog_settings[pair[1]]))
	fog_sheet.mesh = PlaneMesh.new()
	fog_sheet.material_override = fog_material
	fog_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_sheet.position.y = float(fog_settings.heightTiles)
	fog_sheet.visible = bool(fog_settings.enabled)
	add_child(fog_sheet)
	terrain.material_override = ground_material
	rocks.multimesh = _multi(_rock_mesh())
	var rock_material := ShaderMaterial.new()
	rock_material.shader = preload("res://shaders/basalt.gdshader")
	rock_material.set_shader_parameter("strata_strength", float(Settings.data.presentation.terrain.rockStrataStrength))
	rocks.material_override = rock_material
	var chip := PrismMesh.new(); chip.size = Vector3.ONE
	scree.multimesh = _multi(chip)
	scree.material_override = rock_material
	scree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deposits.multimesh = _multi(_rock_mesh())
	gas_vents.multimesh = _multi(_vent_mesh())
	gas_vents.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gas_vapor.multimesh = _multi(PlaneMesh.new())
	vapor_material.shader = preload("res://shaders/gas-seep.gdshader")
	vapor_material.set_shader_parameter("opacity", float(Settings.data.presentation.terrain.gasVaporOpacity))
	gas_vapor.material_override = vapor_material
	gas_vapor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footing_material.shader = preload("res://shaders/contact-shadow.gdshader")
	footing_material.set_shader_parameter("opacity", float(Settings.data.presentation.terrain.contactShadowOpacity))
	light_wash_material.shader = preload("res://shaders/contact-shadow.gdshader")
	light_wash_material.set_shader_parameter("opacity", float(Settings.data.presentation.lighting.serviceLightWashOpacity))
	light_wash_material.set_shader_parameter("tint", Color("bc8b52"))
	preview.mesh = tile
	preview.material_override = material(Color(0.3, 0.9, 0.7, 0.6), true)
	add_child(preview)
	preview.visible = false
	preview_valid = material(Color(0.25, 0.9, 0.7, 0.5), true)
	ghost_valid = material(Color(0.52, 0.8, 0.72, 0.24), true)
	ghost_invalid = material(Color(0.88, 0.4, 0.3, 0.24), true)
	preview_invalid = material(Color(0.95, 0.25, 0.3, 0.55), true)
	for i in range(7):
		var ghost := MeshInstance3D.new()
		ghost.mesh = tile
		add_child(ghost)
		ghost.visible = false
		preview_tiles.append(ghost)
	add_child(shot_mesh)
	shot_mesh.material_override = material(Color("a6f5ee"), true)
	shot_mesh.material_override.vertex_color_use_as_albedo = true
	shot_mesh.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shot_mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	hit_overlay = material(Color(1.0, 0.86, 0.67, 0.36), true)
	shield_overlay = material(Color(0.54, 0.95, 0.9, 0.44), true)
	add_child(particle_mesh)
	particle_mesh.material_override = material(Color.WHITE, true)
	particle_mesh.material_override.vertex_color_use_as_albedo = true
	particle_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _rock_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var levels: Array = []
	for ring in range(3):
		var layer: Array[Vector3] = []
		for i in range(7):
			var a := i * TAU / 7
			var radius_value: float = [0.6, 0.55, 0.4][ring] * (0.78 + fposmod(sin(i * 17.3 + ring * 7.1) * 31, 0.34))
			layer.append(Vector3(cos(a) * radius_value + ring * 0.06, [0.0, 0.43, 0.9][ring] + (0.14 * sin(i * 2.0) if ring > 0 else 0.0), sin(a) * radius_value - ring * 0.035))
		levels.append(layer)
	var triangles: Array = []
	for ring in range(2):
		for i in range(7):
			var next := (i + 1) % 7
			triangles.append([levels[ring][i], levels[ring + 1][i], levels[ring + 1][next]])
			triangles.append([levels[ring][i], levels[ring + 1][next], levels[ring][next]])
	for i in range(7): triangles.append([Vector3(0.12, 0.95, -0.07), levels[2][(i + 1) % 7], levels[2][i]])
	for triangle in triangles:
		var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
		for index in [0, 2, 1]: vertices.append(triangle[index]); normals.append(normal)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _vent_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	for i in range(9):
		var a := i * TAU / 9
		var b := (i + 1) * TAU / 9
		var r := 0.92 + sin(i * 17.1) * 0.13
		var next_r := 0.92 + sin((i + 1) * 17.1) * 0.13
		var outer := Vector3(cos(a) * 0.5 * r, 0, sin(a) * 0.5 * r)
		var next_outer := Vector3(cos(b) * 0.5 * next_r, 0, sin(b) * 0.5 * next_r)
		var crest := Vector3(cos(a) * 0.31 * r, 0.13 + sin(i * 3.1) * 0.03, sin(a) * 0.31 * r)
		var next_crest := Vector3(cos(b) * 0.31 * next_r, 0.13 + sin((i + 1) * 3.1) * 0.03, sin(b) * 0.31 * next_r)
		var inner := Vector3(cos(a) * 0.16, -0.02, sin(a) * 0.16)
		var next_inner := Vector3(cos(b) * 0.16, -0.02, sin(b) * 0.16)
		for tri in [[outer, crest, next_crest], [outer, next_crest, next_outer], [crest, inner, next_inner], [crest, next_inner, next_crest]]:
			var normal: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for index in [0, 2, 1]: vertices.append(tri[index]); normals.append(normal)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	var result := ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if color.a < 1: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _multi(mesh: Mesh) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	var m := material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mesh.surface_set_material(0, m)
	return multi

func initialize(world: WorldState, local_owner: int) -> void:
	state = world
	viewer_owner = local_owner
	memory_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	memory_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	memory_overlay.albedo_color = Color("334752")
	memory_overlay.albedo_color.a = float(state.cfg.presentation.get("structureMemoryTintStrength", 0.75))
	for node in bodies.values(): node.queue_free()
	bodies.clear(); body_views.clear(); terrain_stamp.clear()
	visual_shots.clear(); particles.clear(); impact_rings.clear(); destroyed_ids.clear(); feedback_cursor = 0
	for effect in death_effects: effect.node.queue_free()
	death_effects.clear()
	terrain_cells = state.tiles.keys()
	tile_cache.clear(); tile_indices.clear(); previous_edge.clear(); visibility_splats.clear()
	var resolution := (state.radius * 2 + 4) * 3
	for i in range(terrain_cells.size()):
		var cell: Vector2i = terrain_cells[i]
		tile_indices[cell] = i
		var point := Vector2i((HexGrid.world(cell) / float(state.radius * 2 + 4) + Vector2(0.5, 0.5)) * resolution)
		var pixels := PackedInt32Array()
		for x in range(-2, 3):
			for y in range(-2, 3):
				var pixel := point + Vector2i(x, y)
				if x * x + y * y <= 5 and pixel.x >= 0 and pixel.y >= 0 and pixel.x < resolution and pixel.y < resolution: pixels.append(pixel.y * resolution + pixel.x)
		visibility_splats[cell] = pixels
	terrain.multimesh.instance_count = terrain_cells.size()
	deposits.multimesh.instance_count = terrain_cells.size() * 3
	rocks.multimesh.instance_count = terrain_cells.size() * 3
	scree.multimesh.instance_count = terrain_cells.size() * 3
	gas_vents.multimesh.instance_count = terrain_cells.size()
	gas_vapor.multimesh.instance_count = terrain_cells.size()
	ground_material.set_shader_parameter("map_span", float(state.radius * 2 + 4))
	fog_material.set_shader_parameter("map_span", float(state.radius * 2 + 4))
	vapor_material.set_shader_parameter("map_span", float(state.radius * 2 + 4))
	fog_sheet.mesh.size = Vector2.ONE * float(state.radius * 2 + 4)
	refresh_tiles()
	refresh_entities()

func refresh_tiles() -> void:
	if state == null: return
	var stamp: Array = [state.known.get(viewer_owner, {}).hash(), state.visible.get(viewer_owner, {}).hash(), state.illuminated.hash(), state.gloom.keys().hash(), state.tiles.hash()]
	if stamp == terrain_stamp: return
	terrain_stamp = stamp
	var explored: Dictionary = state.known.get(viewer_owner, {})
	var active: Dictionary = state.visible.get(viewer_owner, {})
	var light: Dictionary = {}
	for area in state.illuminated.values(): light.merge(area, true)
	var changed := false
	var edge: Dictionary = explored.duplicate()
	for cell in explored:
		for direction in HexGrid.DIRECTIONS: edge[cell + direction] = true
	var dirty: Dictionary = edge.duplicate()
	dirty.merge(previous_edge, true)
	var cells: Array = terrain_cells if tile_cache.is_empty() else dirty.keys()
	previous_edge = edge
	for cell in cells:
		if not tile_indices.has(cell): continue
		var i: int = tile_indices[cell]
		var p := HexGrid.world(cell)
		var tile: Dictionary = state.tiles[cell]
		var signature := int(explored.has(cell)) + 2 * int(active.has(cell)) + 4 * int(light.has(cell)) + 8 * int(state.gloom.has(cell)) + 16 * int(bool(tile.cliff)) + 32 * int(int(tile.amount) > 0) + 128 * int(edge.has(cell)) + 256 * int(tile.get("rubble", false))
		if tile_cache.get(cell, -1) == signature: continue
		tile_cache[cell] = signature
		changed = true
		var color := Color("080f18")
		if explored.has(cell): color = Color("3b4b56")
		if active.has(cell): color = Color("314651")
		if light.has(cell): color = Color("858578")
		color = color.lightened(fposmod(sin(float(cell.x * 71 + cell.y * 137)) * 43758.5, 1.0) * 0.035)
		if explored.has(cell) and state.gloom.has(cell): color = Color("512e5e") if active.has(cell) else Color("2a2036")
		terrain.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE if edge.has(cell) else Vector3.ZERO), Vector3(p.x, -0.05, p.y)))
		terrain.multimesh.set_instance_color(i, color.srgb_to_linear())
		var is_rock: bool = bool(tile.cliff) or tile.get("rubble", false) or HexGrid.distance(cell) == state.radius
		var scale_by := 1.0 if is_rock and explored.has(cell) else 0.0
		var height := 0.8 + fposmod(sin(float(cell.x * 31 + cell.y * 97)) * 13.5, 1.0) * 0.65
		if tile.get("rubble", false): height = 0.1
		var basis: Basis
		for fragment in range(3):
			var seed := float(cell.x * 91 + cell.y * 37 + fragment * 127)
			var angle := fposmod(seed * 0.71, TAU)
			var small := 1.0 if fragment == 0 else 0.56
			var offset := Vector2.ZERO if fragment == 0 else Vector2(cos(angle), sin(angle)) * 0.3
			basis = Basis(Vector3.UP, angle).scaled(Vector3(1.03 * small, height * (1.0 if fragment == 0 else 0.66), 0.89 * small) * scale_by)
			rocks.multimesh.set_instance_transform(i * 3 + fragment, Transform3D(basis, Vector3(p.x + offset.x, -0.02, p.y + offset.y)))
			rocks.multimesh.set_instance_color(i * 3 + fragment, color.lightened(0.13 + fragment * 0.015).srgb_to_linear())
			var scatter := explored.has(cell) and not is_rock and fposmod(sin(seed * 1.73) * 43758.5, 1.0) < float(state.cfg.presentation.terrain.scatterDensity)
			var pebble := 0.04 + fposmod(seed * 0.137, 0.06)
			basis = Basis(Vector3.UP, angle).scaled(Vector3(pebble * 1.8, pebble * 0.7, pebble) * (1.0 if scatter else 0.0))
			var jitter := Vector2(sin(seed * 0.83), cos(seed * 1.27)) * 0.42
			scree.multimesh.set_instance_transform(i * 3 + fragment, Transform3D(basis, Vector3(p.x + jitter.x, 0.01, p.y + jitter.y)))
			scree.multimesh.set_instance_color(i * 3 + fragment, color.srgb_to_linear())
		var has_resource: bool = tile.resource != "" and int(tile.amount) > 0 and explored.has(cell) and not tile.cliff
		var resource_color := Color("b69669") if tile.resource == "ore" else Color("619d9a") if tile.resource == "gas" else Color("d2b3a3")
		for j in range(3):
			var angle := j * TAU / 3 + float(cell.x)
			var size_by := Vector3(0.38, 0.23 + 0.11 * j, 0.38) if tile.resource != "gas" else Vector3(0.45, 0.08, 0.45)
			basis = Basis(Vector3.UP, angle).scaled(size_by * (1.0 if has_resource and tile.resource != "gas" else 0.0))
			deposits.multimesh.set_instance_transform(i * 3 + j, Transform3D(basis, Vector3(p.x + cos(angle) * 0.21, 0, p.y + sin(angle) * 0.21)))
			deposits.multimesh.set_instance_color(i * 3 + j, (resource_color if active.has(cell) else resource_color.darkened(0.35)).srgb_to_linear())
		var has_gas: bool = has_resource and tile.resource == "gas"
		gas_vents.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(cell.x + cell.y)).scaled(Vector3(1.2, 1, 0.9) * (1.0 if has_gas else 0.0)), Vector3(p.x, 0.03, p.y)))
		gas_vents.multimesh.set_instance_color(i, (Color("54736e") if active.has(cell) else Color("3c5552")).srgb_to_linear())
		gas_vapor.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(0.65, 1, 0.65) * (1.0 if has_gas and active.has(cell) else 0.0)), Vector3(p.x, 0.22, p.y)))
	if changed: _update_visibility_texture(explored, active, light)

func _update_visibility_texture(explored: Dictionary, active: Dictionary, light: Dictionary) -> Image:
	var side := state.radius * 2 + 4
	var resolution := side * 3
	var pixels := PackedInt32Array()
	pixels.resize(resolution * resolution)
	for cell in explored:
		var mask: int = 255 | (65280 if active.has(cell) else 0) | (16711680 if light.has(cell) else 0) | (-16777216 if state.gloom.has(cell) else 0)
		for index in visibility_splats.get(cell, PackedInt32Array()): pixels[index] = pixels[index] | mask
	var image := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGBA8, pixels.to_byte_array())
	if visibility_texture == null or visibility_texture.get_width() != resolution: visibility_texture = ImageTexture.create_from_image(image)
	else: visibility_texture.update(image)
	ground_material.set_shader_parameter("visibility_map", visibility_texture)
	fog_material.set_shader_parameter("visibility_map", visibility_texture)
	vapor_material.set_shader_parameter("visibility_map", visibility_texture)
	return image

func _piece(parent: Node3D, mesh: Mesh, position: Vector3, color: Color, scale_by: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = position
	m.scale = scale_by
	m.material_override = material(color)
	parent.add_child(m)
	return m

func _body(e: Dictionary) -> Node3D:
	var color: Color = COLORS[int(e.owner) % COLORS.size()] if e.owner >= 0 else Color("a69c8c")
	var root := art.create(e, color, state.cfg.presentation)
	var footing := MeshInstance3D.new()
	footing.name = "ContactShadow"
	footing.mesh = PlaneMesh.new()
	var width: float = (float(state.cfg.structures[e.kind].footprintRadiusTiles) * 2.0 + 1.6) if e.has("cell") else 0.55
	if e.has("pos") and int(state.cfg.units[e.kind].get("driverSeats", 0)) > 0: width = 1.65
	if e.kind == "father": width = 0.95
	footing.mesh.size = Vector2(width, width)
	footing.position.y = 0.008
	footing.material_override = footing_material
	footing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(footing)
	if e.has("cell") and int(e.owner) >= 0 and not e.kind in ["wall", "gate"]:
		var wash := MeshInstance3D.new(); wash.name = "LightWash"
		wash.mesh = PlaneMesh.new(); wash.mesh.size = Vector2(width + 1.2, 2.0)
		wash.position = Vector3(0, 0.018, width * 0.35)
		wash.material_override = light_wash_material
		wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wash)
	var ring := MeshInstance3D.new()
	ring.name = "Selection"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35 if e.has("pos") else float(state.cfg.structures[e.kind].footprintRadiusTiles) + 0.56
	torus.outer_radius = torus.inner_radius + 0.018
	torus.rings = 32; torus.ring_segments = 4
	ring.mesh = torus; ring.position.y = 0.045
	ring.material_override = material(Color("b5c9ad"), true)
	root.add_child(ring)
	root.set_meta("last_position", state.entity_position(e))
	root.set_meta("recoil", 0.0)
	root.set_meta("kick", 0.1)
	root.set_meta("recoil_fresh", false)
	root.set_meta("flash_fresh", false)
	root.set_meta("flash_gate", -1.0)
	root.set_meta("hit_flash", 0.0)
	root.set_meta("shielded", false)
	root.set_meta("overlay_id", 0)
	root.set_meta("surfaces", _surfaces(root.get_node("Model")))
	var parts: Dictionary = {}
	_cache_parts(root.get_node("Model"), root.get_node("Model"), parts)
	root.set_meta("parts", parts)
	root.set_meta("structure", e.has("cell"))
	if e.kind in ["anchor", "floodlight"]:
		var lamp := OmniLight3D.new()
		lamp.name = "Worklight"
		lamp.position = Vector3(0, 1.1, 0)
		lamp.light_color = Color("ffd19a"); lamp.light_energy = float(state.cfg.presentation.lighting.workLightEnergy)
		lamp.omni_range = 4.5 if e.kind == "anchor" else 6.5
		lamp.shadow_enabled = false
		root.add_child(lamp)
	add_child(root)
	var bounds := AABB()
	var first := true
	for surface in root.get_meta("surfaces"):
		var local: Transform3D = root.global_transform.affine_inverse() * surface.global_transform
		var part: AABB = local * surface.get_aabb()
		bounds = part if first else bounds.merge(part); first = false
	root.set_meta("model_bounds", bounds.grow(0.2))
	var view := BodyView.new()
	view.root = root; view.model = root.get_node("Model"); view.ring = ring; view.parts = parts; view.bounds = bounds.grow(0.2); view.last_position = state.entity_position(e)
	body_views[e.id] = view
	var claws: Array = []
	for side in [-1, 1]:
		for i in range(3):
			var key := "Claw%d_%d" % [side, i]
			if parts.has(key): claws.append({"node": parts[key], "side": side, "index": i})
	root.set_meta("claws", claws)
	return root

func refresh_entities() -> void:
	if state == null: return
	var delta := minf(get_process_delta_time(), 0.1)
	if not state.paused: display_time += delta * state.speed
	fog_material.set_shader_parameter("fog_time", display_time)
	vapor_material.set_shader_parameter("drift_time", display_time)
	destroyed_ids.clear()
	_consume_feedback()
	var live: Dictionary = {}
	var planes: Array = view_camera.get_frustum() if is_instance_valid(view_camera) else []
	var interpolation := 1.0 - exp(-delta / float(Settings.data.presentation.motionInterpolationSeconds))
	var rotation_blend := 1.0 - exp(-delta * 18)
	for e in state.units.values() + state.observed_structures(viewer_owner):
		live[e.id] = true
		if e.has("pos") and (int(e.get("vehicle", 0)) != 0 or not WorldState.TargetRules.identifiable(state, e, viewer_owner)):
			if bodies.has(e.id): bodies[e.id].hide()
			continue
		if bodies.has(e.id) and bodies[e.id].get_meta("kind") != e.kind:
			bodies[e.id].queue_free(); bodies.erase(e.id)
		if not bodies.has(e.id): bodies[e.id] = _body(e)
		var body: Node3D = bodies[e.id]
		var view: BodyView = body_views[e.id]
		var pos := state.entity_position(e)
		var target := Vector3(pos.x, 0, pos.y)
		if not body.has_meta("placed"):
			body.position = target; body.rotation.y = float(e.get("heading", 0)); body.set_meta("placed", true)
		body.position = body.position.lerp(target, interpolation)
		body.visible = true
		view.ring.visible = e.id in selection
		if e.has("heading"): body.rotation.y = lerp_angle(body.rotation.y, float(e.heading), rotation_blend)
		if e.has("built") and not e.built: body.scale = Vector3(1, 0.12 + 0.88 * float(e.hp) / float(state.cfg.structures[e.kind].health), 1)
		else: body.scale = Vector3.ONE
		if e.get("buried", false): view.model.position.y = -0.2
		elif e.get("transition", "") != "": view.model.position.y = -0.1 + sin(display_time * 14) * 0.025
		else: view.model.position.y = 0
		var remembered: bool = e.get("remembered", false)
		var on_screen := _body_in_frustum(view, planes)
		body.set_meta("on_screen", on_screen)
		body.set_meta("remembered", remembered)
		if body.has_node("Worklight"): body.get_node("Worklight").visible = not remembered and bool(e.get("powered", false)) and bool(e.get("built", true))
		if remembered:
			if body.has_node("LightWash"): body.get_node("LightWash").hide()
			for rack in ["KitRack", "PersonnelRack"]:
				if view.model.has_node(rack): view.model.get_node(rack).hide()
			body.set_meta("hit_flash", 0.0); body.set_meta("flash_fresh", false)
			_set_overlay(body, memory_overlay)
		else:
			if on_screen: _animate(body, e, pos, delta)
			else: _advance_flashes(body, delta)
	for id in bodies.keys():
		if not live.has(id):
			var node: Node3D = bodies[id]
			if node.visible and destroyed_ids.has(id):
				_burst(Vector2(node.position.x, node.position.z), Color("b0a38b"), 16)
				for surface in node.get_meta("surfaces"): surface.material_overlay = null
				node.get_node("Selection").hide()
				death_effects.append({"node": node, "time": float(state.cfg.presentation.feedback.deathSeconds)})
			else: node.queue_free()
			bodies.erase(id); body_views.erase(id)
	for effect in death_effects:
		effect.time -= delta
		var progress := 1.0 - maxf(0, float(effect.time)) / float(state.cfg.presentation.feedback.deathSeconds)
		effect.node.get_node("Model").rotation.z = lerpf(effect.node.get_node("Model").rotation.z, 0.9, delta * 10)
		effect.node.position.y = -progress * progress * 0.9
		effect.node.scale.y = 1.0 - progress * 0.3
		if effect.time <= 0: effect.node.queue_free()
	death_effects = death_effects.filter(func(effect): return effect.time > 0)
	for shot in visual_shots:
		if shot.get("fresh", false): shot.fresh = false
		else: shot.time -= delta
	visual_shots = visual_shots.filter(func(shot): return shot.time > 0)
	for ring in impact_rings:
		if ring.get("fresh", false): ring.fresh = false
		else: ring.time -= delta
	impact_rings = impact_rings.filter(func(ring): return ring.time > 0)
	_draw_traces()
	_draw_particles(delta)
	_highlight_occluded_units()

func _highlight_occluded_units() -> void:
	if not is_instance_valid(view_camera): return
	var scene: Array = [view_camera.global_transform, view_camera.get_camera_projection(), view_camera.get_viewport().get_visible_rect()]
	var structures: Array[Node3D] = []
	for body in bodies.values():
		if body.visible and body.get_meta("on_screen", true) and body.get_meta("structure", false):
			structures.append(body)
			scene.append([body.get_instance_id(), body.global_transform])
			var parts: Dictionary = body.get_meta("parts", {})
			for name in ["GatePanel", "RadarDish", "Gantry", "Press", "Rotor", "Turret", "Drill", "Assembly"]:
				if parts.has(name): scene.append(parts[name].global_transform)
	if scene != occlusion_scene:
		occlusion_scene = scene; occlusion_revision += 1; occluders.clear()
		for body in structures:
			var bounds: AABB = body.get_meta("model_bounds")
			var rect := Rect2()
			for i in range(8):
				var screen := view_camera.unproject_position(body.global_transform * bounds.get_endpoint(i))
				rect = Rect2(screen, Vector2.ZERO) if i == 0 else rect.expand(screen)
			occluders.append({"body": body, "inverse": body.global_transform.affine_inverse(), "bounds": bounds, "screen": rect})
	for id in bodies:
		var body: Node3D = bodies[id]
		if not body.visible or not body.get_meta("on_screen", true):
			body.set_meta("occluded", false)
			if body.has_meta("occlusion_query"): body.remove_meta("occlusion_query")
			continue
		if body.get_meta("structure", false):
			if not body.get_meta("remembered", false): _set_overlay(body, (shield_overlay if body.get_meta("shielded") else hit_overlay) if float(body.get_meta("hit_flash", 0)) > 0 else null)
			continue
		var point := body.global_position + Vector3(0, 0.5, 0)
		var query: Array = [point, occlusion_revision]
		if body.get_meta("occlusion_query", []) != query:
			body.set_meta("occlusion_query", query); body.set_meta("occluded", false)
			if not view_camera.is_position_behind(point):
				var screen := view_camera.unproject_position(point)
				if view_camera.get_viewport().get_visible_rect().has_point(screen):
					var origin := view_camera.project_ray_origin(screen)
					for entry in occluders:
						if not entry.screen.has_point(screen): continue
						var bounds: AABB = entry.bounds
						if bounds.intersects_segment(entry.inverse * origin, entry.inverse * point) == null: continue
						for surface in entry.body.get_meta("surfaces"):
							if not surface.is_visible_in_tree(): continue
							var inverse: Transform3D = surface.global_transform.affine_inverse()
							if surface.get_aabb().intersects_segment(inverse * origin, inverse * point) != null:
								body.set_meta("occluded", true); break
						if body.get_meta("occluded"): break
		var overlay: Material = null
		if float(body.get_meta("hit_flash", 0)) > 0: overlay = shield_overlay if body.get_meta("shielded") else hit_overlay
		elif body.get_meta("occluded"):
			var entity: Dictionary = state.units.get(int(id), {})
			overlay = friendly_silhouette if int(entity.get("owner", -1)) == viewer_owner else hostile_silhouette
		_set_overlay(body, overlay)

func _set_overlay(body: Node3D, overlay: Material) -> void:
	var overlay_id := overlay.get_instance_id() if overlay != null else 0
	if body.get_meta("overlay_id", 0) == overlay_id: return
	body.set_meta("overlay_id", overlay_id)
	for surface in body.get_meta("surfaces"): surface.material_overlay = overlay

func _animate(body: Node3D, e: Dictionary, pos: Vector2, delta: float) -> void:
	if e.has("cell") and e.kind in ["wall", "relay", "depot"]:
		var view: BodyView = body_views[e.id]
		_advance_flashes(body, delta)
		var signature: Array = [e.built, e.enabled, e.powered, e.brownout, e.blackout]
		if signature != view.structure_signature:
			view.structure_signature = signature
			_animate_facility(view.model, e)
		return
	if int(e.owner) >= 0 and e.has("pos") and e.kind in ["operator", "engineer", "marine", "flamer", "lancer"]:
		_animate_person(body_views[e.id], e, pos, delta); return
	var parts: Dictionary = body.get_meta("parts")
	var model: Node3D = body.get_node("Model")
	var previous: Vector2 = body.get_meta("last_position")
	var visual_position := Vector2(body.position.x, body.position.z)
	var walking := not state.paused and previous.distance_to(visual_position) > 0.0005
	body.set_meta("last_position", visual_position)
	var phase := display_time * 12 + int(e.id) * 0.7
	if parts.has("LegL"):
		parts["LegL"].rotation.x = sin(phase) * 0.55 if walking else lerpf(parts["LegL"].rotation.x, 0, delta * 12)
		parts["LegR"].rotation.x = -sin(phase) * 0.55 if walking else lerpf(parts["LegR"].rotation.x, 0, delta * 12)
		model.position.y = absf(sin(phase)) * 0.025 if walking else sin(display_time * 2 + int(e.id)) * 0.006
		model.rotation.x = -0.07 if walking else 0.0
	if e.owner < 0 and e.has("pos"):
		var anatomy: Vector3 = model.get_meta("base_scale", Vector3.ONE)
		if e.kind != "mother": model.scale = Vector3(anatomy.x, anatomy.y * (1.0 + sin(display_time * 3 + int(e.id)) * 0.025), anatomy.z)
		for claw in body.get_meta("claws"):
			claw.node.rotation.y = int(claw.side) * (int(claw.index) - 1) * -0.45 + (sin(phase * 1.3 + int(claw.index) * 2) * 0.35 if walking else 0.0)
		if e.kind == "shade":
			model.position.y = 0.1 + sin(display_time * 2 + int(e.id)) * 0.06
			model.rotation.z = sin(display_time * 1.5 + int(e.id)) * 0.05
		if e.kind == "father":
			var motion: Dictionary = state.cfg.presentation.fatherMotion
			var hover := display_time * TAU * float(motion.hoverCyclesPerSecond) + int(e.id) * 0.7
			model.position.y = sin(hover) * float(motion.hoverHeightTiles)
			model.rotation.x = -float(motion.movementLeanRadians) if walking else sin(hover) * 0.025
			model.rotation.z = cos(hover * 0.7) * 0.035
			for joint in model.get_meta("tentacles", []):
				var wave := display_time * TAU * float(motion.tentacleCyclesPerSecond) + int(joint.arm) * 0.8 - int(joint.segment) * 0.75
				joint.node.rotation = joint.rest + Vector3(sin(wave), 0, cos(wave * 0.85)) * float(motion.tentacleSwayRadians)
		elif e.kind == "mother" and not state.paused:
			var motion: Dictionary = state.cfg.presentation.motherMotion
			var shamble := display_time * TAU * float(motion.stepCyclesPerSecond) + int(e.id) * 0.7
			var left := sin(shamble) if walking else 0.0
			var right := sin(shamble + PI + 0.55) * float(motion.dragRatio) if walking else 0.0
			model.scale = anatomy
			model.position.y = maxf(0, left) * 0.018
			model.rotation.z = sin(shamble - 0.35) * float(motion.swayRadians) * (1.0 if walking else 0.2)
			parts["ShambleLegL"].rotation.x = left * float(motion.legSwingRadians)
			parts["ShambleLegR"].rotation.x = right * float(motion.legSwingRadians)
			parts["ShambleLegL/Knee"].rotation.x = 0.18 + maxf(0, -left) * 0.2
			parts["ShambleLegR/Knee"].rotation.x = 0.18 + maxf(0, -right) * 0.14
			parts["ShambleTorso"].rotation.x = -0.22 + left * 0.04
			parts["ShambleTorso"].rotation.y = left * float(motion.swayRadians)
			parts["ShambleTorso/Head"].rotation.x = 0.05 + sin(shamble - 1.1) * float(motion.headLagRadians) * (1.0 if walking else 0.25)
			parts["ShambleTorso/ArmL"].rotation.x = 0.5 + left * 0.12
			parts["ShambleTorso/ArmR"].rotation.x = 0.15 + right * 0.16
	var recoil := float(body.get_meta("recoil")) if body.get_meta("recoil_fresh") else maxf(0, float(body.get_meta("recoil")) - delta * 9)
	body.set_meta("recoil_fresh", false)
	body.set_meta("recoil", recoil)
	if parts.has("Weapon"): parts["Weapon"].position.z = recoil * float(body.get_meta("kick"))
	var flash := float(body.get_meta("hit_flash")) if body.get_meta("flash_fresh") else maxf(0, float(body.get_meta("hit_flash")) - delta)
	body.set_meta("flash_fresh", false)
	body.set_meta("hit_flash", flash)
	if not is_instance_valid(view_camera): _set_overlay(body, (shield_overlay if body.get_meta("shielded") else hit_overlay) if flash > 0 else null)
	if parts.has("Turret"):
		var turret: Node3D = parts["Turret"]
		turret.position = Vector3(sin(turret.rotation.y), 0, cos(turret.rotation.y)) * recoil * float(body.get_meta("kick"))
	if parts.has("Rider"):
		parts["Rider"].visible = not e.get("passengers", []).is_empty()
		parts["Rider/Gun"].position.z = recoil * float(body.get_meta("kick"))
		if not e.get("passengers", []).is_empty():
			var rider: Dictionary = state.units.get(int(e.passengers[0]), {})
			parts["Rider/Gun"].visible = not rider.is_empty() and state.cfg.units[rider.kind].weapon != null
			var target := state.entity(int(rider.get("target", 0)))
			if not target.is_empty():
				var aim := state.entity_position(target)
				parts["Rider"].rotation.y = atan2(pos.x - aim.x, pos.y - aim.y) - body.rotation.y
	if parts.has("GatePanel"):
		var lowered := -0.8 if e.open else -0.8 * (1.0 - float(e.opening_remaining) / maxf(0.001, float(state.cfg.construction.gateOpenSeconds))) if e.has("opening_remaining") else 0.0
		parts["GatePanel"].position.y = lerpf(parts["GatePanel"].position.y, lowered, 1.0 - exp(-delta * 14))
	if parts.has("Gantry"):
		var working: bool = e.get("powered", false) and not e.vehicles.is_empty() and state._wants_power(e) and not state.paused
		parts["Gantry"].position.x = sin(display_time * 2.8) * 0.5 if working else 0.0
		if working and int(display_time * 5) != int((display_time - delta) * 5): _burst(pos, Color("e6b477"), 2)
	if parts.has("Rotor") and e.get("fuel", 0) > 0 and e.get("enabled", false) and not state.paused: parts["Rotor"].rotation.y = display_time * 7
	if parts.has("Cargo"): parts["Cargo"].visible = state.cargo_amount(e) > 0
	if parts.has("RadarDish") and e.get("powered", false) and not state.paused: parts["RadarDish"].rotation.y = display_time * 0.65
	if parts.has("ShieldCore"): parts["ShieldCore"].visible = e.get("powered", false) and e.get("enabled", false)
	if parts.has("Headlights"): parts["Headlights"].visible = int(e.get("driver", 0)) != 0
	if parts.has("Tool"): _animate_tool(body, e, pos, delta, parts["Tool"])
	if parts.has("Drill") and not state.paused:
		var drilling: bool = (int(e.get("driver", 0)) != 0 and e.get("job", {}).get("kind", "") == "excavate" and e.route.is_empty()) if e.has("pos") else bool(e.powered) and state._wants_power(e)
		if drilling:
			parts["Drill"].rotate_object_local(Vector3.UP, delta * 12)
			if e.has("cell"): parts["Drill"].position.y = 0.44 + sin(display_time * 13) * 0.09
	if parts.has("Lamp"):
		var enabled: bool = e.get("powered", false) and e.get("built", true)
		parts["Lamp"].material_override = art.mat(Color("ffe5ad") if e.kind == "floodlight" else Color("8bcecf"), true) if enabled else art.mat(SceneArt.DARK)
	if parts.has("Beacon"):
		var period := 0.4 if state.players.get(e.owner, {}).get("extracting", false) else 1.8
		parts["Beacon"].visible = fmod(display_time, period) < period * 0.8
	if e.has("cell") and int(e.owner) >= 0: _animate_facility(model, e)
	if parts.has("Turret") and state.entity(int(e.get("target", 0))).size() > 0:
		var target_position := state.entity_position(state.entity(int(e.target)))
		parts["Turret"].rotation.y = lerp_angle(parts["Turret"].rotation.y, atan2(pos.x - target_position.x, pos.y - target_position.y), 1 - exp(-delta * 15))

func _body_in_frustum(view: BodyView, planes: Array) -> bool:
	var center := view.root.global_transform * view.bounds.get_center()
	var radius := view.bounds.size.length() * 0.5 * maxf(view.root.scale.x, maxf(view.root.scale.y, view.root.scale.z))
	for plane in planes:
		if plane.distance_to(center) > radius: return false
	return true

func _advance_flashes(body: Node3D, delta: float) -> void:
	var recoil := float(body.get_meta("recoil"))
	if recoil > 0:
		if body.get_meta("recoil_fresh"): body.set_meta("recoil_fresh", false)
		else: body.set_meta("recoil", maxf(0, recoil - delta * 9))
	var flash := float(body.get_meta("hit_flash"))
	if flash > 0:
		if body.get_meta("flash_fresh"): body.set_meta("flash_fresh", false)
		else: flash = maxf(0, flash - delta); body.set_meta("hit_flash", flash)
	if not is_instance_valid(view_camera): _set_overlay(body, (shield_overlay if body.get_meta("shielded") else hit_overlay) if flash > 0 else null)

func _animate_person(view: BodyView, e: Dictionary, pos: Vector2, delta: float) -> void:
	var body := view.root
	var parts := view.parts
	var visual_position := Vector2(body.position.x, body.position.z)
	var walking := not state.paused and view.last_position.distance_squared_to(visual_position) > 0.00000025
	view.last_position = visual_position
	var phase := display_time * 12 + int(e.id) * 0.7
	parts["LegL"].rotation.x = sin(phase) * 0.55 if walking else lerpf(parts["LegL"].rotation.x, 0, delta * 12)
	parts["LegR"].rotation.x = -sin(phase) * 0.55 if walking else lerpf(parts["LegR"].rotation.x, 0, delta * 12)
	view.model.position.y = absf(sin(phase)) * 0.025 if walking else sin(display_time * 2 + int(e.id)) * 0.006
	view.model.rotation.x = -0.07 if walking else 0.0
	_advance_flashes(body, delta)
	if parts.has("Weapon"): parts["Weapon"].position.z = float(body.get_meta("recoil")) * float(body.get_meta("kick"))
	parts["Cargo"].visible = state.cargo_amount(e) > 0
	if parts.has("Tool"): _animate_tool(body, e, pos, delta, parts["Tool"])

func _animate_tool(body: Node3D, e: Dictionary, pos: Vector2, delta: float, tool: Node3D) -> void:
	var working: bool = not state.paused and e.job.kind in ["mine", "repair", "build"] and e.route.is_empty()
	if e.job.kind == "mine":
		working = working and not e.job.get("delivering", false) and state.cargo_amount(e) < int(state.cfg.units[e.kind].cargoCapacity)
		var facility := int(e.job.get("facility", 0))
		if facility != 0: working = working and state.structures.has(facility) and int(state.structures[facility].buffer) > 0
		elif e.job.has("source"): working = working and int(state.tiles.get(HexGrid.unkey(e.job.source), {}).get("amount", 0)) > 0
	if e.job.kind == "repair": working = working and (float(e.work) > 0 or int(state.resources(e.owner).get("ore", 0)) > 0)
	tool.rotation.x = sin(display_time * 18) * 0.12 if working else 0.0
	if working and int(display_time * 12) != int((display_time - delta) * 12): _burst(pos + Vector2(-sin(body.rotation.y), -cos(body.rotation.y)) * 0.35, Color("e5b968"), 1)

func _burst(point: Vector2, color: Color, count: int) -> void:
	var limit := int(state.cfg.presentation.feedback.particleLimit)
	for i in range(mini(count, maxi(0, limit - particles.size()))):
		var a := i * 2.399 + display_time * 37
		particles.append({"pos": Vector3(point.x, 0.24, point.y), "velocity": Vector3(cos(a) * 1.6, 0.7 + fposmod(a, 1.1), sin(a) * 1.6), "time": 0.25 + fposmod(a, 0.2), "color": color})

func _draw_particles(delta: float) -> void:
	var mesh := ImmediateMesh.new()
	if not particles.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for particle in particles:
			particle.time -= delta
			particle.velocity.y -= delta * float(state.cfg.presentation.feedback.particleGravity)
			particle.pos += particle.velocity * delta
			mesh.surface_set_color(particle.color.darkened(1 - minf(1, float(particle.time) * 5)))
			mesh.surface_add_vertex(particle.pos)
			mesh.surface_add_vertex(particle.pos - particle.velocity * 0.06)
		mesh.surface_end()
	particles = particles.filter(func(particle): return particle.time > 0)
	particle_mesh.mesh = mesh

func _facility_state(e: Dictionary) -> Dictionary:
	var online: bool = e.built and e.enabled and not e.get("blackout", false)
	if int(state.cfg.structures[e.kind].powerDemand) > 0: online = online and e.powered
	if e.kind in ["generator", "reactor"]: online = online and float(e.fuel) > 0
	var working := false
	if online:
		working = float(e.get("cycle", 0)) > 0
		for key in ["operators", "kits", "vehicles", "upgrades"]:
			for job in e.get(key, []):
				if job.get("done", false): continue
				if float(job.get("progress", 0)) <= 0: continue
				if key == "vehicles" and float(job.progress) >= float(state.cfg.units[job.kind].productionSeconds): continue
				working = true
		if e.kind in ["generator", "reactor"]: working = true
		if e.kind == "fabricator": working = state._wants_power(e)
	return {"online": online, "working": working, "warning": e.built and e.enabled and (not online or e.get("brownout", false))}

func _animate_facility(model: Node3D, e: Dictionary) -> void:
	var parts: Dictionary = model.get_parent().get_meta("parts")
	var activity := _facility_state(e)
	var online: bool = activity.online
	if model.get_parent().has_node("LightWash"): model.get_parent().get_node("LightWash").visible = online
	var working: bool = activity.working
	var warm := Color("ffd09a")
	for lamp in ["PowerLamp", "ServiceLamp-1", "ServiceLamp1", "ServiceRail", "Lamp", "LampSide-1", "LampSide1"]:
		if parts.has(lamp): parts[lamp].material_override = art.mat(warm, true) if online else art.mat(SceneArt.DARK)
	if parts.has("ProductionLamp"): parts["ProductionLamp"].material_override = art.mat(warm, true) if working and fmod(display_time, 0.8) < 0.6 else art.mat(SceneArt.DARK)
	if parts.has("WarningLamp"):
		parts["WarningLamp"].material_override = art.mat(Color("df7048"), true) if activity.warning and fmod(display_time, 1.2) < 0.7 else art.mat(Color("502d26"))
	if parts.has("ProcessGlow"):
		var glow := Color("ec9e58") if e.kind != "synthesizer" else Color("b2d1c3")
		parts["ProcessGlow"].material_override = art.mat(glow, true) if working else art.mat(SceneArt.DARK)
	if parts.has("Press"): parts["Press"].position.y = sin(display_time * 4) * 0.11 if working else 0.0
	if parts.has("Assembly"):
		parts["Assembly"].visible = e.built and not e.vehicles.is_empty()
		if not e.vehicles.is_empty():
			var progress := clampf(float(e.vehicles[0].progress) / float(state.cfg.units[e.vehicles[0].kind].productionSeconds), 0, 1)
			parts["Assembly"].scale.y = 0.2 + progress * 0.8
	for i in range(3):
		if parts.has("ReactorBand%d" % i): parts["ReactorBand%d" % i].material_override = art.mat(Color("d1c299"), true) if online else art.mat(SceneArt.DARK)
	# Racks represent the owner's actual queue. No fabricated personnel entities,
	# and no additional enemy production information or fog-memory animation.
	if not parts.has("KitRack"): return
	var show_queue: bool = e.built and int(e.owner) == viewer_owner
	parts["KitRack"].visible = show_queue
	parts["PersonnelRack"].visible = show_queue
	for i in range(5):
		var slot: Node3D = parts["KitRack/Slot%d" % i]
		slot.visible = i < e.kits.size()
		if not slot.visible: continue
		var kit: Dictionary = e.kits[i]
		var progress := clampf(float(kit.progress) / float(state.cfg.personnel.kits[kit.kind].seconds), 0, 1)
		var colors := {"engineer": Color("d6af65"), "marine": Color("b7b9a8"), "flamer": Color("b86c43"), "lancer": Color("8eaaa8")}
		slot.get_node("Case").material_override = art.mat(colors.get(kit.kind, SceneArt.EDGE) if kit.done else SceneArt.DARK)
		slot.get_node("Case").scale.y = 0.25 if kit.done else 0.08 + 0.17 * progress
		slot.get_node("Latch").material_override = art.mat(Color("b9cbb2"), true) if kit.done and online else art.mat(SceneArt.EDGE)
		slot.get_node("Progress").scale.x = maxf(0.008, 0.16 * progress)
		slot.get_node("Progress").material_override = art.mat(warm, true) if online and progress > 0 else art.mat(SceneArt.DARK)
	for i in range(10):
		var slot: Node3D = parts["PersonnelRack/Slot%d" % i]
		slot.visible = i < e.operators.size()
		if not slot.visible: continue
		var duration := float(state.cfg.personnel.anchorOperatorSeconds if e.kind == "anchor" else state.cfg.personnel.cradleOperatorSeconds)
		var progress := clampf(float(e.operators[i].progress) / duration, 0, 1)
		slot.get_node("Window").material_override = art.mat(warm, true) if online and progress > 0 else art.mat(SceneArt.DARK)
		slot.get_node("Capsule").position.y = 0.42 + (1.0 - progress) * 0.18

func show_wall_line(sites: Array) -> void:
	while wall_previews.size() < sites.size():
		var instance := MeshInstance3D.new()
		instance.mesh = art.wall_prism
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance); wall_previews.append(instance)
	for i in range(wall_previews.size()):
		wall_previews[i].visible = i < sites.size()
		if i >= sites.size(): continue
		var point := HexGrid.world(sites[i].cell)
		wall_previews[i].position = Vector3(point.x, 0.5, point.y)
		wall_previews[i].material_override = ghost_valid if sites[i].valid else ghost_invalid

func show_preview(cell: Vector2i, enabled: bool, kind: String = "wall", valid: bool = true) -> void:
	preview.visible = false
	if enabled and (ghost_model == null or ghost_kind != kind):
		if ghost_model != null: ghost_model.queue_free()
		ghost_model = art.create({"kind": kind, "owner": viewer_owner, "cell": cell}, COLORS[viewer_owner], state.cfg.presentation)
		ghost_kind = kind; add_child(ghost_model)
	if ghost_model != null:
		ghost_model.visible = enabled
		if enabled:
			var point := HexGrid.world(cell); ghost_model.position = Vector3(point.x, 0, point.y)
			for surface in _surfaces(ghost_model):
				surface.material_override = ghost_valid if valid else ghost_invalid
				surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cells := HexGrid.disk(cell, int(state.cfg.structures[kind].footprintRadiusTiles)) if state != null else [cell]
	for i in range(preview_tiles.size()):
		var ghost := preview_tiles[i]
		ghost.visible = enabled and i < cells.size()
		if not ghost.visible: continue
		var p := HexGrid.world(cells[i])
		ghost.position = Vector3(p.x, 0.08, p.y)
		ghost.material_override = preview_valid if valid else preview_invalid


func pick_model(origin: Vector3, direction: Vector3) -> int:
	# Use the displayed meshes, including animation/interpolation transforms.
	# Per-piece bounds give forgiving hits without filling the gaps between parts.
	var best := 0
	var nearest := INF
	for id in bodies:
		var body: Node3D = bodies[id]
		if not body.is_visible_in_tree(): continue
		var body_inverse := body.global_transform.affine_inverse()
		var bounds := _model_bounds(body)
		if bounds.intersects_ray(body_inverse * origin, body_inverse.basis * direction) == null: continue
		for surface in body.get_meta("surfaces", []):
			if not surface.is_visible_in_tree() or surface.mesh == null: continue
			var inverse: Transform3D = surface.global_transform.affine_inverse()
			var hit = surface.get_aabb().intersects_ray(inverse * origin, inverse.basis * direction)
			if hit == null: continue
			var distance: float = origin.distance_to(surface.global_transform * hit)
			if distance < nearest:
				nearest = distance
				best = int(id)
	return best

func _model_bounds(body: Node3D) -> AABB:
	if body.has_meta("model_bounds"): return body.get_meta("model_bounds")
	var bounds := AABB()
	var first := true
	var inverse := body.global_transform.affine_inverse()
	for surface in body.get_meta("surfaces", []):
		var part: AABB = inverse * surface.global_transform * surface.get_aabb()
		bounds = part if first else bounds.merge(part); first = false
	body.set_meta("model_bounds", bounds.grow(0.2))
	return bounds.grow(0.2)

func _surfaces(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_surfaces(child))
	return result

func _cache_parts(model: Node, node: Node, parts: Dictionary) -> void:
	for child in node.get_children():
		parts[str(model.get_path_to(child))] = child
		_cache_parts(model, child, parts)

func _consume_feedback() -> void:
	for event in state.feedback_for(viewer_owner, feedback_cursor):
		feedback_cursor = maxi(feedback_cursor, int(event.serial))
		if state.tick - int(event.tick) > int(state.cfg.presentation.feedback.maxCatchupTicks): continue
		match str(event.kind):
			"fire":
				var profile := WorldState.FeedbackRules.profile(state.cfg, str(event.weapon))
				var effect: Dictionary = event.duplicate(true)
				effect.time = float(profile.traceSeconds); effect.duration = effect.time; effect.profile = profile; effect.fresh = true
				visual_shots.append(effect)
				while visual_shots.size() > int(state.cfg.presentation.feedback.maxTraces): visual_shots.pop_front()
				var attacker := int(event.attacker)
				if state.units.has(attacker) and int(state.units[attacker].vehicle) != 0: attacker = int(state.units[attacker].vehicle)
				if bodies.has(attacker): bodies[attacker].set_meta("recoil", 1.0); bodies[attacker].set_meta("recoil_fresh", true); bodies[attacker].set_meta("kick", float(profile.recoilTiles))
				if profile.visual != "melee": _burst(event.from + (event.to - event.from).normalized() * 0.35, Color("ffe5ae"), int(state.cfg.presentation.feedback.muzzleParticleCount))
				_burst(event.to, Color("d9b17c"), int(profile.impactParticles))
			"hit":
				if state.cfg.presentation.feedback.hitFlashesEnabled and bodies.has(int(event.target)) and display_time >= float(bodies[int(event.target)].get_meta("flash_gate")):
					bodies[int(event.target)].set_meta("flash_gate", display_time + float(state.cfg.presentation.feedback.hitFlashGapSeconds))
					bodies[int(event.target)].set_meta("hit_flash", float(state.cfg.presentation.feedback.hitFlashSeconds))
					bodies[int(event.target)].set_meta("shielded", bool(event.shielded))
					bodies[int(event.target)].set_meta("flash_fresh", true)
				var color := Color("9cddd0") if event.shielded else Color("a38b78") if event.biological else Color("e6b177")
				_burst(event.at, color, int(state.cfg.presentation.feedback.hitParticleCount))
				_ring(event.at, color, 0.45 if event.shielded else 0.25, float(state.cfg.presentation.feedback.impactRingSeconds))
			"destroy":
				destroyed_ids[int(event.target)] = true
				_burst(event.at, Color("a89b85") if event.biological else Color("d4b580"), int(state.cfg.presentation.feedback.destructionParticleCount))
				_ring(event.at, Color("b69b74"), 1.0, float(state.cfg.presentation.feedback.destructionRingSeconds))
			"ready", "deposit":
				_ring(event.at, Color("97c9b4"), 1.2, float(state.cfg.presentation.feedback.completionRingSeconds))
				_burst(event.at, Color("a6d2bc"), int(state.cfg.presentation.feedback.completionParticleCount))

func _ring(at: Vector2, color: Color, radius: float, seconds: float) -> void:
	impact_rings.append({"at": at, "color": color, "radius": radius, "time": seconds, "duration": seconds, "fresh": true})
	if impact_rings.size() > int(state.cfg.presentation.feedback.maxImpactRings): impact_rings.pop_front()

func _quad(mesh: ImmediateMesh, start: Vector3, finish: Vector3, width: float, color: Color) -> void:
	var side := (finish - start).cross(Vector3.UP).normalized() * width * 0.5
	mesh.surface_set_color(color)
	for vertex in [start - side, finish - side, finish + side, start - side, finish + side, start + side]: mesh.surface_add_vertex(vertex)

func _draw_traces() -> void:
	var mesh := ImmediateMesh.new()
	var traces: Array = visual_shots.filter(func(shot): return shot.profile.visual != "melee")
	if not traces.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for shot in traces:
			var profile: Dictionary = shot.profile
			var alpha := clampf(float(shot.time) / float(shot.duration), 0, 1)
			var start := Vector3(shot.from.x, float(shot.get("height", 0.54)), shot.from.y)
			var finish := Vector3(shot.to.x, 0.54, shot.to.y)
			if profile.visual == "melee": continue
			var muzzle := start + (finish - start).normalized() * 0.3
			var flash_color := Color(0.76, 0.96, 1, alpha * alpha) if profile.visual == "laser" else Color(1, 0.9, 0.64, alpha * alpha)
			_quad(mesh, muzzle, muzzle + (finish - start).normalized() * 0.2, float(state.cfg.presentation.feedback.muzzleFlashWidthTiles), flash_color)
			if profile.visual == "flame":
				var direction := (finish - start).normalized()
				var weapon: Dictionary = state.cfg.weapons[shot.weapon]
				for i in range(8):
					var a := direction.rotated(Vector3.UP, deg_to_rad(float(weapon.coneDegrees)) * (float(i) / 8 - 0.5))
					var b := direction.rotated(Vector3.UP, deg_to_rad(float(weapon.coneDegrees)) * (float(i + 1) / 8 - 0.5))
					mesh.surface_set_color(Color(1.0, 0.76, 0.35, alpha * 0.45)); mesh.surface_add_vertex(start)
					mesh.surface_set_color(Color(0.85, 0.32, 0.1, alpha * 0.07)); mesh.surface_add_vertex(start + a * float(weapon.rangeTiles)); mesh.surface_add_vertex(start + b * float(weapon.rangeTiles))
				_quad(mesh, start, finish, 0.09, Color(1, 0.87, 0.58, alpha * 0.8))
			else:
				var color := Color(0.53, 0.86, 0.94, alpha * 0.7) if profile.visual == "laser" else Color(1, 0.72, 0.33, alpha)
				_quad(mesh, start, finish, float(profile.traceWidthTiles), color)
				if profile.visual == "laser": _quad(mesh, start + Vector3.UP * 0.005, finish + Vector3.UP * 0.005, float(profile.traceWidthTiles) * 0.24, Color(0.94, 1, 1, alpha))
		mesh.surface_end()
	if not impact_rings.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for ring in impact_rings:
			var progress := 1.0 - float(ring.time) / float(ring.duration)
			var radius := float(ring.radius) * (0.3 + progress * 0.7)
			mesh.surface_set_color(Color(ring.color, 1.0 - progress))
			for i in range(20):
				for angle in [i * TAU / 20, (i + 1) * TAU / 20]: mesh.surface_add_vertex(Vector3(ring.at.x + cos(angle) * radius, 0.07, ring.at.y + sin(angle) * radius))
		mesh.surface_end()
	shot_mesh.mesh = mesh
