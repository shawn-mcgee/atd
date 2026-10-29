extends RefCounted
## Information comes from local sightings, gunfire, and industrial noise.
## No unit list is used to select a victim until a creature has observed it.
var groups: Array[Dictionary] = []
var outpost_group_created := false
var assaults_started := 0
const FIRST_PROBE_TIME := 18.0
const BASE_GRACE := 55.0
const REINFORCEMENT_INTERVAL := 15.0
const MAX_CREATURES := 16
var reinforcements_spawned := 0

func add_group(anchor: Vector3, id: int, population: int = 4) -> void:
	groups.append({"id": id, "anchor": anchor, "phase": "lurking", "clock": 0.0, "memory": [], "loss": 0.0, "cycles": 0, "rally": anchor,
		"population": population, "refill_clock": 0.0, "spawn_serial": 0})

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

func attack_allowed(game, actor: Node3D) -> bool:
	return game.elapsed >= FIRST_PROBE_TIME and (game.elapsed >= BASE_GRACE or actor.position.distance_to(game.HOME) > 22)

func spawn_member(game, group: Dictionary, initial: bool = false) -> ExpeditionPredator:
	if game.creatures.filter(func(creature): return creature.hp > 0).size() >= (MAX_CREATURES * 2 if game.mission.stolen else MAX_CREATURES): return null
	var radii := [30.0, 34.0, 38.0] if int(group.id) == 0 else [18.0, 22.0, 26.0]
	for radius in radii:
		for i in range(20):
			var angle: float = group.id * 1.7 + group.spawn_serial * 2.4 + i * TAU / 20
			var offset := Vector3(cos(angle), 0, sin(angle))
			var point: Vector3 = game.navigation.terrain.surface(group.anchor + offset * radius)
			if not game.navigation.terrain.contains(point, 1) or game.navigation.blocked(point) or game.light.sample(point) > 0.035: continue
			var safe := true
			for actor in game.units + game.structures:
				if actor.hp <= 0 or (actor is ExpeditionUnit and actor.aboard != null): continue
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
			var creature: ExpeditionPredator = game.add_creature(point, group.id, kind, group.spawn_serial)
			group.spawn_serial += 1
			if not initial: reinforcements_spawned += 1
			return creature
	return null

func replenish(game, group: Dictionary, members: Array, dt: float) -> void:
	if members.size() >= int(group.population): group.refill_clock = 0.0; return
	if game.elapsed < FIRST_PROBE_TIME: return
	group.refill_clock += dt
	if group.refill_clock < (REINFORCEMENT_INTERVAL / 2 if game.mission.stolen else REINFORCEMENT_INTERVAL): return
	var creature := spawn_member(game, group)
	if creature != null:
		members.append(creature); group.refill_clock = 0.0
		if members.size() == 1: change(group, "probing", game)
	else: group.refill_clock = REINFORCEMENT_INTERVAL - 5.0

func defended(game, prey: Dictionary, memories: Array) -> bool:
	for memory in memories:
		if game.elapsed - float(memory.time) > 2 or not is_instance_valid(memory.actor) or memory.actor.hp <= 0: continue
		if memory.actor is ExpeditionUnit and memory.actor.aboard != null: continue
		var reach := 11.0 if memory.kind == "marine" else 5.5 if memory.kind == "flamer" else 14.0 if memory.kind == "turret" and memory.get("operational", false) else 0.0
		if reach == 0: continue
		if memory.actor == prey.actor and memory.kind != "turret": continue
		if memory.position.distance_to(prey.position) <= reach + 1 and game.navigation.can_see(memory.position, prey.position): return true
	return false

func exposed(game, memory: Dictionary, memories: Array) -> bool:
	if game.light.deterrence(memory.position) < 0.15: return true
	return memory.actor is ExpeditionStructure and not defended(game, memory, memories)

