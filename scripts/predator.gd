class_name ExpeditionPredator
extends Node3D
const Visual = preload("res://scripts/expedition_visuals.gd")
var hp := 65.0
var max_hp := 65.0
var cooldown := 0.0
var goal := Vector3.ZERO
var path := PackedVector3Array()
var path_index := 0
var repath := 0.0
var state := "lurking"
var target: Node3D
var group := 0
var loss := 0.0
var visual: Node3D

func setup(point: Vector3, group_id: int) -> void:
	position = point
	goal = point
	group = group_id
	visual = Node3D.new()
	add_child(visual)
	var color := Color("573b59")
	var body := Visual.sphere(visual, 0.7, Vector3(0, 0.65, 0), color)
	body.scale = Vector3(0.8, 0.7, 1.5)
	Visual.sphere(visual, 0.43, Vector3(0, 0.8, -0.8), Color("987689"))
	for side in [-1.0, 1.0]:
		for z in [-0.65, 0.1, 0.7]:
			var leg := Visual.box(visual, Vector3(0.17, 0.7, 0.22), Vector3(side * 0.7, 0.35, z), color)
			leg.rotation.z = side * 0.65
		Visual.sphere(visual, 0.08, Vector3(side * 0.18, 0.92, -1.15), Color("ff9970")).material_override = Visual.material(Color("ff9970"), true)
	visible = false

func navigate(point: Vector3, navigation: RefCounted, illumination: RefCounted = null) -> void:
	if point.distance_to(goal) < 1.5 and repath > 0: return
	goal = point
	path = navigation.path(position, point, illumination if state in ["lurking", "staging", "retreating"] else null)
	path_index = 0
	repath = 2.0

func move_tick(dt: float) -> void:
	repath -= dt
	cooldown = maxf(0, cooldown - dt)
	if path_index >= path.size(): return
	var next := path[path_index]
	if next.distance_to(position) < 0.2:
		path_index += 1
		return
	var speed := 4.6 if state == "retreating" else 3.8 if state == "assault" else 2.2
	var direction := (next - position).normalized()
	visual.rotation.y = rotate_toward(visual.rotation.y, atan2(-direction.x, -direction.z), dt * 6.0)
	position = position.move_toward(next, speed * dt)

func hurt(amount: float) -> void:
	hp -= amount
	loss += amount
