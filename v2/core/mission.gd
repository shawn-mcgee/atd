extends RefCounted
const Hex = preload("res://core/hex_cells.gd")
const WORK_ORDERS := ["repair_point", "mine_nacre", "deliver_nacre"]

static func initialize(game) -> void:
	game.state.mission = {"humans": {}, "fields": {}, "outcome": {}}
	if not enabled(game): return
	for player in game.state.players:
		if player.faction != "human": continue
		var hq = null
		for actor in game.state.actors:
			if int(actor.owner) == int(player.id) and actor.definition == "hq": hq = actor; break
		var point: Array = hq.position.duplicate()
		point[2] = int(point[2]) - 3 * Hex.SCALE
		if not game.valid_point(point): point = hq.position.duplicate()
		game._spawn(settings(game).extraction_definition, int(player.id), point)
		var extraction = game.entity(int(game.state.next_id) - 1)
		@warning_ignore("integer_division")
		extraction.hp = maxi(1, int(game.content.units[extraction.definition].hp) / 4)
		game.state.mission.humans[str(player.id)] = {"hq": int(hq.id), "extraction": int(extraction.id),
			"repair_remaining": int(settings(game).repair_ticks), "deposited": 0, "countdown": -1, "started_tick": -1, "defeated": false, "defeated_tick": -1}

static func settings(game) -> Dictionary:
	return game.content.settings.get("mission", {})

static func enabled(game) -> bool:
	return bool(settings(game).get("enabled", false))

static func defeated(game, owner: int) -> bool:
	return bool(game.state.mission.humans.get(str(owner), {}).get("defeated", false))

static func finished(game) -> bool:
	return not game.state.mission.outcome.is_empty()

static func order(game, actor: Dictionary, kind: String, target: int = 0, manual: bool = true) -> void:
	if not enabled(game) or defeated(game, int(actor.owner)): return
	var progress: Dictionary = game.state.mission.humans.get(str(actor.owner), {})
	if progress.is_empty(): return
	if kind == "start_extraction":
		if int(actor.id) == int(progress.extraction) and int(progress.repair_remaining) == 0 and int(progress.deposited) >= int(settings(game).threshold) and int(progress.countdown) < 0:
			progress.countdown = int(settings(game).countdown_ticks)
			progress.started_tick = int(game.state.tick)
			_event(game, "extraction_started", int(actor.owner), int(actor.id), int(progress.countdown))
		return
	if not game.content.units[actor.definition].capabilities.has("mission_worker"): return
	if kind == "mine_nacre":
		var field: Dictionary = game.state.mission.fields.get(str(target), {})
		if field.is_empty() or not int(actor.owner) in field.known_by: return
		actor.order = {"kind": kind, "target": target, "manual": manual}
	elif kind in ["repair_point", "deliver_nacre"]:
		if target != 0 and target != int(progress.extraction): return
		if kind == "repair_point" and int(progress.repair_remaining) == 0: return
		if kind == "deliver_nacre" and int(actor.nacre) == 0: return
		actor.order = {"kind": kind, "target": int(progress.extraction), "manual": manual}

