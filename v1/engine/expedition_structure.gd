class_name SimStructure
extends "res://engine/entity.gd"
const Rules = preload("res://engine/expedition_rules.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
var ammo := 0
var reload_remaining := 0.0
var auto_reload := true
var complete := true
var funded := true
var progress := 0.0
var waiting_for_clearance := false
var cooldown := 0.0
var enabled := true
var connected := false
var powered := false
var network := -1
var gate_open := false
var gate_locked := false
var gate_auto_opened := false
var gate_clear_time := 0.0
var queue: Array[String] = []
var production_progress := 0.0
var connections: Array[Vector3] = []
var build_direction := 0
var light_radius: float = Rules.Config.value("lighting", "hq_radius")
var light_intensity: float = Rules.Config.value("lighting", "hq_intensity")

func setup(type: String, point: Vector3, finished: bool, direction_index: int = 0) -> void:
	kind = type; position = point; complete = finished; funded = finished; build_direction = direction_index
	hp = float(Rules.STRUCTURES[kind].hp)
	if Rules.TURRETS.has(kind): ammo = int(Rules.TURRETS[kind].magazine)
func connect_fortification(neighbors: Array[Vector3]) -> void:
	connections = neighbors.duplicate()
