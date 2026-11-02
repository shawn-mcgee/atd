extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
const Tactics = preload("res://engine/predator_tactics.gd")
## Packs make explicit commitments. Retreat cannot be replaced by an opportunity.
var groups: Array[Dictionary] = []
var outpost_group_created := false
var assaults_started := 0
static var FIRST_PROBE_TIME: float = float(Config.value("predators_ai", "first_probe_time"))
static var BASE_GRACE: float = float(Config.value("predators_ai", "base_grace"))
static var REINFORCEMENT_INTERVAL: float = float(Config.value("predators_ai", "reinforcement_interval"))
static var MAX_CREATURES: int = int(Config.value("predators_ai", "max_creatures"))
var reinforcements_spawned := 0
var last_hive_hp := -1.0

func add_group(anchor: Vector3, id: int, population: int = 4) -> void:
	groups.append({"id": id, "anchor": anchor, "phase": "lurking", "intent": "probe", "clock": 0.0,
		"memory": [], "loss": 0.0, "pending_loss": 0.0, "cycles": 0, "rally": anchor,
		"population": population, "refill_clock": 0.0, "spawn_serial": 0, "probe_id": 0,
		"probe_success": 0.0, "ready_time": 0.0, "ready": false, "defend_until": 0.0, "alarm_point": anchor})

func escalation(game) -> float:
	return clampf((game.elapsed - maxf(BASE_GRACE, game.layout.base_grace)) / Config.value("predators_ai", "escalation_seconds"), 0, 1)

func population_limit(game) -> int:
	return MAX_CREATURES * 2 if game.mission.stolen else roundi(lerpf(MAX_CREATURES, Config.value("predators_ai", "late_max_creatures"), escalation(game)))

func attack_allowed(game, actor: SimEntity, creature: SimPredator = null) -> bool:
	if game.mission.stolen: return true
	if creature != null:
		for group in groups:
			if int(group.id) == creature.group and game.elapsed < float(group.defend_until): return true
	return game.elapsed >= FIRST_PROBE_TIME and (game.elapsed >= maxf(BASE_GRACE, game.layout.base_grace) or actor.position.distance_to(game.HOME) > 22)

func member_lost(creature: SimPredator) -> void:
	for group in groups:
		if int(group.id) == creature.group:
			group.pending_loss += maxf(1, creature.loss)
			return

func check_hive_alarm(game, attacker: SimEntity = null) -> void:
	if not SimEntity.valid(game.mission.hive): return
	var hive: SimStructure = game.mission.hive
	if last_hive_hp >= 0 and hive.hp < last_hive_hp:
		var center: Vector2i = game.Hex.to_axial(hive.position, game.Terrain.CELL)
		for group in groups:
			var delta: Vector2i = game.Hex.to_axial(group.anchor, game.Terrain.CELL) - center
			if maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.x + delta.y))) > int(Config.value("predators_ai", "hive_alert_tiles")): continue
			group.defend_until = game.elapsed + Config.value("predators_ai", "hive_defense_seconds")
			group.alarm_point = attacker.position if SimEntity.valid(attacker) else hive.position
			if group.phase != "assault": change(group, "assault", game)
			for creature in game.creatures:
				if creature.group == int(group.id):
					creature.committed = true; creature.probe_active = false; creature.retreat_remaining = 0
					creature.state = "assault"; creature.repath = 0
	last_hive_hp = hive.hp

func change(group: Dictionary, phase: String, game) -> void:
	group.phase = phase; group.clock = 0.0; group.loss = 0.0
	group.ready_time = 0.0; group.ready = false; group.probe_success = 0.0
	if phase == "staging":
		var period := 1 if escalation(game) >= 0.75 else 2 if escalation(game) >= 0.35 else 4
		group.intent = "assault" if game.elapsed >= maxf(BASE_GRACE, game.layout.base_grace) and posmod(int(group.cycles) + int(group.id), period) == 0 else "probe"
		game.report_activity(group.anchor)
	if phase == "retreating": group.rally = dark_spot(game, group.anchor, 25, float(group.cycles) * 0.8 + float(group.id))
	if phase == "probing":
		group.probe_id = 0
		for creature in game.creatures:
			if creature.group == int(group.id) and creature.hp > 0 and creature.kind == "runner" and creature.retreat_remaining <= 0:
				group.probe_id = creature.simulation_id; break
	if phase == "assault": assaults_started += 1

