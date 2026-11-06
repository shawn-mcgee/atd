class_name WorldRenderer
extends Node3D

var state: WorldState
var viewer_owner := 0
var terrain := MultiMeshInstance3D.new()
var rocks := MultiMeshInstance3D.new()
var deposits := MultiMeshInstance3D.new()
var bodies: Dictionary = {}
var selection: Array = []
var terrain_cells: Array = []
var tile_cache: Dictionary = {}
var preview := MeshInstance3D.new()
var shot_mesh := MeshInstance3D.new()
var preview_tiles: Array[MeshInstance3D] = []
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
var death_effects: Array = []
var particles: Array = []
var particle_mesh := MeshInstance3D.new()
const COLORS := [Color("4aa9ed"), Color("8ad66b"), Color("ef636c"), Color("efb44d"), Color("b68ef0")]

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("070b12")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("85949d")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_color = Color("b7c7cf")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	for instance in [terrain, rocks, deposits]: add_child(instance)
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deposits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tile := CylinderMesh.new()
	tile.top_radius = HexGrid.RADIUS
	tile.bottom_radius = tile.top_radius
	tile.height = 0.08
	tile.radial_segments = 6
	terrain.multimesh = _multi(tile)
	ground_material.shader = preload("res://shaders/regolith.gdshader")
	ground_material.set_shader_parameter("ground_texture", preload("res://assets/textures/regolith-albedo.png"))
	terrain.material_override = ground_material
	rocks.multimesh = _multi(_rock_mesh())
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.45, 0.5, 0.4)
	deposits.multimesh = _multi(_rock_mesh())
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
		for i in range(6):
			var a := i * TAU / 6
			var radius_value: float = [0.58, 0.61, 0.39][ring] * (0.86 + fposmod(sin(i * 17.3 + ring * 7.1) * 31, 0.25))
			layer.append(Vector3(cos(a) * radius_value, [0.0, 0.49, 1.0][ring] + (0.1 * sin(i * 2.0) if ring == 2 else 0.0), sin(a) * radius_value))
		levels.append(layer)
	var triangles: Array = []
	for ring in range(2):
		for i in range(6):
			var next := (i + 1) % 6
			triangles.append([levels[ring][i], levels[ring + 1][i], levels[ring + 1][next]])
			triangles.append([levels[ring][i], levels[ring + 1][next], levels[ring][next]])
	for i in range(6): triangles.append([Vector3(0, 1.04, 0), levels[2][(i + 1) % 6], levels[2][i]])
	for triangle in triangles:
		var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
		for index in [0, 2, 1]: vertices.append(triangle[index]); normals.append(normal)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

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
	for node in bodies.values(): node.queue_free()
	bodies.clear()
	visual_shots.clear(); particles.clear(); impact_rings.clear(); destroyed_ids.clear(); feedback_cursor = 0
	for effect in death_effects: effect.node.queue_free()
	death_effects.clear()
	terrain_cells = state.tiles.keys()
	tile_cache.clear()
	for instance in [terrain, rocks, deposits]: instance.multimesh.instance_count = terrain_cells.size()
	deposits.multimesh.instance_count = terrain_cells.size() * 3
	ground_material.set_shader_parameter("map_span", float(state.radius * 2 + 4))
	refresh_tiles()
	refresh_entities()

