extends RefCounted
## Flat prototype arena. No nodes, wall time, native physics or floating-point movement.
## q/r positions are integer sub-tiles; y is reserved for elevation in ground positions.
const Geometry = preload("res://core/geometry.gd")
const Crowd = preload("res://core/crowd.gd")
const Steering = preload("res://core/steering.gd")
const Rally = preload("res://core/rally.gd")
const Navigation = preload("res://core/navigation.gd")
const Canonical = preload("res://core/canonical.gd")
const Hex = preload("res://core/hex_cells.gd")
const Veil = preload("res://core/veil.gd")
const Chyme = preload("res://core/chyme.gd")
const Engineering = preload("res://core/engineering.gd")
const Construction = preload("res://core/construction.gd")
const Illumination = preload("res://core/illumination.gd")
const Exploration = preload("res://core/exploration.gd")
const Escalation = preload("res://core/nest_escalation.gd")
const Mission = preload("res://core/mission.gd")
const Spawning = preload("res://core/spawning.gd")
const SCALE := 1024
var content: Dictionary
var state: Dictionary
var accelerated := true # Implementation choice only; reference/native replay must agree.
var _exploration_cache: Dictionary = {}
var _illumination_cache: Dictionary = {}
var _navigation_cache: Dictionary = {}
var _velocity_snapshot: Dictionary = {}
var _enemy_cache: Dictionary = {}
var _crowd := Crowd.new()
var _crowd_dirty := true
var _inside_step := false
var _navigation_searches := 0
var _navigation_expansions := 0

