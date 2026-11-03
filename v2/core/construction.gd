extends RefCounted
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")
const Escalation = preload("res://core/nest_escalation.gd")

static func site_error(game, mother: Dictionary, type: String, point: Array, known_only: bool = false, rotation: int = 0) -> String:
	var cap: Dictionary = game.content.units[mother.definition].capabilities.get("metamorphosis", game.content.units[mother.definition].capabilities.get("builder", {}))
	if int(mother.hp) <= 0 or cap.is_empty() or not type in cap.structures: return "Select a builder and a valid structure."
	if not game.valid_point(point) or rotation < 0 or rotation > 5: return "Site is outside the arena."
	var occupied := Geo.at(game.content.units[type], point, rotation)
	var keys: Dictionary = {}
	for cell in occupied:
		var key := Hex.key(cell)
		if not Hex.inside(cell, int(game.content.settings.map_radius)): return "Footprint is outside the arena."
	for cell in occupied:
		var key := Hex.key(cell)
		if not game.state.revealed[str(mother.owner)].has(key): return "Reveal the entire footprint before building."
		if cell in game.content.settings.get("terrain", []): return "Terrain blocks this footprint."
		keys[key] = true
	for actor in game.state.actors:
		if int(actor.id) == int(mother.id) or int(actor.hp) <= 0: continue
		if known_only and game.visible_to(int(mother.owner), actor) != 2: continue
		if Geo.structure(game, actor):
			for cell in Geo.cells(game, actor):
				if keys.has(Hex.key(cell)): return "Site is occupied."
		elif Geo.intersects_unit(game, actor, occupied): return "Site is occupied."
		if actor.order.get("kind") == "build":
			for cell in Geo.at(game.content.units[actor.order.definition], actor.order.point, int(actor.order.get("rotation", 0))):
				if keys.has(Hex.key(cell)): return "Another builder has reserved this footprint."
	return ""

static func completion_clear(game, site: Dictionary) -> bool:
	var occupied := Geo.cells(game, site)
	for other in game.state.actors:
		if int(other.id) == int(site.id) or int(other.hp) <= 0: continue
		if Geo.structure(game, other):
			for cell in Geo.cells(game, other):
				if cell in occupied: return false
		elif Geo.intersects_collision(game, other, site): return false
	return true

static func order(game, actor: Dictionary, type: String, point: Array, rotation: int = 0) -> void:
	if not game.valid_point(point): return
	var site := Hex.point(Hex.from_point(point))
	if not site_error(game, actor, type, site, false, rotation).is_empty(): return
	if int(game.state.banks[str(actor.owner)]) < int(game.content.units[type].cost): return
	actor.order = {"kind": "build", "definition": type, "point": site, "rotation": rotation, "manual": true}

static func approach(game, actor: Dictionary) -> void:
	var type: String = actor.order.definition
	var site: Array = actor.order.point
	if not site_error(game, actor, type, site, false, int(actor.order.get("rotation", 0))).is_empty():
		actor.order = {}
		return
	if actor.position != site:
		if not game._move(actor, site): actor.order = {}; return
		if actor.position != site: return
	var cost := int(game.content.units[type].cost)
	var bank := str(actor.owner)
	if int(game.state.banks[bank]) < cost:
		actor.order = {}
		return
	actor.rotation = int(actor.order.get("rotation", 0))
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
	if actor.construction.get("kind") == "blueprint": return
	actor.construction.remaining = maxi(0, int(actor.construction.remaining) - Escalation.rate(game, actor, "construction"))
	if int(actor.construction.remaining) > 0: return
	if not completion_clear(game, actor):
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
	game._illumination_cache.clear()
	game._navigation_cache.clear()
	game.invalidate_unit_caches()
	actor.definition = type
	actor.hp = int(game.content.units[type].hp)
	actor.order = {}
	actor.production = []
	actor.construction = {}
	actor.navigation = {}
	actor.velocity = Vector3i.ZERO
	actor.avoidance = {}
	game.Rally.reset(game, actor)
	actor.ready_tick = maxi(int(actor.ready_tick), int(game.state.tick))
	actor.chyme = 0
	actor.next_chyme_tick = int(game.state.tick) + int(game.content.units[type].capabilities.get("chyme_source", {}).get("interval_ticks", 0))
	actor.passive_started_tick = int(game.state.tick)
	actor.passive_remaining = int(game.content.units[type].capabilities.get("passive_spawner", {}).get("interval_ticks", 0))

static func _scaled_hp(hp: int, old_max: int, new_max: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, hp * new_max / old_max)

static func _event(game, kind: String, actor: Dictionary, type: String, amount: int) -> void:
	var event: Dictionary = game._event(kind, int(actor.id), 0, amount)
	event.owner = int(actor.owner)
	event.definition = type
