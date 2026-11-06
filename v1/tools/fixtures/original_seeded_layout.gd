extends "res://engine/scenario_layout.gd"
## Frozen pre-expansion generation for legacy gameplay checkpoints.
func generate(terrain, requested_seed: int = 0) -> void:
	if requested_seed == 0: seed_value = 1
	else: seed_value = requested_seed
	rng.seed = seed_value; terrain.natural_enabled = false
	fields.clear(); rock_cells.clear()
	beacon_position = sample_point(38, 58)
	for attempt in range(100):
		hive_position = sample_point(56, 76)
		if hive_position.distance_to(beacon_position) > 55: break
	for i in range(6):
		var point := sample_point(11 if i == 0 else 17 if i == 1 else 30, 15 if i == 0 else 23 if i == 1 else 75)
		for attempt in range(100):
			if point.distance_to(beacon_position) > 8 and point.distance_to(hive_position) > 9 and fields.all(func(field): return point.distance_to(field.position) > 11): break
			point = sample_point(11 if i == 0 else 17 if i == 1 else 30, 15 if i == 0 else 23 if i == 1 else 75)
		fields.append({"kind": "minerals" if i in [0, 2, 3] else "gas", "position": point, "remaining": [1200, 900, 1600, 1800, 1100, 1400][i]})
	# Starter deposits sit outside HQ's footprint, within its light and relay range.
	fields.append({"kind": "minerals", "position": Hex.to_world(Vector2i(0, 2), Terrain.CELL), "remaining": 3 * ceili(float(fields[0].remaining) / 7), "offsets": [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]})
	fields.append({"kind": "gas", "position": Hex.to_world(Vector2i(-2, 2), Terrain.CELL), "remaining": ceili(float(fields[1].remaining) / 7), "offsets": [Vector2i.ZERO]})
	for ridge in range(24):
		var cell := Hex.to_axial(sample_point(15, 79), Terrain.CELL)
		var heading := rng.randi_range(0, 5)
		for step in range(rng.randi_range(8, 24)):
			if rng.randf() < 0.3: heading = posmod(heading + rng.randi_range(-1, 1), 6)
			cell += Hex.NEIGHBORS[heading]
			for offset in [Vector2i.ZERO, Hex.NEIGHBORS[posmod(heading + 2, 6)]]:
				var tile: Vector2i = cell + offset
				var point := Hex.to_world(tile, Terrain.CELL)
				if original_contains(point, 2) and not reserved(point): rock_cells[tile] = rng.randi_range(0, 2)

func sample_point(low: float, high: float) -> Vector3:
	var angle := rng.randf_range(0, TAU)
	return Hex.snap(Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(low, high), Terrain.CELL)

func reserved(point: Vector3) -> bool:
	if point.length() < 10: return true
	var destinations: Array[Vector3] = [beacon_position, hive_position]
	for field in fields: destinations.append(field.position)
	for destination in destinations:
		if point.distance_to(destination) < 5 or Geometry3D.get_closest_point_to_segment(point, Vector3.ZERO, destination).distance_to(point) < 3.2: return true
	return false

func setup_base(game) -> void:
	game.core = game.add_structure("core", Vector3.ZERO)
	game.home_depot = game.core
	game.add_unit("engineer", Vector3(-2.5, 0, -2))
	game.add_unit("marine", Vector3(2.5, 0, -2))

func setup_resources(game) -> void:
	for field in fields:
		game.add_resource_patch(field.kind, field.position, int(field.remaining))
		if field.has("offsets"): game.resource_nodes[-1].offsets = field.offsets
	game.resource_fields.setup(game)

func make_landscape(game) -> void:
	for cell in rock_cells: game.add_natural_obstacle(Hex.to_world(cell, Terrain.CELL), int(rock_cells[cell]))

# Frozen generation for the pre-expansion gameplay checkpoint fixture.
func original_contains(point: Vector3, margin: int) -> bool:
	var cell := Hex.to_axial(point, Terrain.CELL)
	return maxi(absi(cell.x), maxi(absi(cell.y), absi(cell.x + cell.y))) <= 56 - margin
