extends RefCounted
const Actor = preload("res://core/actor.gd")
## Stateful membrane data lives in Simulation.state. Queries never mutate it.
const Geo = preload("res://core/geometry.gd")
const Hex = preload("res://core/hex_cells.gd")
const DEFAULTS := {"tile_hp": 100, "light_damage_per_tick": 2, "decay_per_tick": 1, "alert_cooldown_ticks": 20, "memory_ticks": 200}
const STANCES := ["neutral", "defensive", "offensive"]

static func initial_state() -> Dictionary:
	return {"cells": {}, "sources": {}, "networks": {}, "next_network": 1, "next_stance_order": 1,
		"network_dirty": false, "contacts": {}, "cooldowns": {}, "revision": 0}

static func settings(game) -> Dictionary:
	return game.content.settings.get("veil", DEFAULTS)

static func perceives(game, owner: int, point: Array) -> bool:
	var cell: Dictionary = game.state.veil.cells.get(Hex.key(Hex.from_point(point)), {})
	return not cell.is_empty() and int(cell.owner) == owner and int(cell.hp) > 0

static func tick(game) -> void:
	var veil: Dictionary = game.state.veil
	var alive: Dictionary = {}
	var occupied: Dictionary = {}
	for cell in game.content.settings.get("terrain", []): occupied[Hex.key(cell)] = [0]
	var lights: Dictionary = game.illumination_cells()
	for actor: Actor in game.state.actors:
		var caps: Dictionary = game.content.units[actor.definition].capabilities
		# Mobile actors never obstruct the membrane, even while standing still.
		if int(actor.hp) <= 0: continue
		if not caps.has("move"):
			for cell in Geo.cells(game, actor):
				var key := Hex.key(cell)
				if not occupied.has(key): occupied[key] = []
				occupied[key].append(int(actor.id))
		if caps.has("veil_source"):
			var id: String = str(actor.id)
			alive[id] = true
			if not veil.sources.has(id):
				veil.sources[id] = {"origin": Hex.from_point(Geo.center(game, actor)), "claimed": [], "next_growth_tick": int(game.state.tick)}
	for id in veil.sources.keys():
		if not alive.has(id): veil.sources.erase(id)
	# A surviving source maintains only membrane it has actually grown/claimed.
	var damage_keys: Array = []
	for key in veil.cells:
		var cell: Dictionary = veil.cells[key]
		for id in cell.sources:
			if alive.has(str(id)): continue
			cell.sources = cell.sources.filter(func(source_id): return alive.has(str(source_id)))
			veil.revision = int(veil.revision) + 1
			break
		if lights.has(key) or cell.sources.is_empty(): damage_keys.append(key)
	# Only hazardous tissue needs a canonical damage/event ordering.
	damage_keys.sort()
	for key in damage_keys:
		var cell: Dictionary = veil.cells[key]
		if lights.has(key):
			_damage(game, key, int(settings(game).light_damage_per_tick), "illumination", 0)
		elif cell.sources.is_empty():
			_damage(game, key, int(settings(game).decay_per_tick), "decay", 0)
	for actor: Actor in game.state.actors:
		if not alive.has(str(actor.id)): continue
		var source: Dictionary = veil.sources[str(actor.id)]
		if int(game.state.tick) >= int(source.next_growth_tick):
			_grow(game, actor, source, occupied, lights)
			source.next_growth_tick = int(game.state.tick) + int(game.content.units[actor.definition].capabilities.veil_source.growth_interval_ticks)
	_ensure_networks(game)
	_contacts(game)
	_adopt_stances(game)
	for key in veil.cooldowns.keys():
		if int(veil.cooldowns[key]) <= int(game.state.tick): veil.cooldowns.erase(key)

static func _grow(game, actor: Actor, source: Dictionary, occupied: Dictionary, lights: Dictionary) -> void:
	var veil: Dictionary = game.state.veil
	var cap: Dictionary = game.content.units[actor.definition].capabilities.veil_source
	var candidates: Dictionary = {}
	if source.claimed.is_empty():
		_offer(game, actor, source, source.origin, occupied, lights, candidates)
	else:
		for key in source.claimed:
			var cell: Dictionary = veil.cells[key]
			_offer_neighbors(game, actor, source, [cell.q, cell.r], occupied, lights, candidates)
	var remaining := int(cap.growth_tiles)
	while remaining > 0 and not candidates.is_empty():
		# Canonical order makes RNG choices independent of dictionary insertion order.
		var ordered := candidates.values()
		ordered.sort_custom(Hex.compare)
		var cell: Array = ordered[game._random() % ordered.size()]
		var key := Hex.key(cell)
		candidates.erase(key)
		if not veil.cells.has(key):
			veil.cells[key] = {"q": int(cell[0]), "r": int(cell[1]), "owner": int(actor.owner),
				"hp": int(settings(game).tile_hp), "sources": [], "network": 0}
			veil.network_dirty = true
		veil.cells[key].sources.append(int(actor.id))
		veil.cells[key].sources.sort()
		source.claimed.append(key)
		veil.revision = int(veil.revision) + 1
		remaining -= 1
		_offer_neighbors(game, actor, source, cell, occupied, lights, candidates)