func replenish(game, group: Dictionary, members: Array, dt: float) -> void:
	var population := int(group.population) + int(escalation(game) * Config.value("predators_ai", "late_group_bonus"))
	if members.size() >= population: group.refill_clock = 0.0; return
	if game.elapsed < FIRST_PROBE_TIME and game.elapsed >= float(group.defend_until) and not game.mission.stolen: return
	var interval := REINFORCEMENT_INTERVAL * (0.5 if game.mission.stolen else lerpf(1, 0.55, escalation(game)))
	group.refill_clock += dt
	if group.refill_clock < interval: return
	var creature := spawn_member(game, group)
	if creature != null:
		members.append(creature); group.refill_clock = 0.0
	else: group.refill_clock = maxf(0, interval - 5)

func pressure_anchor(game, group: Dictionary) -> Vector3:
	if game.elapsed < float(group.defend_until): return group.alarm_point
	if not group.memory.is_empty():
		var best: Dictionary = group.memory[0]
		for memory in group.memory:
			if group.anchor.distance_squared_to(memory.position) < group.anchor.distance_squared_to(best.position): best = memory
		return best.position
	# Established colonies investigate the known landing site, never unseen actors.
	return game.HOME if escalation(game) > 0.25 and int(group.id) != 80 else group.anchor

func update_phase(game, group: Dictionary, members: Array, damage: float, dt: float) -> void:
	var level := escalation(game)
	if game.mission.stolen or game.elapsed < float(group.defend_until):
		if group.phase != "assault": change(group, "assault", game)
		return
	group.clock += dt
	if group.ready: group.ready_time += dt
	group.ready = false
	match group.phase:
		"lurking":
			if damage > 0: change(group, "retreating", game)
			elif members.any(func(creature): return creature.state == "hunting" and creature.target != null): group.clock = 0.0
			elif float(group.clock) >= (4.0 if int(group.cycles) == 0 else lerpf(24, 6, level)): change(group, "staging", game)
		"staging":
			if damage > 0: change(group, "assault" if group.intent == "assault" else "retreating", game)
			elif float(group.ready_time) >= lerpf(10, 4, level): change(group, "assault" if group.intent == "assault" else "probing", game)
		"probing":
			if damage > 0: change(group, "retreating", game)
			elif float(group.probe_success) >= Config.value("predators_ai", "probe_success_seconds") and game.elapsed >= maxf(BASE_GRACE, game.layout.base_grace): change(group, "assault", game)
			elif float(group.clock) >= 18: change(group, "retreating", game)
		"assault":
			if float(group.clock) >= lerpf(25, 75, level) or (float(group.loss) > 130 + level * 200 and level < 0.75): change(group, "retreating", game)
		"retreating":
			if float(group.clock) >= lerpf(12, 6, level):
				group.cycles += 1; change(group, "lurking", game)

func breach(game, group: Dictionary, creature: SimPredator, destination: Vector3) -> SimEntity:
	destination = game.navigation.terrain.surface(destination)
	if game.navigation.clear_segment(creature.position, destination): return null
	var best: SimEntity
	var distance := 10.0 if creature.kind == "brute" else 5.0
	for memory in group.memory:
		var barrier: SimEntity = memory.actor
		if memory.kind not in ["wall", "gate"] or (memory.kind == "gate" and barrier.gate_open): continue
		if game.elapsed - float(memory.time) > 2 or not game.navigation.can_see(creature.position, memory.position): continue
		if Geometry3D.get_closest_point_to_segment(memory.position, creature.position, destination).distance_to(memory.position) > 1.4: continue
		var reach: float = creature.position.distance_to(memory.position)
		if reach < distance: best = barrier; distance = reach
	return best

