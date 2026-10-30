extends RefCounted
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const HARVEST_REACH := Terrain.SPACING + Terrain.CELL * 0.2

func within_reach(unit: SimUnit, point: Vector3) -> bool:
	if unit.aboard != null or absf(unit.position.y - point.y) > 0.6: return false
	var delta := Hex.to_axial(unit.position, Terrain.CELL) - Hex.to_axial(point, Terrain.CELL)
	if maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.x + delta.y))) > 1: return false
	return Vector2(unit.position.x - point.x, unit.position.z - point.z).length() <= HARVEST_REACH

func setup(game) -> void:
	# Fields preserve their total yield; starter deposits can specify fewer cells.
	var originals: Array = game.resource_nodes.duplicate()
	game.resource_nodes.clear()
	for field_id in range(originals.size()):
		var field: Dictionary = originals[field_id]
		var center = game.Hex.to_axial(field.position, game.Terrain.CELL)
		var offsets: Array = field.get("offsets", [Vector2i.ZERO] + game.Hex.NEIGHBORS)
		var valid_offsets: Array = offsets.filter(func(offset): return game.navigation.terrain.height(game.Hex.to_world(center + offset, game.Terrain.CELL)) == game.navigation.terrain.height(field.position))
		for index in range(valid_offsets.size()):
			var point = game.Hex.to_world(center + valid_offsets[index], game.Terrain.CELL)
			if game.navigation.terrain.height(point) != game.navigation.terrain.height(field.position): continue
			var amount := int(field.remaining) / valid_offsets.size() + (int(field.remaining) % valid_offsets.size() if index == 0 else 0)
			game.add_resource_patch(field.kind, point, amount)
			game.resource_nodes[-1].field = field_id

func harvest(game, unit: SimUnit, resource: Dictionary) -> int:
	if unit.kind != "engineer" or not within_reach(unit, resource.position): return 0
	var quantity := 1
	for building in game.structures:
		if building.kind == "extractor" and building.complete and building.powered and building.enabled and game.Hex.to_axial(building.position, game.Terrain.CELL) == game.Hex.to_axial(resource.position, game.Terrain.CELL):
			quantity = 3; break
	quantity = mini(quantity, mini(int(resource.remaining), unit.capacity - unit.cargo_total()))
	resource.remaining -= quantity
	if resource.kind == "minerals": unit.cargo += quantity; unit.mined_cargo += quantity
	else: unit.gas_cargo += quantity
	return quantity

func field_remaining(game, resource: Dictionary) -> int:
	var total := 0
	for patch in game.resource_nodes:
		if patch.get("field", -1) == resource.get("field", -2): total += int(patch.remaining)
	return total

func next_patch(game, resource: Dictionary) -> Dictionary:
	for patch in game.resource_nodes:
		if patch.get("field", -1) == resource.get("field", -2) and patch.discovered and patch.remaining > 0: return patch
	return {}

func discover(game) -> void:
	# Only illuminated cells are surveyed, never an unseen remainder of the field.
	for i in range(game.resource_nodes.size()):
		var patch: Dictionary = game.resource_nodes[i]
		var lit: bool = game.light.sample(patch.position) > 0.05
		if lit and patch.remaining > 0: patch.discovered = true