static func _offer_neighbors(game, actor: Actor, source: Dictionary, cell: Array, occupied: Dictionary, lights: Dictionary, candidates: Dictionary) -> void:
	for offset in Hex.NEIGHBORS:
		_offer(game, actor, source, [int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])], occupied, lights, candidates)

static func _offer(game, actor: Actor, source: Dictionary, cell: Array, occupied: Dictionary, lights: Dictionary, candidates: Dictionary) -> void:
	var key := Hex.key(cell)
	var radius := int(game.content.units[actor.definition].capabilities.veil_source.radius)
	if candidates.has(key) or source.claimed.has(key): return
	if not Hex.inside(cell, int(game.content.settings.map_radius)) or Hex.distance(cell, source.origin) > radius: return
	if not game.state.veil.cells.has(key) and occupied.has(key) and occupied[key].any(func(id): return int(id) != int(actor.id)): return
	if lights.has(key): return
	if game.state.veil.cells.has(key) and int(game.state.veil.cells[key].owner) != int(actor.owner): return
	candidates[key] = cell

static func networks_at(veil: Dictionary, owner: int, position: Array) -> Array:
	var result: Array = []
	if veil.cells.is_empty(): return result
	var cell := Hex.from_point(position)
	for offset in [[0, 0]] + Hex.NEIGHBORS:
		var key := Hex.key([int(cell[0]) + int(offset[0]), int(cell[1]) + int(offset[1])])
		if not veil.cells.has(key) or int(veil.cells[key].owner) != owner: continue
		var id := int(veil.cells[key].network)
		if id > 0 and not result.has(id): result.append(id)
	result.sort()
	return result

static func attack(game, actor: Actor, point: Array) -> void:
	var key := Hex.key(Hex.from_point(point))
	if not game.state.veil.cells.has(key):
		actor.order = {}; return
	var cell: Dictionary = game.state.veil.cells[key]
	if int(cell.owner) == int(actor.owner) or game.visibility_at(int(actor.owner), point) != 2: return
	game._face(actor, point)
	var weapon: Dictionary = game.content.units[actor.definition].capabilities.weapon
	var radius := int(round(float(weapon.range) * Hex.SCALE))
	if game.distance_squared(actor.position, point) > radius * radius:
		game._move(actor, point); return
	if int(actor.combat.ready_tick) > int(game.state.tick): return
	actor.combat.ready_tick = int(game.state.tick) + int(weapon.interval_ticks)
	_damage(game, key, int(weapon.damage), "weapon", int(actor.id))

static func _damage(game, key: String, amount: int, cause: String, source_id: int) -> void:
	if amount <= 0 or not game.state.veil.cells.has(key): return
	var veil: Dictionary = game.state.veil
	var cell: Dictionary = veil.cells[key]
	var damage := mini(amount, int(cell.hp))
	cell.hp = int(cell.hp) - damage
	# Notify before removing the tile, so a severed branch receives its last alert.
	if cause == "illumination" or int(cell.hp) <= 0:
		_ensure_networks(game)
		_alert(game, int(cell.owner), [cell.q, cell.r], cause, source_id, true, damage, int(cell.hp) <= 0)
	veil.revision = int(veil.revision) + 1
	if int(cell.hp) <= 0:
		veil.cells.erase(key)
		for source in veil.sources.values(): source.claimed.erase(key)
		veil.network_dirty = true

static func signal_at(game, owner: int, position: Array, reason: String, source_id: int) -> void:
	_ensure_networks(game)
	_alert(game, owner, Hex.from_point(position), reason, source_id, true)

