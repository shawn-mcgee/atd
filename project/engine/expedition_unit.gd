class_name SimUnit
extends "res://engine/entity.gd"
const Rules = preload("res://engine/expedition_rules.gd")
const STATS := Rules.UNITS
const DRIVER_RANK := {"engineer": 0, "marine": 1, "flamer": 2}
const MINING_DRIVER_RANK := {"marine": 0, "flamer": 1, "engineer": 2}
var battery := 100.0
var auto_recharge := true
var charging := false
var order_queue: Array[Dictionary] = []
var combat_target: SimEntity
var combat_last_seen := Vector3.ZERO
var defense_point := Vector3.ZERO
var patrol_points: Array[Vector3] = []
var patrol_index := 0
var path := PackedVector3Array()
var path_index := 0
var order := "idle"
var cooldown := 0.0
var work_clock := 0.0
var cargo := 0
var mined_cargo := 0
var gas_cargo := 0
var capacity := 160
var passengers: Array[SimUnit] = []
var driver: SimUnit
var aboard: SimUnit
var facing := Vector3.FORWARD
var goal := Vector3.ZERO
var desired_yaw := 0.0
var formation_slot := 0
var complex_id := 0
var escort_speed_limit := INF
var motion_velocity := Vector3.ZERO
var light_state = null
var harvest_kind := "minerals"
var harvest_origin := Vector3.ZERO

func setup(type: String, point: Vector3) -> void:
	kind = type; position = point; hp = STATS[kind].hp
	capacity = 160 if kind == "jeep" else 40 if kind == "scout" else 20
	update_light_state()
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
	if is_vehicle() and battery <= 0:
		update_light_state()
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

func moving() -> bool:
	return (not is_vehicle() or has_driver()) and path_index < path.size()

func is_vehicle() -> bool:
	return kind in ["jeep", "scout", "drill"]

func has_driver() -> bool:
	return SimEntity.valid(driver) and driver.hp > 0

func seat_capacity() -> int:
	return 4 if kind == "jeep" else 1 if kind in ["scout", "drill"] else 0

func occupied_seats() -> int:
	return passengers.size() + (1 if has_driver() else 0)

func board(unit: SimUnit) -> bool:
	if not is_vehicle() or hp <= 0 or occupied_seats() >= seat_capacity() or unit.aboard != null: return false
	if not has_driver(): driver = unit; unit.order = "piloting"
	else: passengers.append(unit); unit.order = "aboard"
	unit.aboard = self
	unit.visible = false
	unit.path.clear()
	update_light_state()
	return true

func disembark(unit: SimUnit, point: Vector3) -> void:
	if driver == unit: driver = null; path.clear(); order = "idle"
	passengers.erase(unit)
	unit.aboard = null; unit.visible = true; unit.position = point
	unit.order = "idle"; unit.target = null
	unit.path.clear(); unit.goal = point
	update_light_state()

func cargo_total() -> int:
	return cargo + gas_cargo

func turn(dt: float) -> void:
	yaw = rotate_toward(yaw, desired_yaw, dt * (3.0 if is_vehicle() else 7.0))
	facing = Vector3(-sin(yaw), 0, -cos(yaw))
func update_light_state() -> void:
	light_state = has_driver() and battery > 0 and hp > 0
