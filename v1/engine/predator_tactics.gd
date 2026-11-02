extends RefCounted
## Local observations and species roles; no rendering or unseeded randomness.

static func observe(game, group: Dictionary, members: Array) -> void:
	var memories: Array = group.memory
	for i in range(memories.size() - 1, -1, -1):
		var actor: SimEntity = memories[i].actor
		if not SimEntity.valid(actor) or actor.hp <= 0 or (actor is SimUnit and actor.aboard != null) or game.elapsed - float(memories[i].time) > 35:
			memories.remove_at(i)
	for creature in members:
		for actor in game.units + game.structures:
			if actor.hp <= 0 or (actor is SimUnit and actor.aboard != null): continue
			if creature.position.distance_to(actor.position) > float(game.Rules.PREDATORS[creature.kind].sight) or not game.navigation.can_see(creature.position, actor.position): continue
			var memory: Dictionary = {}
			for entry in memories:
				if entry.actor == actor: memory = entry; break
			if memory.is_empty():
				memory = {"actor": actor}; memories.append(memory)
			memory.merge({"position": actor.position, "time": game.elapsed, "kind": actor.kind, "hp": actor.hp,
				"operational": actor is SimStructure and actor.complete and actor.powered and actor.enabled}, true)

static func defended(game, prey: Dictionary, memories: Array) -> bool:
	for memory in memories:
		if game.elapsed - float(memory.time) > 2: continue
		var reach: float = game.Config.value("simulation", memory.kind + "_range") if memory.kind in ["marine", "flamer"] else float(game.Rules.TURRETS[memory.kind].range) if game.Rules.TURRETS.has(memory.kind) and memory.operational else 0.0
		if reach > 0 and memory.position.distance_to(prey.position) <= reach + 1 and game.navigation.can_see(memory.position, prey.position): return true
	return false

static func value(game, memory: Dictionary, species: String, memories: Array) -> float:
	var actor: SimEntity = memory.actor
	var maximum: float = game.Rules.UNITS[actor.kind].hp if actor is SimUnit else game.Rules.STRUCTURES[actor.kind].hp
	var score := 6.0 if memory.kind == "engineer" else 5.0 if memory.kind in ["generator", "repeater", "floodlight", "extractor"] else 4.0 if game.Rules.TURRETS.has(memory.kind) else 3.0 if memory.kind not in ["wall", "gate"] else 0.0
	score += (1.0 - clampf(float(memory.hp) / maximum, 0, 1)) * 4
	if defended(game, memory, memories): score -= 3
	if species == "runner" and memory.kind == "engineer": score += 3
	if species == "stalker" and memory.kind in ["generator", "repeater", "floodlight", "extractor"]: score += 3
	if species == "brute" and game.Rules.TURRETS.has(memory.kind): score += 3
	return score

static func choose(game, director, group: Dictionary, creature: SimPredator, dark_only: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var score := -INF
	var distance := INF
	var locked: Dictionary = {}
	for memory in group.memory:
		if not director.attack_allowed(game, memory.actor, creature): continue
		if dark_only and (game.elapsed - float(memory.time) > 6 or game.light.deterrence(memory.position) >= 0.15): continue
		if not game.mission.stolen and game.elapsed < float(group.defend_until) and memory.position.distance_to(game.mission.hive.position) > 24 and memory.position.distance_to(group.alarm_point) > 12: continue
		if memory.actor == creature.target: locked = memory
		var candidate := value(game, memory, creature.kind, group.memory)
		var reach: float = creature.position.distance_squared_to(memory.position)
		if candidate > score or (is_equal_approx(candidate, score) and reach < distance):
			score = candidate; distance = reach; best = memory
	# Short commitment prevents equally attractive moving targets causing oscillation.
	return locked if game.elapsed < creature.target_until and not locked.is_empty() else best

static func boundary_point(game, creature: SimPredator, anchor: Vector3, flank: float) -> Vector3:
	if game.elapsed < creature.probe_until and creature.probe_anchor.distance_to(anchor) < 2 and not game.navigation.blocked(creature.probe_goal) and game.light.sample(creature.probe_goal) < 0.3: return creature.probe_goal
	var candidates: Array[Dictionary] = []
	var bearing := atan2(creature.position.z - anchor.z, creature.position.x - anchor.x) + flank
	for radius in [6.0, 9.0, 12.0, 15.0, 18.0, 22.0, 28.0, 36.0, 48.0, 64.0]:
		for i in range(12):
			var angle := bearing + i * TAU / 12
			var point: Vector3 = game.navigation.terrain.surface(anchor + Vector3(cos(angle), 0, sin(angle)) * radius)
			if game.navigation.blocked(point): continue
			var visibility: float = game.light.sample(point)
			var score: float = absf(visibility - 0.09) * 30 + game.light.deterrence(point) * 12 + creature.position.distance_to(point) * 0.04
			if visibility > 0.065 and visibility < 0.3: score -= 4
			candidates.append({"point": point, "score": score})
	candidates.sort_custom(func(a, b): return a.score < b.score)
	for candidate in candidates.slice(0, 6):
		var path: PackedVector3Array = game.navigation.path(creature.position, candidate.point, game.light, false)
		if not path.is_empty() and path[-1].distance_to(candidate.point) < 0.8:
			creature.probe_goal = candidate.point; creature.probe_anchor = anchor; creature.probe_until = game.elapsed + 6
			return candidate.point
	return creature.position