func initialize(definitions: Dictionary, players: Array, seed_value: int) -> void:
	content = definitions.duplicate(true)
	_exploration_cache.clear()
	_illumination_cache.clear()
	_navigation_cache.clear()
	_velocity_snapshot.clear()
	_enemy_cache.clear()
	_crowd = Crowd.new(accelerated)
	_crowd_dirty = true
	_inside_step = false
	state = {"version": 16, "content_hash": Canonical.hash_of(content), "tick": 0, "next_id": 1,
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
	# Keep starting mobile bodies clear of the authored base footprints.
	for actor in state.actors:
		if not Geometry.structure(self, actor): actor.position = free_spawn(actor.definition, actor.position, int(actor.owner))
	Mission.initialize(self)
	Exploration.record(self, _exploration_cache)

func checkpoint() -> Dictionary:
	return state.duplicate(true)

func restore(saved: Dictionary) -> void:
	assert(saved.content_hash == state.content_hash, "Checkpoint content mismatch")
	state = Canonical.normalize(saved)
	Exploration.reset(_exploration_cache)
	_illumination_cache.clear()
	_navigation_cache.clear()
	_velocity_snapshot.clear()
	_enemy_cache.clear()
	_crowd = Crowd.new(accelerated)
	_crowd_dirty = true
	_inside_step = false

func state_hash() -> String:
	if _crowd.backend != null:
		var bytes: PackedByteArray = _crowd.backend.call("state_bytes", state)
		if not bytes.is_empty():
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(bytes)
			return digest.finish().hex_encode()
	# State already contains integer scalars and string keys. Native sorted JSON
	# preserves the wire hash without a second recursive copy/sort in GDScript.
	return JSON.stringify(state, "", true, true).sha256_text()

func step(commands: Array) -> void:
	state.events = []
	if Mission.finished(self):
		state.tick = int(state.tick) + 1
		return
	Navigation.field(self, _navigation_cache)
	Illumination.field(self, _illumination_cache)
	_enemy_cache.clear()
	_crowd_dirty = true
	_navigation_searches = 0
	_navigation_expansions = 0
	_inside_step = true
	for command in commands: _apply(command)
	_velocity_snapshot = {}
	for actor in state.actors:
		# Velocities are replaced, never edited in place; retain the previous array.
		_velocity_snapshot[str(actor.id)] = actor.get("velocity", [0, 0, 0])
		actor.velocity = [0, 0, 0]
	for actor in state.actors:
		if int(actor.hp) <= 0 or Mission.defeated(self, int(actor.owner)): continue
		if actor.order.get("kind") == "construct":
			Engineering.work(self, actor)
			continue
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
			_face(actor, Geometry.center(self, target))
			var range_fp := int(round(float(caps.get("weapon", {}).get("range", 0)) * SCALE))
			if caps.has("weapon") and distance_to_actor(Geometry.center(self, actor), target) <= range_fp * range_fp:
				actor.navigation = {}
				if int(actor.ready_tick) <= int(state.tick):
					var damage := maxi(int(content.settings.minimum_damage), int(caps.weapon.damage) - int(content.units[target.definition].armor))
					Chyme.collect(self, actor, mini(int(target.hp), damage))
					target.hp = maxi(0, int(target.hp) - damage)
					if int(target.hp) == 0:
						invalidate_light(target)
						invalidate_unit_caches(int(target.owner), true)
						if Geometry.structure(self, target): _navigation_cache.clear()
					actor.ready_tick = int(state.tick) + int(caps.weapon.interval_ticks)
					_event("attack", int(actor.id), int(target.id), damage)
					if target.definition == "nest": Veil.signal_at(self, int(target.owner), target.position, "nest_attacked", int(target.id))
			elif caps.has("move"): _move(actor, target.position, target, range_fp)
		elif actor.order.get("kind") == "approach":
			var following = entity(int(actor.order.target))
			if following == null or int(following.hp) <= 0 or visible_to(int(actor.owner), following) != 2: actor.order = {}
			else:
				var adjacent := Geometry.adjacent_radius(self, actor, following)
				if interaction_distance(actor.position, following) <= adjacent * adjacent: actor.order = {}; actor.navigation = {}; actor.avoidance = {}
				else: _move(actor, following.position, following, adjacent, true)
		elif actor.order.get("kind") == "move":
			if int(actor.order.get("start_tick", 0)) <= int(state.tick): _move(actor, actor.order.point)
	for actor in state.actors:
		if int(actor.hp) > 0 and not Mission.defeated(self, int(actor.owner)) and actor.order.is_empty() and not Geometry.structure(self, actor): Steering.separate_idle(self, actor)
	Escalation.resolve(self)
	Mission.resolve(self)
	state.actors = state.actors.filter(func(actor): return int(actor.hp) > 0)
	Veil.tick(self)
	Exploration.record(self, _exploration_cache)
	Mission.record_visibility(self)
	state.tick = int(state.tick) + 1
	_inside_step = false

func entity(id: int):
	for actor in state.actors:
		if int(actor.id) == id: return actor
	return null

func visible_to(owner: int, target: Dictionary, light_snapshot = null) -> int:
	if int(target.owner) == owner: return 2
	if Geometry.structure(self, target):
		var result := 0
		for cell in Geometry.cells(self, target):
			result = maxi(result, visibility_at(owner, Hex.point(cell), light_snapshot))
			if result == 2: return result
		return result
	return visibility_at(owner, target.position, light_snapshot)

func illumination_cells(owner: int = -1) -> Dictionary:
	var field: Dictionary = _illumination_cache.field if _inside_step and _illumination_cache.has("field") else Illumination.field(self, _illumination_cache)
	return field.all if owner == -1 else field.owners.get(str(owner), {})

func invalidate_light(actor: Dictionary) -> void:
	var caps: Dictionary = content.units[actor.definition].capabilities
	if caps.has("illumination") or caps.has("light_blocker"): _illumination_cache.clear()

func visibility_at(owner: int, point: Array, light_snapshot = null) -> int:
	var lit: Dictionary = illumination_cells(owner) if light_snapshot == null else light_snapshot.get(str(owner), {})
	if Veil.perceives(self, owner, point) or lit.has(Hex.key(Hex.from_point(point))): return 2
	var detected := false
	for source in state.actors:
		if int(source.owner) != owner or int(source.hp) <= 0: continue
		var caps: Dictionary = content.units[source.definition].capabilities
		var distance := distance_squared(Geometry.center(self, source), point)
		for cap in ["perception", "detection"]:
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
			if actor.construction.get("kind") == "blueprint" or actor.order.get("kind") == "construct": Engineering.cancel(self, actor)
			else: Construction.cancel(self, actor)
			continue
		if not actor.construction.is_empty(): continue
		var caps: Dictionary = content.units[actor.definition].capabilities
		if command.get("kind") in ["build", "construct", "repair_point", "mine_nacre", "deliver_nacre", "deliver_chyme", "attack", "attack_veil"]: actor.avoidance = {}
		match command.get("kind"):
			"rally":
				if Rally.capable(self, actor) and valid_point(command.get("point")): actor.rally_point = command.point.duplicate()
			"repair_point", "mine_nacre", "deliver_nacre", "start_extraction": Mission.order(self, actor, command.kind, int(command.get("target", 0)))
			"construct": Engineering.assign(self, actor, int(command.get("target", 0)))
			"build":
				if valid_point(command.get("point")):
					if caps.has("builder"): Engineering.order(self, actor, str(command.get("definition", "")), command.point, int(command.get("rotation", 0)))
					else: Construction.order(self, actor, str(command.get("definition", "")), command.point, int(command.get("rotation", 0)))
			"approach":
				var target = entity(int(command.get("target", 0)))
				if caps.has("move") and target != null and int(target.id) != int(actor.id) and visible_to(int(actor.owner), target) == 2:
					actor.navigation = {}; actor.avoidance = {}
					actor.order = {"kind": "approach", "target": int(target.id), "manual": true}
			"move":
				if caps.has("move") and valid_point(command.get("point")):
					actor.navigation = {}
					actor.avoidance = {}
					actor.order = {"kind": "move", "point": command.point.duplicate(), "manual": true}
			"stop": actor.order = {}; actor.navigation = {}; actor.avoidance = {}
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
		var position := production_spawn(actor, type)
		if position.is_empty():
			actor.production.push_front({"definition": type, "remaining": 0})
			return
		_spawn(type, int(actor.owner), position)
		Rally.dispatch(self, actor, entity(int(state.next_id) - 1))

func _spawn(type: String, owner: int, position: Array) -> void:
	state.actors.append({"id": int(state.next_id), "owner": owner, "definition": type, "position": position.duplicate(), "rotation": 0, "navigation": {}, "velocity": [0, 0, 0], "avoidance": {},
		"hp": int(content.units[type].hp), "order": {}, "ready_tick": 0, "production": [], "construction": {}, "veil_networks": [],
		"nacre": 0, "mining_ready_tick": 0,
		"facing": [0, 0, -SCALE],
		"spawn_source": 0, "passive_started_tick": int(state.tick), "passive_remaining": int(content.units[type].capabilities.get("passive_spawner", {}).get("interval_ticks", 0)),
		"chyme": 0, "next_chyme_tick": int(state.tick) + int(content.units[type].capabilities.get("chyme_source", {}).get("interval_ticks", 0)),
		"veil_stance": {"mode": "neutral", "network": 0, "order": 0, "target": [], "expires": 0}})
	Rally.reset(self, state.actors.back())
	invalidate_light(state.actors.back())
	state.next_id = int(state.next_id) + 1
	invalidate_unit_caches(owner, true)
	if not content.units[type].capabilities.has("move"): _navigation_cache.clear()

func invalidate_unit_caches(owner: int = -1, membership: bool = false) -> void:
	if owner == -1 or membership: _crowd_dirty = true
	for key in _enemy_cache.keys():
		if owner != -1 and int(key) == owner: continue
		if owner == -1 or membership: _enemy_cache.erase(key)

func movement_crowd() -> Crowd:
	if not _inside_step or _crowd_dirty:
		_crowd.rebuild(state.actors, content.units, _velocity_snapshot if _inside_step else {})
		_crowd_dirty = false
	return _crowd

func update_friendly(actor: Dictionary) -> void:
	# Patch foreign obstacle snapshots in place; a moving body does not require
	# recopying and hashing every hostile unit for each interleaved actor.
	for key in _enemy_cache:
		if int(key) == int(actor.owner): continue
		var data: Dictionary = _enemy_cache[key]
		var circle: Dictionary = data.by_id.get(str(actor.id), {})
		if circle.is_empty(): continue
		circle.position = actor.position.duplicate()
		@warning_ignore("integer_division")
		var extent := (int(circle.radius) * 1183 + 1023) / 1024 + 2
		data.bounds[0] = mini(int(data.bounds[0]), int(actor.position[0]) - extent)
		data.bounds[1] = maxi(int(data.bounds[1]), int(actor.position[0]) + extent)
		data.bounds[2] = mini(int(data.bounds[2]), int(actor.position[2]) - extent)
		data.bounds[3] = maxi(int(data.bounds[3]), int(actor.position[2]) + extent)
	if not _crowd_dirty: _crowd.moved(actor)

func friendly_units(owner: int, point: Array, reach: int, scan_limit: int = 0, offset: int = 0) -> Array:
	var result: Array = []
	for body in movement_crowd().query(owner, int(point[0]), int(point[2]), reach, scan_limit, offset):
		result.append({"actor": body.actor, "radius": body.radius})
	return result

func hostile_units(owner: int, point: Array, reach: int, scan_limit: int = 0, offset: int = 0) -> Array:
	var result: Array = []
	for body in movement_crowd().hostiles(owner, int(point[0]), int(point[2]), reach, scan_limit, offset):
		result.append({"actor": body.actor, "radius": body.radius})
	return result

func enemy_circles(owner: int) -> Dictionary:
	var key := str(owner)
	if _inside_step and _enemy_cache.has(key): return _enemy_cache[key]
	var enemies: Array = []
	for other in state.actors:
		if int(other.hp) <= 0 or int(other.owner) == owner or Geometry.structure(self, other): continue
		enemies.append({"id": int(other.id), "position": other.position.duplicate(), "radius": Geometry.radius(self, other)})
	var bounds: Array = []
	for enemy in enemies:
		@warning_ignore("integer_division")
		var extent := (int(enemy.radius) * 1183 + 1023) / 1024 + 2
		var q := int(enemy.position[0]); var r := int(enemy.position[2])
		if bounds.is_empty(): bounds = [q - extent, q + extent, r - extent, r + extent]
		else:
			bounds[0] = mini(int(bounds[0]), q - extent); bounds[1] = maxi(int(bounds[1]), q + extent)
			bounds[2] = mini(int(bounds[2]), r - extent); bounds[3] = maxi(int(bounds[3]), r + extent)
	var by_id: Dictionary = {}
	for circle in enemies: by_id[str(circle.id)] = circle
	var result := {"enemies": enemies, "bounds": bounds, "by_id": by_id}
	_enemy_cache[key] = result
	return result

func navigation_field() -> Dictionary:
	if _inside_step and _navigation_cache.has("field"): return _navigation_cache.field
	return Navigation.field(self, _navigation_cache)

func free_spawn(type: String, preferred: Array, owner: int) -> Array:
	var size := int(round(float(content.units[type].get("collision_radius", 0.2)) * SCALE))
	var data := Navigation.actor_field(self, {"owner": owner})
	if Navigation.segment_clear(self, preferred, preferred, size, data.blocked, data.enemies): return preferred.duplicate()
	var center := Hex.from_point(preferred)
	for ring in range(1, int(content.settings.map_radius) * 2 + 1):
		for q in range(int(center[0]) - ring, int(center[0]) + ring + 1):
			for r in range(int(center[1]) - ring, int(center[1]) + ring + 1):
				var cell := [q, r]
				if Hex.distance(center, cell) == ring and Navigation.center_clear(self, cell, size, data): return Hex.point(cell)
	return []

func production_spawn(source: Dictionary, type: String, preferred: Array = []) -> Array:
	return Rally.spawn_position(self, source, type, preferred)

func distance_to_actor(point: Array, target: Dictionary) -> int:
	return Geometry.distance_to_actor(self, point, target)

func interaction_distance(point: Array, target: Dictionary) -> int:
	return Geometry.interaction_distance(self, point, target)

func _move(actor: Dictionary, destination: Array, target = null, reach: int = 0, interaction: bool = false) -> bool:
	var caps: Dictionary = content.units[actor.definition].capabilities
	if not caps.has("move"): return false
	var point_order: bool = target == null and actor.order.get("kind") == "move"
	if point_order:
		reach = SCALE
		if distance_squared(actor.position, destination) <= reach * reach:
			actor.order = {}; actor.navigation = {}; actor.avoidance = {"settled_goal": destination.duplicate()}
			return true
	var remaining := integer_sqrt(distance_squared(actor.position, destination))
	if actor.avoidance.get("progress_for", []) != destination:
		actor.avoidance.progress_for = destination.duplicate()
		actor.avoidance.progress_best = remaining
		actor.avoidance.progress_tick = int(state.tick)
	elif int(actor.avoidance.progress_best) - remaining >= SCALE / 16:
		actor.avoidance.progress_best = remaining
		actor.avoidance.progress_tick = int(state.tick)
	elif int(state.tick) - int(actor.avoidance.progress_tick) >= maxi(2, int(content.settings.tick_hz) / 2):
		actor.avoidance.pass_ticks = int(content.settings.tick_hz)
		actor.avoidance.progress_tick = int(state.tick)
		actor.avoidance.progress_best = remaining
	var movement := navigation_field()
	var waypoint := Navigation.next(self, actor, destination, target, reach, interaction, movement)
	if waypoint.is_empty():
		if actor.order.get("kind") == "move": actor.order = {}
		return false
	_face(actor, waypoint)
	var distance := integer_sqrt(distance_squared(actor.position, waypoint))
	var speed := maxi(1, int(round(float(caps.move.speed) * SCALE / int(content.settings.tick_hz))))
	var point: Array = actor.position.duplicate()
	if distance <= speed: point = waypoint.duplicate()
	else:
		for axis in [0, 2]:
			@warning_ignore("integer_division")
			point[axis] = int(point[axis]) + (int(waypoint[axis]) - int(point[axis])) * speed / distance
	var intended: Array = point # Steering reads the input; it returns a fresh array when deflecting.
	point = Steering.choose(self, actor, point, speed, movement, waypoint, reach if point_order and waypoint == destination else 0)
	actor.velocity = [int(point[0]) - int(actor.position[0]), 0, int(point[2]) - int(actor.position[2])]
	if point != intended and point != actor.position:
		_face(actor, point)
		actor.navigation.deviated = true
	if point != actor.position:
		invalidate_unit_caches(int(actor.owner))
		invalidate_light(actor)
	actor.position = point
	update_friendly(actor)
	if point_order and distance_squared(point, destination) <= reach * reach: actor.order = {}; actor.navigation = {}; actor.avoidance = {"settled_goal": destination.duplicate()}
	return true

func previous_velocity(actor: Dictionary) -> Array:
	return _velocity_snapshot.get(str(actor.id), actor.get("velocity", [0, 0, 0]))

func _face(actor: Dictionary, destination: Array) -> void:
	var origin := Geometry.center(self, actor)
	var q := int(destination[0]) - int(origin[0])
	var r := int(destination[2]) - int(origin[2])
	if q != 0 or r != 0: actor.facing = [q, 0, r]

func _nearest_enemy(actor: Dictionary):
	var best = null
	var nearest := 0x7fffffffffffffff
	for target in state.actors:
		if int(target.hp) <= 0 or int(target.owner) == int(actor.owner) or Mission.defeated(self, int(target.owner)) or visible_to(int(actor.owner), target) != 2: continue
		var distance := distance_to_actor(Geometry.center(self, actor), target)
		if distance < nearest:
			nearest = distance
			best = target
	return best

func _automatic_order(actor: Dictionary) -> void:
	if actor.order.get("manual", false): return
	if actor.order.get("kind") == "deliver_chyme": return
	var caps: Dictionary = content.units[actor.definition].capabilities
	if caps.get("weapon", {}).get("turret", false) and not caps.has("move"):
		var best = null
		var range_fp := int(round(float(caps.weapon.range) * SCALE))
		var nearest := range_fp * range_fp + 1
		for target in state.actors:
			if int(target.hp) <= 0 or int(target.owner) == int(actor.owner) or Mission.defeated(self, int(target.owner)) or visible_to(int(actor.owner), target) == 0: continue
			var distance := distance_to_actor(Geometry.center(self, actor), target)
			if distance < nearest:
				nearest = distance
				best = target
		actor.order = {"kind": "attack", "target": int(best.id)} if best != null else {}
		return
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

@warning_ignore("integer_division")
static func integer_sqrt(value: int) -> int:
	if value <= 0: return 0
	# Native sqrt supplies only an estimate. Integer division corrects either
	# rounding direction and proves the exact floor, including all int64 inputs.
	# No floating-point approximation can enter movement or checkpoint state.
	var root := int(sqrt(float(value)))
	while root > value / root: root -= 1
	while root + 1 <= value / (root + 1): root += 1
	return root
