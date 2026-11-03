extends RefCounted
const Actor = preload("res://core/actor.gd")
## Source-local passive production. Paid queues and resource income are independent.
const Rally = preload("res://core/rally.gd")
const Escalation = preload("res://core/nest_escalation.gd")

static func alive_count(game, source: int) -> int:
	var alive := 0
	for actor: Actor in game.state.actors:
		if int(actor.hp) > 0 and int(actor.production_state.spawn_source) == source: alive += 1
	return alive

static func tick(game, source: Actor) -> void:
	var cap: Dictionary = game.content.units[source.definition].capabilities.get("passive_spawner", {})
	if cap.is_empty() or int(game.state.tick) <= int(source.production_state.passive_started_tick): return
	var alive := alive_count(game, int(source.id))
	var work := Escalation.rate(game, source, "production")
	while work > 0 and alive < int(cap.max_alive):
		var remaining := int(source.production_state.passive_remaining)
		if remaining > work:
			source.production_state.passive_remaining = remaining - work
			return
		work -= remaining
		source.production_state.passive_remaining = 0
		var point := Rally.spawn_position(game, source, str(cap.definition))
		if point.is_empty(): return
		game._spawn(cap.definition, int(source.owner), point)
		var child = game.entity(int(game.state.next_id) - 1)
		child.production_state.spawn_source = int(source.id)
		Rally.dispatch(game, source, child)
		source.production_state.passive_remaining = int(cap.interval_ticks)
		alive += 1
		var event: Dictionary = game._event("passive_spawn", int(source.id), int(child.id), 1)
		event.owner = int(source.owner)
		event.definition = str(cap.definition)