static func _alert(game, owner: int, cell: Array, reason: String, source_id: int, hostile: bool, amount: int = 0, destroyed: bool = false) -> void:
	var veil: Dictionary = game.state.veil
	var point := Hex.point(cell)
	var networks := networks_at(veil, owner, point)
	for id in networks:
		var key := "%d:%d:%s:%d" % [owner, id, reason, source_id]
		if not destroyed and int(veil.cooldowns.get(key, -1)) > int(game.state.tick): continue
		if not destroyed: veil.cooldowns[key] = int(game.state.tick) + int(settings(game).alert_cooldown_ticks)
		var network: Dictionary = veil.networks[str(id)]
		if hostile:
			network.threat = {"point": point, "expires": int(game.state.tick) + int(settings(game).memory_ticks), "reason": reason}
		var recipients: Array = []
		for actor: Actor in game.state.actors:
			if int(actor.hp) > 0 and int(actor.owner) == owner and networks_at(veil, owner, actor.position).has(id):
				recipients.append(int(actor.id))
				if game.content.units[actor.definition].capabilities.has("move"): _inherit_actor(actor, network)
		var event: Dictionary = game._event("veil_alert", source_id, 0, amount)
		event.merge({"owner": owner, "network": id, "point": point, "reason": reason,
			"hostile": hostile, "destroyed": destroyed, "recipients": recipients})

static func _contacts(game) -> void:
	var veil: Dictionary = game.state.veil
	var next: Dictionary = {}
	if veil.cells.is_empty():
		veil.contacts = next
		return
	for actor: Actor in game.state.actors:
		if not game.content.units[actor.definition].capabilities.has("move"): continue
		var cell := Hex.from_point(actor.position)
		var key := Hex.key(cell)
		if not veil.cells.has(key): continue
		var identity: String = str(actor.id)
		next[identity] = key
		if int(actor.owner) != int(veil.cells[key].owner):
			# Occupancy remains sensed while on the membrane, without repeating
			# entry notifications or tracking the unit after it leaves.
			var network: Dictionary = veil.networks[str(veil.cells[key].network)]
			network.threat = {"point": Hex.point(cell), "expires": int(game.state.tick) + int(settings(game).memory_ticks), "reason": "contact"}
		if veil.contacts.get(identity, "") != key:
			_alert(game, int(veil.cells[key].owner), cell, "contact", int(actor.id), int(actor.owner) != int(veil.cells[key].owner))
	veil.contacts = next

static func set_stance(game, actor: Actor, stance: String, point: Array) -> bool:
	if not stance in STANCES: return false
	_ensure_networks(game)
	var veil: Dictionary = game.state.veil
	var networks := networks_at(veil, int(actor.owner), actor.position)
	if networks.is_empty(): return false
	if stance == "offensive":
		if not game.valid_point(point): return false
		var key := Hex.key(Hex.from_point(point))
		if veil.cells.has(key) and networks.has(int(veil.cells[key].network)): return false
	for id in networks:
		var network: Dictionary = veil.networks[str(id)]
		network.stance = stance
		network.stance_order = int(veil.next_stance_order)
		network.target = point.duplicate() if stance == "offensive" else []
		veil.next_stance_order = int(veil.next_stance_order) + 1
	veil.revision = int(veil.revision) + 1
	return true

static func _adopt_stances(game) -> void:
	var veil: Dictionary = game.state.veil
	for actor: Actor in game.state.actors:
		actor.veil_networks = networks_at(veil, int(actor.owner), actor.position)
		if not game.content.units[actor.definition].capabilities.has("move") or actor.veil_networks.is_empty(): continue
		var network: Dictionary = veil.networks[str(actor.veil_networks[0])]
		_inherit_actor(actor, network)

static func _inherit_actor(actor: Actor, network: Dictionary) -> void:
	if int(actor.veil_stance.network) != int(network.id) or int(actor.veil_stance.order) != int(network.stance_order):
		actor.veil_stance = {"mode": network.stance, "network": int(network.id), "order": int(network.stance_order), "target": [], "expires": 0}
		if actor.order.get("veil_order", false): actor.order = {}
	if network.stance == "offensive": actor.veil_stance.target = network.target.duplicate()
	elif network.stance == "defensive" and not network.threat.is_empty():
		actor.veil_stance.target = network.threat.point.duplicate()
		actor.veil_stance.expires = int(network.threat.expires)

static func _ensure_networks(game) -> void:
	# One global network per owner, regardless of gaps or disconnected patches.
	var veil: Dictionary = game.state.veil
	if not veil.network_dirty: return
	var by_owner: Dictionary = {}
	for network in veil.networks.values():
		network.cells = []
		by_owner[str(network.owner)] = int(network.id)
	var keys: Array = veil.cells.keys()
	keys.sort()
	for key in keys:
		var cell: Dictionary = veil.cells[key]
		var owner: String = str(cell.owner)
		if not by_owner.has(owner):
			var id := int(veil.next_network)
			veil.next_network = id + 1
			by_owner[owner] = id
			veil.networks[str(id)] = {"id": id, "owner": int(cell.owner), "stance": "neutral", "stance_order": 0, "target": [], "threat": {}, "cells": []}
		var id := int(by_owner[owner])
		cell.network = id
		veil.networks[str(id)].cells.append(key)
	veil.network_dirty = false
