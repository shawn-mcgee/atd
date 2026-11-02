extends RefCounted
## Flat prototype arena. No nodes, wall time, native physics or floating-point movement.
## q/r positions are integer sub-tiles; y is reserved for elevation in ground positions.
const Canonical = preload("res://core/canonical.gd")
const Hex = preload("res://core/hex_cells.gd")
const Veil = preload("res://core/veil.gd")
const Chyme = preload("res://core/chyme.gd")
const Construction = preload("res://core/construction.gd")
const Exploration = preload("res://core/exploration.gd")
const Escalation = preload("res://core/nest_escalation.gd")
const Mission = preload("res://core/mission.gd")
const Spawning = preload("res://core/spawning.gd")
const SCALE := 1024
var content: Dictionary
var state: Dictionary
var _exploration_cache: Dictionary = {}

func initialize(definitions: Dictionary, players: Array, seed_value: int) -> void:
	content = definitions.duplicate(true)
	_exploration_cache.clear()
	state = {"version": 9, "content_hash": Canonical.hash_of(content), "tick": 0, "next_id": 1,
		"rng": seed_value & 0x7fffffff, "players": players.duplicate(true), "actors": [], "banks": {}, "revealed": {}, "escalations": {}, "events": [], "event_serial": 0, "veil": Veil.initial_state()}
	var starts := [[-8, 0], [8, 0], [0, -8], [0, 8], [-8, 8], [8, -8], [-4, -4], [4, 4]]
	var span := mini(8, int(content.settings.map_radius) - 3)
	for index in players.size():
		var player: Dictionary = players[index]
		state.revealed[str(player.id)] = {}
		@warning_ignore("integer_division")
		var start := [int(starts[index][0]) * span / 8, int(starts[index][1]) * span / 8]
		state.banks[str(player.id)] = int(content.settings.get("chyme", {}).get("initial_reserve", 100)) if player.faction == "lightless" else 100
		var base := "hq" if player.faction == "human" else "nest"
		var position := [int(start[0]) * SCALE, 0, int(start[1]) * SCALE]
		_spawn(base, int(player.id), position)
		var slot := 0
		for type in (["engineer", "marine"] if player.faction == "human" else ["scavenger", "scavenger"]):
			position = [int(start[0]) * SCALE + (slot * 2 - 1) * 768 + _random() % 256 - 128, 0, int(start[1]) * SCALE + 1536]
			_spawn(type, int(player.id), position)
			slot += 1
	Mission.initialize(self)
	Exploration.record(self, _exploration_cache)

func checkpoint() -> Dictionary:
	return state.duplicate(true)

func restore(saved: Dictionary) -> void:
	assert(saved.content_hash == state.content_hash, "Checkpoint content mismatch")
	state = saved.duplicate(true)
	_exploration_cache.clear()

func state_hash() -> String:
	return Canonical.hash_of(state)

func step(commands: Array) -> void:
	state.events = []
	if Mission.finished(self):
		state.tick = int(state.tick) + 1
		return
	for command in commands: _apply(command)
	for actor in state.actors:
		if int(actor.hp) <= 0 or Mission.defeated(self, int(actor.owner)): continue
		if actor.order.get("kind") in Mission.WORK_ORDERS:
			Mission.work(self, actor)
			continue
		if not actor.construction.is_empty():
			Construction.advance(self, actor)
			continue
		if actor.order.get("kind") == "build":
			Construction.approach(self, actor)
			continue
		var definition: Dictionary = content.units[actor.definition]
		var caps: Dictionary = definition.capabilities
		Chyme.passive(self, actor)
		if not actor.production.is_empty(): _production(actor)
		Spawning.tick(self, actor)
		if actor.order.get("kind") == "attack":
			var ordered_target = entity(int(actor.order.target))
			if ordered_target == null or (not actor.order.get("manual", false) and Mission.defeated(self, int(ordered_target.owner))): actor.order = {}
		if caps.has("weapon") and int(state.tick) % 10 == 0: _automatic_order(actor)
		if actor.order.get("kind") == "deliver_chyme":
			Chyme.deliver(self, actor)
			continue
		if actor.order.get("kind") == "attack_veil":
			Veil.attack(self, actor, actor.order.point)
			continue
		var target = null
		if actor.order.get("kind") == "attack": target = entity(int(actor.order.target))
		var visibility := visible_to(int(actor.owner), target) if target != null else 0
		var targetable: bool = visibility == 2 or (visibility == 1 and caps.get("weapon", {}).get("turret", false))
		if target != null and int(target.hp) > 0 and int(target.owner) != int(actor.owner) and targetable:
			_face(actor, target.position)
			var range_fp := int(round(float(caps.get("weapon", {}).get("range", 0)) * SCALE))
			if caps.has("weapon") and distance_squared(actor.position, target.position) <= range_fp * range_fp:
				if int(actor.ready_tick) <= int(state.tick):
					var damage := maxi(int(content.settings.minimum_damage), int(caps.weapon.damage) - int(content.units[target.definition].armor))
					Chyme.collect(self, actor, mini(int(target.hp), damage))
					target.hp = maxi(0, int(target.hp) - damage)
					actor.ready_tick = int(state.tick) + int(caps.weapon.interval_ticks)
					_event("attack", int(actor.id), int(target.id), damage)
					if target.definition == "nest": Veil.signal_at(self, int(target.owner), target.position, "nest_attacked", int(target.id))
			elif caps.has("move"): _move(actor, target.position)
		elif actor.order.get("kind") == "move":
			_move(actor, actor.order.point)
	Escalation.resolve(self)
	Mission.resolve(self)
	state.actors = state.actors.filter(func(actor): return int(actor.hp) > 0)
	Veil.tick(self)
	Exploration.record(self, _exploration_cache)
	Mission.record_visibility(self)
	state.tick = int(state.tick) + 1

