extends RefCounted
const Hex = preload("res://core/hex_cells.gd")
const Escalation = preload("res://core/nest_escalation.gd")

static func site_error(game, mother: Dictionary, type: String, point: Array, known_only: bool = false) -> String:
	var cap: Dictionary = game.content.units[mother.definition].capabilities.get("metamorphosis", {})
	if int(mother.hp) <= 0 or cap.is_empty() or not type in cap.structures: return "Select a Mother and a valid structure."
	if not game.valid_point(point): return "Site is outside the arena."
	var cell := Hex.from_point(point)
	if not game.state.revealed[str(mother.owner)].has(Hex.key(cell)): return "Reveal this tile before building."
	for actor in game.state.actors:
		if int(actor.id) == int(mother.id) or int(actor.hp) <= 0: continue
		if known_only and game.visible_to(int(mother.owner), actor) != 2: continue
		if Hex.from_point(actor.position) == cell: return "Site is occupied."
		if int(actor.owner) == int(mother.owner) and actor.order.get("kind") == "build" and Hex.from_point(actor.order.point) == cell: return "Another Mother has reserved this tile."
	return ""

static func order(game, actor: Dictionary, type: String, point: Array) -> void:
	if not game.valid_point(point): return
	var site := Hex.point(Hex.from_point(point))
	if not site_error(game, actor, type, site).is_empty(): return
	if int(game.state.banks[str(actor.owner)]) < int(game.content.units[type].cost): return
	actor.order = {"kind": "build", "definition": type, "point": site, "manual": true}

static func approach(game, actor: Dictionary) -> void:
	var type: String = actor.order.definition
	var site: Array = actor.order.point
	if not site_error(game, actor, type, site).is_empty():
		actor.order = {}
		return
	if actor.position != site:
		game._move(actor, site)
		if actor.position != site: return
	var cost := int(game.content.units[type].cost)
	var bank := str(actor.owner)
	if int(game.state.banks[bank]) < cost:
		actor.order = {}
		return
	var mother: String = actor.definition
	var womb: String = game.content.units[mother].capabilities.metamorphosis.womb
	var hp := int(actor.hp)
	game.state.banks[bank] = int(game.state.banks[bank]) - cost
	_change(game, actor, womb)
	actor.hp = _scaled_hp(hp, int(game.content.units[mother].hp), int(game.content.units[womb].hp))
	actor.construction = {"definition": type, "mother": mother, "mother_hp": hp, "womb_hp": int(actor.hp), "cost": cost,
		"remaining": int(game.content.units[type].construction_ticks), "total": int(game.content.units[type].construction_ticks)}
	_event(game, "construction_started", actor, type, cost)

static func advance(game, actor: Dictionary) -> void:
	actor.construction.remaining = maxi(0, int(actor.construction.remaining) - Escalation.rate(game, actor, "construction"))
	if int(actor.construction.remaining) > 0: return
	for other in game.state.actors:
		if int(other.id) != int(actor.id) and int(other.hp) > 0 and Hex.from_point(other.position) == Hex.from_point(actor.position):
			actor.construction.blocked = true
			return
	var type: String = actor.construction.definition
	var hp := _scaled_hp(int(actor.hp), int(game.content.units[actor.definition].hp), int(game.content.units[type].hp))
	_change(game, actor, type)
	actor.hp = hp
	_event(game, "construction_completed", actor, type, 0)

static func cancel(game, actor: Dictionary) -> void:
	if actor.construction.is_empty():
		if actor.order.get("kind") == "build": actor.order = {}
		return
	var work: Dictionary = actor.construction.duplicate(true)
	var damage := maxi(0, int(work.womb_hp) - int(actor.hp))
	var womb_max := int(game.content.units[actor.definition].hp)
	@warning_ignore("integer_division")
	var loss := (damage * int(game.content.units[work.mother].hp) + womb_max - 1) / womb_max
	var hp := maxi(1, int(work.mother_hp) - loss)
	game.state.banks[str(actor.owner)] = int(game.state.banks[str(actor.owner)]) + int(work.cost)
	Escalation.forget_structure(game, actor)
	_change(game, actor, work.mother)
	actor.hp = hp
	_event(game, "construction_cancelled", actor, work.definition, int(work.cost))

static func _change(game, actor: Dictionary, type: String) -> void:
	actor.definition = type
	actor.hp = int(game.content.units[type].hp)
	actor.order = {}
	actor.production = []
	actor.construction = {}
	actor.ready_tick = maxi(int(actor.ready_tick), int(game.state.tick))
	actor.chyme = 0
	actor.next_chyme_tick = int(game.state.tick) + int(game.content.units[type].capabilities.get("chyme_source", {}).get("interval_ticks", 0))

static func _scaled_hp(hp: int, old_max: int, new_max: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, hp * new_max / old_max)

static func _event(game, kind: String, actor: Dictionary, type: String, amount: int) -> void:
	var event: Dictionary = game._event(kind, int(actor.id), 0, amount)
	event.owner = int(actor.owner)
	event.definition = type