func tick(game, dt: float) -> void:
	check_hive_alarm(game)
	for group in groups:
		var members: Array[SimPredator] = []
		var damage: float = group.pending_loss
		group.pending_loss = 0.0
		for creature in game.creatures:
			if creature.group != int(group.id) or creature.hp <= 0: continue
			members.append(creature); damage += creature.loss; creature.loss = 0
		replenish(game, group, members, dt)
		if members.is_empty(): continue
		if game.elapsed < FIRST_PROBE_TIME and game.elapsed >= float(group.defend_until) and not game.mission.stolen: continue
		Tactics.observe(game, group, members)
		if int(group.id) == 80 or float(group.defend_until) > 0:
			for memory in group.memory:
				if memory.position.distance_to(game.mission.hive.position) < 20 and game.elapsed - float(memory.time) < 1:
					group.defend_until = maxf(float(group.defend_until), game.elapsed + 10); group.alarm_point = memory.position
		group.loss += damage
		update_phase(game, group, members, damage, dt)
		var anchor := pressure_anchor(game, group)
		var probing := false
		for i in range(members.size()):
			var creature := members[i]
			var previous_target: SimEntity = creature.target
			creature.committed = group.phase == "assault"
			creature.probe_active = group.phase == "probing" and creature.simulation_id == int(group.probe_id)
			if creature.committed: creature.retreat_remaining = 0
			var withdrawing: bool = not creature.committed and (group.phase == "retreating" or creature.retreat_remaining > 0 or creature.hp < creature.max_hp * 0.35)
			var prey: Dictionary = {}
			if not withdrawing:
				if creature.committed or creature.probe_active: prey = Tactics.choose(game, self, group, creature)
				elif group.phase == "lurking": prey = Tactics.choose(game, self, group, creature, true)
			var destination: Vector3
			creature.state = "retreating" if withdrawing else "staging" if group.phase == "probing" and not creature.probe_active else group.phase
			if withdrawing:
				destination = dark_spot(game, group.anchor, 25, float(i) + float(group.cycles))
				if game.light.sample(creature.position) < 0.05: creature.hp = minf(creature.max_hp, creature.hp + dt * 2)
			elif not prey.is_empty():
				destination = prey.position
				if not creature.committed and not creature.probe_active: creature.state = "hunting"
			elif creature.committed:
				destination = anchor
			else:
				destination = Tactics.boundary_point(game, creature, anchor, float(i % 3 - 1) * 0.5 + float(group.clock) * 0.025)
				if creature.position.distance_to(destination) < 2: group.ready = true
			# Stalkers skirt the defenders before approaching their selected support target.
			if creature.kind == "stalker" and creature.committed and not prey.is_empty() and creature.position.distance_to(destination) > 7 and game.elapsed >= float(group.defend_until):
				var direction: Vector3 = (creature.position - destination).normalized()
				var flank: Vector3 = game.navigation.terrain.surface(destination + direction.rotated(Vector3.UP, 0.65 if i % 2 == 0 else -0.65) * 6)
				if not game.navigation.blocked(flank): destination = flank
			creature.target = null
			if not prey.is_empty() and creature.position.distance_to(prey.position) <= float(game.Rules.PREDATORS[creature.kind].sight) and game.navigation.can_see(creature.position, prey.position) and game.elapsed - float(prey.time) < 1:
				creature.target = prey.actor
				if previous_target != creature.target: creature.target_until = game.elapsed + 3
			if creature.probe_active and creature.target != null and creature.position.distance_to(creature.target.position) < 3:
				probing = true
			if game.mission.stolen:
				if prey.is_empty():
					destination = game.mission.destination()
					if SimEntity.valid(game.mission.carrier):
						var carrier: SimUnit = game.mission.carrier
						creature.target = carrier.aboard if SimEntity.valid(carrier.aboard) else carrier
				creature.state = "assault"
			if creature.state in ["assault", "hunting", "probing"] and not withdrawing:
				var barrier := breach(game, group, creature, destination)
				if barrier != null: creature.target = barrier; destination = barrier.position
			if creature.target != null and destination.distance_to(creature.target.position) < 3: destination = attack_point(game, creature, creature.target.position)
			creature.navigate(destination, game.navigation, game.light)
		if group.phase == "probing": group.probe_success = float(group.probe_success) + dt if probing and damage == 0 else 0.0


