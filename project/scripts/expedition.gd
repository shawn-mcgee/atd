extends Node3D
const Visual = preload("res://scripts/expedition_visuals.gd")
const Hex = preload("res://scripts/hex_grid.gd")
const Navigation = preload("res://scripts/expedition_navigation.gd")
const Illumination = preload("res://scripts/illumination.gd")
const Unit = preload("res://scripts/expedition_unit.gd")
const Structure = preload("res://scripts/expedition_structure.gd")
const Predator = preload("res://scripts/predator.gd")
const Director = preload("res://scripts/predator_director.gd")
const SelectionBox = preload("res://scripts/selection_box.gd")
const Rules = preload("res://scripts/expedition_rules.gd")
const Economy = preload("res://scripts/expedition_economy.gd")
const Power = preload("res://scripts/expedition_power.gd")
const PowerPlacement = preload("res://scripts/power_placement_overlay.gd")
const WallPlacement = preload("res://scripts/wall_placement.gd")
const GPUPicker = preload("res://scripts/gpu_picker.gd")
const FocusOverlay = preload("res://scripts/unit_focus_overlay.gd")
const SoftSpacing = preload("res://scripts/soft_unit_spacing.gd")
const ComplexCommands = preload("res://scripts/complex_commands.gd")
const Terrain = preload("res://scripts/expedition_terrain.gd")
const TERRAIN_COLLISION_LAYER := 1 << 19
const GAS_DEPOSIT := Vector3(51, 3, 7)
const BUILD_KINDS := ["floodlight", "generator", "repeater", "turret", "wall", "gate", "depot", "gas_tank", "barracks", "garage", "scanner", "platform", "ramp", "extractor", "laser_turret", "flame_turret"]
const Footprints = preload("res://scripts/structure_footprints.gd")
const TICK := 0.1
const HOME := Vector3.ZERO
const DEPOSIT := Vector3(32, 0, -24)
const SHIPMENT := 30
const MINT := Color("7bf4d0")
const AMBER := Color("efbd77")
var layout := preload("res://scripts/scenario_layout.gd").new()
var scenario_seed := 0
var turret_system := preload("res://scripts/turret_system.gd").new()
var tactical_groups := preload("res://scripts/tactical_groups.gd").new()
var tactics := preload("res://scripts/tactical_orders.gd").new()
var mission := preload("res://scripts/hive_mission.gd").new()
var resource_fields := preload("res://scripts/resource_fields.gd").new()
var vehicles := preload("res://scripts/vehicle_systems.gd").new()
var tactical_mode := ""
var mining_mode := false
var selected_resource: Dictionary = {}
var terrain_meshes: Dictionary = {}
var economy := Economy.new()
var power := Power.new()
var wrecks: Array[Dictionary] = []
var resource_nodes: Array[Dictionary] = []
var gas_marker: Node3D
var resource_meshes: Array[Node3D] = []
var resource_markers: Array[Node3D] = []
var placement_direction := 0
var sensor_blips: Array[Node3D] = []
var power_lines: MeshInstance3D
var build_buttons: Dictionary = {}
var navigation := Navigation.new()
var light := Illumination.new()
var director := Director.new()
var units: Array[ExpeditionUnit] = []
var soft_spacing := SoftSpacing.new()
var construction_clearance := preload("res://scripts/construction_clearance.gd").new()
var complex_commands := ComplexCommands.new()
var gate_passage := preload("res://scripts/gate_passage.gd").new()
var next_formation_slot := 0
var structures: Array[ExpeditionStructure] = []
var creatures: Array[ExpeditionPredator] = []
var selected: Array[Node3D] = []
var rocks: Array[Dictionary] = []
var core: ExpeditionStructure
var jeep: ExpeditionUnit
var home_depot: ExpeditionStructure
var elapsed := 0.0
var started := false
var paused := false
var ended := false
var victorious := false
var accumulator := 0.0
var tick_number := 0
var audio_enabled := true
var fog_materials: Array[ShaderMaterial] = []
var fog_material_cache: Dictionary = {}
var outpost_established := false
var returned_materials := 0
var sensor_activity := 0.0
var low_fuel_warned := false
var build_kind := ""
var repair_mode := false
var expedition_mode := false
var camera: Camera3D
var picker: Node
var focus_overlay: MeshInstance3D
var occluded_units: Node3D
var click_serial := 0
var terrain_body: StaticBody3D
var camera_zoom := 48.0
var camera_yaw := 0.0
var camera_pitch := atan2(46.0, 32.0)
var focus := HOME + Vector3(7, 0, -2)
var dragging := false
var select_start := Vector2.ZERO
var pressed_pick: RefCounted
var pressed_serial := 0
var selecting := false
var mouse_world := Vector3.ZERO
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var power_placement: Node3D
var wall_placement: Node3D
var power_preview_label: Label
var deposit_mesh: Node3D
var signal_marker: Node3D
var effects: Array[Dictionary] = []
var hud: RefCounted
var world_bars: Control
var ui: Control
var selection_box: Control
var stats: Label
var objective_label: Label
var details: Label
var message: Label
var sensors: Label
var pause_button: Button
var command_panel: PanelContainer
var command_scroll: ScrollContainer
var command_content: VBoxContainer
var minimap: Control
var command_title: Label
var construction_panel: PanelContainer
var context_buttons: Dictionary = {}
var overlay: ColorRect
var overlay_title: Label
var overlay_text: Label
var overlay_button: Button
var notice_time := 0.0

func _ready() -> void:
	get_window().min_size = Vector2i(1100, 720)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): scenario_seed = int(argument.trim_prefix("--seed="))
	layout.generate(navigation.terrain, scenario_seed)
	scenario_seed = layout.seed_value
	make_world()
	get_viewport().size_changed.connect(update_camera)
	layout.setup_base(self)
	layout.setup_resources(self)
	power_lines = MeshInstance3D.new(); add_child(power_lines)
	mission.setup(self)
	economy.recalculate(structures); power.tick(structures, economy, 0)
	rebuild_navigation(); rebuild_light(); refresh_visual_lights(); update_power_lines()
	director.populate(self)
	make_ui()
	get_viewport().size_changed.connect(fit_command_panel)
	construction_panel.minimum_size_changed.connect(fit_construction_panel)
	call_deferred("fit_construction_panel")
	show_briefing(); refresh_ui()
	minimap = preload("res://scripts/minimap.gd").new(); ui.add_child(minimap); minimap.setup(self)
	setup_picking()
	occluded_units = preload("res://scripts/occluded_units.gd").new(); add_child(occluded_units)
	occluded_units.setup(camera)
	for child in get_children():
		if child is Node3D and child.get_meta("pick_occluder", false): occluded_units.register_occluder(child)
	for structure in structures: occluded_units.register_occluder(structure)
	for unit in units: occluded_units.register_actor(unit)
	for creature in creatures: occluded_units.register_actor(creature)
	occluded_units.sync(light)
	mission.register(self)

func fog_material(color: Color) -> ShaderMaterial:
	var key := color.to_html(true)
	if fog_material_cache.has(key): return fog_material_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/expedition_terrain.gdshader")
	mat.set_shader_parameter("tint", color)
	fog_materials.append(mat)
	fog_material_cache[key] = mat
	return mat

func make_world() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("66899c")
	env.ambient_light_energy = 0.38
	world.environment = env
	add_child(world)
	var outline := PackedVector2Array()
	for i in range(6): outline.append(Vector2(cos(i * TAU / 6), sin(i * TAU / 6)) * (Terrain.MAP_RADIUS + 0.5) * Terrain.SPACING)
	var ground := MeshInstance3D.new(); ground.mesh = Terrain.polygon_prism(outline, 0, -0.5); add_child(ground)
	ground.set_meta("pick_occluder", true)
	ground.material_override = fog_material(Color("344c53"))
	terrain_body = StaticBody3D.new(); terrain_body.name = "TerrainRaycastSurface"
	terrain_body.collision_layer = TERRAIN_COLLISION_LAYER; terrain_body.collision_mask = 0
	var terrain_shape := CollisionShape3D.new()
	terrain_shape.shape = ground.mesh.create_trimesh_shape()
	terrain_body.add_child(terrain_shape); add_child(terrain_body)
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES, fog_material(Color("47656c")))
	for r in range(-Terrain.MAP_RADIUS, Terrain.MAP_RADIUS + 1):
		for q in range(-Terrain.MAP_RADIUS, Terrain.MAP_RADIUS + 1):
			var center := Hex.to_world(Vector2i(q, r), Terrain.CELL)
			if not Terrain.contains(center): continue
			for edge in range(6):
				for angle in [PI / 6 + edge * TAU / 6, PI / 6 + (edge + 1) * TAU / 6]:
					grid.surface_add_vertex(navigation.terrain.surface(center + Vector3(cos(angle) * Terrain.CELL, 0, sin(angle) * Terrain.CELL)) + Vector3.UP * 0.015)
	grid.surface_end()
	var grid_instance := MeshInstance3D.new()
	grid_instance.mesh = grid
	add_child(grid_instance)
	layout.make_landscape(self)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48
	camera.far = 200
	add_child(camera)
	camera.current = true
	update_camera()
	ghost = MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = Terrain.CELL
	shape.bottom_radius = Terrain.CELL
	shape.radial_segments = 6
	shape.height = 0.1
	ghost.mesh = shape
	ghost_mat = Visual.material(Color(MINT, 0.4), true)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material_override = ghost_mat
	add_child(ghost)
	ghost.visible = false
	power_placement = PowerPlacement.new(); add_child(power_placement); power_placement.setup()
	wall_placement = WallPlacement.new(); add_child(wall_placement)

func add_natural_obstacle(point: Vector3, seed_index: int) -> void:
	point = Hex.snap(point, Terrain.CELL)
	if not Terrain.contains(point, 1) or point.distance_to(HOME) < 10: return
	if layout.fields.any(func(field): return point.distance_to(field.position) < 5): return
	var cell := Hex.to_axial(point, Terrain.CELL)
	for obstacle in rocks:
		if obstacle.get("cell") == cell: return
	point = navigation.terrain.surface(point)
	var height := 4.0 + posmod(seed_index, 3) * 0.4
	var rock := MeshInstance3D.new(); rock.mesh = Terrain.hex_mesh(height); rock.position = point; add_child(rock)
	rock.material_override = fog_material(Color("52636d")); rock.set_meta("pick_occluder", true)
	add_terrain_collider(rock)
	rocks.append({"position": point, "radius": Terrain.CELL * 0.82, "height": height, "cell": cell, "node": rock})

