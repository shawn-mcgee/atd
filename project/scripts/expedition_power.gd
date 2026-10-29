extends RefCounted
const Rules = preload("res://scripts/expedition_rules.gd")
const LINK_RANGE := 10.4
const GENERATOR_RANGE := 3.5
const CORE_RANGE := 7.0
const CORE_OUTPUT := 4
const SOURCES := ["generator", "repeater", "core"]

static func source_range(source: Node3D) -> float:
	return GENERATOR_RANGE if source.kind == "generator" else CORE_RANGE if source.kind == "core" else LINK_RANGE

static func covers(source: Node3D, point: Vector3) -> bool:
	return source.position.distance_squared_to(point) <= source_range(source) * source_range(source)

const GENERATOR_OUTPUT := 12
const GAS_PER_POWER_SECOND := 0.025
var capacity := 0
var demand := 0
var used := 0
var fuel_rate := 0.0
var links: Array[Dictionary] = []
var grids: Array[Dictionary] = []

func grid_for(actor: Node3D, structures: Array, powered_only: bool = false) -> Dictionary:
	if not is_instance_valid(actor) or actor.hp <= 0: return {}
	if actor is ExpeditionPredator: return {}
	var point := actor.position
	if actor is ExpeditionUnit and is_instance_valid(actor.aboard): point = actor.aboard.position
	var source: Node3D
	var nearest := INF
	var best_rank := -1
	for node in structures:
		if node.kind not in SOURCES or not node.complete or not node.enabled or node.hp <= 0 or node.network < 0 or not node.connected: continue
		if powered_only and not node.powered: continue
		var wired: bool = actor is ExpeditionStructure and actor.connected and actor.network >= 0
		if wired and node.network != actor.network: continue
		if not wired and not covers(node, point): continue
		var rank := 1 if node.powered else 0
		var distance: float = node.position.distance_squared_to(point)
		if rank > best_rank or (rank == best_rank and distance < nearest): source = node; nearest = distance; best_rank = rank
	if source == null: return {}
	for grid in grids:
		if grid.id == source.network:
			var connection := grid.duplicate(); connection.source = source
			return connection
	return {}

static func is_electrical(kind: String) -> bool:
	return Rules.STRUCTURES.has(kind) and (kind in SOURCES or int(Rules.STRUCTURES[kind].power) > 0)

static func within_range(a: Vector3, b: Vector3) -> bool:
	return a.distance_squared_to(b) <= LINK_RANGE * LINK_RANGE

static func placement_connection(kind: String, point: Vector3, structures: Array) -> Dictionary:
	var source: Node3D
	var nearest := INF
	var rank := -1
	for b in structures:
		if b.kind not in SOURCES or b.hp <= 0 or not covers(b, point): continue
		var candidate_rank := 3 if b.complete and b.enabled and b.connected else 2 if b.complete and b.enabled else 1 if not b.complete else 0
		var distance := point.distance_squared_to(b.position)
		if candidate_rank > rank or (candidate_rank == rank and distance < nearest):
			source = b; nearest = distance; rank = candidate_rank
	if kind == "generator": return {"state": "source", "text": "New generator / independent power source", "source": source}
	if source == null: return {"state": "missing", "text": "No generator within %.1fm or repeater within %.1fm" % [GENERATOR_RANGE, LINK_RANGE], "source": null}
	if not source.complete: return {"state": "planned", "text": "Planned connection / source still under construction", "source": source}
	if not source.enabled or not source.connected: return {"state": "offline", "text": "In range / source is disconnected or disabled", "source": source}
	if not source.powered: return {"state": "offline", "text": "Grid connection available / generator has no fuel", "source": source}
	var capacity := 0
	var demand := int(Rules.STRUCTURES[kind].power)
	for b in structures:
		if not b.complete or not b.enabled or b.hp <= 0 or b.network != source.network: continue
		if b.kind == "generator": capacity += GENERATOR_OUTPUT
		elif b.kind == "core": capacity += CORE_OUTPUT
		demand += int(Rules.STRUCTURES[b.kind].power)
	if demand > capacity: return {"state": "overload", "text": "Grid connection available / add generation for this load", "source": source}
	return {"state": "ready", "text": "Grid connection available", "source": source}

func tick(structures: Array, economy: RefCounted, dt: float) -> void:
	capacity = 0; demand = 0; used = 0; fuel_rate = 0; links.clear(); grids.clear()
	var networks: Array[Dictionary] = []
	for b in structures: b.connected = false; b.powered = false; b.network = -1
	for root in structures:
		if not root.complete or root.hp <= 0 or not root.enabled or root.kind not in ["core", "generator"] or root.network >= 0: continue
		var network := {"capacity": 0, "auxiliary": 0, "nodes": [], "consumers": []}
		var id := networks.size()
		var frontier: Array = [root]; root.network = id
		while not frontier.is_empty():
			var source = frontier.pop_front()
			source.connected = true; network.nodes.append(source)
			if source.kind == "generator": network.capacity += GENERATOR_OUTPUT
			elif source.kind == "core": network.capacity += CORE_OUTPUT; network.auxiliary += CORE_OUTPUT
			for b in structures:
				if not b.complete or b.hp <= 0 or not b.enabled or b.network >= 0 or b.kind not in SOURCES: continue
				if covers(source, b.position) or (b.kind in ["generator", "core"] and covers(b, source.position)):
					b.network = id; frontier.append(b); links.append({"a": source.position, "b": b.position})
		networks.append(network)
	for b in structures:
		if not b.complete or b.hp <= 0 or not b.enabled or int(Rules.STRUCTURES[b.kind].power) == 0: continue
		var source: Node3D
		var best := INF
		for net in networks:
			for node in net.nodes:
				var distance: float = node.position.distance_squared_to(b.position)
				if covers(node, b.position) and distance < best: source = node; best = distance
		demand += int(Rules.STRUCTURES[b.kind].power)
		if source != null:
			b.connected = true; b.network = source.network; networks[b.network].consumers.append(b)
			if source != b: links.append({"a": source.position, "b": b.position})
	for net in networks:
		var available: int = net.capacity if economy.gas > 0 else net.auxiliary
		var load := 0
		var served: Array = []
		for kind in ["core", "floodlight", "gate", "turret", "laser_turret", "flame_turret", "extractor", "scanner"]:
			for b in net.consumers:
				var need: int = Rules.STRUCTURES[b.kind].power
				if b.kind == kind and load + need <= available: served.append(b); load += need
		var rate := maxf(0, load - int(net.auxiliary)) * GAS_PER_POWER_SECOND
		var fueled: bool = rate == 0 or economy.spend({"gas": rate * dt})
		if not fueled:
			# A fractional final fuel tick falls back to HQ auxiliary output atomically.
			available = int(net.auxiliary); served.clear(); load = 0; rate = 0
			for b in net.consumers:
				var need: int = Rules.STRUCTURES[b.kind].power
				if load + need <= available: served.append(b); load += need
		capacity += available; used += load; fuel_rate += rate
		var grid_demand := 0
		for consumer in net.consumers: grid_demand += int(Rules.STRUCTURES[consumer.kind].power)
		grids.append({"id": net.nodes[0].network, "capacity": available, "installed_capacity": int(net.capacity), "used": load, "demand": grid_demand, "fuel_rate": rate})
		for b in net.nodes: b.powered = available > 0 and (b.kind != "generator" or economy.gas > 0)
		for b in served: b.powered = true
	for b in structures:
		if b.complete and b.enabled and b.hp > 0 and int(Rules.STRUCTURES[b.kind].power) == 0 and b.kind not in SOURCES: b.powered = true
		b.update_visual()