func probe_point(game, creature: ExpeditionPredator, anchor: Vector3, flank: float) -> Vector3:
	if game.elapsed < creature.probe_until and creature.probe_anchor.distance_to(anchor) < 2 and not game.navigation.blocked(creature.probe_goal): return creature.probe_goal
	var candidates: Array[Dictionary] = []
	var bearing := atan2(creature.position.z - anchor.z, creature.position.x - anchor.x) + flank
	for radius in [9.0, 12.0, 15.0, 18.0]:
		for i in range(12):
			var angle := bearing + i * TAU / 12
			var point: Vector3 = game.navigation.terrain.surface(anchor + Vector3(cos(angle), 0, sin(angle)) * radius)
			if game.navigation.blocked(point): continue
			var visibility: float = game.light.sample(point)
			var score: float = absf(visibility - float(game.Rules.PREDATORS[creature.kind].probe_light)) * 8 + creature.position.distance_to(point) * 0.06
			if visibility > 0.065: score -= 5
			candidates.append({"point": point, "score": score})
	candidates.sort_custom(func(a, b): return a.score < b.score)
	for candidate in candidates.slice(0, 6):
		var path: PackedVector3Array = game.navigation.path(creature.position, candidate.point, null, false)
		if not path.is_empty() and path[-1].distance_to(candidate.point) < 0.8:
			creature.probe_goal = candidate.point; creature.probe_anchor = anchor; creature.probe_until = game.elapsed + 4
			return candidate.point
	return dark_spot(game, anchor, 12, bearing)

func attack_point(game, creature: ExpeditionPredator, point: Vector3) -> Vector3:
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

func change(group: Dictionary, phase: String, game) -> void:
	group.phase = phase
	group.clock = 0.0
	group.loss = 0.0
	if phase in ["staging", "retreating", "lurking"]:
		group.rally = dark_spot(game, group.anchor, 17.0 if phase == "staging" else 23.0, float(group.id) * 1.7 + float(group.cycles) * 0.8)
	if phase == "staging":
		# Broad scanner activity, without exposing coordinates or a countdown.
		game.report_activity(group.anchor)
		game.play_cue(90.0, 0.45, 0.16)
	if phase == "assault": assaults_started += 1