func add_terrain_collider(mesh: MeshInstance3D) -> void:
	var body := StaticBody3D.new(); body.collision_layer = TERRAIN_COLLISION_LAYER; body.collision_mask = 0
	var shape := CollisionShape3D.new(); shape.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(shape); mesh.add_child(body)

func add_resource_patch(kind: String, point: Vector3, amount: int) -> void:
	point = navigation.terrain.surface(point)
	resource_nodes.append({"kind": kind, "position": point, "remaining": amount, "discovered": false})
	var mesh := Node3D.new(); mesh.position = point; add_child(mesh)
	for i in range(4):
		var crystal := Visual.box(mesh, Vector3(0.8, 1.8, 0.8), Vector3(cos(i * 1.5), 0.9, sin(i * 1.5)), MINT)
		crystal.material_override = fog_material(MINT if kind == "minerals" else Color("86aa6a"))
	resource_meshes.append(mesh); mesh.visible = false
	var marker := Node3D.new(); marker.position = point; add_child(marker)
	Visual.ring(marker, 4, AMBER if kind == "minerals" else Color("a9c97b"))
	var tag := Label3D.new(); tag.text = ("MATERIAL" if kind == "minerals" else "METHANE") + " SIGNAL / ±4m"
	tag.position.y = 2.5; tag.font_size = 25; tag.pixel_size = 0.018; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED; marker.add_child(tag)
	resource_markers.append(marker); marker.visible = false

func update_fortifications() -> void:
	var occupied: Dictionary = {}
	for building in structures:
		if building.kind in ["wall", "gate"]:
			var cell := Hex.to_axial(building.position, Terrain.CELL)
			occupied[Vector3i(cell.x, cell.y, roundi(building.position.y * 10))] = building
	for building in structures:
		if building.kind not in ["wall", "gate"]: continue
		var neighbors: Array[Vector3] = []
		var cell := Hex.to_axial(building.position, Terrain.CELL)
		for offset in Hex.NEIGHBORS:
			var key := Vector3i(cell.x + offset.x, cell.y + offset.y, roundi(building.position.y * 10))
			if occupied.has(key): neighbors.append(occupied[key].position - building.position)
		if neighbors == building.connections: continue
		if picker != null: picker.remove_owner(building)
		if occluded_units != null: occluded_units.remove_occluder(building)
		building.connect_fortification(neighbors); building.update_visual()
		Visual.paint(building.model, fog_material(Color("7d9197")))
		if picker != null: picker.register_actor(building)
		if occluded_units != null: occluded_units.register_occluder(building)

func add_unit(kind: String, point: Vector3) -> ExpeditionUnit:
	var unit := Unit.new()
	unit.setup(kind, navigation.terrain.surface(point))
	unit.formation_slot = next_formation_slot; next_formation_slot += 1
	add_child(unit)
	units.append(unit)
	if picker != null: picker.register_actor(unit)
	if occluded_units != null: occluded_units.register_actor(unit)
	return unit

func add_structure(kind: String, point: Vector3, finished: bool = true, direction_index: int = -1) -> ExpeditionStructure:
	var structure := Structure.new()
	point = navigation.terrain.surface(Hex.snap(point, Terrain.CELL))
	if kind in ["platform", "ramp"]: point.y = 0
	structure.setup(kind, point, finished, placement_direction if direction_index < 0 else direction_index)
	if kind in ["wall", "gate", "platform", "ramp"]: Visual.paint(structure.model, fog_material(Color("7d9197")))
	add_child(structure)
	structures.append(structure)
	if picker != null: picker.register_actor(structure)
	if occluded_units != null: occluded_units.register_occluder(structure)
	if kind in ["wall", "gate"]: update_fortifications()
	return structure

func add_creature(point: Vector3, group: int, kind: String = "stalker", variation: int = 0) -> ExpeditionPredator:
	var creature := Predator.new()
	creature.setup(navigation.terrain.surface(point), group, kind, variation)
	creature.visible = light.sample(creature.position) > 0.065
	add_child(creature)
	creatures.append(creature)
	if picker != null: picker.register_actor(creature)
	if occluded_units != null: occluded_units.register_actor(creature)
	return creature

func rebuild_navigation() -> void:
	navigation.terrain.structures.assign(structures.filter(func(building): return building.kind in ["platform", "ramp"]))
	update_fortifications()
	var blockers: Array[Dictionary] = rocks.duplicate()
	for b in structures:
		if not b.complete: continue
		if b.kind == "gate" and b.gate_open: continue
		if b.kind in ["platform", "ramp"]: continue
		var auto_gate: bool = b.kind == "gate" and b.powered and not b.gate_locked
		for tile in Footprints.points(b):
			blockers.append({"position": tile, "radius": Terrain.CELL * 0.58, "auto_gate": auto_gate, "owner": b})
		if b.kind in ["wall", "gate"]:
			for offset in b.connections: blockers.append({"position": b.position, "end": b.position + offset * 0.5, "radius": 0.32, "auto_gate": auto_gate})
	navigation.rebuild(blockers)
	for unit in units:
		if unit.moving() and navigation.affects_path(unit.position, unit.path, unit.path_index): unit.travel(unit.goal, navigation)
	for creature in creatures:
		if navigation.affects_path(creature.position, creature.path, creature.path_index): creature.path.clear(); creature.repath = 0

func rebuild_light() -> void:
	light.sources.clear()
	for b in structures:
		if not b.complete or b.hp <= 0: continue
		if b.kind == "core":
			light.add_source(b.position, 4, Vector3.ZERO, -1, 0.2, false)
			if b.powered and b.enabled: light.add_source(b.position, b.lamp.omni_range, Vector3.ZERO, -1, minf(1.0, b.lamp.light_energy))
		if b.kind == "floodlight" and b.powered and b.enabled: light.add_source(b.position, 13)
	for unit in units:
		if unit.aboard != null or unit.hp <= 0: continue
		if unit.is_vehicle():
			light.add_source(unit.position, 4, Vector3.ZERO, -1, 0.2, false)
			if unit.has_driver() and unit.battery > 0:
				light.add_source(unit.position, 5)
				light.add_source(unit.position, 18, unit.facing, cos(deg_to_rad(52)))
		else: light.add_source(unit.position, 2.6, Vector3.ZERO, -1, 0.45, false)
	for wreck in wrecks:
		light.add_source(wreck.node.position, 4, Vector3.ZERO, -1, float(wreck.life) / 30.0 * 0.2, false)

	resource_fields.discover(self)

func refresh_visual_lights() -> void:
	# The GPU evaluates the same light shapes continuously; no low-frequency fog texture.
	var positions := PackedVector4Array()
	var directions := PackedVector4Array()
	positions.resize(64)
	directions.resize(64)
	var count := mini(64, light.sources.size())
	for i in range(count):
		var source := light.sources[i]
		positions[i] = Vector4(source.position.x, source.position.z, source.radius, source.cone)
		directions[i] = Vector4(source.direction.x, source.direction.z, source.intensity, 0)
	for mat in fog_materials:
		mat.set_shader_parameter("light_count", count)
		mat.set_shader_parameter("light_data", positions)
		mat.set_shader_parameter("light_directions", directions)

func update_camera() -> void:
	# Preserve world-to-screen scale while a larger window reveals more terrain.
	camera.size = camera_zoom * get_viewport().get_visible_rect().size.y / 800.0
	var distance := Vector2(46, 32).length()
	var horizontal := distance * cos(camera_pitch)
	camera.position = focus + Vector3(sin(camera_yaw) * horizontal, distance * sin(camera_pitch), cos(camera_yaw) * horizontal)
	camera.look_at(focus)

func camera_pan_vector(direction: Vector2) -> Vector3:
	return Vector3(direction.x, 0, direction.y).rotated(Vector3.UP, camera_yaw).normalized()

func orbit_camera(motion: Vector2) -> void:
	camera_yaw = wrapf(camera_yaw - motion.x * 0.006, -PI, PI)
	camera_pitch = clampf(camera_pitch + motion.y * 0.004, deg_to_rad(35), deg_to_rad(75))
	update_camera()

func reset_camera() -> void:
	camera_yaw = 0; camera_pitch = atan2(46.0, 32.0); camera_zoom = 48
	focus = HOME + Vector3(7, 0, -2)
	update_camera()

func _process(dt: float) -> void:
	if started and not paused and not ended:
		advance_movement(minf(dt, 0.2))
		accumulator = minf(accumulator + dt, TICK * 5)
		while accumulator >= TICK:
			accumulator -= TICK
			simulation_tick(TICK, false)
			if ended: break
		rebuild_light()
		refresh_visual_lights()
	if started:
		if Input.is_physical_key_pressed(KEY_COMMA): camera_yaw = wrapf(camera_yaw + dt * deg_to_rad(60), -PI, PI)
		if Input.is_physical_key_pressed(KEY_PERIOD): camera_yaw = wrapf(camera_yaw - dt * deg_to_rad(60), -PI, PI)
		var pan := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): pan.z -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): pan.z += 1
		if Input.is_physical_key_pressed(KEY_LEFT): pan.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): pan.x += 1
		focus += camera_pan_vector(Vector2(pan.x, pan.z)) * dt * camera.size * 0.45
		focus.x = clampf(focus.x, -100, 100)
		focus.z = clampf(focus.z, -88, 88)
		update_camera()
	var terrain := terrain_raycast(get_viewport().get_mouse_position())
	mouse_world = navigation.terrain.surface(Hex.snap(terrain.position, Terrain.CELL)) if not terrain.is_empty() else Vector3.INF
	ghost.visible = not build_kind.is_empty() and started and not ended and mouse_world.is_finite()
	if ghost.visible:
		ghost.position = mouse_world + Vector3.UP * 0.12
		ghost.rotation.y = atan2(-Terrain.direction(placement_direction).z, Terrain.direction(placement_direction).x) if build_kind == "ramp" else 0.0
		ghost_mat.albedo_color = Color(MINT if valid_site(build_kind, mouse_world) else Color("ed8278"), 0.4)
	if wall_placement.active:
		if build_kind != "wall" or not started or ended or selected_engineers().is_empty(): wall_placement.cancel()
		else:
			wall_placement.update_preview(self, mouse_world)
			ghost.visible = false
	update_power_placement()
	if notice_time > 0:
		notice_time -= dt
		if notice_time <= 0: message.text = ""
	refresh_ui()
	update_focus_lines()
	if occluded_units != null: occluded_units.sync(light)