func entity(id: int):
	for actor in state.actors:
		if int(actor.id) == id: return actor
	return null

func visible_to(owner: int, target: Dictionary) -> int:
	if int(target.owner) == owner: return 2
	return visibility_at(owner, target.position)

func visibility_at(owner: int, point: Array) -> int:
	if Veil.perceives(self, owner, point): return 2
	var detected := false
	for source in state.actors:
		if int(source.owner) != owner or int(source.hp) <= 0: continue
		var caps: Dictionary = content.units[source.definition].capabilities
		var distance := distance_squared(source.position, point)
		for cap in ["perception", "illumination", "detection"]:
			if not caps.has(cap): continue
			var radius := int(round(float(caps[cap].radius) * SCALE))
			if distance <= radius * radius:
				if cap != "detection": return 2
				detected = true
	return 1 if detected else 0

func _apply(command: Dictionary) -> void:
	if Mission.defeated(self, int(command.player)): return
	for id in command.get("actors", []):
		var actor = entity(int(id))
		if actor == null or int(actor.owner) != int(command.player) or int(actor.hp) <= 0: continue
		if command.get("kind") == "cancel_build":
			Construction.cancel(self, actor)
			continue
		if not actor.construction.is_empty(): continue
		var caps: Dictionary = content.units[actor.definition].capabilities
		match command.get("kind"):
			"repair_point", "mine_nacre", "deliver_nacre", "start_extraction": Mission.order(self, actor, command.kind, int(command.get("target", 0)))
			"build":
				if valid_point(command.get("point")): Construction.order(self, actor, str(command.get("definition", "")), command.point)
			"move":
				if caps.has("move") and valid_point(command.get("point")):
					actor.order = {"kind": "move", "point": command.point.duplicate(), "manual": true}
			"stop": actor.order = {}
			"deliver_chyme": Chyme.order_delivery(self, actor, int(command.get("target", 0)))
			"veil_stance": Veil.set_stance(self, actor, command.stance, command.get("point", []))
			"attack_veil":
				if caps.has("weapon") and valid_point(command.get("point")):
					var point := Hex.point(Hex.from_point(command.point))
					var key := Hex.key(Hex.from_point(point))
					if state.veil.cells.has(key) and int(state.veil.cells[key].owner) != int(actor.owner) and visibility_at(int(actor.owner), point) == 2:
						actor.order = {"kind": "attack_veil", "point": point, "manual": true}
			"attack":
				var target = entity(int(command.get("target", 0)))
				if caps.has("weapon") and target != null and int(target.owner) != int(actor.owner):
					var visibility := visible_to(int(actor.owner), target)
					if visibility == 2 or (visibility == 1 and caps.weapon.get("turret", false)):
						actor.order = {"kind": "attack", "target": int(target.id), "manual": true}
			"train":
				var type: String = command.get("definition", "")
				if not caps.has("factory") or not type in caps.factory.produces or actor.production.size() >= 5: continue
				var bank: String = str(actor.owner)
				var cost := int(content.units[type].cost)
				if int(state.banks[bank]) < cost: continue
				state.banks[bank] = int(state.banks[bank]) - cost
				actor.production.append({"definition": type, "remaining": int(content.units[type].production_ticks)})

