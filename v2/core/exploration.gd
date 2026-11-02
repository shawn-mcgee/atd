extends RefCounted
const Hex = preload("res://core/hex_cells.gd")

static func record(game, cache: Dictionary) -> void:
	for actor in game.state.actors:
		if int(actor.hp) <= 0: continue
		var signature := [actor.definition, actor.position]
		var id := str(actor.id)
		if cache.get(id, []) == signature: continue
		cache[id] = signature.duplicate(true)
		var caps: Dictionary = game.content.units[actor.definition].capabilities
		var radius := -1
		for cap in ["perception", "illumination"]:
			if caps.has(cap): radius = maxi(radius, int(round(float(caps[cap].radius) * Hex.SCALE)))
		if radius < 0: continue
		var known: Dictionary = game.state.revealed[str(actor.owner)]
		var center := Hex.from_point(actor.position)
		# Axial coordinate bounds can exceed a circular range by sqrt(4/3).
		var span := ceili(float(radius) * 1.16 / Hex.SCALE) + 1
		for q in range(int(center[0]) - span, int(center[0]) + span + 1):
			for r in range(int(center[1]) - span, int(center[1]) + span + 1):
				var cell := [q, r]
				var key := Hex.key(cell)
				if known.has(key) or not Hex.inside(cell, int(game.content.settings.map_radius)): continue
				if game.distance_squared(actor.position, Hex.point(cell)) <= radius * radius: known[key] = true
	var alive: Dictionary = {}
	for actor in game.state.actors: alive[str(actor.id)] = true
	for id in cache.keys():
		if not alive.has(id): cache.erase(id)
