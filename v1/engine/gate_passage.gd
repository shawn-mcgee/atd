extends RefCounted
var states: Dictionary = {}

func crosses(unit, gate: SimStructure, lookahead: float = 7.0) -> bool:
	var previous: Vector3 = unit.position
	var distance := 0.0
	for i in range(unit.path_index, unit.path.size()):
		var point: Vector3 = unit.path[i]
		var end: Vector3 = previous.move_toward(point, maxf(0, lookahead - distance))
		if Geometry3D.get_closest_point_to_segment(gate.position, previous, end).distance_to(gate.position) < 1.9: return true
		distance += previous.distance_to(point)
		if distance >= lookahead: break
		previous = point
	return false

func update(game, dt: float) -> void:
	var gates: Array = []
	var next: Dictionary = {}
	for gate in game.structures:
		if gate.kind != "gate" or not gate.complete or gate.hp <= 0: continue
		gates.append(gate); next[gate.simulation_id] = [gate.gate_open, gate.gate_locked, gate.powered]
	if next != states:
		states = next; game.rebuild_navigation()
	for gate in gates:
		var needed := false
		var occupied := false
		for unit in game.units:
			if unit.hp <= 0 or unit.aboard != null: continue
			var distance: float = unit.position.distance_to(gate.position)
			if distance < 2.7: occupied = true
			if distance < 6 and unit.moving() and crosses(unit, gate): needed = true
		if needed and not gate.gate_open and gate.powered and not gate.gate_locked:
			game.set_gate(gate, true, false, true)
		if gate.gate_auto_opened and gate.gate_open and gate.powered:
			gate.gate_clear_time = 0.0 if occupied or needed else gate.gate_clear_time + dt
			if gate.gate_clear_time > 0.5: game.set_gate(gate, false, false, true)
		if not gate.gate_open:
			for creature in game.creatures:
				if creature.position.distance_to(gate.position) < 4 and crosses(creature, gate): creature.path.clear(); creature.repath = 0