func refresh_tiles() -> void:
	if state == null: return
	var explored: Dictionary = state.known.get(viewer_owner, {})
	var active: Dictionary = state.visible.get(viewer_owner, {})
	var light: Dictionary = {}
	for area in state.illuminated.values(): light.merge(area, true)
	var changed := false
	var edge: Dictionary = explored.duplicate()
	for cell in explored:
		for direction in HexGrid.DIRECTIONS: edge[cell + direction] = true
	for i in range(terrain_cells.size()):
		var cell: Vector2i = terrain_cells[i]
		var p := HexGrid.world(cell)
		var tile: Dictionary = state.tiles[cell]
		var signature := int(explored.has(cell)) + 2 * int(active.has(cell)) + 4 * int(light.has(cell)) + 8 * int(state.gloom.has(cell)) + 16 * int(bool(tile.cliff)) + 32 * int(int(tile.amount) > 0) + 128 * int(edge.has(cell)) + 256 * int(tile.get("rubble", false))
		if tile_cache.get(cell, -1) == signature: continue
		tile_cache[cell] = signature
		changed = true
		var color := Color("080f18")
		if explored.has(cell): color = Color("182733")
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
		var basis := Basis(Vector3.UP, fposmod(float(cell.x * 91 + cell.y * 37), TAU)).scaled(Vector3(1.05, height, 1.05) * scale_by)
		rocks.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p.x, -0.02, p.y)))
		rocks.multimesh.set_instance_color(i, color.lightened(0.08).srgb_to_linear())
		var has_resource: bool = tile.resource != "" and int(tile.amount) > 0 and explored.has(cell) and not tile.cliff
		var resource_color := Color("b69669") if tile.resource == "ore" else Color("619d9a") if tile.resource == "gas" else Color("d2b3a3")
		for j in range(3):
			var angle := j * TAU / 3 + float(cell.x)
			var size_by := Vector3(0.38, 0.23 + 0.11 * j, 0.38) if tile.resource != "gas" else Vector3(0.45, 0.08, 0.45)
			basis = Basis(Vector3.UP, angle).scaled(size_by * (1.0 if has_resource else 0.0))
			deposits.multimesh.set_instance_transform(i * 3 + j, Transform3D(basis, Vector3(p.x + cos(angle) * 0.21, 0, p.y + sin(angle) * 0.21)))
			deposits.multimesh.set_instance_color(i * 3 + j, (resource_color if active.has(cell) else resource_color.darkened(0.65)).srgb_to_linear())
	if changed: _update_visibility_texture(explored, active, light)

func _update_visibility_texture(explored: Dictionary, active: Dictionary, light: Dictionary) -> void:
	var side := state.radius * 2 + 4
	var resolution := side * 3
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for cell in explored:
		var point := (HexGrid.world(cell) / float(side) + Vector2(0.5, 0.5)) * resolution
		var color := Color(1, int(active.has(cell)), int(light.has(cell)), int(state.gloom.has(cell)))
		for x in range(-2, 3):
			for y in range(-2, 3):
				if x * x + y * y > 5: continue
				var pixel := Vector2i(point) + Vector2i(x, y)
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < resolution and pixel.y < resolution: image.set_pixelv(pixel, color)
	if visibility_texture == null: visibility_texture = ImageTexture.create_from_image(image)
	else: visibility_texture.set_image(image)
	ground_material.set_shader_parameter("visibility_map", visibility_texture)

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
	root.set_meta("surfaces", _surfaces(root.get_node("Model")))
	if e.kind in ["anchor", "floodlight"]:
		var lamp := OmniLight3D.new()
		lamp.name = "Worklight"
		lamp.position = Vector3(0, 1.1, 0)
		lamp.light_color = Color("ffe0a1"); lamp.light_energy = 1.2
		lamp.omni_range = 4.5 if e.kind == "anchor" else 6.5
		lamp.shadow_enabled = false
		root.add_child(lamp)
	add_child(root)
	return root

func refresh_entities() -> void:
	if state == null: return
	var delta := minf(get_process_delta_time(), 0.1)
	if not state.paused: display_time += delta * state.speed
	destroyed_ids.clear()
	_consume_feedback()
	var live: Dictionary = {}
	for e in state.units.values() + state.structures.values():
		live[e.id] = true
		if bodies.has(e.id) and bodies[e.id].get_meta("kind") != e.kind:
			bodies[e.id].queue_free(); bodies.erase(e.id)
		if not bodies.has(e.id): bodies[e.id] = _body(e)
		var body: Node3D = bodies[e.id]
		var pos := state.entity_position(e)
		var target := Vector3(pos.x, 0, pos.y)
		if not body.has_meta("placed"):
			body.position = target; body.rotation.y = float(e.get("heading", 0)); body.set_meta("placed", true)
		body.position = body.position.lerp(target, 1.0 - exp(-delta / float(Settings.data.presentation.motionInterpolationSeconds)))
		body.visible = (e.owner == viewer_owner or state.known.get(viewer_owner, {}).has(e.cell)) if e.has("cell") else WorldState.TargetRules.identifiable(state, e, viewer_owner)
		if e.get("vehicle", 0) != 0: body.visible = false
		body.get_node("Selection").visible = e.id in selection
		if e.has("heading"): body.rotation.y = lerp_angle(body.rotation.y, float(e.heading), 1.0 - exp(-delta * 18))
		if e.has("built") and not e.built: body.scale = Vector3(1, 0.12 + 0.88 * float(e.hp) / float(state.cfg.structures[e.kind].health), 1)
		else: body.scale = Vector3.ONE
		if e.get("buried", false): body.get_node("Model").position.y = -0.2
		elif e.get("transition", "") != "": body.get_node("Model").position.y = -0.1 + sin(display_time * 14) * 0.025
		else: body.get_node("Model").position.y = 0
		if body.has_node("Worklight"): body.get_node("Worklight").visible = bool(e.get("powered", false)) and bool(e.get("built", true))
		_animate(body, e, pos, delta)
	for id in bodies.keys():
		if not live.has(id):
			var node: Node3D = bodies[id]
			if node.visible and destroyed_ids.has(id):
				_burst(Vector2(node.position.x, node.position.z), Color("b0a38b"), 16)
				for surface in node.get_meta("surfaces"): surface.material_overlay = null
				node.get_node("Selection").hide()
				death_effects.append({"node": node, "time": float(state.cfg.presentation.feedback.deathSeconds)})
			else: node.queue_free()
			bodies.erase(id)
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