func _production(actor: Dictionary) -> void:
	var work := Escalation.rate(self, actor, "production")
	while work > 0 and not actor.production.is_empty():
		var remaining := int(actor.production[0].remaining)
		if remaining > work:
			actor.production[0].remaining = remaining - work
			return
		work -= remaining
		var type: String = actor.production.pop_front().definition
		var position: Array = actor.position.duplicate()
		position[0] = int(position[0]) + _random() % 512 - 256
		position[2] = int(position[2]) + 1024
		if not valid_point(position): position = actor.position.duplicate()
		_spawn(type, int(actor.owner), position)

func _spawn(type: String, owner: int, position: Array) -> void:
	state.actors.append({"id": int(state.next_id), "owner": owner, "definition": type, "position": position.duplicate(),
		"hp": int(content.units[type].hp), "order": {}, "ready_tick": 0, "production": [], "construction": {}, "veil_networks": [],
		"nacre": 0, "mining_ready_tick": 0,
		"facing": [0, 0, -SCALE],
		"spawn_source": 0, "passive_started_tick": int(state.tick), "passive_remaining": int(content.units[type].capabilities.get("passive_spawner", {}).get("interval_ticks", 0)),
		"chyme": 0, "next_chyme_tick": int(state.tick) + int(content.units[type].capabilities.get("chyme_source", {}).get("interval_ticks", 0)),
		"veil_stance": {"mode": "neutral", "network": 0, "order": 0, "target": [], "expires": 0}})
	state.next_id = int(state.next_id) + 1

func _move(actor: Dictionary, destination: Array) -> void:
	var caps: Dictionary = content.units[actor.definition].capabilities
	if not caps.has("move"): return
	_face(actor, destination)
	var distance := integer_sqrt(distance_squared(actor.position, destination))
	var speed := maxi(1, int(round(float(caps.move.speed) * SCALE / int(content.settings.tick_hz))))
	if distance <= speed:
		actor.position = destination.duplicate()
		if actor.order.get("kind") == "move": actor.order = {}
		return
	var point: Array = actor.position.duplicate()
	for axis in [0, 2]:
		@warning_ignore("integer_division")
		point[axis] = int(point[axis]) + (int(destination[axis]) - int(point[axis])) * speed / distance
	if valid_point(point): actor.position = point

func _face(actor: Dictionary, destination: Array) -> void:
	var q := int(destination[0]) - int(actor.position[0])
	var r := int(destination[2]) - int(actor.position[2])
	if q != 0 or r != 0: actor.facing = [q, 0, r]

func _nearest_enemy(actor: Dictionary):
	var best = null
	var nearest := 0x7fffffffffffffff
	for target in state.actors:
		if int(target.hp) <= 0 or int(target.owner) == int(actor.owner) or Mission.defeated(self, int(target.owner)) or visible_to(int(actor.owner), target) != 2: continue
		var distance := distance_squared(actor.position, target.position)
		if distance < nearest:
			nearest = distance
			best = target
	return best

func _automatic_order(actor: Dictionary) -> void:
	if actor.order.get("manual", false): return
	if actor.order.get("kind") == "deliver_chyme": return
	var stance: Dictionary = actor.veil_stance
	var active: bool = stance.mode != "neutral" and not stance.target.is_empty() and (int(stance.expires) == 0 or int(stance.expires) > int(state.tick))
	if active:
		var target = _nearest_enemy(actor)
		actor.order = {"kind": "attack", "target": int(target.id), "veil_order": true} if target != null else {"kind": "move", "point": stance.target.duplicate(), "veil_order": true}
	elif actor.order.get("veil_order", false): actor.order = {}

func valid_point(value) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not component is int: return false
	var radius := int(content.settings.map_radius) * SCALE
	return int(value[1]) == 0 and abs(int(value[0])) <= radius and abs(int(value[2])) <= radius and abs(int(value[0]) + int(value[2])) <= radius

func _random() -> int:
	state.rng = (int(state.rng) * 1103515245 + 12345) & 0x7fffffff
	return int(state.rng)

func _event(type: String, source: int, target: int, amount: int) -> Dictionary:
	state.event_serial = int(state.event_serial) + 1
	var event := {"id": int(state.event_serial), "tick": int(state.tick), "type": type, "source": source, "target": target, "amount": amount}
	state.events.append(event)
	return event

static func distance_squared(a: Array, b: Array) -> int:
	var q := int(a[0]) - int(b[0])
	var r := int(a[2]) - int(b[2])
	return q * q + r * r + q * r

static func integer_sqrt(value: int) -> int:
	if value <= 0: return 0
	var x := value
	@warning_ignore("integer_division")
	var y := (x + 1) / 2
	while y < x:
		x = y
		@warning_ignore("integer_division")
		y = (x + value / x) / 2
	return x
