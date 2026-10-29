class_name ExpeditionStructure
extends Node3D
const Visual = preload("res://scripts/expedition_visuals.gd")
const Rules = preload("res://scripts/expedition_rules.gd")
const Terrain = preload("res://scripts/expedition_terrain.gd")
const MODELS := {"core": "command_core", "floodlight": "power_relay", "depot": "storage_depot", "gas_tank": "outpost_generator", "generator": "outpost_generator", "repeater": "power_relay", "turret": "pulse_turret", "barracks": "command_core", "garage": "storage_depot", "scanner": "power_relay"}
var kind := "core"
var hp := 700.0
var complete := true
var funded := true
var progress := 0.0
var cooldown := 0.0
var enabled := true
var connected := false
var powered := false
var network := -1
var gate_open := false
var queue: Array[String] = []
var production_progress := 0.0
var model: Node3D
var lamp: OmniLight3D
var indicator: MeshInstance3D
var status_lamp: MeshInstance3D
var gate_bar: MeshInstance3D
var gate_bars: Array[MeshInstance3D] = []
var connections: Array[Vector3] = []
var build_direction := 0
var scan_charge := 120.0
var terrain_collision: StaticBody3D

func setup(type: String, point: Vector3, finished: bool, direction_index: int = 0) -> void:
	kind = type; position = point; complete = finished; funded = finished; build_direction = direction_index
	hp = float(Rules.STRUCTURES[kind].hp)
	if kind in ["wall", "gate"]:
		model = Node3D.new(); add_child(model)
		connect_fortification([])
	elif kind in ["platform", "ramp"]:
		model = Node3D.new(); add_child(model)
		var mesh := MeshInstance3D.new()
		mesh.mesh = Terrain.hex_mesh(Terrain.LEVEL) if kind == "platform" else Terrain.ramp_mesh()
		if kind == "ramp": mesh.rotation.y = atan2(-Terrain.direction(build_direction).z, Terrain.direction(build_direction).x)
		mesh.material_override = Visual.material(Color("71858b"))
		model.add_child(mesh)
		terrain_collision = StaticBody3D.new(); terrain_collision.collision_layer = 1 << 19; terrain_collision.collision_mask = 0
		var collision := CollisionShape3D.new(); collision.shape = mesh.mesh.create_trimesh_shape(); collision.rotation = mesh.rotation
		terrain_collision.add_child(collision); add_child(terrain_collision)
	else:
		model = (load("res://scenes/props/%s.tscn" % MODELS[kind]) as PackedScene).instantiate()
		add_child(model)
		model.position.y = -float({"command_core": 0.15, "power_relay": 0.2, "storage_depot": 0.12, "outpost_generator": 0.15, "pulse_turret": 0.15}[MODELS[kind]])
		var tint := Color("9eb7b9") if kind in ["core", "floodlight"] else Color("be9765") if kind in ["generator", "gas_tank"] else Color("7795a8")
		Visual.paint(model, Visual.material(tint))
		if kind == "scanner": Visual.sphere(model, 0.75, Vector3(0, 3, 0), Color("729bba"))
	indicator = Visual.ring(self, 2.4, Color("7bf4d0")); indicator.visible = false
	status_lamp = Visual.sphere(self, 0.15, Vector3(0, 2.5, 0), Color("75deba"))
	if kind == "platform": status_lamp.position.y = 3.2
	var tag := Label3D.new()
	tag.text = Rules.title(kind)
	tag.position.y = 3.9; tag.font_size = 28; tag.pixel_size = 0.024
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color("a5bcc6")
	if kind in ["wall", "gate", "platform", "ramp"]:
		tag.set_meta("selection_label", true); tag.visible = not complete
	add_child(tag)
	if kind in ["core", "floodlight"]:
		lamp = OmniLight3D.new(); lamp.position.y = 3.5
		lamp.omni_range = 14 if kind == "core" else 13
		lamp.light_energy = 2; lamp.light_color = Color("ccedda")
		add_child(lamp)
	update_visual()

func update_visual() -> void:
	model.scale = Vector3.ONE * (1.0 if complete else 0.35 + progress * 0.65)
	if lamp != null: lamp.visible = complete and enabled and powered
	for bar in gate_bars: bar.position.y = 3.4 if kind == "gate" and gate_open else 1.1
	if terrain_collision != null: terrain_collision.process_mode = Node.PROCESS_MODE_INHERIT if complete else Node.PROCESS_MODE_DISABLED
	if terrain_collision != null: terrain_collision.collision_layer = (1 << 19) if complete else 0
	var needs_power := int(Rules.STRUCTURES[kind].power) > 0 or kind in ["generator", "repeater"]
	status_lamp.material_override = Visual.material(Color("68d8b0") if complete and (powered or not needs_power) else Color("cf875e"), true)

func connect_fortification(neighbors: Array[Vector3]) -> void:
	connections = neighbors.duplicate(); gate_bars.clear(); gate_bar = null
	for child in model.get_children(): child.free()
	if kind == "wall": Visual.box(model, Vector3(0.8, 2.4, 0.8), Vector3(0, 1.2, 0), Color("596c74"))
	var arms: Array[Vector3] = neighbors.duplicate()
	if arms.is_empty(): arms.assign([Terrain.direction(build_direction) * Terrain.SPACING, -Terrain.direction(build_direction) * Terrain.SPACING])
	for offset in arms:
		var length := offset.length() * 0.5
		var bar := Visual.box(model, Vector3(length + 0.15, 1.8, 0.6), offset * 0.25 + Vector3.UP * 1.1, Color("8f9d9c"))
		bar.rotation.y = atan2(-offset.z, offset.x)
		gate_bars.append(bar)
		if gate_bar == null: gate_bar = bar
		if kind == "gate": Visual.box(model, Vector3(0.35, 2.4, 0.5), offset * 0.5 + Vector3.UP * 1.2, Color("596c74"))