static func work(game, actor: Dictionary) -> void:
	var progress: Dictionary = game.state.mission.humans.get(str(actor.owner), {})
	var cap: Dictionary = game.content.units[actor.definition].capabilities.get("mission_worker", {})
	if progress.is_empty() or cap.is_empty(): actor.order = {}; return
	var kind: String = actor.order.kind
	var field: Dictionary = game.state.mission.fields.get(str(actor.order.get("target", 0)), {}) if kind == "mine_nacre" else {}
	var receiver = game.entity(int(progress.extraction))
	if receiver == null or int(receiver.hp) <= 0: actor.order = {}; return
	if kind == "mine_nacre" and field.is_empty(): actor.order = {}; return
	var destination: Array = field.position if kind == "mine_nacre" else receiver.position
	game._face(actor, destination)
	var radius := int(round(float(cap.work_range) * Hex.SCALE))
	if game.distance_squared(actor.position, destination) > radius * radius:
		game._move(actor, destination)
		return
	match kind:
		"repair_point":
			if int(progress.repair_remaining) > 0:
				progress.repair_remaining = maxi(0, int(progress.repair_remaining) - 1)
				if int(progress.repair_remaining) == 0:
					receiver.hp = int(game.content.units[receiver.definition].hp)
					_event(game, "extraction_repaired", int(actor.owner), int(receiver.id), 0)
			if int(progress.repair_remaining) == 0:
				if int(actor.nacre) > 0: actor.order.kind = "deliver_nacre"
				else: actor.order = {}
		"mine_nacre":
			if int(field.remaining) <= 0:
				if int(actor.nacre) > 0: _return_cargo(actor, progress)
				else: actor.order = {}
				return
			if int(actor.nacre) < int(cap.capacity) and int(actor.mining_ready_tick) <= int(game.state.tick):
				var amount := mini(int(cap.mining_amount), mini(int(cap.capacity) - int(actor.nacre), int(field.remaining)))
				actor.nacre = int(actor.nacre) + amount
				field.remaining = int(field.remaining) - amount
				actor.mining_ready_tick = int(game.state.tick) + int(cap.mining_interval_ticks)
				_event(game, "nacre_mined", int(actor.owner), int(actor.id), amount)
			if int(actor.nacre) >= int(cap.capacity) or int(field.remaining) == 0: _return_cargo(actor, progress)
		"deliver_nacre":
			if int(progress.repair_remaining) > 0:
				actor.order.kind = "repair_point"
				return
			progress.deposited = int(progress.deposited) + int(actor.nacre)
			if int(actor.nacre) > 0: _event(game, "nacre_deposited", int(actor.owner), int(actor.id), int(actor.nacre))
			actor.nacre = 0
			var resume := int(actor.order.get("resume", 0))
			var manual := bool(actor.order.get("manual", false))
			actor.order = {}
			if resume > 0: order(game, actor, "mine_nacre", resume, manual)

static func _return_cargo(actor: Dictionary, progress: Dictionary) -> void:
	actor.order = {"kind": "deliver_nacre", "target": int(progress.extraction), "resume": int(actor.order.target), "manual": bool(actor.order.get("manual", false))}

static func resolve(game) -> void:
	if not enabled(game): return
	for actor in game.state.actors:
		if actor.definition == "nest" and int(actor.hp) <= 0 and not game.state.mission.fields.has(str(actor.id)):
			game.state.mission.fields[str(actor.id)] = {"position": actor.position.duplicate(), "remaining": int(settings(game).nacre_amount), "known_by": []}
	var living := 0
	for player in game.state.players:
		if player.faction != "human": continue
		var progress: Dictionary = game.state.mission.humans[str(player.id)]
		var hq = game.entity(int(progress.hq))
		var extraction = game.entity(int(progress.extraction))
		if not progress.defeated and (hq == null or int(hq.hp) <= 0 or extraction == null or int(extraction.hp) <= 0):
			progress.defeated = true
			progress.defeated_tick = int(game.state.tick)
			progress.countdown = -1
			for actor in game.state.actors:
				if int(actor.owner) == int(player.id): actor.order = {}; actor.production = []
			_event(game, "participant_defeated", int(player.id), 0, 0)
		if not progress.defeated: living += 1
	if living == 0:
		for player in game.state.players:
			if player.faction == "lightless": _win(game, int(player.id), "lightless", 0)
		return
	for player in game.state.players:
		if player.faction != "human": continue
		var progress: Dictionary = game.state.mission.humans[str(player.id)]
		if progress.defeated or int(progress.countdown) < 0 or int(progress.started_tick) == int(game.state.tick): continue
		progress.countdown = maxi(0, int(progress.countdown) - 1)
		if int(progress.countdown) == 0:
			_win(game, int(player.id), "human", int(progress.deposited))
			return

static func record_visibility(game) -> void:
	# Resolve discoveries after membrane growth/decay, using this tick's final senses.
	for field in game.state.mission.fields.values():
		for player in game.state.players:
			if not int(player.id) in field.known_by and game.visibility_at(int(player.id), field.position) == 2: field.known_by.append(int(player.id))

static func _win(game, owner: int, faction: String, nacre: int) -> void:
	game.state.mission.outcome = {"winner": owner, "faction": faction, "nacre": nacre, "tick": int(game.state.tick)}
	var event := _event(game, "match_won", owner, 0, nacre)
	event.faction = faction

static func _event(game, kind: String, owner: int, source: int, amount: int) -> Dictionary:
	var event: Dictionary = game._event(kind, source, 0, amount)
	event.owner = owner
	return event