func advance_movement(dt: float) -> void:
	gate_passage.update(self, dt)
	for unit in units: unit.escort_speed_limit = INF
	for unit in units:
		if unit.hp <= 0 or unit.aboard != null or unit.order not in ["escort", "convoy_escort"]: continue
		if is_instance_valid(unit.target) and unit.target is ExpeditionUnit and unit.target.is_vehicle():
			unit.target.escort_speed_limit = minf(unit.target.escort_speed_limit, float(Rules.UNITS[unit.kind].speed))
	complex_commands.exploration.apply_speed_limits(self)
	tactical_groups.apply_speed_limits(self)
	for unit in units: unit.tick_move(dt)
	soft_spacing.apply(units, navigation, dt)
	for creature in creatures: creature.move_tick(dt)
	for unit in units:
		if unit.aboard == null: unit.position.y = navigation.terrain.height(unit.position)
	for creature in creatures: creature.position.y = navigation.terrain.height(creature.position)

func simulation_tick(dt: float, advance_motion: bool = true) -> void:
	if ended: return
	if advance_motion: advance_movement(dt)
	elapsed += dt; tick_number += 1
	sensor_activity = maxf(0, sensor_activity - dt)
	economy.recalculate(structures); power.tick(structures, economy, dt)
	if economy.gas <= 15 and power.fuel_rate > 0 and not low_fuel_warned:
		low_fuel_warned = true; notify("Methane reserve low / send engineers to the methane signal and deliver to a Methane Tank")
	elif economy.gas >= 30: low_fuel_warned = false
	vehicles.tick(self, dt)
	tactics.tick(self, dt)
	tactical_groups.tick(self, dt)
	for unit in units: process_order(unit, dt)
	complex_commands.tick(self, dt)
	for b in structures:
		b.cooldown = maxf(0, b.cooldown - dt)
		if b.complete and not b.queue.is_empty():
			b.production_progress += dt
			var kind: String = b.queue[0]
			if b.production_progress >= float(Rules.UNITS[kind].time):
				var spawn_point := free_spawn(b.position)
				add_unit(kind, spawn_point); b.queue.pop_front(); b.production_progress = 0
				notify("%s ready%s" % [Rules.title(kind), " / needs a driver" if kind in ["jeep", "scout"] else ""])
	var operating_light := false
	for b in structures:
		if b.kind == "floodlight" and b.complete and b.powered and b.position.distance_to(layout.fields[0].position) < 12: operating_light = true
	if operating_light and not outpost_established:
		outpost_established = true; notify("Mining perimeter illuminated / order an engineer to gather materials")
	if outpost_established and not director.outpost_group_created:
		director.outpost_group_created = true; director.add_group(layout.fields[0].position, 1)
		for i in range(4): director.spawn_member(self, director.groups[-1], true)
	if tick_number % 4 == 0: director.tick(self, dt * 4)
	mission.tick(self, dt)
	rebuild_light(); combat_tick(dt); cleanup_dead(); rebuild_light()
	for creature in creatures: creature.visible = light.sample(creature.position) > 0.065
	mission.hive.visible = mission.hive_discovered and light.sample(mission.hive.position) > 0.05
	if tick_number % 5 == 0: update_scanner_contacts(); update_power_lines()
	for i in range(wrecks.size() - 1, -1, -1):
		wrecks[i].life -= dt
		if float(wrecks[i].life) <= 0:
			if picker != null: picker.remove_owner(wrecks[i].node)
			wrecks[i].node.queue_free(); wrecks.remove_at(i)
	update_effects(dt); check_mission()

func issue_order(unit: ExpeditionUnit, order: String, point: Vector3, target: Node3D = null, append: bool = false) -> bool:
	return tactics.issue(self, unit, order, point, target, append)

func set_order(unit: ExpeditionUnit, order: String, point: Vector3, target: Node3D = null) -> bool:
	if unit.aboard != null: return false
	complex_commands.interrupt(unit)
	tactical_groups.interrupt(unit)
	if unit.is_vehicle() and not unit.has_driver():
		notify("%s needs a driver / board infantry first" % Rules.title(unit.kind)); return false
	unit.order = order; unit.target = target; unit.work_clock = 0
	if not unit.travel(point, navigation): unit.order = "idle"; notify("No clear route to that location"); return false
	return true

func process_order(unit: ExpeditionUnit, dt: float) -> void:
	if unit.aboard != null: return
	tactics.advance_queue(self, unit)
	var target := unit.target
	if unit.order in ["build", "repair", "board", "escort", "stock", "deliver", "deposit", "to_carrier", "close_gate"] and not is_instance_valid(target): unit.order = "idle"; return
	if unit.order in ["build", "repair", "close_gate", "stock", "deliver", "deposit"] and not unit.moving():
		var reach := 4.2 if unit.order in ["stock", "deliver", "deposit"] else 4.0
		if (Footprints.reach(target, unit.position) if target is ExpeditionStructure else unit.position.distance_to(target.position)) >= reach: unit.travel(target.position, navigation)
	if unit.order in ["board", "escort"]:
		unit.work_clock -= dt
		if unit.work_clock <= 0:
			unit.work_clock = 0.8
			var lane := float(unit.formation_slot % 3) - 1.0
			var rank := float((unit.formation_slot / 3) % 2)
			var point: Vector3 = target.position if unit.order == "board" else target.position - target.facing * (2.5 + rank) + target.facing.cross(Vector3.UP) * lane * 1.5
			if unit.goal.distance_to(point) > 1.5 or not unit.moving(): unit.travel(point, navigation)
		if unit.order == "board" and unit.position.distance_to(target.position) < 3.8:
			if target.board(unit): selected.erase(unit); refresh_context_commands()
			else: unit.order = "escort"
	elif unit.order == "build" and Footprints.reach(target, unit.position) < 4:
		unit.path.clear()
		if target.complete: continue_maintenance(unit, target); return
		target.progress += dt / float(Rules.STRUCTURES[target.kind].time)
		if target.progress >= 1:
			if complete_construction(target): continue_maintenance(unit, target)
			else: target.progress = 0.99
		target.update_visual()
	elif unit.order == "repair" and Footprints.reach(target, unit.position) < 4:
		unit.path.clear(); unit.work_clock += dt
		if unit.work_clock >= 1:
			unit.work_clock = 0
			if target.hp >= float(Rules.STRUCTURES[target.kind].hp): continue_maintenance(unit, target)
			elif economy.spend({"minerals": 1}): target.hp = minf(float(Rules.STRUCTURES[target.kind].hp), target.hp + 8)
	elif unit.order == "harvest": process_harvest(unit, dt)
	elif unit.order == "to_carrier":
		if unit.position.distance_to(target.position) < 3.8:
			unit.path.clear(); transfer_cargo(unit, target)
			if unit.cargo_total() > 0: send_to_receiver(unit)
			else: set_order(unit, "harvest", unit.harvest_origin)
		else:
			unit.work_clock -= dt
			if unit.work_clock <= 0: unit.travel(target.position, navigation); unit.work_clock = 1
	elif unit.order in ["stock", "deliver", "deposit"] and unit.position.distance_to(target.position) < 4.2:
		unit.path.clear(); deposit_cargo(unit, target)
		if unit.order == "deposit" and unit.cargo_total() == 0: set_order(unit, "harvest", unit.harvest_origin)
		elif unit.cargo_total() == 0: unit.order = "idle"
	elif unit.order == "close_gate" and unit.position.distance_to(target.position) < 4:
		unit.path.clear(); unit.work_clock += dt
		if unit.work_clock >= 2 and set_gate(target, false, true): unit.order = "idle"
	elif unit.order == "move" and not unit.moving(): unit.order = "idle"

func complete_construction(building: ExpeditionStructure) -> bool:
	if building.complete: return true
	var clearance: Dictionary = construction_clearance.plan(self, building)
	building.waiting_for_clearance = not clearance.ready
	if not clearance.ready: return false
	var destinations: Dictionary = {}
	for actor: ExpeditionUnit in clearance.moves:
		if actor.moving(): destinations[actor] = actor.goal
		actor.position = clearance.moves[actor]
		soft_spacing.velocities.erase(actor.get_instance_id())
		actor.motion_velocity = Vector3.ZERO
		if not actor.moving(): actor.path.clear(); actor.goal = actor.position
	for actor in units:
		if actor.aboard != null: actor.position = actor.aboard.position
	building.complete = true; building.progress = 0
	if building == mission.beacon: building.hp = float(Rules.STRUCTURES[building.kind].hp)
	rebuild_navigation()
	for actor: ExpeditionUnit in destinations: actor.travel(destinations[actor], navigation)
	economy.recalculate(structures); power.tick(structures, economy, 0); rebuild_light()
	building.update_visual(); notify("%s complete" % Rules.title(building.kind))
	return true

func continue_maintenance(unit: ExpeditionUnit, building: ExpeditionStructure) -> void:
	if not unit.order_queue.is_empty(): unit.order = "idle"; unit.path.clear(); return
	var next := complex_commands.nearby_work(self, building, unit.position)
	if next != null and set_order(unit, "repair" if next.complete else "build", next.position, next): return
	unit.order = "idle"; unit.path.clear(); unit.target = null
	unit.goal = unit.position; unit.work_clock = 0

func consume_materials(_point: Vector3, cost: int) -> bool:
	return economy.spend({"minerals": cost})

