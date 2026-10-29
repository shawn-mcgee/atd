class_name ExpeditionUnit
extends Node3D
const Visual = preload("res://scripts/expedition_visuals.gd")
const Rules = preload("res://scripts/expedition_rules.gd")
const STATS := Rules.UNITS
var kind := "marine"
var hp := 110.0
var path := PackedVector3Array()
var path_index := 0
var order := "idle"
var target: Node3D
var focus_target: Node3D
var cooldown := 0.0
var work_clock := 0.0
var cargo := 0
var mined_cargo := 0
var gas_cargo := 0
var capacity := 160
var passengers: Array[ExpeditionUnit] = []
var driver: ExpeditionUnit
var aboard: ExpeditionUnit
var facing := Vector3.FORWARD
var indicator: MeshInstance3D
var visual: Node3D
var goal := Vector3.ZERO
var desired_yaw := 0.0
var formation_slot := 0
var complex_id := 0
var escort_speed_limit := INF
var motion_velocity := Vector3.ZERO
var headlight: SpotLight3D
var headlamps: Array[MeshInstance3D] = []
var harvest_kind := "minerals"
var harvest_origin := Vector3.ZERO

func setup(type: String, point: Vector3) -> void:
	kind = type
	position = point
	hp = STATS[kind].hp
	capacity = 160 if kind == "jeep" else 40 if kind == "scout" else 20
	visual = Node3D.new()
	add_child(visual)
	if is_vehicle():
		Visual.box(visual, Vector3(1.8, 0.65, 2.8), Vector3(0, 0.8, 0), Color("65877f"))
		Visual.box(visual, Vector3(1.55, 0.7, 1.1), Vector3(0, 1.4, -0.25), Color("91bac0"))
		for x in [-1.0, 1.0]:
			for z in [-0.95, 0.95]: Visual.sphere(visual, 0.45, Vector3(x, 0.45, z), Color("1b2730"))
			headlamps.append(Visual.box(visual, Vector3(0.3, 0.2, 0.12), Vector3(x * 0.65, 1, -1.45), Color("dcf7df")))
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(0, 1.8, -1.2)
		lamp.rotation_degrees.x = -18
		lamp.spot_range = 18
		lamp.spot_angle = 52
		lamp.light_energy = 3
		lamp.light_color = Color("d3f6e5")
		visual.add_child(lamp)
		headlight = lamp
		if kind == "scout": visual.scale = Vector3(0.65, 0.8, 0.7)
		Visual.sphere(visual, 0.12, Vector3(0, 1.9, 0.3), Color("d99547")).material_override = Visual.material(Color("d99547"), true)
		update_lights()
	else:
		var color := Color("e3b46c") if kind == "engineer" else Color("c78365") if kind == "flamer" else Color("89aab6")
		Visual.box(visual, Vector3(0.64, 0.85, 0.45), Vector3(0, 1.05, 0), color)
		Visual.sphere(visual, 0.32, Vector3(0, 1.7, 0), color)
		Visual.box(visual, Vector3(0.48, 0.13, 0.18), Vector3(0, 1.7, -0.27), Color("9af2dc")).material_override = Visual.material(Color("9af2dc"), true)
		for x in [-0.2, 0.2]: Visual.box(visual, Vector3(0.23, 0.6, 0.25), Vector3(x, 0.3, 0), Color("465b64"))
		Visual.box(visual, Vector3(0.18, 0.2, 0.85), Vector3(0.4, 1.1, -0.35), Color("314650"))
		if kind == "flamer": Visual.box(visual, Vector3(0.65, 0.8, 0.35), Vector3(0, 1.05, 0.4), Color("9b654a"))
	indicator = Visual.ring(self, 1.65 if is_vehicle() else 0.85, Color("7bf4d0"))
	indicator.visible = false

func travel(destination: Vector3, navigation: RefCounted) -> bool:
	destination = navigation.terrain.surface(destination)
	goal = destination
	path = navigation.path(position, destination)
	path_index = 0
	return not path.is_empty()

func tick_move(dt: float) -> void:
	motion_velocity = Vector3.ZERO
	cooldown = maxf(0, cooldown - dt)
	if aboard != null:
		position = aboard.position
		return
	if is_vehicle() and not has_driver():
		path.clear()
		return
	while path_index < path.size() and path[path_index].distance_to(position) < 0.18:
		path_index += 1
	if path_index >= path.size():
		turn(dt)
		return
	var point := path[path_index]
	var offset := point - position
	var direction := offset.normalized()
	desired_yaw = atan2(-direction.x, -direction.z)
	turn(dt)
	var previous := position
	position = position.move_toward(point, minf(float(STATS[kind].speed), escort_speed_limit) * dt)
	if dt > 0: motion_velocity = (position - previous) / dt
	if position.distance_squared_to(point) < 0.00001: path_index += 1

func turn(dt: float) -> void:
	visual.rotation.y = rotate_toward(visual.rotation.y, desired_yaw, dt * (3.0 if is_vehicle() else 7.0))
	facing = Vector3(-sin(visual.rotation.y), 0, -cos(visual.rotation.y))

func moving() -> bool:
	return (not is_vehicle() or has_driver()) and path_index < path.size()

func is_vehicle() -> bool:
	return kind in ["jeep", "scout"]

func has_driver() -> bool:
	return is_instance_valid(driver) and driver.hp > 0

func seat_capacity() -> int:
	return 4 if kind == "jeep" else 1 if kind == "scout" else 0

func occupied_seats() -> int:
	return passengers.size() + (1 if has_driver() else 0)

func board(unit: ExpeditionUnit) -> bool:
	if not is_vehicle() or hp <= 0 or occupied_seats() >= seat_capacity() or unit.aboard != null: return false
	if not has_driver(): driver = unit; unit.order = "piloting"
	else: passengers.append(unit); unit.order = "aboard"
	unit.aboard = self
	unit.visible = false
	unit.path.clear()
	update_lights()
	return true

func disembark(unit: ExpeditionUnit, point: Vector3) -> void:
	if driver == unit: driver = null; path.clear(); order = "idle"
	passengers.erase(unit)
	unit.aboard = null; unit.visible = true; unit.position = point
	unit.order = "idle"; unit.target = null
	unit.path.clear(); unit.goal = point
	update_lights()

func update_lights() -> void:
	if headlight == null: return
	headlight.visible = has_driver() and hp > 0
	for mesh in headlamps: mesh.material_override = Visual.material(Color("dcf7df") if headlight.visible else Color("263c40"), headlight.visible)

func cargo_total() -> int:
	return cargo + gas_cargo
