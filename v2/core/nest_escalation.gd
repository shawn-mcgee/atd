extends RefCounted
## Resolve deaths at the tick boundary. Faster work starts on the following tick.

static func resolve(game) -> void:
	var settings: Dictionary = game.content.settings.get("nest_loss", {})
	if settings.is_empty(): return
	for actor in game.state.actors:
		if actor.definition != "nest" or int(actor.hp) > 0: continue
		var owner := str(actor.owner)
		if game.state.escalations.has(owner): continue
		var eligible: Array = []
		for structure in game.state.actors:
			if int(structure.owner) == int(actor.owner) and int(structure.hp) > 0 and _is_structure(game, structure): eligible.append(int(structure.id))
		eligible.sort()
		game.state.escalations[owner] = {"tick": int(game.state.tick), "nest": int(actor.id), "structures": eligible}
		game.state.banks[owner] = int(game.state.banks[owner]) + int(settings.chyme_grant)
		var event: Dictionary = game._event("nest_destroyed", int(actor.id), 0, int(settings.chyme_grant))
		event.owner = int(actor.owner)
		event.production_rate = int(settings.production_rate)
		event.construction_rate = int(settings.construction_rate)
		event.affect_new_structures = bool(settings.affect_new_structures)

static func rate(game, actor: Dictionary, work: String) -> int:
	var owner := str(actor.owner)
	if not game.state.escalations.has(owner) or not _is_structure(game, actor): return 1
	var settings: Dictionary = game.content.settings.nest_loss
	if not settings.affect_new_structures and not int(actor.id) in game.state.escalations[owner].structures: return 1
	return int(settings[work + "_rate"])

static func forget_structure(game, actor: Dictionary) -> void:
	var owner := str(actor.owner)
	if game.state.escalations.has(owner): game.state.escalations[owner].structures.erase(int(actor.id))

static func _is_structure(game, actor: Dictionary) -> bool:
	var definition: Dictionary = game.content.units[actor.definition]
	return definition.faction == "lightless" and not definition.capabilities.has("move")