func valid_site(kind: String, point: Vector3) -> bool:
	if not Rules.STRUCTURES.has(kind) or kind == "core": return false
	point = navigation.terrain.surface(point)
	if not Terrain.contains(point, 1) or light.sample(point) < 0.055: return false
	if kind in ["platform", "ramp"] and point.y > 0.1: return false
	if kind not in ["platform", "ramp"]:
		if minf(absf(point.y), absf(point.y - Terrain.LEVEL)) > 0.1: return false
		for i in range(6):
			if absf(navigation.terrain.height(point + Terrain.direction(i) * (Terrain.CELL * 0.75)) - point.y) > 0.1: return false
	if kind == "ramp":
		var forward := Terrain.direction(placement_direction)
		var footprint := [Hex.to_axial(point, Terrain.CELL), Hex.to_axial(point - forward * Terrain.SPACING, Terrain.CELL)]
		for b in structures:
			if footprint.has(Hex.to_axial(b.position, Terrain.CELL)): return false
		for rock in rocks:
			if rock.has("cell") and footprint.has(rock.cell): return false
		if navigation.terrain.height(point + forward * (Terrain.SPACING * 0.5 + 0.2)) < Terrain.LEVEL - 0.1: return false
		for i in range(8):
			var sample := point + forward * (-Terrain.SPACING * 1.5 + float(i) / 7 * Terrain.SPACING * 1.9)
			if not Terrain.contains(sample, 1) or navigation.terrain.height(sample) > 0.1: return false
			for rock in rocks:
				if sample.distance_to(rock.position) < float(rock.radius) + 0.6: return false
			for b in structures:
				if b.kind not in ["platform", "ramp"] and sample.distance_to(b.position) < 2: return false
	var occupied := Footprints.cells(kind, point, placement_direction)
	for cell in occupied:
		var tile := Hex.to_world(cell, Terrain.CELL)
		if not Terrain.contains(tile, 1) or absf(navigation.terrain.height(tile) - point.y) > 0.1: return false
		for b in structures:
			if b.kind == "platform" and kind not in ["platform", "ramp"]: continue
			if absf(b.position.y - point.y) < 0.2 and Footprints.cells(b.kind, b.position, b.build_direction).has(cell): return false
		for rock in rocks:
			if rock.get("cell") == cell: return false
	if kind == "extractor":
		var resource := resource_at(point)
		if resource.is_empty() or not resource.discovered or resource.remaining <= 0: return false
	elif kind not in ["platform", "ramp"] and not resource_at(point).is_empty(): return false
	return true

func order_build(kind: String, point: Vector3) -> ExpeditionStructure:
	var engineers := selected_engineers()
	if engineers.is_empty(): notify("Select an engineer on foot to build"); return null
	point = navigation.terrain.surface(Hex.snap(point, Terrain.CELL))
	if not valid_site(kind, point): notify("Ramp: high end must join raised ground / T rotates" if kind == "ramp" else "Use illuminated, clear terrain"); return null
	if not economy.spend(Rules.cost(kind)): notify("Insufficient banked materials or methane"); return null
	var site := add_structure(kind, point, false); site.funded = true
	rebuild_navigation(); issue_order(engineers[0], "build", point, site, Input.is_physical_key_pressed(KEY_SHIFT))
	notify("%s funded from global reserves / engineer en route" % Rules.title(kind))
	return site

func order_wall_line(start: Vector3, endpoint: Vector3) -> int:
	if not start.is_finite() or not endpoint.is_finite(): return 0
	var engineers := selected_engineers()
	if engineers.is_empty(): notify("Select an engineer on foot to build"); return 0
	var sites: Array[ExpeditionStructure] = []
	for point in Hex.line(start, endpoint, Terrain.CELL):
		point = navigation.terrain.surface(point)
		if not valid_site("wall", point): continue
		if not economy.spend(Rules.cost("wall")): break
		var site := add_structure("wall", point, false); site.funded = true
		sites.append(site)
	if sites.is_empty(): notify("No affordable walls on illuminated, clear terrain"); return 0
	# Keep the engineer working from the beginning; nearby maintenance chains the line.
	rebuild_navigation()
	for i in range(sites.size()):
		issue_order(engineers[0], "build", sites[i].position, sites[i], i > 0 or Input.is_physical_key_pressed(KEY_SHIFT))
	notify("%d wall segments funded / %d materials / blocked cells skipped" % [sites.size(), sites.size() * int(Rules.cost("wall").minerals)])
	return sites.size()

func visible_target(point: Vector3, radius: float) -> ExpeditionPredator:
	var best: ExpeditionPredator
	var distance := radius * radius
	for creature in creatures:
		if creature.hp <= 0: continue
		var candidate := point.distance_squared_to(creature.position)
		if candidate >= distance or light.sample(creature.position) < 0.065: continue
		if navigation.can_see(point, creature.position):
			distance = candidate
			best = creature
	return best

func combat_tick(_dt: float) -> void:
	for unit in units:
		if unit.kind not in ["marine", "flamer"] or unit.aboard != null or unit.cooldown > 0: continue
		var enemy: Node3D = unit.combat_target if tactics.valid(unit.combat_target) else visible_target(unit.position, 5.5 if unit.kind == "flamer" else 11)
		if enemy != null and (unit.position.distance_to(enemy.position) > (5.5 if unit.kind == "flamer" else 11) or not navigation.can_see(unit.position, enemy.position) or (enemy is ExpeditionPredator and light.sample(enemy.position) < 0.065)): enemy = null
		if enemy != null:
			unit.focus_target = enemy
			if unit.kind == "flamer":
				if not enemy is ExpeditionPredator: enemy.hp -= 18
				for other in creatures:
					if other.position.distance_to(enemy.position) < 2.7 and light.sample(other.position) > 0.065 and navigation.can_see(unit.position, other.position): other.hurt(18)
			else:
				if enemy is ExpeditionPredator: enemy.hurt(10)
				else: enemy.hp -= 10
			unit.cooldown = 0.85 if unit.kind == "flamer" else 0.65
			shot(unit.position + Vector3.UP * 1.2, enemy.position + Vector3.UP * 0.7, Color("f28a42") if unit.kind == "flamer" else AMBER)
	turret_system.tick(self, _dt)
	for creature in creatures:
		var target := creature.target
		if creature.hp <= 0 or not is_instance_valid(target) or target.hp <= 0 or creature.cooldown > 0 or creature.state not in ["probing", "assault", "hunting"]: continue
		if not director.attack_allowed(self, target): continue
		if target is ExpeditionUnit and target.aboard != null: continue
		if creature.position.distance_to(target.position) < 3 and navigation.can_see(creature.position, target.position):
			target.hp -= float(Rules.PREDATORS[creature.kind].damage); creature.cooldown = float(Rules.PREDATORS[creature.kind].attack_delay)
			shot(creature.position + Vector3.UP * 0.7, target.position + Vector3.UP, Color("d66b82"))

func cleanup_dead() -> void:
	var changed := false
	for i in range(creatures.size() - 1, -1, -1):
		if creatures[i].hp <= 0:
			if picker != null: picker.remove_owner(creatures[i])
			creatures[i].queue_free(); creatures.remove_at(i)
	for i in range(units.size() - 1, -1, -1):
		var unit := units[i]
		if unit.hp > 0: continue
		mission.drop(unit)
		complex_commands.interrupt(unit)
		if picker != null: picker.remove_owner(unit)
		if unit.is_vehicle():
			var occupants: Array[ExpeditionUnit] = unit.passengers.duplicate()
			if unit.has_driver(): occupants.push_front(unit.driver)
			for j in range(occupants.size()):
				unit.disembark(occupants[j], free_spawn(unit.position + Vector3(2 + j, 0, 1)))
				occupants[j].hp -= 30
			unit.update_lights(); unit.indicator.visible = false; unit.visual.rotation.z = 0.18
			wrecks.append({"node": unit, "life": 30.0})
			if picker != null: picker.register_occluder(unit)
		else:
			if is_instance_valid(unit.aboard):
				var vehicle := unit.aboard
				vehicle.disembark(unit, vehicle.position)
			unit.queue_free()
		selected.erase(unit); units.remove_at(i); notify("%s lost" % Rules.title(unit.kind))
	for i in range(structures.size() - 1, -1, -1):
		var b := structures[i]
		if b.hp > 0: continue
		if b == mission.beacon:
			b.hp = 1; b.complete = false; b.progress = 0; mission.extraction = 0; b.update_visual(); changed = true; continue
		if picker != null: picker.remove_owner(b)
		selected.erase(b); structures.remove_at(i); b.queue_free(); changed = true
		notify("%s destroyed" % Rules.title(b.kind))
	if changed: rebuild_navigation(); economy.recalculate(structures); power.tick(structures, economy, 0)

func check_mission() -> void:
	if ended: return
	if not is_instance_valid(core) or core.hp <= 0 or not structures.has(core): finish(false, "Command Center destroyed.")

func selected_vehicles() -> Array[ExpeditionUnit]:
	var result: Array[ExpeditionUnit] = []
	for actor in selected:
		if is_instance_valid(actor) and actor is ExpeditionUnit and actor.is_vehicle() and actor.hp > 0: result.append(actor)
	return result

func toggle_auto_recharge() -> void:
	var vehicles_selected := selected_vehicles()
	if vehicles_selected.is_empty(): return
	var enable := not vehicles_selected.all(func(unit): return unit.auto_recharge)
	for vehicle in vehicles_selected: vehicle.auto_recharge = enable
	vehicles.tick(self, 0); refresh_ui()

func selected_jeep() -> ExpeditionUnit:
	for actor in selected:
		if is_instance_valid(actor) and actor is ExpeditionUnit and actor.is_vehicle() and actor.hp > 0: return actor
	return null

func selected_infantry() -> Array[ExpeditionUnit]:
	var result: Array[ExpeditionUnit] = []
	for actor in selected:
		if is_instance_valid(actor) and actor is ExpeditionUnit and not actor.is_vehicle() and actor.aboard == null and actor.hp > 0: result.append(actor)
	return result

func selected_engineers() -> Array[ExpeditionUnit]:
	var result: Array[ExpeditionUnit] = []
	for unit in selected_infantry():
		if unit.kind == "engineer": result.append(unit)
	return result

func board_squad() -> void:
	var vehicle := selected_jeep()
	var infantry := selected_infantry()
	if vehicle == null and not infantry.is_empty(): vehicle = nearest_vehicle(infantry[0].position, true)
	if vehicle == null: notify("Select infantry or a vehicle with a free seat"); return
	complex_commands.interrupt(vehicle)
	vehicle.path.clear(); vehicle.order = "idle"
	if not infantry.is_empty():
		for unit in infantry: issue_order(unit, "board", vehicle.position, vehicle, Input.is_physical_key_pressed(KEY_SHIFT))
		return
	var seats := vehicle.seat_capacity() - vehicle.occupied_seats()
	for unit in units:
		if seats <= 0: break
		if not unit.is_vehicle() and unit.aboard == null and unit.hp > 0 and unit.position.distance_to(vehicle.position) < 24:
			issue_order(unit, "board", vehicle.position, vehicle, Input.is_physical_key_pressed(KEY_SHIFT)); seats -= 1
	notify("First boarder drives; remaining seats carry passengers")

