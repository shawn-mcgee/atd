extends RefCounted
## Plan all moves before making a blueprint solid, so completion cannot trap units.
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")

func occupies(building: SimStructure, point: Vector3, padding: float) -> bool:
	if absf(point.y - building.position.y) > 2.4: return false
	if building.kind == "platform": return Hex.to_axial(point, Terrain.CELL) == Hex.to_axial(building.position, Terrain.CELL)
	if building.kind == "ramp": return Terrain.ramp_sample(point, building.position, building.build_direction) >= 0
	point.y = building.position.y
	for tile in preload("res://engine/structure_footprints.gd").points(building):
		if point.distance_to(tile) < Terrain.CELL * 0.75 + padding: return true
	if building.kind in ["wall", "gate"]:
		for offset in building.connections:
			var nearest := Geometry3D.get_closest_point_to_segment(point, building.position, building.position + offset * 0.5)
			if point.distance_to(nearest) < 0.67 + padding: return true
	return false

func plan(game, building: SimStructure) -> Dictionary:
	var moves: Dictionary = {}
	var live: Array[SimUnit] = []
	for unit in game.units:
		if unit.hp > 0 and unit.aboard == null: live.append(unit)
	for unit in live:
		var padding: float = game.soft_spacing.radius(unit) + 0.1
		if not occupies(building, unit.position, padding): continue
		var away := unit.position - building.position
		var angle := atan2(away.z, away.x) if away.length_squared() > 0.001 else unit.formation_slot * 2.4
		var found := false
		# Search outward from each occupant, favoring the shortest safe displacement.
		for step in range(1, 14):
			for i in range(24):
				var heading := angle + i * TAU / 24
				var point: Vector3 = game.navigation.terrain.surface(unit.position + Vector3(cos(heading), 0, sin(heading)) * step * 0.5)
				if absf(point.y - unit.position.y) > 0.1 or occupies(building, point, padding): continue
				if game.navigation.blocked(point) or not game.navigation.clear_segment(unit.position, point): continue
				var clear := true
				for other in live:
					if other == unit: continue
					var other_point: Vector3 = moves.get(other, other.position)
					if point.distance_to(other_point) < game.soft_spacing.radius(unit) + game.soft_spacing.radius(other) + 0.12:
						clear = false; break
				if not clear: continue
				moves[unit] = point; found = true; break
			if found: break
		if not found: return {"ready": false, "moves": {}}
	return {"ready": true, "moves": moves}
