extends RefCounted
## Source-local passive production. Paid queues and resource income are independent.
const Hex = preload("res://core/hex_cells.gd")
const Escalation = preload("res://core/nest_escalation.gd")

static func alive_count(game, source: int) -> int:
	var alive := 0
	for actor in game.state.actors:
		if int(actor.hp) > 0 and int(actor.spawn_source) == source: alive += 1
	return alive

static func tick(game, source: Dictionary) -> void:
	var cap: Dictionary = game.content.units[source.definition].capabilities.get("passive_spawner", {})
	if cap.is_empty() or int(game.state.tick) <= int(source.passive_started_tick): return
	var alive := alive_count(game, int(source.id))
	var work := Escalation.rate(game, source, "production")
	while work > 0 and alive < int(cap.max_alive):
		var remaining := int(source.passive_remaining)
		if remaining > work:
			source.passive_remaining = remaining - work
			return
		work -= remaining
		source.passive_remaining = 0
		var point := _free_position(game, source, int(cap.spawn_radius))
		if point.is_empty(): return
		game._spawn(cap.definition, int(source.owner), point)
		var child = game.entity(int(game.state.next_id) - 1)
		child.spawn_source = int(source.id)
		game._face(child, [int(point[0]) * 2 - int(source.position[0]), 0, int(point[2]) * 2 - int(source.position[2])])
		source.passive_remaining = int(cap.interval_ticks)
		alive += 1
		var event: Dictionary = game._event("passive_spawn", int(source.id), int(child.id), 1)
		event.owner = int(source.owner)
		event.definition = str(cap.definition)

static func _free_position(game, source: Dictionary, radius: int) -> Array:
	var occupied: Dictionary = {}
	for actor in game.state.actors:
		if int(actor.hp) <= 0: continue
		occupied[Hex.key(Hex.from_point(actor.position))] = true
		if actor.order.get("kind") == "build": occupied[Hex.key(Hex.from_point(actor.order.point))] = true
	var center := Hex.from_point(source.position)
	# Prefer the outer ring; fall back inward at edges or around occupied tiles.
	for ring in range(radius, 0, -1):
		var cells: Array = []
		for q in range(int(center[0]) - ring, int(center[0]) + ring + 1):
			for r in range(int(center[1]) - ring, int(center[1]) + ring + 1):
				var cell := [q, r]
				if Hex.distance(center, cell) != ring or not Hex.inside(cell, int(game.content.settings.map_radius)) or occupied.has(Hex.key(cell)): continue
				cells.append(cell)
		if not cells.is_empty():
			cells.sort_custom(Hex.compare)
			return Hex.point(cells[game._random() % cells.size()])
	return []