func unload() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	complex_commands.interrupt(vehicle); tactical_groups.interrupt(vehicle)
	vehicle.path.clear(); vehicle.order = "idle"
	if not vehicle.passengers.is_empty():
		var passengers: Array[ExpeditionUnit] = vehicle.passengers.duplicate()
		for i in range(passengers.size()): vehicle.disembark(passengers[i], free_spawn(vehicle.position + Vector3((i % 2) * 2 - 1, 0, 3 + i)))
		notify("Passengers dismounted / driver stays aboard; U again to unload driver")
	elif vehicle.has_driver():
		vehicle.disembark(vehicle.driver, free_spawn(vehicle.position + Vector3(2, 0, 2)))
		notify("Driver dismounted / headlights off; emergency beacon remains")
	# Keep the vehicle selected so a second U always acts on the same vehicle.
	select_actor(vehicle); rebuild_light(); refresh_visual_lights()

func load_nearest() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	var loaded := 0
	for unit in units:
		if not unit.is_vehicle() and unit.aboard == null and unit.position.distance_to(vehicle.position) < 5: loaded += transfer_cargo(unit, vehicle)
	notify("Collected %d carried resources from nearby personnel" % loaded)

func return_home() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	var receiver := find_receiver(vehicle.position, "minerals" if vehicle.cargo > 0 else "gas", true)
	if receiver != null: issue_order(vehicle, "deliver", receiver.position, receiver, Input.is_physical_key_pressed(KEY_SHIFT))

func stock_depot() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	var receiver := find_receiver(vehicle.position, "minerals" if vehicle.cargo > 0 else "gas")
	if receiver != null: issue_order(vehicle, "stock", receiver.position, receiver, Input.is_physical_key_pressed(KEY_SHIFT))
	else: notify("Build a Material Depot or Methane Tank for that resource")

func escort() -> void:
	for actor in selected_infantry():
		var vehicle := nearest_vehicle(actor.position)
		if vehicle != null: issue_order(actor, "escort", vehicle.position, vehicle, Input.is_physical_key_pressed(KEY_SHIFT))


func shot(a: Vector3, b: Vector3, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, Visual.material(color, true))
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	add_child(node)
	effects.append({"node": node, "time": 0.16})

