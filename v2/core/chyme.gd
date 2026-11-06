extends RefCounted
## Cargo is not spendable until delivered. All schedules and cargo live on actors.

static func collect(game, actor: Dictionary, damage: int) -> void:
	var collector: Dictionary = game.content.units[actor.definition].capabilities.get("chyme_collector", {})
	if collector.is_empty() or damage <= 0: return
	var amount := mini(int(collector.capacity) - int(actor.chyme), damage * int(collector.yield_per_damage))
	if amount <= 0: return
	actor.chyme = int(actor.chyme) + amount
	_event(game, "chyme_collected", actor, 0, amount)

static func passive(game, actor: Dictionary) -> void:
	var source: Dictionary = game.content.units[actor.definition].capabilities.get("chyme_source", {})
	if source.is_empty() or int(game.state.tick) < int(actor.next_chyme_tick): return
	actor.next_chyme_tick = int(game.state.tick) + int(source.interval_ticks)
	var bank := str(actor.owner)
	game.state.banks[bank] = int(game.state.banks[bank]) + int(source.amount)
	_event(game, "chyme_generated", actor, 0, int(source.amount))

static func is_receiver(game, actor: Dictionary, receiver) -> bool:
	return receiver != null and int(receiver.hp) > 0 and int(receiver.owner) == int(actor.owner) and game.content.units[receiver.definition].capabilities.has("chyme_receiver")

static func nearest_receiver(game, actor: Dictionary):
	var best = null
	var nearest := 0x7fffffffffffffff
	for receiver in game.state.actors:
		if not is_receiver(game, actor, receiver): continue
		var distance: int = game.distance_to_actor(actor.position, receiver)
		if distance < nearest:
			nearest = distance
			best = receiver
	return best

static func order_delivery(game, actor: Dictionary, target: int = 0, manual: bool = true) -> void:
	if int(actor.chyme) <= 0 or not game.content.units[actor.definition].capabilities.has("chyme_collector"): return
	var receiver = nearest_receiver(game, actor) if target == 0 else game.entity(target)
	if is_receiver(game, actor, receiver):
		actor.order = {"kind": "deliver_chyme", "target": int(receiver.id), "manual": manual}

static func deliver(game, actor: Dictionary) -> void:
	var receiver = game.entity(int(actor.order.target))
	if int(actor.chyme) <= 0 or not is_receiver(game, actor, receiver):
		actor.order = {}
		return
	game._face(actor, receiver.position)
	var radius := int(round(float(game.content.units[receiver.definition].capabilities.chyme_receiver.radius) * game.SCALE))
	if game.interaction_distance(actor.position, receiver) > radius * radius:
		if not game._move(actor, receiver.position, receiver, radius, true): actor.order = {}
		return
	actor.navigation = {}
	var amount := int(actor.chyme)
	var bank := str(actor.owner)
	game.state.banks[bank] = int(game.state.banks[bank]) + amount
	actor.chyme = 0
	actor.order = {}
	_event(game, "chyme_delivered", actor, int(receiver.id), amount)

static func _event(game, kind: String, actor: Dictionary, target: int, amount: int) -> void:
	var event: Dictionary = game._event(kind, int(actor.id), target, amount)
	event.owner = int(actor.owner)