func tick(game, dt: float) -> void:
	for group in groups:
		var members: Array[ExpeditionPredator] = []
		for creature in game.creatures:
			if creature.group == int(group.id) and creature.hp > 0: members.append(creature)
		replenish(game, group, members, dt)
		if members.is_empty(): continue
		# Visible probes begin during setup; attacks near HQ wait until the grace ends.
		if game.elapsed < FIRST_PROBE_TIME: continue
		group.clock += dt
		var memories: Array = group.memory
		for i in range(memories.size() - 1, -1, -1):
			if not is_instance_valid(memories[i].actor) or memories[i].actor.hp <= 0 or (memories[i].actor is ExpeditionUnit and memories[i].actor.aboard != null) or game.elapsed - float(memories[i].time) > 35.0:
				memories.remove_at(i)
		for creature in members:
			group.loss += creature.loss
			creature.loss = 0
			var actors: Array = []
			actors.append_array(game.units)
			actors.append_array(game.structures)
			for actor in actors:
				if actor.hp <= 0: continue
				if actor is ExpeditionUnit and actor.aboard != null: continue
				if creature.position.distance_to(actor.position) > float(game.Rules.PREDATORS[creature.kind].sight) or not game.navigation.can_see(creature.position, actor.position): continue
				var memory: Dictionary = {}
				for entry in memories:
					if entry.actor == actor: memory = entry; break
				if memory.is_empty():
					memory = {"actor": actor}
					memories.append(memory)
				memory.position = actor.position
				memory.time = game.elapsed
				memory.kind = actor.kind
				memory.hp = actor.hp
				memory.operational = actor is ExpeditionStructure and actor.complete and actor.powered and actor.enabled
		var duration: float = group.clock
		match group.phase:
			"lurking":
				if duration > 4.0 + float(int(group.id) % 3): change(group, "probing", game)
			"probing":
				if float(group.loss) > 60.0: change(group, "retreating", game)
				elif duration > 14.0:
					change(group, "staging" if game.elapsed >= BASE_GRACE and (int(group.id) == 1 or int(group.cycles) % 3 == 2) else "retreating", game)
			"staging":
				if duration > 8.0 and game.elapsed >= BASE_GRACE: change(group, "assault", game)
			"assault":
				if duration > 20.0 or float(group.loss) > 130.0 or members.size() <= 1: change(group, "retreating", game)
			"retreating":
				if duration > 7.0:
					group.cycles += 1
					# A repelled outpost probe regroups on another flank before committing.
					change(group, "staging" if int(group.id) == 1 and int(group.cycles) == 1 else "lurking", game)
		var remembered: Node3D
		var priority := -INF
		var last_point: Vector3 = group.anchor
		var opportunity: Dictionary = {}
		var opportunity_score := -INF
		for memory in memories:
			if not is_instance_valid(memory.actor) or memory.actor.hp <= 0: continue
			var weight := 3.0 if memory.kind == "engineer" else 2.8 if memory.kind == "floodlight" else 1.8 if memory.kind in ["generator", "repeater", "depot", "gas_tank"] else 0.8
			var score: float = weight - float(memory.hp) * 0.002 - group.anchor.distance_to(memory.position) * 0.025
			if game.light.deterrence(memory.position) < 0.15: score += 3
			if exposed(game, memory, memories) and attack_allowed(game, memory.actor) and game.elapsed - float(memory.time) <= 6 and group.anchor.distance_to(memory.position) < 42:
				if score > opportunity_score: opportunity_score = score; opportunity = memory
			if score > priority:
				priority = score
				remembered = memory.actor
				last_point = memory.position
		for i in range(members.size()):
			var creature := members[i]
			creature.state = group.phase
			creature.target = null
			var destination: Vector3
			match group.phase:
				"lurking":
					destination = dark_spot(game, group.anchor, 20.0 + i * 1.5, float(group.cycles) + i * 1.7 + float(group.clock) * 0.035)
				"probing":
					destination = opportunity.position if not opportunity.is_empty() else probe_point(game, creature, last_point, float(i % 3 - 1) * 0.45)
				"staging", "retreating": destination = group.rally + Vector3(i * 1.4, 0, -i * 0.5)
				_:
					destination = last_point + Vector3(i - 1, 0, 0)
					if remembered != null and creature.position.distance_to(remembered.position) < float(game.Rules.PREDATORS[creature.kind].sight) and game.navigation.can_see(creature.position, remembered.position): creature.target = remembered
			if not opportunity.is_empty():
				creature.state = "hunting"; destination = opportunity.position
				var prey: Node3D = opportunity.actor
				if creature.position.distance_to(prey.position) <= float(game.Rules.PREDATORS[creature.kind].sight) and game.navigation.can_see(creature.position, prey.position): creature.target = prey
			if creature.hp < creature.max_hp * 0.35:
				creature.state = "retreating"
				creature.target = null
				destination = dark_spot(game, group.anchor, 25, i + 2)
				if game.light.sample(creature.position) < 0.05: creature.hp = minf(creature.max_hp, creature.hp + dt * 2)
			# Noncommitted creatures shy away from newly illuminated ground.
			if creature.state in ["lurking", "retreating"] and game.light.deterrence(destination) > 0.1:
				destination = dark_spot(game, group.anchor, 25, i + float(group.clock) * 0.1)
			# A closed perimeter is an obstacle to breach, using only observed barriers.
			if creature.state in ["assault", "hunting"] and not game.navigation.clear_segment(creature.position, destination):
				var barrier_distance := 5.0
				for memory in memories:
					var barrier = memory.actor
					if not is_instance_valid(barrier) or not barrier is ExpeditionStructure or barrier.kind not in ["wall", "gate"]: continue
					if barrier.kind == "gate" and barrier.gate_open: continue
					var distance := creature.position.distance_to(barrier.position)
					if distance < barrier_distance:
						barrier_distance = distance; creature.target = barrier; destination = barrier.position
			# The hive reacts immediately to intruders. Theft broadcasts the core's
			# location to the colony and replaces probing with committed retrieval.
			if game.mission.stolen:
				creature.state = "assault"; creature.target = null
				destination = game.mission.destination()
				if is_instance_valid(game.mission.carrier):
					var carrier: ExpeditionUnit = game.mission.carrier
					creature.target = carrier.aboard if is_instance_valid(carrier.aboard) else carrier
			elif int(group.id) == 80:
				var intruder: Node3D
				var distance := 22.0
				for actor in game.units:
					if actor.hp <= 0 or actor.aboard != null or actor.position.distance_to(game.mission.hive.position) > 20: continue
					var reach: float = creature.position.distance_to(actor.position)
					if reach < distance and game.navigation.can_see(creature.position, actor.position): intruder = actor; distance = reach
				if intruder != null: creature.state = "assault"; creature.target = intruder; destination = intruder.position
				else: destination = game.mission.hive.position + Vector3(cos(i * TAU / 6), 0, sin(i * TAU / 6)) * 8
			if creature.target != null: destination = attack_point(game, creature, creature.target.position)
			creature.navigate(destination, game.navigation, game.light)
