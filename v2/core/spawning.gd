extends RefCounted
## Source-local passive production. Paid queues and resource income are independent.
const Rally = preload("res://core/rally.gd")
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
		var point := Rally.spawn_position(game, source, str(cap.definition))
		if point.is_empty(): return
		game._spawn(cap.definition, int(source.owner), point)
		var child = game.entity(int(game.state.next_id) - 1)
		child.spawn_source = int(source.id)
		Rally.dispatch(game, source, child)
		source.passive_remaining = int(cap.interval_ticks)
		alive += 1
		var event: Dictionary = game._event("passive_spawn", int(source.id), int(child.id), 1)
		event.owner = int(source.owner)
		event.definition = str(cap.definition)
