extends RefCounted
const Rules = preload("res://scripts/expedition_rules.gd")
const LINK_RANGE := 32.0
const GENERATOR_OUTPUT := 12
const GAS_PER_POWER_SECOND := 0.025
const SCAN_ENERGY := 120.0
const SCAN_CHARGE_RATE := 12.0
var capacity := 0
var demand := 0
var used := 0
var fuel_rate := 0.0
var links: Array[Dictionary] = []

static func is_electrical(kind: String) -> bool:
	return Rules.STRUCTURES.has(kind) and (kind in ["generator", "repeater"] or int(Rules.STRUCTURES[kind].power) > 0)

static func within_range(a: Vector3, b: Vector3) -> bool:
	return a.distance_squared_to(b) <= LINK_RANGE * LINK_RANGE

static func placement_connection(kind: String, point: Vector3, structures: Array) -> Dictionary:
	var source: Node3D
	var nearest := INF
	var rank := -1
	for b in structures:
		if b.kind not in ["generator", "repeater"] or b.hp <= 0 or not within_range(point, b.position): continue
		var candidate_rank := 3 if b.complete and b.enabled and b.connected else 2 if b.complete and b.enabled else 1 if not b.complete else 0
		var distance := point.distance_squared_to(b.position)
		if candidate_rank > rank or (candidate_rank == rank and distance < nearest):
			source = b; nearest = distance; rank = candidate_rank
	if kind == "generator": return {"state": "source", "text": "New generator / independent power source", "source": source}
	if source == null: return {"state": "missing", "text": "No generator or repeater within %.0fm" % LINK_RANGE, "source": null}
	if not source.complete: return {"state": "planned", "text": "Planned connection / source still under construction", "source": source}
	if not source.enabled or not source.connected: return {"state": "offline", "text": "In range / source is disconnected or disabled", "source": source}
	if not source.powered: return {"state": "offline", "text": "Grid connection available / generator has no fuel", "source": source}
	var capacity := 0
	var demand := int(Rules.STRUCTURES[kind].power)
	for b in structures:
		if not b.complete or not b.enabled or b.hp <= 0 or b.network != source.network: continue
		if b.kind == "generator": capacity += GENERATOR_OUTPUT
		demand += int(Rules.STRUCTURES[b.kind].power)
	if demand > capacity: return {"state": "overload", "text": "Grid connection available / add generation for this load", "source": source}
	return {"state": "ready", "text": "Grid connection available", "source": source}

func tick(structures: Array, economy: RefCounted, dt: float) -> void:
	capacity = 0; demand = 0; used = 0; fuel_rate = 0
	links.clear()
	var networks: Array[Dictionary] = []
	for b in structures:
		b.connected = false; b.powered = false; b.network = -1
	for root in structures:
		if not root.complete or root.hp <= 0 or not root.enabled or root.kind != "generator" or root.network >= 0: continue
		var network := {"capacity": 0, "nodes": [], "consumers": []}
		var id := networks.size()
		var frontier: Array = [root]
		root.network = id
		while not frontier.is_empty():
			var source = frontier.pop_front()
			source.connected = true
			network.nodes.append(source)
			if source.kind == "generator": network.capacity += GENERATOR_OUTPUT
			for b in structures:
				if not b.complete or b.hp <= 0 or not b.enabled or b.network >= 0 or b.kind not in ["generator", "repeater"]: continue
				if within_range(source.position, b.position):
					b.network = id; frontier.append(b)
					links.append({"a": source.position, "b": b.position})
		networks.append(network)
	for b in structures:
		if not b.complete or b.hp <= 0 or not b.enabled or int(Rules.STRUCTURES[b.kind].power) == 0: continue
		var best_distance := LINK_RANGE + 0.001
		var source: Node3D
		for net in networks:
			for node in net.nodes:
				var distance: float = b.position.distance_to(node.position)
				if within_range(node.position, b.position) and distance < best_distance: best_distance = distance; source = node
		demand += int(Rules.STRUCTURES[b.kind].power)
		if source != null:
			b.connected = true; b.network = source.network
			networks[b.network].consumers.append(b)
			links.append({"a": source.position, "b": b.position})
	for net in networks:
		var load := 0
		var served: Array = []
		# Automatic safety priority; there is no sector switching or manual allocation.
		for kind in ["core", "floodlight", "gate", "turret", "scanner"]:
			for b in net.consumers:
				var need: int = Rules.STRUCTURES[b.kind].power
				if b.kind == kind and load + need <= int(net.capacity): served.append(b); load += need
		var rate: float = load * GAS_PER_POWER_SECOND
		var charge := 0.0
		var command_center: Node3D
		for b in served:
			if b.kind == "core": command_center = b; break
		if command_center != null and dt > 0:
			charge = minf(SCAN_CHARGE_RATE, minf(float(net.capacity) - load, (SCAN_ENERGY - command_center.scan_charge) / dt))
			charge = maxf(0, charge)
		rate += charge * GAS_PER_POWER_SECOND
		var fueled: bool = economy.gas > 0 and economy.spend({"gas": rate * dt})
		if fueled:
			capacity += int(net.capacity); used += load + ceili(charge); demand += ceili(charge); fuel_rate += rate
			if command_center != null: command_center.scan_charge = minf(SCAN_ENERGY, command_center.scan_charge + charge * dt)
			for b in net.nodes: b.powered = true
			for b in served: b.powered = true
	for b in structures:
		if b.complete and b.enabled and int(Rules.STRUCTURES[b.kind].power) == 0 and b.kind not in ["generator", "repeater"]: b.powered = true
		b.update_visual()
