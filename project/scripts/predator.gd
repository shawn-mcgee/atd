class_name ExpeditionPredator
extends Node3D
const Visual = preload("res://scripts/expedition_visuals.gd")
const Rules = preload("res://scripts/expedition_rules.gd")
var kind := "stalker"
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
var legs: Array[Node3D] = []
var leg_rest: Array[float] = []
var gait_clock := 0.0
var probe_goal := Vector3.INF
var probe_anchor := Vector3.INF
var probe_until := 0.0

func setup(point: Vector3, group_id: int, type: String = "stalker", variation: int = 0) -> void:
	kind = type if Rules.PREDATORS.has(type) else "stalker"
	max_hp = float(Rules.PREDATORS[kind].hp); hp = max_hp
	position = point
	goal = point
	group = group_id
	visual = Node3D.new()
	add_child(visual)
	var color := Color("ad9866") if kind == "runner" else Color("92595b") if kind == "brute" else Color("786186")
	color = color.lightened(float(posmod(variation, 5)) * 0.025)
	var body := Visual.sphere(visual, 0.48 if kind == "runner" else 0.95 if kind == "brute" else 0.7, Vector3(0, 0.85 if kind == "brute" else 0.55, 0), color)
	body.scale = Vector3(0.65, 0.65, 1.6) if kind == "runner" else Vector3(1.0, 0.9, 1.25) if kind == "brute" else Vector3(0.8, 0.7, 1.5)
	var head_z := -1.0 if kind == "brute" else -0.8
	Visual.sphere(visual, 0.55 if kind == "brute" else 0.3 if kind == "runner" else 0.43, Vector3(0, 0.9 if kind == "brute" else 0.65, head_z), color.lightened(0.18))
	var width := 0.95 if kind == "brute" else 0.48 if kind == "runner" else 0.7
	var leg_z := [-0.6, 0.6] if kind == "runner" else [-0.8, -0.25, 0.3, 0.85] if kind == "brute" else [-0.65, 0.1, 0.7]
	for side in [-1.0, 1.0]:
		for z in leg_z:
			var leg := Visual.box(visual, Vector3(0.27 if kind == "brute" else 0.14, 0.9 if kind == "brute" else 0.65, 0.24), Vector3(side * width, 0.4, z), color)
			leg.rotation.z = side * 0.65; legs.append(leg); leg_rest.append(leg.rotation.z)
		Visual.sphere(visual, 0.11 if kind == "brute" else 0.08, Vector3(side * 0.18, 1.03 if kind == "brute" else 0.78, head_z - 0.35), Color("ffbc7d")).material_override = Visual.material(Color("ffbc7d"), true)
	if kind == "brute":
		for z in [-0.45, 0.15, 0.75]: Visual.box(visual, Vector3(1.5, 0.28, 0.45), Vector3(0, 1.55, z), Color("c18d7b"))
	elif kind == "runner":
		var tail := Visual.box(visual, Vector3(0.16, 0.18, 1.0), Vector3(0, 0.65, 1.15), color)
		tail.rotation.x = -0.25
	visual.scale *= 0.94 + float(posmod(variation, 7)) * 0.02
	visible = false

func navigate(point: Vector3, navigation: RefCounted, illumination: RefCounted = null) -> void:
	if point.distance_to(goal) < 1.5 and repath > 0: return
	goal = point
	path = navigation.path(position, point, null, false)
	# Most habitat routes are already dark. Only pay for weighted light avoidance
	# when the ordinary route would actually cross protective illumination.
	if illumination != null and state in ["lurking", "staging", "retreating"]:
		var crosses_light := false
		for i in range(1, path.size()):
			var samples := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 2))
			for sample in range(samples + 1):
				if illumination.deterrence(path[i - 1].lerp(path[i], float(sample) / samples)) > 0.2: crosses_light = true; break
			if crosses_light: break
		if crosses_light: path = navigation.path(position, point, illumination, false)
	path_index = 0
	repath = 2.0 + fmod(absf(position.x * 0.017 + position.z * 0.029), 0.7)

func move_tick(dt: float) -> void:
	repath -= dt
	cooldown = maxf(0, cooldown - dt)
	if path_index >= path.size(): return
	var next := path[path_index]
	if next.distance_to(position) < 0.2:
		path_index += 1
		return
	var speed := float(Rules.PREDATORS[kind].retreat_speed if state == "retreating" else Rules.PREDATORS[kind].speed)
	if state in ["lurking", "staging"]: speed *= 0.65
	var direction := (next - position).normalized()
	visual.rotation.y = rotate_toward(visual.rotation.y, atan2(-direction.x, -direction.z), dt * 6.0)
	position = position.move_toward(next, speed * dt)
	gait_clock += dt * speed * 3.0
	visual.position.y = absf(sin(gait_clock)) * (0.035 if kind == "brute" else 0.07)
	for i in range(legs.size()): legs[i].rotation.z = leg_rest[i] + sin(gait_clock + i * PI) * 0.22

func hurt(amount: float) -> void:
	hp -= amount
	loss += amount
