extends RefCounted
## Information comes from local sightings, gunfire, and industrial noise.
## No unit list is used to select a victim until a creature has observed it.
var groups: Array[Dictionary] = []
var outpost_group_created := false
var assaults_started := 0

func add_group(anchor: Vector3, id: int) -> void:
	groups.append({"id": id, "anchor": anchor, "phase": "lurking", "clock": 0.0, "memory": [], "loss": 0.0, "cycles": 0, "rally": anchor})

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
			if creature.group == int(group.id): members.append(creature)
		if members.is_empty(): continue
		# The initial grace period permits loading, scanning, and the first drive.
		if game.elapsed < 55.0: continue
		group.clock += dt
		var memories: Array = group.memory
		for i in range(memories.size() - 1, -1, -1):
			if not is_instance_valid(memories[i].actor) or game.elapsed - float(memories[i].time) > 35.0:
				memories.remove_at(i)
		for creature in members:
			group.loss += creature.loss
			creature.loss = 0
			var actors: Array = []
			actors.append_array(game.units)
			actors.append_array(game.structures)
			for actor in actors:
				if actor is ExpeditionUnit and actor.aboard != null: continue
				if creature.position.distance_to(actor.position) > 12 or not game.navigation.can_see(creature.position, actor.position): continue
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
		var duration: float = group.clock
		match group.phase:
			"lurking":
				if duration > (8.0 if int(group.id) == 1 and int(group.cycles) == 0 else 22.0): change(group, "probing", game)
			"probing":
				if float(group.loss) > 22.0: change(group, "retreating", game)
				elif duration > 10.0:
					change(group, "staging" if int(group.id) == 1 else "retreating", game)
			"staging":
				if duration > 12.0: change(group, "assault", game)
			"assault":
				if duration > 20.0 or float(group.loss) > 130.0 or members.size() <= 1: change(group, "retreating", game)
			"retreating":
				if duration > 18.0:
					group.cycles += 1
					# A repelled outpost probe regroups on another flank before committing.
					change(group, "staging" if int(group.id) == 1 and int(group.cycles) == 1 else "lurking", game)
		var remembered: Node3D
		var priority := -INF
		var last_point: Vector3 = group.anchor
		for memory in memories:
			var weight := 3.0 if memory.kind == "engineer" else 2.8 if memory.kind == "floodlight" else 1.8 if memory.kind in ["generator", "repeater", "depot", "gas_tank"] else 0.8
			var score: float = weight - float(memory.hp) * 0.002
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
					if i == 0:
						destination = last_point + Vector3(4, 0, -3)
						if remembered != null and creature.position.distance_to(remembered.position) < 12: creature.target = remembered
					else: destination = dark_spot(game, last_point, 14, i * 1.7)
				"staging", "retreating": destination = group.rally + Vector3(i * 1.4, 0, -i * 0.5)
				_:
					destination = last_point + Vector3(i - 1, 0, 0)
					if remembered != null and creature.position.distance_to(remembered.position) < 12: creature.target = remembered
			if creature.hp < creature.max_hp * 0.35:
				creature.state = "retreating"
				creature.target = null
				destination = dark_spot(game, group.anchor, 25, i + 2)
			# Noncommitted creatures shy away from newly illuminated ground.
			if creature.state in ["lurking", "retreating"] and game.light.deterrence(destination) > 0.1:
				destination = dark_spot(game, group.anchor, 25, i + float(group.clock) * 0.1)
			# A closed perimeter is an obstacle to breach, using only observed barriers.
			if creature.state == "assault" and not game.navigation.clear_segment(creature.position, destination):
				var barrier_distance := 5.0
				for memory in memories:
					var barrier = memory.actor
					if not is_instance_valid(barrier) or not barrier is ExpeditionStructure or barrier.kind not in ["wall", "gate"]: continue
					if barrier.kind == "gate" and barrier.gate_open: continue
					var distance := creature.position.distance_to(barrier.position)
					if distance < barrier_distance:
						barrier_distance = distance; creature.target = barrier; destination = barrier.position
			creature.navigate(destination, game.navigation, game.light)