func _animate(body: Node3D, e: Dictionary, pos: Vector2, delta: float) -> void:
	var model: Node3D = body.get_node("Model")
	var previous: Vector2 = body.get_meta("last_position")
	var visual_position := Vector2(body.position.x, body.position.z)
	var walking := not state.paused and previous.distance_to(visual_position) > 0.0005
	body.set_meta("last_position", visual_position)
	var phase := display_time * 12 + int(e.id) * 0.7
	if model.has_node("LegL"):
		model.get_node("LegL").rotation.x = sin(phase) * 0.55 if walking else lerpf(model.get_node("LegL").rotation.x, 0, delta * 12)
		model.get_node("LegR").rotation.x = -sin(phase) * 0.55 if walking else lerpf(model.get_node("LegR").rotation.x, 0, delta * 12)
		model.position.y = absf(sin(phase)) * 0.025 if walking else sin(display_time * 2 + int(e.id)) * 0.006
		model.rotation.x = -0.07 if walking else 0.0
	if e.owner < 0 and e.has("pos"):
		var anatomy: Vector3 = model.get_meta("base_scale", Vector3.ONE)
		model.scale = Vector3(anatomy.x, anatomy.y * (1.0 + sin(display_time * 3 + int(e.id)) * 0.025), anatomy.z)
		for side in [-1, 1]:
			for i in range(3):
				var claw := model.get_node_or_null("Claw%d_%d" % [side, i])
				if claw: claw.rotation.y = side * (i - 1) * -0.45 + (sin(phase * 1.3 + i * 2) * 0.35 if walking else 0.0)
	var recoil := float(body.get_meta("recoil")) if body.get_meta("recoil_fresh") else maxf(0, float(body.get_meta("recoil")) - delta * 9)
	body.set_meta("recoil_fresh", false)
	body.set_meta("recoil", recoil)
	if model.has_node("Weapon"): model.get_node("Weapon").position.z = recoil * float(body.get_meta("kick"))
	var flash := float(body.get_meta("hit_flash")) if body.get_meta("flash_fresh") else maxf(0, float(body.get_meta("hit_flash")) - delta)
	body.set_meta("flash_fresh", false)
	body.set_meta("hit_flash", flash)
	for surface in body.get_meta("surfaces"):
		surface.material_overlay = (shield_overlay if body.get_meta("shielded") else hit_overlay) if flash > 0 else null
	if model.has_node("Turret"):
		var turret: Node3D = model.get_node("Turret")
		turret.position = Vector3(sin(turret.rotation.y), 0, cos(turret.rotation.y)) * recoil * float(body.get_meta("kick"))
	if model.has_node("Rider"):
		model.get_node("Rider").visible = not e.get("passengers", []).is_empty()
		model.get_node("Rider/Gun").position.z = recoil * float(body.get_meta("kick"))
		if not e.get("passengers", []).is_empty():
			var rider: Dictionary = state.units.get(int(e.passengers[0]), {})
			model.get_node("Rider/Gun").visible = not rider.is_empty() and state.cfg.units[rider.kind].weapon != null
			var target := state.entity(int(rider.get("target", 0)))
			if not target.is_empty():
				var aim := state.entity_position(target)
				model.get_node("Rider").rotation.y = atan2(pos.x - aim.x, pos.y - aim.y) - body.rotation.y
	if model.has_node("GatePanel"):
		var lowered := -0.8 if e.open else -0.8 * (1.0 - float(e.opening_remaining) / maxf(0.001, float(state.cfg.construction.gateOpenSeconds))) if e.has("opening_remaining") else 0.0
		model.get_node("GatePanel").position.y = lerpf(model.get_node("GatePanel").position.y, lowered, 1.0 - exp(-delta * 14))
	if model.has_node("Gantry"):
		var working: bool = e.get("powered", false) and not e.vehicles.is_empty() and state._wants_power(e) and not state.paused
		model.get_node("Gantry").position.x = sin(display_time * 2.8) * 0.5 if working else 0.0
		if working and int(display_time * 5) != int((display_time - delta) * 5): _burst(pos, Color("e6b477"), 2)
	if model.has_node("Rotor") and e.get("fuel", 0) > 0 and e.get("enabled", false) and not state.paused: model.get_node("Rotor").rotation.y = display_time * 7
	if model.has_node("Cargo"): model.get_node("Cargo").visible = state.cargo_amount(e) > 0
	if model.has_node("RadarDish") and e.get("powered", false) and not state.paused: model.get_node("RadarDish").rotation.y = display_time * 0.65
	if model.has_node("ShieldCore"): model.get_node("ShieldCore").visible = e.get("powered", false) and e.get("enabled", false)
	if model.has_node("Headlights"): model.get_node("Headlights").visible = int(e.get("driver", 0)) != 0
	if model.has_node("Tool"):
		var working: bool = not state.paused and e.job.kind in ["mine", "repair", "build"] and e.route.is_empty()
		if e.job.kind == "mine":
			working = working and not e.job.get("delivering", false) and state.cargo_amount(e) < int(state.cfg.units[e.kind].cargoCapacity)
			var facility := int(e.job.get("facility", 0))
			if facility != 0: working = working and state.structures.has(facility) and int(state.structures[facility].buffer) > 0
			elif e.job.has("source"): working = working and int(state.tiles.get(HexGrid.unkey(e.job.source), {}).get("amount", 0)) > 0
		if e.job.kind == "repair": working = working and (float(e.work) > 0 or int(state.resources(e.owner).get("ore", 0)) > 0)
		model.get_node("Tool").rotation.x = sin(display_time * 18) * 0.12 if working else 0.0
		if working and int(display_time * 12) != int((display_time - delta) * 12): _burst(pos + Vector2(-sin(body.rotation.y), -cos(body.rotation.y)) * 0.35, Color("e5b968"), 1)
	if model.has_node("Drill") and not state.paused:
		var drilling: bool = (int(e.get("driver", 0)) != 0 and e.get("job", {}).get("kind", "") == "excavate" and e.route.is_empty()) if e.has("pos") else bool(e.powered) and state._wants_power(e)
		if drilling:
			model.get_node("Drill").rotate_object_local(Vector3.UP, delta * 12)
			if e.has("cell"): model.get_node("Drill").position.y = 0.44 + sin(display_time * 13) * 0.09
	if model.has_node("Lamp"):
		var enabled: bool = e.get("powered", false) and e.get("built", true)
		model.get_node("Lamp").material_override = art.mat(Color("ffe5ad") if e.kind == "floodlight" else Color("8bcecf"), true) if enabled else art.mat(SceneArt.DARK)
	if model.has_node("Beacon"):
		var period := 0.4 if state.players.get(e.owner, {}).get("extracting", false) else 1.8
		model.get_node("Beacon").visible = fmod(display_time, period) < period * 0.8
	if model.has_node("Turret") and state.entity(int(e.get("target", 0))).size() > 0:
		var target_position := state.entity_position(state.entity(int(e.target)))
		model.get_node("Turret").rotation.y = lerp_angle(model.get_node("Turret").rotation.y, atan2(pos.x - target_position.x, pos.y - target_position.y), 1 - exp(-delta * 15))

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


func _surfaces(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_surfaces(child))
	return result

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