func update_effects(dt: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		effects[i].time -= dt
		if float(effects[i].time) <= 0:
			effects[i].node.queue_free()
			effects.remove_at(i)

func play_cue(frequency: float, duration: float, volume: float) -> void:
	if not audio_enabled or DisplayServer.get_name() == "headless": return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(int(duration * 22050) * 2)
	for i in range(samples.size() / 2):
		var t := float(i) / 22050
		var sample := int(sin(t * frequency * TAU) * (1.0 - t / duration) * volume * 32767)
		samples.encode_s16(i * 2, sample)
	stream.data = samples
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

func camera_plane_point(screen: Vector2) -> Vector3:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return point if point != null else Vector3.ZERO

func terrain_raycast(screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * camera.far, TERRAIN_COLLISION_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query)

func ground_point(screen: Vector2) -> Vector3:
	var hit := terrain_raycast(screen)
	return hit.position if not hit.is_empty() else Vector3.INF

func pick(screen: Vector2) -> Node3D:
	return await picker.pick_actor(screen)

func setup_picking() -> void:
	picker = GPUPicker.new(); add_child(picker); picker.setup(camera)
	for actor in units: picker.register_actor(actor)
	for actor in structures: picker.register_actor(actor)
	for creature in creatures: picker.register_actor(creature)
	for child in get_children():
		if child is Node3D and child.has_meta("pick_occluder"): picker.register_occluder(child)
	for resource in resource_meshes: picker.register_occluder(resource)
	focus_overlay = FocusOverlay.new(); add_child(focus_overlay); focus_overlay.setup()
	picker.warm_up()

func update_focus_lines() -> void:
	if focus_overlay != null: focus_overlay.update_focus(selected, light)

func select_click(screen: Vector2, append: bool, request: RefCounted = null, serial: int = -1) -> void:
	if request == null:
		click_serial += 1; serial = click_serial; request = picker.request_pick(screen)
	var actor: Node3D = await picker.resolve_pick(request)
	if serial != click_serial: return
	if actor == null:
		var hit := terrain_raycast(screen)
		if hit.is_empty(): return
		selected_resource = resource_at(hit.position)
		if not selected_resource.is_empty() and not selected_resource.discovered: selected_resource = {}
	else: selected_resource = {}
	select_actor(actor, append)

func select_double_click(screen: Vector2, append: bool) -> void:
	click_serial += 1
	var serial := click_serial
	var request: RefCounted = picker.request_pick(screen)
	# The second press selects immediately; its release must not become a box
	# selection or apply an older mouse-down pick over the chosen unit.
	selecting = false; pressed_pick = null
	selection_box.active = false; selection_box.queue_redraw()
	var actor: Node3D = await picker.resolve_pick(request)
	if serial != click_serial or not started or ended: return
	if not actor is ExpeditionUnit or actor.hp <= 0 or actor.aboard != null: return
	build_kind = ""; repair_mode = false; expedition_mode = false
	ghost.visible = false
	if not append: selected.clear()
	if not selected.has(actor): selected.append(actor)
	var screen_rect := get_viewport().get_visible_rect()
	for unit in units:
		if unit.kind != actor.kind or unit.hp <= 0 or unit.aboard != null or not unit.is_visible_in_tree(): continue
		var center := unit.global_position + Vector3.UP
		if camera.is_position_behind(center) or not screen_rect.has_point(camera.unproject_position(center)): continue
		if not selected.has(unit): selected.append(unit)
	update_indicators(); update_power_placement()

func build_click(screen: Vector2) -> void:
	click_serial += 1
	var serial := click_serial
	var kind := build_kind
	var actor := await pick(screen)
	if serial != click_serial or kind != build_kind: return
	if actor != null and not (actor is ExpeditionStructure and actor.kind in ["platform", "ramp"] and actor.complete):
		build_kind = ""; select_actor(actor); update_power_placement(); return
	var terrain := terrain_raycast(screen)
	if not terrain.is_empty() and order_build(kind, terrain.position) != null and not Input.is_physical_key_pressed(KEY_SHIFT): build_kind = ""

func repair_click(screen: Vector2) -> void:
	click_serial += 1
	var serial := click_serial
	var actor := await pick(screen)
	if serial != click_serial or not repair_mode: return
	if actor is ExpeditionStructure and actor.complete and actor.hp < float(Rules.STRUCTURES[actor.kind].hp):
		for engineer in selected_engineers(): issue_order(engineer, "repair", actor.position, actor, Input.is_physical_key_pressed(KEY_SHIFT))
		repair_mode = false
	elif actor != null:
		repair_mode = false; select_actor(actor)
	else: notify("Click a damaged structure to repair, or right click to cancel")


func select_actor(actor: Node3D, append: bool = false) -> void:
	if actor is ExpeditionPredator and (not actor.visible or light.sample(actor.position) < 0.065): return
	if not append: selected.clear()
	if actor != null and not selected.has(actor): selected.append(actor)
	update_indicators()

func update_indicators() -> void:
	click_serial += 1
	wall_placement.cancel()
	expedition_mode = false; tactical_mode = ""
	for unit in units: unit.indicator.visible = selected.has(unit) and unit.aboard == null
	for b in structures + ([mission.hive] if is_instance_valid(mission.hive) else []):
		b.indicator.visible = selected.has(b)
		for child in b.get_children():
			if child is Label3D and child.get_meta("selection_label", false): child.visible = selected.has(b)
	refresh_context_commands()
	update_focus_lines()

func choose_expedition(mining: bool = false) -> void:
	click_serial += 1; wall_placement.cancel()
	var crew := complex_commands.expedition_selection(selected)
	if not (complex_commands.mining_available(crew) if mining else complex_commands.expedition_available(crew)):
		notify("Mining needs at least one working engineer and separate vehicle drivers" if mining else "Select infantry or crewed vehicles"); return
	expedition_mode = not expedition_mode or mining_mode != mining
	mining_mode = mining; build_kind = ""; repair_mode = false; tactical_mode = ""
	update_power_placement(); refresh_context_commands()
	notify("MINING / choose a surveyed patch or a material depot / methane tank" if mining else "EXPLORATION / choose reachable terrain")

func expedition_click(screen: Vector2) -> void:
	click_serial += 1
	var serial := click_serial
	var crew: Array = complex_commands.expedition_selection(selected)
	var actor := await pick(screen)
	if serial != click_serial or not expedition_mode: return
	var terrain := terrain_raycast(screen)
	if terrain.is_empty(): return
	var resource := resource_at(terrain.position)
	if mining_mode:
		if actor is ExpeditionStructure and actor.kind in ["depot", "gas_tank", "core"]:
			var nearest := INF
			for patch in resource_nodes:
				if not patch.discovered or patch.remaining <= 0 or (actor.kind != "core" and patch.kind != ("minerals" if actor.kind == "depot" else "gas")): continue
				var distance: float = patch.position.distance_squared_to(actor.position)
				if distance < nearest: resource = patch; nearest = distance
		if resource.is_empty() or not resource.discovered or resource.remaining <= 0:
			notify("Mining requires a surveyed patch or a receiver with a surveyed field"); return
	else: resource = {}
	for unit in crew:
		if unit is ExpeditionUnit: unit.order_queue.clear()
	if complex_commands.start_expedition(self, crew, resource, terrain.position): expedition_mode = false
	refresh_context_commands(); update_focus_lines()

func choose_tactical(mode: String) -> void:
	if not tactical_groups.available(selected) and not selected.any(func(actor): return actor is ExpeditionUnit and actor.kind == "drill"): return
	tactical_mode = "" if tactical_mode == mode else mode
	expedition_mode = false; build_kind = ""; repair_mode = false
	notify(mode.capitalize() + " / choose a destination or target / Shift adds orders")

func tactical_click(screen: Vector2, append: bool) -> void:
	var mode := tactical_mode
	var ordered: Array = selected.duplicate()
	if ordered.any(func(actor): return actor is ExpeditionUnit and actor.is_vehicle() and complex_commands.is_expedition(actor)): ordered = complex_commands.expedition_selection(ordered)
	var actor := await pick(screen)
	if mode != tactical_mode: return
	var terrain := terrain_raycast(screen)
	if terrain.is_empty(): return
	var point: Vector3 = actor.position if actor != null else terrain.position
	var group_order := "attack" if mode == "attack_move" and (actor is ExpeditionPredator or actor == mission.hive) else mode
	var crew := tactical_groups.roster(ordered)
	if mode != "drill" and (crew.members.size() > 1 or not crew.vehicles.is_empty()) and tactical_groups.start(self, ordered, group_order, point, actor if group_order in ["attack", "defend"] else null, append):
		if not append and mode != "patrol": tactical_mode = ""
		return
	for unit in ordered:
		if not unit is ExpeditionUnit: continue
		if mode == "drill" and unit.kind == "drill": issue_order(unit, "drill", Hex.snap(point, Terrain.CELL), null, append)
		elif unit.kind in ["marine", "flamer"]:
			var order := "attack" if mode == "attack_move" and actor != null and (actor is ExpeditionPredator or actor == mission.hive) else mode
			issue_order(unit, order, point, actor if order in ["attack", "defend"] else null, append)
	if not append and mode != "patrol": tactical_mode = ""

func destroy_selected() -> void:
	for actor in selected.duplicate():
		if actor is ExpeditionUnit or (actor is ExpeditionStructure and actor != mission.hive): actor.hp = 0
	cleanup_dead(); check_mission(); refresh_context_commands()

func toggle_repeater() -> void:
	for actor in selected:
		if actor is ExpeditionStructure and actor.kind == "repeater": actor.enabled = not actor.enabled
	power.tick(structures, economy, 0); rebuild_light(); update_power_lines()

func contextual_order(screen: Vector2, append: bool = false) -> void:
	click_serial += 1
	var serial := click_serial
	var ordered: Array[Node3D] = selected.duplicate()
	var actor := await pick(screen)
	if serial != click_serial: return
	if not append:
		for member in ordered:
			if member is ExpeditionUnit: member.order_queue.clear()
	var point := Vector3.ZERO
	var resource: Dictionary = {}
	if actor != null: point = actor.position
	else:
		var terrain := terrain_raycast(screen)
		if terrain.is_empty(): return
		point = terrain.position; resource = resource_at(point)
	if not append and actor is ExpeditionUnit and complex_commands.join_member(self, ordered, actor):
		refresh_context_commands(); update_focus_lines(); return
	if not append and actor == null and complex_commands.join_resource(self, ordered, resource):
		refresh_context_commands(); update_focus_lines(); return
	# Only an explicit resource order can retask an expedition implicitly. A plain
	# terrain right-click is a direct move and permanently interrupts auto-scouting.
	if not append and actor == null and not resource.is_empty() and resource.discovered and resource.remaining > 0 and ordered.any(func(unit): return complex_commands.is_expedition(unit)):
		complex_commands.start_expedition(self, complex_commands.expedition_selection(ordered), resource, point)
		refresh_context_commands(); update_focus_lines(); return
	var mixed_crew := ordered.any(func(unit): return unit is ExpeditionUnit and not unit.is_vehicle() and unit.aboard == null)
	if not append and mixed_crew and actor != mission.hive and actor != mission.beacon and (actor == null or actor is ExpeditionStructure) and complex_commands.start(self, ordered, {}, actor as ExpeditionStructure, point):
		update_focus_lines(); return
	var index := 0
	for unit in ordered:
		if not is_instance_valid(unit) or not selected.has(unit) or not unit is ExpeditionUnit or unit.aboard != null: continue
		if actor == mission.hive or (not is_instance_valid(mission.carrier) and point.distance_to(mission.item.position) < 3 and (mission.dropped or mission.hive.hp <= 0)):
			if not unit.is_vehicle(): issue_order(unit, "take_core", mission.item.position, null, append)
		elif actor is ExpeditionPredator and unit.kind in ["marine", "flamer"]: issue_order(unit, "attack", actor.position, actor, append)
		elif actor is ExpeditionUnit and actor.is_vehicle() and not unit.is_vehicle(): issue_order(unit, "board", actor.position, actor, append)
		elif actor is ExpeditionStructure and unit.kind == "engineer" and actor.kind == "gate" and actor.gate_open and not actor.powered:
			issue_order(unit, "close_gate", actor.position, actor, append)
		elif actor is ExpeditionStructure and unit.kind == "engineer" and (not actor.complete or actor.hp < float(Rules.STRUCTURES[actor.kind].hp)):
			issue_order(unit, "build" if not actor.complete else "repair", actor.position, actor, append)
		elif actor is ExpeditionStructure and actor.kind in ["depot", "gas_tank", "core"]:
			issue_order(unit, "stock", actor.position, actor, append)
		elif not resource.is_empty() and resource.discovered and unit.kind == "engineer":
			issue_order(unit, "harvest", resource.position, null, append)
		else:
			var offset := Vector3((index % 3 - 1) * 1.5, 0, (index / 3) * 1.5) if selected.size() > 1 else Vector3.ZERO
			if actor is ExpeditionUnit and actor != unit: issue_order(unit, "escort", point + offset, actor, append)
			else: issue_order(unit, "move", point + offset, actor, append)
			index += 1
	var marker := Visual.ring(self, 1, MINT); marker.position = point; effects.append({"node": marker, "time": 1.2})
	update_focus_lines()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed: dragging = false
	if wall_placement.active:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			wall_placement.cancel(); build_kind = ""; click_serial += 1
			get_viewport().set_input_as_handled(); return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var start: Vector3 = wall_placement.start_world
			var screen: Vector2 = wall_placement.start_screen
			wall_placement.cancel()
			if started and not ended and build_kind == "wall" and get_viewport().gui_get_hovered_control() == null:
				var endpoint := ground_point(event.position)
				if endpoint.is_finite():
					if event.position.distance_to(screen) <= 8: build_click(event.position)
					elif order_wall_line(start, endpoint) > 0: build_kind = ""
			get_viewport().set_input_as_handled(); return
	if not selecting: return
	if event is InputEventMouseMotion:
		selection_box.rectangle = Rect2(select_start, event.position - select_start).abs()
		selection_box.active = event.position.distance_to(select_start) > 8
		selection_box.queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		selecting = false
		if selection_box.active:
			if not event.shift_pressed: selected.clear()
			for unit in units:
				if unit.aboard == null and selection_box.rectangle.has_point(camera.unproject_position(unit.position)) and not selected.has(unit): selected.append(unit)
			update_indicators()
		else: select_click(select_start, event.shift_pressed, pressed_pick, pressed_serial)
		pressed_pick = null
		selection_box.active = false
		selection_box.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and wall_placement != null:
		wall_placement.cancel()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not started: begin_run()
		if not started or ended: return
		match event.keycode:
			KEY_T:
				if not build_kind.is_empty(): placement_direction = (placement_direction + 1) % 6; ghost.mesh = Footprints.preview(build_kind, placement_direction) if build_kind != "ramp" else Terrain.ramp_mesh(); notify("Placement rotated / direction %d of 6" % (placement_direction + 1))
			KEY_1: numbered_command(0)
			KEY_2: numbered_command(1)
			KEY_3: numbered_command(2)
			KEY_4: numbered_command(3)
			KEY_5: numbered_command(4)
			KEY_6: numbered_command(5)
			KEY_7: numbered_command(6)
			KEY_8: numbered_command(7)
			KEY_9: numbered_command(8)
			KEY_0: numbered_command(9)
			KEY_O: toggle_gate()
			KEY_K: toggle_gate_lock()
			KEY_ESCAPE:
				if hud.help_overlay.visible: hud.toggle_help(); return
				tactical_mode = ""
				wall_placement.cancel()
				if expedition_mode: expedition_mode = false; click_serial += 1; refresh_context_commands()
				else: build_kind = ""; selected.clear(); update_indicators()
			KEY_SPACE: toggle_pause()
			KEY_F: focus = HOME
			KEY_HOME: reset_camera()
			KEY_B: board_squad()
			KEY_U: unload()
			KEY_L: load_nearest()
			KEY_J: stock_depot()
			KEY_H: return_home()
			KEY_G: escort()
			KEY_R: choose_repair()
			KEY_E: choose_expedition(false)
			KEY_M: choose_expedition(true)
			KEY_A: choose_tactical("attack_move")
			KEY_V: choose_tactical("defend")
			KEY_P: choose_tactical("patrol")
			KEY_C: choose_tactical("drill")
			KEY_DELETE: destroy_selected()
			KEY_Y: toggle_repeater()
			KEY_Z: toggle_turret_reload()
			KEY_N: toggle_auto_recharge()
			KEY_F1: hud.toggle_help()
			KEY_X: stop_selected()
	if not started or ended: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: camera_zoom = maxf(24, camera_zoom - 3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: camera_zoom = minf(190, camera_zoom + 3)
		elif event.button_index == MOUSE_BUTTON_MIDDLE: dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if tactical_mode != "": tactical_click(event.position, event.shift_pressed)
			elif expedition_mode: expedition_click(event.position)
			elif not build_kind.is_empty() or repair_mode:
				build_kind = ""; repair_mode = false; expedition_mode = false; click_serial += 1; refresh_context_commands()
			else: contextual_order(event.position, event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.double_click:
				select_double_click(event.position, event.shift_pressed)
			elif tactical_mode != "":
				tactical_click(event.position, event.shift_pressed)
			elif expedition_mode:
				expedition_click(event.position)
			elif repair_mode:
				repair_click(event.position)
			elif not build_kind.is_empty():
				if build_kind == "wall":
					var point := ground_point(event.position)
					if point.is_finite():
						wall_placement.begin(event.position, point)
						wall_placement.update_preview(self, point)
				else: build_click(event.position)
			else:
				selecting = true
				select_start = event.position
				click_serial += 1; pressed_serial = click_serial
				pressed_pick = picker.request_pick(event.position)
	if event is InputEventMouseMotion and dragging:
		if event.alt_pressed:
			orbit_camera(event.relative)
		else:
			# Drag the terrain under the cursor at any orbit angle and zoom level.
			focus += camera_plane_point(event.position - event.relative) - camera_plane_point(event.position)
			update_camera()

func choose_build(kind: String) -> void:
	click_serial += 1
	wall_placement.cancel()
	expedition_mode = false
	if selected_engineers().is_empty():
		build_kind = ""
		notify("Select an engineer on foot to open construction")
		return
	repair_mode = false
	if hud != null: hud.show_tab("build")
	build_kind = "" if build_kind == kind else kind
	if build_kind == "platform": ghost.mesh = Terrain.hex_mesh(Terrain.LEVEL)
	elif build_kind == "ramp": ghost.mesh = Terrain.ramp_mesh()
	else:
		ghost.mesh = Footprints.preview(build_kind, placement_direction)
	if build_kind == "wall": notify("Click for one wall / drag a wall line and release / right click cancels")
	elif not build_kind.is_empty(): notify("Place %s / T rotates ramp or gate / right click cancels" % Rules.title(kind))
	update_power_placement()

func update_power_placement() -> void:
	if power_placement == null: return
	var active := started and not ended and not build_kind.is_empty() and Power.is_electrical(build_kind) and mouse_world.is_finite()
	var status: Dictionary = power_placement.update_preview(build_kind if active else "", mouse_world, structures)
	if power_preview_label != null:
		power_preview_label.visible = active
		if active:
			power_preview_label.text = status.text
			power_preview_label.add_theme_color_override("font_color", power_placement.status_color())
	if active and ghost.visible and valid_site(build_kind, mouse_world): ghost_mat.albedo_color = Color(power_placement.status_color(), 0.4)
	if wall_placement.active and power_preview_label != null:
		power_preview_label.visible = true
		power_preview_label.text = "%d walls / %d materials" % [wall_placement.count, wall_placement.count * int(Rules.cost("wall").minerals)]
		power_preview_label.add_theme_color_override("font_color", MINT)

func selected_turrets() -> Array[ExpeditionStructure]:
	var result: Array[ExpeditionStructure] = []
	for actor in selected:
		if actor is ExpeditionStructure and Rules.TURRETS.has(actor.kind): result.append(actor)
	return result

func reload_selected_turrets() -> void:
	var started_reload := 0
	for turret in selected_turrets():
		if turret_system.reload(self, turret): started_reload += 1
	notify("Reloading %d turrets" % started_reload if started_reload > 0 else "Reload requires an operating ammunition turret and sufficient reserves")

func toggle_turret_reload() -> void:
	var turrets := selected_turrets()
	if turrets.is_empty(): return
	var enable := not turrets[0].auto_reload
	for turret in turrets: turret.auto_reload = enable
	refresh_context_commands()

func choose_repair() -> void:
	if selected_engineers().is_empty() and not selected_turrets().is_empty(): reload_selected_turrets(); return
	click_serial += 1
	wall_placement.cancel()
	expedition_mode = false
	if selected_engineers().is_empty(): return
	build_kind = ""
	repair_mode = not repair_mode
	if repair_mode: notify("Click a damaged structure to repair  /  supplies required nearby")

func stop_selected() -> void:
	click_serial += 1
	wall_placement.cancel()
	expedition_mode = false; tactical_mode = ""
	for actor in selected:
		if actor is ExpeditionUnit and actor.aboard == null:
			complex_commands.interrupt(actor); tactical_groups.interrupt(actor)
			actor.path.clear(); actor.order_queue.clear(); actor.combat_target = null
			actor.order = "idle"
			actor.target = null
	build_kind = ""
	repair_mode = false

func refresh_context_commands() -> void:
	if construction_panel == null: return
	var engineers := selected_engineers()
	var infantry := selected_infantry()
	var vehicle := selected_jeep()
	var factory := selected_factory()
	var gate := selected_gate()
	var has_engineer := not engineers.is_empty()
	var has_infantry := not infantry.is_empty()
	var has_vehicle := vehicle != null
	var fallback := nearest_vehicle(infantry[0].position, true) if has_infantry else null
	var visible_commands := {
		"reload_turret": selected_turrets().any(func(turret): return Rules.TURRETS[turret.kind].magazine > 0),
		"auto_reload": selected_turrets().any(func(turret): return Rules.TURRETS[turret.kind].magazine > 0),
		"mining": complex_commands.mining_available(complex_commands.expedition_selection(selected)),
		"attack": tactical_groups.available(selected), "defend": tactical_groups.available(selected), "patrol": tactical_groups.available(selected),
		"drill_order": selected.any(func(actor): return actor is ExpeditionUnit and actor.kind == "drill"),
		"destroy": selected.any(func(actor): return actor is ExpeditionUnit or (actor is ExpeditionStructure and actor != mission.hive)),
		"recharge": has_vehicle,
		"repeater": selected.any(func(actor): return actor is ExpeditionStructure and actor.kind == "repeater"),
		"drill": factory != null and factory.kind == "garage",
		"expedition": complex_commands.expedition_available(complex_commands.expedition_selection(selected)),
		"board": fallback != null or (has_vehicle and vehicle.occupied_seats() < vehicle.seat_capacity()),
		"unload": has_vehicle and vehicle.occupied_seats() > 0,
		"load": has_vehicle,
		"stock": has_vehicle and vehicle.cargo_total() > 0,
		"home": has_vehicle,
		"escort": has_infantry and nearest_vehicle(infantry[0].position) != null,
		"repair": has_engineer,
		"stop": has_vehicle or has_infantry,
		"gate": gate != null,
		"gate_lock": gate != null,
		"engineer": factory != null and factory.kind in ["barracks", "core"],
		"marine": factory != null and factory.kind == "barracks",
		"flamer": factory != null and factory.kind == "barracks",
		"scout": factory != null and Rules.PRODUCTION[factory.kind].has("scout"),
		"jeep": factory != null and factory.kind == "garage",
		"cancel_train": factory != null and not factory.queue.is_empty()
	}
	var changed := false
	if expedition_mode and not visible_commands.expedition:
		expedition_mode = false; click_serial += 1
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if expedition_mode or tactical_mode != "" else Input.CURSOR_ARROW)
	for key in context_buttons:
		var show: bool = visible_commands[key]
		changed = changed or context_buttons[key].visible != show
		context_buttons[key].visible = show
		if Rules.UNITS.has(key):
			context_buttons[key].disabled = not economy.can_spend(Rules.cost(key))
			if factory != null and Rules.PRODUCTION[factory.kind].has(key):
				context_buttons[key].text = "%d %s\n%s" % [Rules.PRODUCTION[factory.kind].find(key) + 1, Rules.title(key), cost_label(key)]
	if not selected_turrets().is_empty(): context_buttons.auto_reload.text = "Auto: %s [Z]" % ("ON" if selected_turrets()[0].auto_reload else "OFF")
	context_buttons.board.text = "Board units [B]" if has_infantry else "Board squad [B]"
	context_buttons.expedition.text = "Explore target [E]" if expedition_mode and not mining_mode else "Explore [E]"
	context_buttons.unload.text = "Unload passengers [U]" if has_vehicle and not vehicle.passengers.is_empty() else "Unload driver [U]"
	context_buttons.home.disabled = has_vehicle and not vehicle.has_driver()
	context_buttons.stock.disabled = has_vehicle and not vehicle.has_driver()
	context_buttons.gate.text = "Close gate [O]" if gate != null and gate.gate_open else "Open gate [O]"
	if gate != null and gate.gate_open and not gate.powered: context_buttons.gate.text = "Manual close [O]"
	if gate != null: context_buttons.gate.disabled = not gate.gate_open and (not gate.powered or gate.gate_locked)
	context_buttons.gate_lock.text = "Unlock gate [K]" if gate != null and gate.gate_locked else "Lock gate [K]"
	command_title.text = "SELECTION COMMANDS" if has_vehicle or has_infantry else "PRODUCTION" if factory != null else "STRUCTURE DETAILS" if not selected.is_empty() else "SELECT A UNIT"
	if not has_engineer:
		wall_placement.cancel()
		build_kind = ""; repair_mode = false
		if ghost != null: ghost.visible = false
		if power_placement != null: power_placement.visible = false
		if power_preview_label != null: power_preview_label.visible = false
	for kind in build_buttons: build_buttons[kind].disabled = not economy.can_spend(Rules.cost(kind))
	if power_lines != null:
		var show_grid := has_engineer
		for actor in selected:
			if actor is ExpeditionStructure and int(Rules.STRUCTURES[actor.kind].power) > 0 or actor is ExpeditionStructure and actor.kind in ["generator", "repeater"]: show_grid = true
		power_lines.visible = show_grid
	if hud != null: hud.after_context()
	if changed: call_deferred("fit_command_panel")

func fit_command_panel() -> void:
	if hud != null: hud.fit()

func fit_construction_panel() -> void:
	if hud != null: hud.fit()

func toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Resume" if paused else "Pause"

func notify(text: String) -> void:
	if message != null:
		message.text = text.split(" / ")[0]; message.tooltip_text = text; notice_time = 3.5

func style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("37525d")
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func panel(parent: Node) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", style(Color(0.025, 0.05, 0.068, 0.95)))
	parent.add_child(node)
	return node

func label(parent: Node, text: String, size: int = 15, color: Color = Color("d4e4eb")) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 34
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_stylebox_override("normal", style(Color("172e38")))
	node.add_theme_stylebox_override("hover", style(Color("294b54")))
	node.add_theme_stylebox_override("pressed", style(Color("38666b")))
	node.add_theme_font_size_override("font_size", 13)
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func make_ui() -> void:
	hud = preload("res://scripts/game_hud.gd").new()
	hud.setup(self)

func show_briefing() -> void:
	overlay_title.text = "People keep the lights on."
	overlay_text.text = "You land with HQ, one engineer, and one marine. HQ stores both resources and provides a small emergency grid. Scout the darkness to find extraction and the Lightless Hive.\n\n1. Scout for and repair the extraction beacon with an engineer.\n2. Scout for the hive, then send infantry to steal its core.\n3. Bring the carrier to extraction and hold for 60 seconds.\n\nThe core drops if its carrier dies. If the Lightless recover it, or HQ is destroyed, the mission is lost. Leaving extraction or losing the beacon resets the timer.\n\nScout with units to discover resources; HQ starts beside a small material field and one methane patch. M starts mining at a patch or receiver; E explores terrain. A attack-moves, V defends, P patrols. Shift adds orders and patrol points. Vehicle batteries recharge near powered generators or repeaters."


func begin_run() -> void:
	started = true; overlay.visible = false; select_actor(jeep if is_instance_valid(jeep) else core)
	if minimap != null: minimap.visible = true
	refresh_ui()

func finish(won: bool, reason: String) -> void:
	wall_placement.cancel()
	ended = true; victorious = won; build_kind = ""; expedition_mode = false
	if minimap != null: minimap.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	overlay.visible = true
	overlay_title.text = "Hive Core secured." if won else "Expedition lost."
	overlay_text.text = reason + "\n\nMission time  %02d:%02d / Seed %d\n\n" % [int(elapsed) / 60, int(elapsed) % 60, scenario_seed] + ("A foothold in the dark. More will follow." if won else "Keep marines close, establish light before mining, and preserve the jeep.")
	overlay_button.text = "RESTART EXPEDITION"

func refresh_ui() -> void:
	if hud == null: return
	refresh_context_commands()
	hud.update()

func nearest_vehicle(point: Vector3, free_seat: bool = false) -> ExpeditionUnit:
	var result: ExpeditionUnit
	var distance := INF
	for unit in units:
		if not unit.is_vehicle() or unit.hp <= 0 or (free_seat and unit.occupied_seats() >= unit.seat_capacity()): continue
		var candidate := point.distance_to(unit.position)
		if candidate < distance: distance = candidate; result = unit
	return result

func free_spawn(anchor: Vector3) -> Vector3:
	for radius in [3.5, 5.0, 7.0]:
		for i in range(12):
			var point: Vector3 = anchor + Vector3(cos(i * TAU / 12), 0, sin(i * TAU / 12)) * float(radius)
			if not Terrain.contains(point, 1) or navigation.blocked(navigation.terrain.surface(point)): continue
			var clear := true
			for unit in units:
				if unit.aboard == null and unit.position.distance_to(point) < (3.0 if unit.is_vehicle() else 1.1): clear = false; break
			if clear: return navigation.terrain.surface(point)
	return navigation.graph.get_point_position(navigation.graph.get_closest_point(anchor))

func resource_at(point: Vector3) -> Dictionary:
	var cell := Hex.to_axial(point, Terrain.CELL)
	for resource in resource_nodes:
		if Hex.to_axial(resource.position, Terrain.CELL) == cell: return resource
	return {}

func process_harvest(unit: ExpeditionUnit, dt: float) -> void:
	if unit.cargo_total() >= unit.capacity:
		var carrier := nearest_vehicle(unit.position)
		if carrier != null and carrier.position.distance_to(unit.position) < 8 and carrier.cargo_total() < carrier.capacity: set_order(unit, "to_carrier", carrier.position, carrier)
		else: send_to_receiver(unit)
		return
	if unit.position.distance_to(unit.harvest_origin) > 3.5:
		if not unit.moving(): unit.travel(unit.harvest_origin, navigation)
		return
	unit.path.clear(); unit.work_clock += dt
	if unit.work_clock < 0.7: return
	unit.work_clock -= 0.7
	var resource := resource_at(unit.harvest_origin)
	if resource.is_empty() or int(resource.remaining) <= 0:
		if unit.cargo_total() > 0: send_to_receiver(unit)
		else: unit.order = "idle"
		return
	resource_fields.harvest(self, unit, resource)

func transfer_cargo(source: ExpeditionUnit, target: ExpeditionUnit) -> int:
	var available := target.capacity - target.cargo_total()
	var minerals := mini(available, source.cargo)
	var mined := mini(minerals, source.mined_cargo)
	available -= minerals
	var gas := mini(available, source.gas_cargo)
	source.cargo -= minerals; source.mined_cargo -= mined; source.gas_cargo -= gas
	target.cargo += minerals; target.mined_cargo += mined; target.gas_cargo += gas
	return minerals + gas

func find_receiver(point: Vector3, resource: String, home_only: bool = false) -> ExpeditionStructure:
	var result: ExpeditionStructure
	var distance := INF
	for b in structures:
		if not b.complete or b.hp <= 0 or b.kind not in ["core", "depot" if resource == "minerals" else "gas_tank"]: continue
		if home_only and b.position.distance_to(HOME) > 16: continue
		var candidate := point.distance_to(b.position)
		if candidate < distance: distance = candidate; result = b
	return result

func send_to_receiver(unit: ExpeditionUnit) -> void:
	var receiver := find_receiver(unit.position, "minerals" if unit.cargo > 0 else "gas")
	if receiver != null: set_order(unit, "deposit", receiver.position, receiver)
	else: unit.path.clear(); notify("No receiving structure for carried resources")

func deposit_cargo(unit: ExpeditionUnit, receiver: ExpeditionStructure) -> void:
	if not receiver.complete: return
	if receiver.kind in ["depot", "core"]:
		var accepted: int = economy.deposit("minerals", unit.cargo)
		var mined := mini(accepted, unit.mined_cargo)
		unit.cargo -= accepted; unit.mined_cargo -= mined
		if receiver.position.distance_to(HOME) < 16: returned_materials += mined
	if receiver.kind in ["gas_tank", "core"]:
		var accepted: int = economy.deposit("gas", unit.gas_cargo)
		unit.gas_cargo -= accepted
	# Mixed cargo proceeds to the other appropriate receiving structure.
	if unit.cargo_total() > 0:
		var next := cargo_receiver(unit, unit.order == "deliver")
		if next != null and next != receiver:
			unit.target = next
			if unit.aboard == null: unit.travel(next.position, navigation)
		elif next == null: unit.path.clear()

func cargo_receiver(unit: ExpeditionUnit, home_only: bool = false) -> ExpeditionStructure:
	var result: ExpeditionStructure
	var distance := INF
	for kind in ["minerals", "gas"]:
		if (unit.cargo if kind == "minerals" else unit.gas_cargo) <= 0 or economy.space(kind) <= 0: continue
		var receiver := find_receiver(unit.position, kind, home_only)
		if receiver != null and unit.position.distance_to(receiver.position) < distance:
			result = receiver; distance = unit.position.distance_to(receiver.position)
	return result

func selected_factory() -> ExpeditionStructure:
	for actor in selected:
		if actor is ExpeditionStructure and actor.complete and actor.kind in ["barracks", "garage", "core"]: return actor
	return null

func selected_gate() -> ExpeditionStructure:
	for actor in selected:
		if actor is ExpeditionStructure and actor.complete and actor.kind == "gate": return actor
	return null

func train_unit(kind: String) -> bool:
	if not Rules.UNITS.has(kind): return false
	var factory := selected_factory()
	if factory == null or not Rules.PRODUCTION[factory.kind].has(kind): notify("Select HQ for engineers/scouts, Barracks for infantry, or Garage for vehicles"); return false
	if factory.queue.size() >= 5: notify("Production queue is full"); return false
	if not economy.spend(Rules.cost(kind)): notify("Insufficient global materials or methane"); return false
	factory.queue.append(kind); notify("%s queued" % Rules.title(kind)); return true

func cancel_training() -> void:
	var factory := selected_factory()
	if factory == null or factory.queue.is_empty(): return
	var kind: String = factory.queue.pop_back()
	economy.minerals += int(Rules.cost(kind).minerals); economy.gas += float(Rules.cost(kind).gas)
	if factory.queue.is_empty(): factory.production_progress = 0

func numbered_command(index: int) -> void:
	if not selected_engineers().is_empty():
		if index < BUILD_KINDS.size(): choose_build(BUILD_KINDS[index])
		return
	var factory := selected_factory()
	if factory == null: return
	var choices: Array = Rules.PRODUCTION[factory.kind]
	if index < choices.size(): train_unit(choices[index])

func cost_label(kind: String) -> String:
	var cost := Rules.cost(kind)
	return "%d MAT%s" % [cost.minerals, " + %d CH4" % cost.gas if int(cost.gas) > 0 else ""]

func set_gate(gate: ExpeditionStructure, opened: bool, manual: bool = false, automatic: bool = false) -> bool:
	if gate.kind != "gate" or not gate.complete: return false
	if gate.gate_open == opened:
		if not automatic: gate.gate_auto_opened = false
		return true
	if opened and gate.gate_locked: notify("Gate is locked / K unlocks it"); return false
	if opened and not gate.powered: notify("Gate requires a powered grid to open"); return false
	if not opened:
		if not gate.powered:
			var worker := false
			for unit in units:
				if unit.kind == "engineer" and unit.aboard == null and unit.position.distance_to(gate.position) < 4: worker = true
			if not manual or not worker: return false
		for unit in units:
			if unit.aboard == null and unit.position.distance_to(gate.position) < 2.1: notify("Gate obstructed by personnel or a vehicle"); return false
		for creature in creatures:
			if creature.position.distance_to(gate.position) < 2.1: return false
	gate.gate_open = opened; gate.gate_auto_opened = automatic and opened; gate.gate_clear_time = 0
	gate.update_visual(); rebuild_navigation(); return true

func toggle_gate_lock() -> void:
	var gate := selected_gate()
	if gate == null: return
	if not gate.gate_locked and gate.gate_open and not set_gate(gate, false): return
	gate.gate_locked = not gate.gate_locked; gate.gate_auto_opened = false
	rebuild_navigation(); refresh_context_commands()

func toggle_gate() -> void:
	var gate := selected_gate()
	if gate == null: return
	if gate.gate_open and not gate.powered:
		var engineer: ExpeditionUnit
		var distance := 16.0
		for unit in units:
			if unit.kind == "engineer" and unit.aboard == null and unit.position.distance_to(gate.position) < distance: engineer = unit; distance = unit.position.distance_to(gate.position)
		if engineer != null: set_order(engineer, "close_gate", gate.position, gate)
		else: notify("Bring an engineer to manually close the gate")
	else: set_gate(gate, not gate.gate_open)

func update_power_lines() -> void:
	if power_lines == null: return
	var mesh := ImmediateMesh.new()
	if not power.links.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, Visual.material(Color("326a64"), true))
		for link in power.links:
			mesh.surface_add_vertex(link.a + Vector3.UP * 0.14); mesh.surface_add_vertex(link.b + Vector3.UP * 0.14)
		mesh.surface_end()
	power_lines.mesh = mesh

func update_scanner_contacts() -> void:
	for blip in sensor_blips: blip.queue_free()
	sensor_blips.clear()
	var cells: Dictionary = {}
	var sources: Array[Vector3] = []
	for b in structures:
		if b.kind != "scanner" or not b.complete or not b.powered: continue
		sources.append(b.position)
	for unit in units:
		if unit.kind == "scout" and unit.hp > 0 and unit.has_driver(): sources.append(unit.position)
	for source in sources:
		for creature in creatures:
			if creature.hp <= 0 or creature.position.distance_to(source) > complex_commands.scouts.SCAN_RANGE: continue
			var cell := Hex.to_axial(creature.position, Terrain.CELL)
			if cells.has(cell): continue
			cells[cell] = true
			var blip := Visual.ring(self, 1.4, AMBER); blip.position = Hex.to_world(cell, Terrain.CELL)
			sensor_blips.append(blip)

func report_activity(point: Vector3) -> void:
	for b in structures:
		if b.kind == "scanner" and b.complete and b.powered and point.distance_to(b.position) < 28: sensor_activity = 14
	for unit in units:
		if unit.kind == "scout" and unit.hp > 0 and unit.has_driver() and point.distance_to(unit.position) < 28: sensor_activity = 14
