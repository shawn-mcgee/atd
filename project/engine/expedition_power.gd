extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
const Rules = preload("res://engine/expedition_rules.gd")
static var LINK_RANGE: float = float(Config.value("power", "link_range"))
static var GENERATOR_RANGE: float = float(Config.value("power", "generator_range"))
static var CORE_RANGE: float = float(Config.value("power", "core_range"))
static var CORE_OUTPUT: int = int(Config.value("power", "core_output"))
const SOURCES := ["generator", "repeater", "core"]

static func source_range(source: SimEntity) -> float:
	return GENERATOR_RANGE if source.kind == "generator" else CORE_RANGE if source.kind == "core" else LINK_RANGE

static func covers(source: SimEntity, point: Vector3) -> bool:
	return source.position.distance_squared_to(point) <= source_range(source) * source_range(source)

static var GENERATOR_OUTPUT: int = int(Config.value("power", "generator_output"))
static var GAS_PER_POWER_SECOND: float = float(Config.value("power", "gas_per_power_second"))
var capacity := 0
var demand := 0
var used := 0
var fuel_rate := 0.0
var links: Array[Dictionary] = []
var grids: Array[Dictionary] = []

static func sources_connect(a: SimEntity, b: SimEntity) -> bool:
	var reach := source_range(a) + source_range(b) if a.kind == "repeater" or b.kind == "repeater" else maxf(source_range(a), source_range(b))
	return a.position.distance_squared_to(b.position) <= reach * reach

static func covers_structure(source: SimEntity, kind: String, point: Vector3, direction: int = 0) -> bool:
	for cell in Footprints.cells(kind, point, direction):
		var tile := preload("res://engine/hex_grid.gd").to_world(cell, 1); tile.y = point.y
		if covers(source, tile): return true
	return false

func grid_for(actor: SimEntity, structures: Array, powered_only: bool = false) -> Dictionary:
	if not SimEntity.valid(actor) or actor.hp <= 0: return {}
	if actor is SimPredator: return {}
	var point := actor.position
	if actor is SimUnit and SimEntity.valid(actor.aboard): point = actor.aboard.position
	var source: SimEntity
	var nearest := INF
	var best_rank := -1
	for node in structures:
		if node.kind not in SOURCES or not node.complete or not node.enabled or node.hp <= 0 or node.network < 0 or not node.connected: continue
		if powered_only and not node.powered: continue
		var wired: bool = actor is SimStructure and actor.connected and actor.network >= 0
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
	var source: SimEntity
	var nearest := INF
	var rank := -1
	for b in structures:
		if b.kind not in SOURCES or b.hp <= 0: continue
		var reach := source_range(b) + LINK_RANGE if kind == "repeater" else source_range(b)
		if kind == "repeater":
			if b.position.distance_squared_to(point) > reach * reach: continue
		elif not covers_structure(b, kind, point): continue
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
				if sources_connect(source, b):
					b.network = id; frontier.append(b); links.append({"a": source.position, "b": b.position})
		networks.append(network)
	for b in structures:
		if not b.complete or b.hp <= 0 or not b.enabled or int(Rules.STRUCTURES[b.kind].power) == 0: continue
		var source: SimEntity
		var best := INF
		for net in networks:
			for node in net.nodes:
				var distance: float = node.position.distance_squared_to(b.position)
				if covers_structure(node, b.kind, b.position, b.build_direction) and distance < best: source = node; best = distance
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
		b.state_changed()
