class_name SimEntity
extends RefCounted
## Authoritative actor data. Coordinates are x/z ground position and y elevation.
var simulation_id := 0
var position := Vector3.ZERO
var kind := ""
var hp := 0.0
var visible := true
var disposed := false
var yaw := 0.0
var target: SimEntity
var focus_target: SimEntity
var revision := 0

static func valid(value) -> bool:
	return value is SimEntity and is_instance_valid(value) and not value.disposed

func state_changed() -> void:
	revision += 1

func queue_free() -> void:
	disposed = true; target = null; focus_target = null
