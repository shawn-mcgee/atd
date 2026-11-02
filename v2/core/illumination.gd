extends RefCounted
## Derived tile light field. Blockers receive light but never forward it.
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")

static func field(game, cache: Dictionary) -> Dictionary:
	var signature: Array = [int(game.content.settings.map_radius), game.content.settings.get("terrain", [])]
	var sources: Array = []
	var blockers: Dictionary = {}
	for cell in game.content.settings.get("terrain", []): blockers[Hex.key(cell)] = true
	for actor in game.state.actors:
		if int(actor.hp) <= 0: continue
		var caps: Dictionary = game.content.units[actor.definition].capabilities
		if not caps.has("illumination") and not caps.has("light_blocker"): continue
		var cell := Hex.from_point(Geo.center(game, actor))
		var radius := int(floor(float(caps.illumination.radius))) if caps.has("illumination") else -1
		var occupied: Array = Geo.cells(game, actor) if caps.has("light_blocker") else []
		signature.append([int(actor.owner), cell, radius, occupied])
		for blocked in occupied: blockers[Hex.key(blocked)] = true
		if radius >= 0: sources.append({"owner": int(actor.owner), "cell": cell, "radius": radius})
	if cache.get("signature", []) == signature: return cache.field
	var result: Dictionary = {"all": {}, "owners": {}}
	for source in sources:
		var owner := str(source.owner)
		if not result.owners.has(owner): result.owners[owner] = {}
		var reached := _spread(source.cell, int(source.radius), int(game.content.settings.map_radius), blockers)
		result.owners[owner].merge(reached)
		result.all.merge(reached)
	cache.signature = signature
	cache.field = result
	return result

static func _spread(origin: Array, radius: int, map_radius: int, blockers: Dictionary) -> Dictionary:
	var reached: Dictionary = {}
	if not Hex.inside(origin, map_radius): return reached
	var queue: Array = [[origin, 0]]
	reached[Hex.key(origin)] = origin
	var head := 0
	while head < queue.size():
		var entry: Array = queue[head]
		head += 1
		var cell: Array = entry[0]
		var distance := int(entry[1])
		# An emitter can light outward from its own occupied/blocking tile.
		if distance >= radius or (distance > 0 and blockers.has(Hex.key(cell))): continue
		for offset in Hex.NEIGHBORS:
			var next := [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])]
			var key := Hex.key(next)
			if reached.has(key) or not Hex.inside(next, map_radius): continue
			reached[key] = next
			queue.append([next, distance + 1])
	return reached
