extends RefCounted
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const Config = preload("res://engine/gameplay_config.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
static var HARVEST_REACH: float = Config.value("resources", "reach")

func within_reach(unit: SimUnit, point: Vector3, game = null) -> bool:
	if unit.aboard != null or absf(unit.position.y - point.y) > 0.6: return false
	if game != null:
		var extractor := extractor_at(game, point)
		if extractor != null and Footprints.reach(extractor, unit.position) <= HARVEST_REACH: return true
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

func covered_patches(game, building: SimStructure) -> Array:
	var footprint := Footprints.cells(building.kind, building.position, building.build_direction)
	return game.resource_nodes.filter(func(patch): return footprint.has(Hex.to_axial(patch.position, Terrain.CELL)))

func extractor_at(game, point: Vector3) -> SimStructure:
	var cell := Hex.to_axial(point, Terrain.CELL)
	for building in game.structures:
		if building.kind == "extractor" and building.hp > 0 and building.complete and building.powered and building.enabled and Footprints.cells("extractor", building.position).has(cell): return building
	return null

func extractor_site(game, point: Vector3, direction: int = 0) -> bool:
	var cells := Footprints.cells("extractor", point, direction)
	for patch in game.resource_nodes:
		if patch.discovered and patch.remaining > 0 and cells.has(Hex.to_axial(patch.position, Terrain.CELL)): return true
	return false

func available(game, resource: Dictionary) -> bool:
	if int(resource.remaining) > 0: return true
	var extractor := extractor_at(game, resource.position)
	if extractor != null:
		for patch in covered_patches(game, extractor):
			if patch.remaining > 0: return true
	return false

func harvest(game, unit: SimUnit, resource: Dictionary) -> int:
	if unit.kind != "engineer" or not within_reach(unit, resource.position, game): return 0
	var extractor := extractor_at(game, resource.position)
	var patches: Array = covered_patches(game, extractor) if extractor != null else [resource]
	var quantity := int(Config.value("resources", "extractor_yield" if extractor != null else "hand_yield"))
	var gathered := 0
	for i in range(mini(quantity, unit.capacity - unit.cargo_total())):
		var next: Dictionary = {}; var fullness := -1.0
		for patch in patches:
			if patch.remaining <= 0: continue
			if not patch.has("initial_remaining"): patch.initial_remaining = int(patch.remaining)
			var ratio := float(patch.remaining) / maxi(1, int(patch.initial_remaining))
			if ratio > fullness: next = patch; fullness = ratio
		if next.is_empty(): break
		next.remaining -= 1; next.discovered = true; gathered += 1
		if next.kind == "minerals": unit.cargo += 1; unit.mined_cargo += 1
		else: unit.gas_cargo += 1
	return gathered

func field_remaining(game, resource: Dictionary) -> int:
	var extractor := extractor_at(game, resource.position)
	if extractor != null:
		var amount := 0
		for patch in covered_patches(game, extractor): amount += int(patch.remaining)
		return amount
	var total := 0
	for patch in game.resource_nodes:
		if patch.get("field", -1) == resource.get("field", -2): total += int(patch.remaining)
	return total

func next_patch(game, resource: Dictionary) -> Dictionary:
	var extractor := extractor_at(game, resource.position)
	if extractor != null:
		for patch in covered_patches(game, extractor):
			if patch.remaining > 0: return patch
	for patch in game.resource_nodes:
		if patch.get("field", -1) == resource.get("field", -2) and patch.discovered and patch.remaining > 0: return patch
	return {}

func discover(game) -> void:
	# Only illuminated cells are surveyed, never an unseen remainder of the field.
	for i in range(game.resource_nodes.size()):
		var patch: Dictionary = game.resource_nodes[i]
		var lit: bool = game.light.sample(patch.position) > Config.value("lighting", "discovery_threshold")
		if lit and patch.remaining > 0: patch.discovered = true
