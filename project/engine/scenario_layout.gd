extends RefCounted
## A seed owns the entire layout. Protected approaches make all objectives reachable.
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
var base_grace := 120.0
var seed_value := 0
var rng := RandomNumberGenerator.new()
var beacon_position := Vector3.ZERO
var hive_position := Vector3.ZERO
var fields: Array[Dictionary] = []
var rock_cells: Dictionary = {}

func generate(terrain, requested_seed: int = 0) -> void:
	if requested_seed == 0: seed_value = 1
	else: seed_value = requested_seed
	rng.seed = seed_value; terrain.natural_enabled = false
	fields.clear(); rock_cells.clear()
	beacon_position = sample_point(57, 87)
	for attempt in range(100):
		hive_position = sample_point(84, 114)
		if hive_position.distance_to(beacon_position) > 82.5: break
	for i in range(6):
		var point := sample_point(11 if i == 0 else 17 if i == 1 else 45, 15 if i == 0 else 23 if i == 1 else 112.5)
		for attempt in range(100):
			if point.distance_to(beacon_position) > 8 and point.distance_to(hive_position) > 9 and fields.all(func(field): return point.distance_to(field.position) > 11): break
			point = sample_point(11 if i == 0 else 17 if i == 1 else 45, 15 if i == 0 else 23 if i == 1 else 112.5)
		fields.append({"kind": "minerals" if i in [0, 2, 3] else "gas", "position": point, "remaining": [1200, 900, 1600, 1800, 1100, 1400][i]})
	# Starter deposits sit outside HQ's footprint, within its light and relay range.
	fields.append({"kind": "minerals", "position": Hex.to_world(Vector2i(0, 2), Terrain.CELL), "remaining": 3 * ceili(float(fields[0].remaining) / 7), "offsets": [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]})
	fields.append({"kind": "gas", "position": Hex.to_world(Vector2i(-2, 2), Terrain.CELL), "remaining": ceili(float(fields[1].remaining) / 7), "offsets": [Vector2i.ZERO]})
	for ridge in range(72):
		var cell := Hex.to_axial(sample_point(12, 122), Terrain.CELL)
		var heading := rng.randi_range(0, 5)
		for step in range(rng.randi_range(14, 32)):
			if rng.randf() < 0.3: heading = posmod(heading + rng.randi_range(-1, 1), 6)
			cell += Hex.NEIGHBORS[heading]
			var shoulder: Vector2i = Hex.NEIGHBORS[posmod(heading + 2, 6)]
			var cross_section: Array[Vector2i] = [Vector2i.ZERO, shoulder]
			if ridge % 3 == 0: cross_section.append(-shoulder)
			for offset in cross_section:
				var tile: Vector2i = cell + offset
				var point := Hex.to_world(tile, Terrain.CELL)
				if Terrain.contains(point, 2) and not reserved(point): rock_cells[tile] = rng.randi_range(0, 2)

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
