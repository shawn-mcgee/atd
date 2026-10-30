extends RefCounted
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")

static func offsets(kind: String, direction: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = [Vector2i.ZERO]
	if kind in ["core", "extractor"]: result.append_array(Hex.NEIGHBORS)
	elif kind in ["generator", "barracks", "garage"]:
		result.append_array([Vector2i(1, 0), Vector2i(0, 1)])
		if kind == "garage": result.append(Vector2i(1, 1))
	elif kind == "ramp": result.append(-Hex.NEIGHBORS[posmod(direction, 6)])
	if kind in ["generator", "barracks", "garage"]:
		for i in range(result.size()):
			for rotation in range(posmod(direction, 6)):
				result[i] = Vector2i(-result[i].y, result[i].x + result[i].y)
	return result

static func cells(kind: String, point: Vector3, direction: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var anchor := Hex.to_axial(point, Terrain.CELL)
	for offset in offsets(kind, direction): result.append(anchor + offset)
	return result

static func points(building: SimEntity) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for cell in cells(building.kind, building.position, building.build_direction):
		var point := Hex.to_world(cell, Terrain.CELL); point.y = building.position.y
		result.append(point)
	return result

static func reach(building: SimEntity, point: Vector3) -> float:
	var distance := INF
	for tile in points(building): distance = minf(distance, tile.distance_to(point))
	return distance