func populate(game) -> void:
	add_group(game.HOME, 0)
	for i in range(4): spawn_member(game, groups[-1], true)
	# One habitat per distant field, independent of the number of patches.
	var seen: Dictionary = {}
	for resource in game.resource_nodes:
		var field_id: int = resource.get("field", 0)
		if field_id < 2 or seen.has(field_id): continue
		seen[field_id] = true
		add_group(resource.position, field_id + 2, 2)
		for j in range(2): spawn_member(game, groups[-1], true)
	for group in groups:
		if int(group.id) == 80:
			for i in range(6): spawn_member(game, group, true)
	last_hive_hp = game.mission.hive.hp

func spawn_member(game, group: Dictionary, initial: bool = false) -> SimPredator:
	if game.creatures.filter(func(creature): return creature.hp > 0).size() >= population_limit(game): return null
	var radii := [30.0, 34.0, 38.0] if int(group.id) == 0 else [18.0, 22.0, 26.0]
	for radius in radii:
		for i in range(20):
			var angle: float = group.id * 1.7 + group.spawn_serial * 2.4 + i * TAU / 20
			var offset := Vector3(cos(angle), 0, sin(angle))
			var point: Vector3 = game.navigation.terrain.surface(group.anchor + offset * radius)
			if not game.navigation.terrain.contains(point, 1) or game.navigation.blocked(point) or game.light.sample(point) > 0.035: continue
			var safe := true
			for actor in game.units + game.structures:
				if actor.hp <= 0 or (actor is SimUnit and actor.aboard != null): continue
				if point.distance_to(actor.position) < 18: safe = false; break
			for other in game.creatures:
				if other.hp > 0 and point.distance_to(other.position) < 2: safe = false; break
			if not safe: continue
			var approach: Vector3 = game.navigation.terrain.surface(group.anchor + offset * 13)
			var route: PackedVector3Array = game.navigation.path(point, approach, null, false)
			if route.is_empty() or route[-1].distance_to(approach) > 1: continue
			for step in range(1, route.size()):
				if not game.navigation.clear_segment(route[step - 1], route[step]): safe = false; break
			if not safe: continue
			var kind: String = ["runner", "stalker", "runner", "brute"][posmod(int(group.spawn_serial) + int(group.id), 4)]
			var creature: SimPredator = game.add_creature(point, group.id, kind, group.spawn_serial)
			group.spawn_serial += 1
			if not initial: reinforcements_spawned += 1
			return creature
	return null

func attack_point(game, creature: SimPredator, point: Vector3) -> Vector3:
	# Stop beside solid structures, close enough to bite rather than at the next hex center.
	if not game.navigation.blocked(point): return point
	var stand_off := creature.goal.distance_to(point)
	if stand_off > 2 and stand_off < 2.8 and not game.navigation.blocked(creature.goal) and game.navigation.can_see(creature.goal, point): return creature.goal
	var bearing := atan2(creature.position.z - point.z, creature.position.x - point.x)
	for i in range(12):
		var angle := bearing + i * TAU / 12
		var approach: Vector3 = game.navigation.terrain.surface(point + Vector3(cos(angle), 0, sin(angle)) * 2.45)
		if absf(approach.y - point.y) > 0.2 or game.navigation.blocked(approach): continue
		var path: PackedVector3Array = game.navigation.path(creature.position, approach, null, false)
		if not path.is_empty() and path[-1].distance_to(approach) < 0.5: return approach
	return point

func dark_spot(game, anchor: Vector3, radius: float, bias: float) -> Vector3:
	var best := anchor + Vector3(radius, 0, 0)
	var score := INF
	for i in range(12):
		var angle := bias + i * TAU / 12.0
		var point := anchor + Vector3(cos(angle), 0, sin(angle)) * radius
		if not game.navigation.terrain.contains(point, 1): continue
		point = game.navigation.terrain.surface(point)
		var candidate: float = game.light.deterrence(point) * 12.0 + i * 0.025
		if not game.navigation.blocked(point) and candidate < score:
			score = candidate
			best = point
	return best
