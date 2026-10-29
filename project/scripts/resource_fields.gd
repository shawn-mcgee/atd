extends RefCounted

func setup(game) -> void:
	# Every field has seven distinct one-cell patches and preserves its total yield.
	var originals: Array = game.resource_nodes.duplicate()
	for mesh in game.resource_meshes: mesh.queue_free()
	for marker in game.resource_markers: marker.queue_free()
	game.resource_nodes.clear(); game.resource_meshes.clear(); game.resource_markers.clear()
	for field_id in range(originals.size()):
		var field: Dictionary = originals[field_id]
		var center = game.Hex.to_axial(field.position, game.Terrain.CELL)
		var offsets: Array = [Vector2i.ZERO] + game.Hex.NEIGHBORS
		var valid_offsets: Array = offsets.filter(func(offset): return game.navigation.terrain.height(game.Hex.to_world(center + offset, game.Terrain.CELL)) == game.navigation.terrain.height(field.position))
		for index in range(valid_offsets.size()):
			var point = game.Hex.to_world(center + valid_offsets[index], game.Terrain.CELL)
			if game.navigation.terrain.height(point) != game.navigation.terrain.height(field.position): continue
			var amount := int(field.remaining) / valid_offsets.size() + (int(field.remaining) % valid_offsets.size() if index == 0 else 0)
			game.add_resource_patch(field.kind, point, amount)
			game.resource_nodes[-1].field = field_id
			game.resource_meshes[-1].scale = Vector3.ONE * 0.45
			game.resource_markers[-1].scale = Vector3.ONE * 0.25

func harvest(game, unit: ExpeditionUnit, resource: Dictionary) -> int:
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
		if patch.get("field", -1) == resource.get("field", -2) and patch.remaining > 0: return patch
	return {}
