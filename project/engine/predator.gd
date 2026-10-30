class_name SimPredator
extends "res://engine/entity.gd"
const Rules = preload("res://engine/expedition_rules.gd")
var max_hp := 65.0
var cooldown := 0.0
var goal := Vector3.ZERO
var path := PackedVector3Array()
var path_index := 0
var repath := 0.0
var state := "lurking"
var group := 0
var loss := 0.0
var gait_clock := 0.0
var probe_goal := Vector3.INF
var probe_anchor := Vector3.INF
var probe_until := 0.0
var probe_active := false
var committed := false
var retreat_remaining := 0.0
var target_until := 0.0
var route_avoids_light := true
var route_revision := -1

func setup(point: Vector3, group_id: int, type: String = "stalker", _variation: int = 0) -> void:
	kind = type if Rules.PREDATORS.has(type) else "stalker"
	max_hp = float(Rules.PREDATORS[kind].hp); hp = max_hp; position = point; goal = point; group = group_id; visible = false
func navigate(point: Vector3, navigation: RefCounted, illumination: RefCounted = null) -> void:
	var avoid_light := state != "assault"
	if point.distance_to(goal) < 1.5 and repath > 0 and avoid_light == route_avoids_light and route_revision == navigation.revision: return
	route_avoids_light = avoid_light; route_revision = navigation.revision
	goal = point
	path = navigation.path(position, point, null, false)
	# Most habitat routes are already dark. Only pay for weighted light avoidance
	# when the ordinary route would actually cross protective illumination.
	if illumination != null and avoid_light:
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
	retreat_remaining = maxf(0, retreat_remaining - dt)
	cooldown = maxf(0, cooldown - dt)
	if path_index >= path.size(): return
	var next := path[path_index]
	if next.distance_to(position) < 0.2:
		path_index += 1
		return
	var speed := float(Rules.PREDATORS[kind].retreat_speed if state == "retreating" else Rules.PREDATORS[kind].speed)
	if state in ["lurking", "staging"]: speed *= 0.65
	var direction := (next - position).normalized()
	position = position.move_toward(next, speed * dt)
	gait_clock += dt * speed * 3.0

func hurt(amount: float) -> void:
	if amount <= 0: return
	hp -= amount
	loss += amount
	if probe_active and not committed:
		state = "retreating"; target = null; retreat_remaining = 8
		path.clear(); repath = 0
