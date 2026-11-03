extends RefCounted
const Actor = preload("res://core/actor.gd")
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")

static func reset(cache: Dictionary) -> void:
	# Only immutable coordinate metadata survives rollback, never discoveries or
	# observer/fringe state. Restoring cannot change a query's gameplay result.
	var grid: Dictionary = cache.get("@grid", {})
	var stencils: Dictionary = cache.get("@stencils", {})
	cache.clear()
	cache["@grid"] = grid; cache["@stencils"] = stencils

static func record(game, cache: Dictionary) -> void:
	for player in game.state.players:
		var known: Dictionary = game.state.revealed[str(player.id)]
		for key in game.illumination_cells(int(player.id)): known[key] = true
	if cache.get("@veil_revision", -1) != int(game.state.veil.revision):
		for key in game.state.veil.cells:
			var cell: Dictionary = game.state.veil.cells[key]
			if int(cell.hp) > 0: game.state.revealed[str(cell.owner)][key] = true
		cache["@veil_revision"] = int(game.state.veil.revision)
	var units: Dictionary = game.content.units
	var map_radius := int(game.content.settings.map_radius)
	var side := map_radius * 2 + 1
	if cache.get("@grid", {}).get("radius", -1) != map_radius:
		var tiles := PackedStringArray()
		tiles.resize(side * side)
		for q in range(-map_radius, map_radius + 1):
			for r in range(-map_radius, map_radius + 1):
				if absi(q + r) <= map_radius: tiles[(q + map_radius) * side + r + map_radius] = Hex.key([q, r])
		cache["@grid"] = {"radius": map_radius, "tiles": tiles}
	var tiles: PackedStringArray = cache["@grid"].tiles
	var fringes: Dictionary = cache.get("@fringes", {})
	var stencils: Dictionary = cache.get("@stencils", {})
	for actor: Actor in game.state.actors:
		if int(actor.hp) <= 0: continue
		var caps: Dictionary = units[actor.definition].capabilities
		if not caps.has("perception"): continue
		var position := Geo.center(game, actor)
		var id := str(actor.id)
		var radius := int(round(float(caps.perception.radius) * Hex.SCALE))
		var previous: Dictionary = cache.get(id, {})
		if previous.get("position", []) == position and previous.get("radius", -1) == radius and previous.get("owner", -1) == int(actor.owner): continue
		var known: Dictionary = game.state.revealed[str(actor.owner)]
		var center := Hex.from_point(position)
		var fringe_key := Vector4i(int(actor.owner), radius, int(center[0]), int(center[1]))
		if not fringes.has(fringe_key):
			# Every point in a hex is within one tile of its center. A shared
			# envelope therefore covers every sub-tile position in this cell.
			if not stencils.has(radius):
				var offsets: Array = []
				var reach := radius + Hex.SCALE
				var span := ceili(float(reach) * 1.16 / Hex.SCALE)
				for q in range(-span, span + 1):
					for r in range(-span, span + 1):
						if (q * q + q * r + r * r) * Hex.SCALE * Hex.SCALE <= reach * reach: offsets.append(Vector2i(q, r))
				stencils[radius] = offsets
			var candidates: Array = []
			for offset in stencils[radius]:
				var q := int(center[0]) + int(offset.x); var r := int(center[1]) + int(offset.y)
				if absi(q) > map_radius or absi(r) > map_radius or absi(q + r) > map_radius: continue
				var index := (q + map_radius) * side + r + map_radius
				if not known.has(tiles[index]): candidates.append(Vector3i(index, q * Hex.SCALE, r * Hex.SCALE))
			if fringes.size() >= 512: fringes.erase(fringes.keys()[0])
			fringes[fringe_key] = candidates
		var remaining: Array = []
		var q := int(position[0]); var r := int(position[2])
		for candidate: Vector3i in fringes[fringe_key]:
			var key := tiles[candidate.x]
			if known.has(key): continue
			var dq := q - candidate.y; var dr := r - candidate.z
			if dq * dq + dq * dr + dr * dr <= radius * radius: known[key] = true
			else: remaining.append(candidate)
		# Discovery only grows between restores, so all observers can discard
		# discovered candidates together. An empty envelope needs no tile scans.
		fringes[fringe_key] = remaining
		cache[id] = {"radius": radius, "owner": int(actor.owner), "position": position.duplicate()}
	cache["@fringes"] = fringes
	cache["@stencils"] = stencils
	var alive: Dictionary = {}
	for actor: Actor in game.state.actors: alive[str(actor.id)] = true
	for id in cache.keys():
		if not str(id).begins_with("@") and not alive.has(id): cache.erase(id)
