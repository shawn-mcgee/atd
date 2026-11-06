class_name WorldState
extends RefCounted

var cfg: Dictionary
var seed_value := 1
var tick := 0
var time_seconds := 0.0
var radius := 36
var tiles: Dictionary = {}
var units: Dictionary = {}
var structures: Dictionary = {}
var players: Dictionary = {}
var visible: Dictionary = {}
var detected: Dictionary = {}
var illuminated: Dictionary = {}
var known: Dictionary = {}
var gloom: Dictionary = {}
var shots: Array = []
var feedback_events: Array = []
var feedback_serial := 0
var medusa_dead := false
var ended := false
var result := ""
var paused := false
var speed := 1.0
var next_id := 1
var random := RandomNumberGenerator.new()
var navigation := AStar2D.new()
var dark_navigation := AStar2D.new()
var point_ids: Dictionary = {}
var corpse := Vector2i.ZERO
var gloom_spread_time := 0.0

func _init(settings: Dictionary = {}) -> void:
	cfg = settings

func reset(map_seed: int, count: int = 1) -> void:
	seed_value = map_seed
	random.seed = map_seed
	radius = int(cfg.map.radiusTiles)
	tick = 0
	time_seconds = 0
	gloom_spread_time = 0
	next_id = 1
	feedback_events.clear(); feedback_serial = 0
	ended = false
	result = ""
	medusa_dead = false
	paused = false
	speed = 1.0
	for collection in [tiles, units, structures, players, visible, detected, illuminated, known, gloom, point_ids]: collection.clear()
	for cell in HexGrid.disk(Vector2i.ZERO, radius):
		tiles[cell] = {"cliff": random.randf() < float(cfg.map.cliffTileFraction), "resource": "", "amount": 0, "rock_health": float(cfg.map.cliffHealth)}
	var inset := radius - int(cfg.map.anchorEdgeInsetTiles)
	var corners: Array[Vector2i] = []
	for direction in HexGrid.DIRECTIONS: corners.append(direction * inset)
	var selected: Array[int] = []
	var best_score := -1
	var choices: Array = []
	for mask in range(1, 64):
		var indices: Array[int] = []
		for i in range(6):
			if mask & (1 << i): indices.append(i)
		if indices.size() != count: continue
		var minimum := 999
		var total := 0
		for a in indices:
			for b in indices:
				if a >= b: continue
				var dist := HexGrid.distance(corners[a], corners[b])
				minimum = mini(minimum, dist)
				total += dist
		var score := minimum * 10000 + total
		if score > best_score:
			best_score = score
			choices.clear()
		if score == best_score: choices.append(indices)
	selected.assign(choices[random.randi_range(0, choices.size() - 1)])
	for owner in range(count):
		var spawn := corners[selected[owner]]
		players[owner] = {"resources": cfg.map.startingResources.duplicate(true), "alive": true, "anchor": 0, "upgrades": {}, "extracting": false, "remaining": 0.0}
		known[owner] = {}
		for c in HexGrid.disk(spawn, 6):
			if tiles.has(c): tiles[c].cliff = false
		var anchor := add_structure("anchor", spawn, owner)
		players[owner].anchor = anchor
		add_unit("engineer", HexGrid.world(spawn + Vector2i(2, 0)), owner)
		add_unit("marine", HexGrid.world(spawn + Vector2i(2, -1)), owner)
		_field(spawn + Vector2i(-2, 3), "gas", 1)
		_field(spawn + Vector2i(3, -1), "ore", 3)
		for c in HexGrid.line(spawn, Vector2i.ZERO):
			for nearby in HexGrid.disk(c, 1):
				if tiles.has(nearby): tiles[nearby].cliff = false
	for resource in ["ore", "gas"]:
		for i in range(int(cfg.map.additionalFieldsPerPlayer[resource]) * count):
			var center := Vector2i(random.randi_range(-radius + 4, radius - 4), random.randi_range(-radius + 4, radius - 4))
			if not tiles.has(center) or HexGrid.distance(center) < 5: continue
			var roll := random.randi_range(0, 5)
			_field(center, resource, 1 if roll < 3 else 3 if roll < 5 else 7, false)
	for c in HexGrid.disk(Vector2i.ZERO, 3): tiles[c].cliff = false
	add_structure("medusa", Vector2i.ZERO, -1)
	for i in range(int(cfg.lightless.startingScavengers)):
		add_unit("scavenger", HexGrid.world(HexGrid.DIRECTIONS[i % 6] * 2), -1)
	for c in HexGrid.disk(Vector2i.ZERO, int(cfg.structures.medusa.gloomRangeBeyondFootprintTiles) + 1):
		gloom[c] = float(cfg.gloom.tileHealth)
	_rebuild_navigation()
	_update_power(0)
	update_visibility()

func _field(center: Vector2i, resource: String, size: int, clear_cliff: bool = true) -> void:
	var cells: Array[Vector2i] = [center]
	if size == 3: cells.append_array([center + Vector2i(1, 0), center + Vector2i(0, 1)])
	if size == 7: cells = HexGrid.disk(center, 1)
	for c in cells:
		if not tiles.has(c) or tiles[c].resource != "": continue
		tiles[c].resource = resource
		tiles[c].amount = int(cfg.map.resourcePatchAmounts[resource])
		if clear_cliff: tiles[c].cliff = false

func add_unit(kind: String, position: Vector2, owner: int) -> int:
	var id := next_id
	next_id += 1
	var definition: Dictionary = cfg.units[kind]
	units[id] = {"id": id, "kind": kind, "pos": position, "owner": owner, "hp": float(definition.health), "job": {"kind": "idle"}, "route": [], "cargo": {}, "cooldown": 0.0, "work": 0.0, "stance": str(definition.get("defaultStance", cfg.lightless.startingStance)), "home": position, "last_damage": -999, "target": 0, "driver": 0, "vehicle": 0, "heading": 0.0}
	units[id].passengers = []
	return id

func add_structure(kind: String, cell: Vector2i, owner: int, built: bool = true, depot_type: String = "ore") -> int:
	var id := next_id
	next_id += 1
	structures[id] = {"id": id, "kind": kind, "cell": cell, "owner": owner, "hp": float(cfg.structures[kind].health) if built else float(cfg.construction.startingHealth), "built": built, "started": built, "depot_type": depot_type, "enabled": true, "powered": false, "brownout": false, "blackout": false, "open": false, "locked": false, "buffer": 0, "cycle": 0.0, "batch": {}, "operators": [], "kits": [], "vehicles": [], "upgrades": [], "fuel": 0.0, "cooldown": 0.0, "passive": 0.0}
	structures[id].configuration_remaining = 0.0
	structures[id].personnel_source = 0
	structures[id].request_personnel = bool(cfg.personnel.personnelRequestDefaultEnabled)
	structures[id].vehicle_assignments = {}
	if owner >= 0 and kind in ["armory", "factory", "cradle"]:
		var source := personnel_source(owner, cell)
		if not source.is_empty(): structures[id].personnel_source = source.id
	return id

func footprint(s: Dictionary) -> Array[Vector2i]:
	return HexGrid.disk(s.cell, int(cfg.structures[s.kind].footprintRadiusTiles))

func blocked(cell: Vector2i, ignore: int = 0) -> bool:
	if not tiles.has(cell) or HexGrid.distance(cell) >= radius or tiles[cell].cliff: return true
	for s in structures.values():
		if s.id == ignore or not s.started: continue
		if s.kind == "gate" and s.open: continue
		if cell in footprint(s): return true
	return false

func _rebuild_navigation() -> void:
	navigation.clear()
	dark_navigation.clear()
	point_ids.clear()
	var id := 0
	for cell in tiles:
		point_ids[cell] = id
		navigation.add_point(id, HexGrid.world(cell))
		navigation.set_point_disabled(id, blocked(cell))
		dark_navigation.add_point(id, HexGrid.world(cell), float(cfg.lightless.darkPathLightPenalty) if is_lit(cell) else 1.0)
		dark_navigation.set_point_disabled(id, blocked(cell))
		id += 1
	for cell in tiles:
		for direction in HexGrid.DIRECTIONS:
			var neighbour: Vector2i = cell + direction
			if point_ids.has(neighbour) and point_ids[cell] < point_ids[neighbour]:
				navigation.connect_points(point_ids[cell], point_ids[neighbour])
				dark_navigation.connect_points(point_ids[cell], point_ids[neighbour])

func is_lit(cell: Vector2i) -> bool:
	for area in illuminated.values():
		if area.has(cell): return true
	return false

func nearest_free(cell: Vector2i) -> Vector2i:
	for ring in range(0, 8):
		for c in HexGrid.disk(cell, ring):
			if not blocked(c): return c
	return cell

func move_to(u: Dictionary, destination: Vector2) -> void:
	var start := nearest_free(HexGrid.cell(u.pos))
	var finish := nearest_free(HexGrid.cell(destination))
	u.route = []
	if not point_ids.has(start) or not point_ids.has(finish): return
	var graph := dark_navigation if u.owner < 0 and u.job.kind != "attack" else navigation
	# Gates remain solid for collision and light. Temporarily admit only the owner's
	# unlocked doors while calculating this route; restore the shared graph afterward.
	var admitted: Array[int] = []
	for gate in structures.values():
		if gate.kind != "gate" or gate.owner != u.owner or not gate.built or gate.locked or gate.open: continue
		for cell in footprint(gate):
			if point_ids.has(cell): graph.set_point_disabled(point_ids[cell], false); admitted.append(point_ids[cell])
	var path := graph.get_point_path(point_ids[start], point_ids[finish], true)
	for id in admitted: graph.set_point_disabled(id, true)
	for p in path: u.route.append(p)
	if not blocked(HexGrid.cell(destination)) and not u.route.is_empty() and HexGrid.cell(u.route.back()) == finish: u.route[u.route.size() - 1] = destination

func _move(u: Dictionary, delta: float) -> bool:
	if u.vehicle != 0 or u.get("buried", false) or u.get("transition", "") != "": return false
	if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0: return false
	if u.route.is_empty(): return false
	var goal: Vector2 = u.route[0]
	for gate in structures.values():
		if gate.kind != "gate" or gate.open or not gate.built or not HexGrid.cell(goal) in footprint(gate): continue
		if gate.owner == u.owner and not gate.locked:
			if not gate.has("opening_remaining"): gate.opening_remaining = float(cfg.construction.gateOpenSeconds); gate.auto_close = true
			return false
		u.route.clear(); return false
	var distance: float = u.pos.distance_to(goal)
	var step := float(cfg.units[u.kind].speedTilesPerSecond) * delta
	if distance <= step:
		if not blocked(HexGrid.cell(goal)): u.pos = goal
		u.route.pop_front()
	else:
		var direction: Vector2 = (goal - u.pos).normalized()
		u.heading = atan2(-direction.x, -direction.y)
		var proposed: Vector2 = u.pos + direction * step
		if not blocked(HexGrid.cell(proposed)): u.pos = proposed
		else: u.route.clear()
	return true

func resources(owner: int) -> Dictionary:
	return players[owner].resources

func capacity(owner: int, resource: String) -> int:
	var has_anchor := structures.has(int(players[owner].anchor))
	if resource == "nacre": return int(cfg.match.anchorNacreCapacity) if has_anchor else 0
	var amount := int(cfg.map.anchorStorage.get(resource, 0)) if has_anchor else 0
	for s in structures.values():
		if s.owner == owner and s.kind == "depot" and s.built and float(s.get("configuration_remaining", 0)) <= 0 and s.depot_type == resource: amount += int(cfg.economy.depotCapacityPerResource)
	return amount

func _pay(owner: int, cost: Dictionary) -> bool:
	for resource in cost:
		if int(resources(owner).get(resource, 0)) < int(cost[resource]): return false
	for resource in cost: resources(owner)[resource] = int(resources(owner).get(resource, 0)) - int(cost[resource])
	return true

func command(owner: int, order: Dictionary) -> String:
	if ended or not players.has(owner) or not players[owner].alive: return "Player cannot issue orders"
	var action := str(order.get("action", ""))
	if not order.get("ids", []) is Array or order.get("ids", []).size() > 128: return "Invalid unit selection"
	var required: Dictionary = {"move": ["x", "z"], "patrol": ["x", "z"], "escort": ["target"], "mine": ["q", "r"], "attack": ["target"], "equip": ["target"], "board": ["target"], "load_cargo": ["target"], "excavate": ["q", "r"], "build": ["q", "r"]}
	for field in required.get(action, []):
		if not order.has(field) or not (order[field] is int or order[field] is float) or not is_finite(float(order[field])): return "Invalid order coordinates or target"
	if action in ["build", "kit", "vehicle"] and not order.get("kind") is String: return "Missing production type"
	if action == "stance" and not order.get("stance") is String: return "Invalid stance"
	var ids: Array = order.get("ids", [])
	for raw_id in ids:
		if not (raw_id is int or raw_id is float): return "Invalid unit selection"
	if action in ["patrol", "escort"]:
		var target := entity(int(order.get("target", 0)))
		if action == "escort" and (target.is_empty() or target.owner != owner): return "Choose a friendly unit or structure to escort"
		var assigned := 0
		for raw_id in ids:
			var unit: Dictionary = units.get(int(raw_id), {})
			if unit.is_empty() or unit.owner != owner or int(unit.vehicle) != 0 or unit.get("buried", false) or unit.get("transition", "") != "": continue
			if action == "escort" and unit.id == target.id: continue
			if action == "patrol":
				var old_route: Array = unit.route.duplicate()
				move_to(unit, Vector2(float(order.x), float(order.z)))
				if unit.route.is_empty(): unit.route = old_route; continue
				var finish: Vector2 = unit.route.back()
				unit.job = {"kind": "patrol", "a": [unit.pos.x, unit.pos.y], "b": [finish.x, finish.y], "leg": 1, "anchor": [unit.pos.x, unit.pos.y], "interrupted": false, "repath": 0.0}
				unit.home = finish
			else:
				var per_ring := int(cfg.movement.routeOrders.escortSlotsPerRing)
				var ring := assigned / per_ring
				var slots := mini(per_ring, ids.size() - ring * per_ring)
				var index := assigned % per_ring
				var angle := float(index) * TAU / maxi(1, slots) if target.has("cell") else (float(index) / maxi(1, slots - 1) - 0.5) * deg_to_rad(float(cfg.movement.routeOrders.escortRearArcDegrees)) if slots > 1 else 0.0
				var offset := [cos(angle), sin(angle)] if target.has("cell") else [sin(angle), cos(angle)]
				unit.job = {"kind": "escort", "target": target.id, "offset": offset, "ring": ring, "relative": target.has("pos"), "repath": 0.0}
			unit.target = 0; assigned += 1
		return "%s assigned to %d units" % [action.capitalize(), assigned] if assigned > 0 else "No eligible units or reachable route"
	if action == "burrow":
		var changed := false
		for raw_id in ids:
			var unit: Dictionary = units.get(int(raw_id), {})
			if unit.is_empty() or unit.owner != owner: continue
			changed = BurrowRules.request(self, unit, not bool(unit.get("buried", false))) or changed
		return "Burrowing transition started" if changed else "No eligible stationary burrower selected"
	if action == "attack_tile":
		var cell := Vector2i(int(order.get("q", 99999)), int(order.get("r", 99999)))
		if not detected.get(owner, {}).has(cell): return "No radar contact on that tile"
		var assigned := false
		for raw_id in ids:
			var turret: Dictionary = structures.get(int(raw_id), {})
			if turret.is_empty() or turret.owner != owner or not cfg.structures[turret.kind].has("weapon"): continue
			for target in units.values():
				if target.owner != owner and HexGrid.cell(target.pos) == cell and TargetRules.targetable(self, turret, target):
					turret.target = target.id; turret.manual_target = true; assigned = true; break
		return "Turret contact target assigned" if assigned else "Select a turret; infantry require vision"
	if action == "attack":
		for raw_id in ids:
			var turret: Dictionary = structures.get(int(raw_id), {})
			var target := entity(int(order.get("target", 0)))
			if not turret.is_empty() and turret.owner == owner and cfg.structures[turret.kind].has("weapon") and not target.is_empty() and TargetRules.targetable(self, turret, target):
				turret.target = target.id; turret.manual_target = true
	if action == "unload":
		for raw_id in ids:
			var vehicle := units.get(int(raw_id), {}) as Dictionary
			if not vehicle.is_empty() and vehicle.owner == owner and cfg.units[vehicle.kind].has("driverSeats"): unload_vehicle(vehicle, false)
		return "Occupants unloaded; passengers leave before the driver"
	if action == "excavate":
		var cell := Vector2i(int(order.get("q", 99999)), int(order.get("r", 99999)))
		if not known[owner].has(cell) or not tiles.has(cell) or not tiles[cell].cliff or HexGrid.distance(cell) >= radius: return "Select a revealed cliff inside the map boundary"
		for raw_id in ids:
			var unit := units.get(int(raw_id), {}) as Dictionary
			if not unit.is_empty() and unit.owner == owner and unit.kind == "excavator":
				unit.job = {"kind": "excavate", "source": HexGrid.key(cell)}; move_to(unit, HexGrid.world(nearest_free(cell)))
		return "Cliff clearing ordered; a driver is required"
	if action == "load_cargo":
		var vehicle := units.get(int(order.get("target", 0)), {}) as Dictionary
		if vehicle.is_empty() or vehicle.owner != owner or not cfg.units[vehicle.kind].has("driverSeats") or int(cfg.units[vehicle.kind].cargoCapacity) == 0: return "Choose a friendly cargo vehicle"
		for raw_id in ids:
			var worker := units.get(int(raw_id), {}) as Dictionary
			if not worker.is_empty() and worker.owner == owner and worker.kind in ["operator", "engineer"] and int(worker.vehicle) == 0:
				worker.job = {"kind": "load_cargo", "target": vehicle.id}; move_to(worker, vehicle.pos)
		return "Load cargo ordered; workers retain cargo if the vehicle is full"
	if action == "board" and (not units.has(int(order.target)) or not cfg.units[units[int(order.target)].kind].has("driverSeats")): return "Choose a vehicle to board"
	if action == "stop":
		for raw_id in ids:
			if units.has(int(raw_id)) and units[int(raw_id)].owner == owner:
				var u: Dictionary = units[int(raw_id)]
				u.job = {"kind": "idle"}; u.route.clear(); u.target = 0; u.home = u.pos
		return "Orders stopped; cargo retained"
	if action in ["deposit", "repair"]:
		var target := entity(int(order.get("target", 0)))
		if target.is_empty() or target.owner != owner: return "Select a friendly target"
		if action == "deposit" and (not target.has("cell") or not target.kind in ["anchor", "depot"] or not target.built): return "Select an Anchor or Depot"
		if action == "repair" and ((target.has("cell") and not target.built) or (target.has("pos") and cfg.units[target.kind].get("biological", false))): return "Engineers repair completed structures and vehicles"
		for raw_id in ids:
			if not units.has(int(raw_id)): continue
			var u: Dictionary = units[int(raw_id)]
			if u.owner != owner or int(u.vehicle) != 0: continue
			if action == "repair" and u.kind != "engineer": continue
			if action == "deposit" and cargo_amount(u) == 0: continue
			u.job = {"kind": action, "target": int(target.id)}
			u.work = 0.0; u.target = 0
			move_to(u, entity_position(target))
		return "Delivery ordered" if action == "deposit" else "Repair ordered; consumes Ore while working"
	if action == "move" or action == "mine" or action == "attack" or action == "equip" or action == "board":
		var formation := 0
		for raw_id in ids:
			var id := int(raw_id)
			if not units.has(id) or units[id].owner != owner or units[id].vehicle != 0 or units[id].get("transition", "") != "": continue
			if action in ["move", "mine", "equip", "board"] and units[id].get("buried", false): continue
			var u: Dictionary = units[id]
			if action == "equip" and u.kind != "operator": continue
			if action == "board" and (not u.kind in ["operator", "engineer", "marine", "flamer", "lancer"] or not can_board(u, int(order.target))): continue
			u.target = 0
			if action == "move":
				var p := Vector2(float(order.x), float(order.z))
				p += Vector2((formation % 3) - mini(ids.size() - 1, 2) * 0.5, floorf(formation / 3.0)) * float(cfg.movement.formationSpacingTiles)
				formation += 1
				u.job = {"kind": "move"}
				u.home = p
				move_to(u, p)
				u.home = u.route.back() if not u.route.is_empty() else u.pos
			elif action == "mine":
				if not u.kind in ["operator", "engineer"]: continue
				var cell := Vector2i(int(order.q), int(order.r))
				if not known.get(owner, {}).has(cell): continue
				u.job = {"kind": "mine", "source": HexGrid.key(cell), "facility": int(order.get("facility", 0)), "delivering": false, "deposit": 0}
				move_to(u, HexGrid.world(nearest_free(cell)))
			elif action == "attack":
				u.target = int(order.target)
				u.job = {"kind": "attack"}
			else:
				u.job = {"kind": action, "target": int(order.target)}
				var target := entity(int(order.target))
				if not target.is_empty(): move_to(u, entity_position(target))
		return "Order issued"
	if action == "stance":
		if not str(order.stance) in ["neutral", "defensive", "aggressive"]: return "Invalid stance"
		for raw_id in ids:
			var id := int(raw_id)
			if units.has(id) and units[id].owner == owner: units[id].stance = str(order.stance)
		return "Stance changed"
	if action == "build":
		var kind := str(order.kind)
		if not cfg.structures.has(kind) or kind in ["anchor", "medusa", "womb", "gland", "chyme_gland", "stoma"]: return "Unavailable structure"
		var builder: Dictionary = {}
		for raw_id in ids:
			if units.has(int(raw_id)) and units[int(raw_id)].owner == owner and units[int(raw_id)].kind == "engineer" and int(units[int(raw_id)].vehicle) == 0: builder = units[int(raw_id)]; break
		if builder.is_empty(): return "Select an Engineer"
		var cell := Vector2i(int(order.q), int(order.r))
		for c in HexGrid.disk(cell, int(cfg.structures[kind].footprintRadiusTiles)):
			if not known[owner].has(c) or not tiles.has(c): return "Entire footprint must be revealed"
		if kind == "extractor" and tiles[cell].resource == "": return "Place Extractors on a resource patch"
		if not _pay(owner, cfg.structures[kind].cost): return "Not enough resources"
		var id := add_structure(kind, cell, owner, false, str(order.get("depot_type", "ore")))
		builder.job = {"kind": "build", "target": id}
		move_to(builder, _work_position(structures[id], builder.pos))
		return "Blueprint placed"
	var target_id := int(order.get("target", 0))
	if not structures.has(target_id) or structures[target_id].owner != owner: return "Select an owned structure"
	var s: Dictionary = structures[target_id]
	if action == "vehicle" and s.kind == "factory" and s.built:
		var kind := str(order.get("kind", ""))
		if not cfg.units.has(kind) or not cfg.units[kind].has("driverSeats"): return "Invalid vehicle type"
		if s.vehicles.size() >= int(cfg.personnel.vehicleQueueLimit): return "Vehicle queue is full"
		var auto_personnel := bool(order.get("personnel", s.request_personnel))
		var source: Dictionary = structures.get(int(s.personnel_source), {})
		if auto_personnel and (source.is_empty() or source.operators.size() >= int(cfg.personnel.operatorQueueLimit)): return "Personnel source unavailable"
		var cost: Dictionary = cfg.units[kind].cost.duplicate()
		if auto_personnel:
			for resource in cfg.personnel.operatorCost: cost[resource] = int(cost.get(resource, 0)) + int(cfg.personnel.operatorCost[resource])
		if not _pay(owner, cost): return "Not enough resources"
		var serial := next_id; next_id += 1
		s.vehicles.append({"kind": kind, "progress": 0.0, "serial": serial})
		if auto_personnel: source.operators.append({"progress": 0.0, "destination": s.id, "vehicle_order": serial})
		return "Vehicle queued"
	if action == "cancel_vehicle":
		var index := int(order.get("index", -1))
		if index < 0 or index >= s.vehicles.size(): return "Invalid queue position"
		var item: Dictionary = s.vehicles[index]
		if float(item.progress) == 0:
			for resource in cfg.units[item.kind].cost: resources(owner)[resource] = int(resources(owner).get(resource, 0)) + int(cfg.units[item.kind].cost[resource])
		s.vehicle_assignments[int(item.serial)] = 0; s.vehicles.remove_at(index)
		return "Vehicle order canceled; personnel orders remain separate"
	if action == "depot_type" and s.kind == "depot":
		var resource := str(order.get("resource", ""))
		if not resource in ["ore", "gas", "alloy", "polymer", "crystal"]: return "Invalid Depot resource"
		if s.started and not s.built: return "Depot construction has started"
		if float(s.configuration_remaining) > 0: return "Depot is reconfiguring"
		if resource == s.depot_type: return "Depot already configured"
		if s.built and capacity(owner, s.depot_type) - int(cfg.economy.depotCapacityPerResource) < int(resources(owner).get(s.depot_type, 0)): return "Cannot remove capacity below stored supply"
		s.depot_type = resource
		if s.built: s.configuration_remaining = float(cfg.economy.depotReconfigureSeconds)
		return "Depot configuration changed"
	if action == "personnel_settings":
		if not s.kind in ["anchor", "cradle", "armory", "factory"]: return "No personnel requests at this structure"
		if order.has("source"):
			var source_id := int(order.source)
			if not structures.has(source_id) or structures[source_id].owner != owner or not structures[source_id].built or not structures[source_id].kind in ["anchor", "cradle"]: return "Invalid personnel source"
			s.personnel_source = source_id
		if order.has("enabled"): s.request_personnel = bool(order.enabled)
		return "Personnel settings updated"
	if action in ["cancel_operator", "cancel_upgrade"]:
		var queue: Array = s.operators if action == "cancel_operator" else s.upgrades
		var index := int(order.get("index", -1))
		if index < 0 or index >= queue.size(): return "Invalid queue position"
		var item: Dictionary = queue[index]
		if float(item.progress) == 0:
			var cost: Dictionary = cfg.personnel.operatorCost if action == "cancel_operator" else cfg.upgrades.fabricatorArmor.costPerType
			for r in cost: resources(owner)[r] = int(resources(owner).get(r, 0)) + int(cost[r])
		queue.remove_at(index)
		return "Order canceled"
	if action == "upgrade" and s.kind == "fabricator" and s.built:
		var kind := str(order.get("kind", ""))
		if not kind in cfg.upgrades.fabricatorArmor.types or players[owner].upgrades.has(kind): return "Upgrade unavailable or already complete"
		for facility in structures.values():
			if facility.owner == owner:
				for item in facility.upgrades:
					if item.kind == kind: return "Upgrade already queued"
		if s.upgrades.size() >= int(cfg.personnel.upgradeQueueLimit): return "Upgrade queue is full"
		if not _pay(owner, cfg.upgrades.fabricatorArmor.costPerType): return "Not enough resources"
		s.upgrades.append({"kind": kind, "progress": 0.0})
		return "Upgrade purchased; assign Engineers to work the Fabricator"
	if action == "cancel_build" and not s.built:
		if not s.started:
			for resource in cfg.structures[s.kind].cost: resources(owner)[resource] += int(cfg.structures[s.kind].cost[resource])
		structures.erase(target_id)
		_rebuild_navigation()
		return "Construction canceled"
	if action == "work":
		for raw_id in ids:
			if units.has(int(raw_id)) and units[int(raw_id)].kind == "engineer" and units[int(raw_id)].owner == owner:
				units[int(raw_id)].job = {"kind": "research" if s.built and s.kind == "fabricator" else "build", "target": target_id}
				move_to(units[int(raw_id)], _work_position(s, units[int(raw_id)].pos))
		return "Engineers assigned"
	if action == "extract" and s.kind == "anchor":
		if int(resources(owner).get("nacre", 0)) < int(cfg.match.extractionMinimumNacre): return "Deliver 500 Nacre first"
		if not players[owner].extracting:
			players[owner].extracting = true
			players[owner].remaining = float(cfg.match.extractionSeconds)
		return "Extraction initiated"
	if not s.built: return "Construction is unfinished"
	if action == "operator" and s.kind in ["anchor", "cradle"]:
		if s.operators.size() >= int(cfg.personnel.operatorQueueLimit): return "Personnel queue is full"
		if not _pay(owner, cfg.personnel.operatorCost): return "Not enough resources"
		s.operators.append({"progress": 0.0, "destination": 0})
		return "Operator requested"
	if action == "kit":
		var kind := str(order.kind)
		if not cfg.personnel.kits.has(kind) or not s.kind in cfg.personnel.kits[kind].sources: return "Kit unavailable here"
		if s.kits.size() >= int(cfg.personnel.kitQueueLimit): return "Five-kit queue is full"
		var source: Dictionary = structures.get(int(s.personnel_source), {})
		if s.kind in ["anchor", "cradle"]: source = s
		var auto_personnel := bool(order.get("personnel", s.request_personnel))
		if auto_personnel and (source.is_empty() or source.operators.size() >= int(cfg.personnel.operatorQueueLimit)): return "Personnel source unavailable"
		var cost: Dictionary = cfg.personnel.kits[kind].cost.duplicate()
		if auto_personnel:
			for r in cfg.personnel.operatorCost: cost[r] = int(cost.get(r, 0)) + int(cfg.personnel.operatorCost[r])
		if not _pay(owner, cost): return "Not enough resources"
		s.kits.append({"kind": kind, "progress": 0.0, "done": false})
		if auto_personnel: source.operators.append({"progress": 0.0, "destination": s.id})
		return "Kit queued"
	if action == "cancel_kit":
		var index := int(order.get("index", 0))
		if index < 0 or index >= s.kits.size(): return "No kit at this position"
		var kit: Dictionary = s.kits[index]
		if float(kit.progress) == 0:
			for r in cfg.personnel.kits[kit.kind].cost: resources(owner)[r] += int(cfg.personnel.kits[kit.kind].cost[r])
		s.kits.remove_at(index)
		return "Kit discarded"
	if action == "toggle": s.enabled = not s.enabled; return "Power toggled"
	if action == "gate" and s.kind == "gate":
		s.open = not s.open; s.auto_close = false; s.erase("opening_remaining"); _rebuild_navigation(); update_visibility(); return "Gate state changed"
	if action == "gate_lock" and s.kind == "gate":
		s.locked = not s.locked; s.erase("opening_remaining"); _rebuild_navigation(); return "Gate locked" if s.locked else "Gate unlocked"
	return "This action is not available yet"

func personnel_source(owner: int, point: Vector2i) -> Dictionary:
	var best: Dictionary = {}
	var distance := 99999
	for s in structures.values():
		if s.owner != owner or not s.built or not s.kind in ["anchor", "cradle"]: continue
		var d := HexGrid.distance(point, s.cell)
		if d < distance: distance = d; best = s
	return best

func entity(id: int) -> Dictionary:
	return units.get(id, structures.get(id, {}))

func entity_position(e: Dictionary) -> Vector2:
	return e.pos if e.has("pos") else HexGrid.world(e.cell)

func step(delta: float) -> void:
	if ended or paused: return
	tick += 1
	time_seconds += delta
	shots.clear()
	GateRules.update(self, delta)
	_update_power(delta)
	RadarSystem.update(self)
	for s in structures.values(): _production(s, delta)
	for id in units.keys():
		if units.has(id): _unit_step(units[id], delta)
	_separate_units(delta)
	_update_occupants(delta)
	_healing(delta)
	for s in structures.values():
		if s.built and s.kind in ["sentry", "torch", "lance"] and s.powered: _fire(s, str(cfg.structures[s.kind].weapon), delta)
	for owner in players:
		if players[owner].extracting and players[owner].alive:
			players[owner].remaining -= delta
			if players[owner].remaining <= 0: ended = true; result = "Player %d extracted successfully" % (owner + 1)
	if tick % int(cfg.targeting.refreshIntervalTicks) == 0: update_visibility(); _update_gloom(delta * int(cfg.targeting.refreshIntervalTicks))

func _unit_step(u: Dictionary, delta: float) -> void:
	if u.vehicle != 0: return
	if BurrowRules.update(self, u, delta): return
	if u.owner < 0 and cfg.units[u.kind].has("buriedWeapon") and not u.get("buried", false) and u.job.kind == "idle":
		BurrowRules.request(self, u, true); return
	if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0: return
	u.cooldown = maxf(0, float(u.cooldown) - delta)
	if u.owner < 0 and u.stance == "probe":
		_probe_step(u, delta)
		return
	if u.owner == -1 and u.job.kind == "idle":
		var target: Dictionary = {}
		var distance := INF
		for s in structures.values():
			if s.kind != "anchor": continue
			var d: float = u.pos.distance_to(HexGrid.world(s.cell))
			if d < distance: distance = d; target = s
		if not target.is_empty(): u.target = target.id; u.job = {"kind": "attack"}
	if u.job.kind in ["patrol", "escort"]: RouteOrders.update(self, u, delta)
	var weapon = BurrowRules.weapon(self, u)
	if u.kind == "scout" and u.job.kind == "attack":
		var target := entity(int(u.target))
		if target.is_empty(): u.job = {"kind": "idle"}; u.target = 0
		elif not u.passengers.is_empty():
			var passenger: Dictionary = units.get(int(u.passengers[0]), {})
			var passenger_weapon = cfg.units[passenger.kind].get("weapon") if not passenger.is_empty() else null
			if passenger_weapon != null and u.pos.distance_to(entity_position(target)) > float(cfg.weapons[passenger_weapon].rangeTiles):
				if u.route.is_empty(): move_to(u, entity_position(target))
			else: u.route.clear()
	if weapon != null and (u.job.kind == "attack" or u.stance in ["aggressive", "defensive", "attack", "defend"]):
		if _fire(u, str(weapon), delta): return
	if u.get("buried", false): return
	if u.job.kind == "mine":
		_mine(u, delta)
	elif u.job.kind == "build":
		_build(u, delta)
	elif u.job.kind == "research":
		var facility := structures.get(int(u.job.target), {}) as Dictionary
		if facility.is_empty(): u.job = {"kind": "idle"}
		elif not facility.upgrades.is_empty() and facility.powered:
			if u.pos.distance_to(entity_position(facility)) <= int(cfg.structures.fabricator.footprintRadiusTiles) + 1.4:
				u.route.clear()
				var item: Dictionary = facility.upgrades[0]
				item.progress += delta * (float(cfg.power.brownout.productionRateMultiplier) if facility.brownout else 1.0)
				if float(item.progress) >= float(cfg.upgrades.fabricatorArmor.engineerWorkSeconds):
					players[u.owner].upgrades[item.kind] = true; facility.upgrades.pop_front()
	elif u.job.kind == "repair":
		_repair(u, delta)
	elif u.job.kind == "crew_wait":
		var factory: Dictionary = structures.get(int(u.job.factory), {})
		if factory.is_empty(): u.job = {"kind": "idle"}
		elif factory.vehicle_assignments.has(int(u.job.order)):
			var vehicle_id := int(factory.vehicle_assignments[int(u.job.order)])
			u.job = {"kind": "board", "target": vehicle_id} if units.has(vehicle_id) else {"kind": "idle"}
			if vehicle_id != 0 and units.has(vehicle_id): move_to(u, units[vehicle_id].pos)
	elif u.job.kind == "load_cargo":
		var vehicle: Dictionary = units.get(int(u.job.target), {})
		if vehicle.is_empty() or vehicle.owner != u.owner: u.job = {"kind": "idle"}
		elif u.pos.distance_to(vehicle.pos) <= float(cfg.economy.interactionRangeTiles):
			u.route.clear()
			var free := int(cfg.units[vehicle.kind].cargoCapacity) - cargo_amount(vehicle)
			for resource in u.cargo:
				var count := mini(free, int(u.cargo[resource])); free -= count
				u.cargo[resource] -= count; vehicle.cargo[resource] = int(vehicle.cargo.get(resource, 0)) + count
			if cargo_amount(u) == 0: u.job = {"kind": "idle"}
		elif u.route.is_empty(): move_to(u, vehicle.pos)
	elif u.job.kind == "excavate":
		var cell := HexGrid.unkey(u.job.source)
		if not tiles.has(cell) or not tiles[cell].cliff: u.job = {"kind": "idle"}
		elif u.pos.distance_to(HexGrid.world(cell)) <= float(cfg.economy.interactionRangeTiles) + HexGrid.RADIUS:
			u.route.clear(); tiles[cell].rock_health -= float(cfg.units.excavator.cliffDamagePerSecond) * delta
			if float(tiles[cell].rock_health) <= 0:
				tiles[cell].cliff = false; tiles[cell].rubble = true
				for resource in cfg.map.cliffYield:
					var count := mini(int(cfg.map.cliffYield[resource]), int(cfg.units.excavator.cargoCapacity) - cargo_amount(u))
					u.cargo[resource] = int(u.cargo.get(resource, 0)) + count
				u.job = {"kind": "idle"}; _rebuild_navigation()
		elif u.route.is_empty(): move_to(u, HexGrid.world(nearest_free(cell)))
	elif u.job.kind == "deposit":
		var destination := int(u.job.target)
		if not structures.has(destination):
			destination = _deposit_destination(u)
			u.job.target = destination
		if destination != 0:
			var depot: Dictionary = structures[destination]
			if u.pos.distance_to(entity_position(depot)) <= int(cfg.structures[depot.kind].footprintRadiusTiles) + 1.2:
				u.route.clear()
				_deposit_cargo(u, depot)
				if cargo_amount(u) == 0: u.job = {"kind": "idle"}
			elif u.route.is_empty(): move_to(u, entity_position(depot))
	elif u.job.kind == "equip":
		var destination := int(u.job.target)
		if structures.has(destination):
			var s: Dictionary = structures[destination]
			if u.kind == "operator" and u.pos.distance_to(HexGrid.world(s.cell)) <= int(cfg.structures[s.kind].footprintRadiusTiles) + 1.2 and not s.kits.is_empty() and s.kits[0].done and cargo_amount(u) == 0:
				u.kind = s.kits.pop_front().kind
				u.hp = float(cfg.units[u.kind].health)
				u.stance = cfg.units[u.kind].get("defaultStance", "neutral")
				u.job = {"kind": "idle"}
		else: u.job = {"kind": "idle"}
	elif u.job.kind == "board":
		var destination := int(u.job.target)
		if can_board(u, destination):
			var vehicle: Dictionary = units[destination]
			if u.pos.distance_to(vehicle.pos) <= float(cfg.economy.interactionRangeTiles):
				if int(vehicle.driver) == 0: vehicle.driver = u.id; vehicle.owner = u.owner
				else: vehicle.passengers.append(u.id)
				u.vehicle = vehicle.id; u.pos = vehicle.pos; u.job = {"kind": "riding"}; u.route.clear(); u.target = 0
			elif u.route.is_empty() or u.route.back().distance_to(vehicle.pos) > 1: move_to(u, vehicle.pos)
		else: u.job = {"kind": "idle"}; u.route.clear()
	_move(u, delta)
	if u.job.kind == "move" and u.route.is_empty():
		if u.pos.distance_to(u.home) > 0.3: move_to(u, u.home)
		else: u.job = {"kind": "idle"}
	if u.job.kind == "attack" and int(u.target) == 0 and u.route.is_empty(): u.job = {"kind": "idle"}

func _probe_step(u: Dictionary, delta: float) -> void:
	if u.kind in ["mother", "father"]: return
	if u.job.kind == "retreat":
		_move(u, delta)
		if u.route.is_empty() and float(u.hp) >= float(cfg.units[u.kind].health): u.job = {"kind": "idle"}
		return
	if u.job.kind == "attack":
		if not _fire(u, str(cfg.units[u.kind].weapon), delta): _move(u, delta)
		return
	if u.job.kind == "idle": u.job = {"kind": "probe", "pressure": 0.0, "damage_tick": int(u.last_damage)}
	if int(u.last_damage) > int(u.job.get("damage_tick", -999)):
		u.job = {"kind": "retreat"}; u.target = 0; u.route.clear()
		var destination := nearest_free(Vector2i.ZERO)
		var distance := INF
		for cell in gloom:
			if blocked(cell) or is_lit(cell): continue
			var d: float = u.pos.distance_to(HexGrid.world(cell))
			if d < distance: distance = d; destination = cell
		move_to(u, HexGrid.world(destination))
		return
	var candidate: Dictionary = {}
	var nearest := INF
	var vision := flood(HexGrid.cell(u.pos), int(cfg.units[u.kind].visionRangeTiles))
	for e in units.values() + structures.values():
		if e.owner < 0: continue
		var seen := vision.has(HexGrid.cell(entity_position(e)))
		if e.has("cell"):
			for cell in footprint(e):
				if vision.has(cell): seen = true; break
		if not seen: continue
		var d: float = u.pos.distance_to(entity_position(e))
		if d < nearest: nearest = d; candidate = e
	if not candidate.is_empty():
		if int(u.target) != int(candidate.id): u.job.pressure = 0.0
		u.target = candidate.id
		u.job.pressure += delta
		if float(u.job.pressure) >= float(cfg.lightless.probeResistanceWindowSeconds):
			var target_id := int(candidate.id)
			for other in units.values():
				if other.owner < 0 and other.kind == "scavenger" and other.stance == "probe" and other.job.kind != "retreat" and other.pos.distance_to(u.pos) <= float(cfg.lightless.probePressureSignalRangeTiles):
					other.target = target_id; other.job = {"kind": "attack"}; other.route.clear()
			return
	else: u.target = 0; u.job.pressure = 0.0
	if u.route.is_empty():
		var goal: Dictionary = {}
		var distance := INF
		for s in structures.values():
			if s.kind != "anchor": continue
			var d: float = u.pos.distance_to(entity_position(s))
			if d < distance: distance = d; goal = s
		if not goal.is_empty(): move_to(u, entity_position(goal))
	# Probes test from the dark edge. Committed attacks may cross illumination.
	if not u.route.is_empty() and not is_lit(HexGrid.cell(u.route[0])): _move(u, delta)

func _healing(delta: float) -> void:
	for u in units.values():
		if not cfg.units[u.kind].get("biological", false) or u.vehicle != 0: continue
		if u.owner < 0:
			if gloom.has(HexGrid.cell(u.pos)): u.hp = minf(float(cfg.units[u.kind].health), float(u.hp) + float(cfg.gloom.unitRegenerationPerSecond) * delta)
			continue
		var anchor_id := int(players[u.owner].anchor)
		if structures.has(anchor_id):
			var anchor: Dictionary = structures[anchor_id]
			var reach := float(cfg.structures.anchor.footprintRadiusTiles) + float(cfg.combat.anchorHealingRangeBeyondFootprintTiles)
			if u.pos.distance_to(entity_position(anchor)) <= reach:
				u.hp = minf(float(cfg.units[u.kind].health), float(u.hp) + float(cfg.combat.anchorBiologicalHealingPerSecond) * delta)
	for s in structures.values():
		if s.owner < 0 and s.built: s.hp = minf(float(cfg.structures[s.kind].health), float(s.hp) + float(cfg.gloom.structureRegenerationPerSecond) * delta)

func _separate_units(delta: float) -> void:
	var buckets: Dictionary = {}
	for u in units.values():
		if int(u.vehicle) != 0 or u.get("buried", false): continue
		var key := Vector2i(floori(u.pos.x), floori(u.pos.y))
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(u.id)
	for u in units.values():
		if int(u.vehicle) != 0 or u.get("buried", false): continue
		if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0: continue
		var key := Vector2i(floori(u.pos.x), floori(u.pos.y))
		var push := Vector2.ZERO
		for x in range(-1, 2):
			for y in range(-1, 2):
				for id in buckets.get(key + Vector2i(x, y), []):
					if id == u.id: continue
					var other: Dictionary = units[id]
					var offset: Vector2 = u.pos - other.pos
					var desired := float(cfg.units[u.kind].collisionRadiusTiles) + float(cfg.units[other.kind].collisionRadiusTiles)
					if offset.length() >= desired: continue
					var direction := offset.normalized() if offset.length() > 0.001 else Vector2.RIGHT * (1 if int(u.id) > int(id) else -1)
					push += direction * (desired - offset.length())
		var proposed: Vector2 = u.pos + push.limit_length(float(cfg.movement.separationTilesPerSecond) * delta)
		if not blocked(HexGrid.cell(proposed)): u.pos = proposed

func _deposit_cargo(u: Dictionary, depot: Dictionary) -> void:
	var delivered := 0
	for resource in u.cargo.keys():
		if resource == "nacre" and depot.kind != "anchor": continue
		var amount := mini(int(u.cargo[resource]), maxi(0, capacity(u.owner, resource) - int(resources(u.owner).get(resource, 0))))
		resources(u.owner)[resource] = int(resources(u.owner).get(resource, 0)) + amount
		u.cargo[resource] -= amount; delivered += amount
	if delivered > 0: emit_feedback("deposit", entity_position(depot), {"amount": delivered, "owner": u.owner, "target": depot.id}, [int(u.owner)])

func _repair(u: Dictionary, delta: float) -> void:
	var target := entity(int(u.job.target))
	if target.is_empty(): u.job = {"kind": "idle"}; return
	var maximum := float(cfg.structures[target.kind].health) if target.has("cell") else float(cfg.units[target.kind].health)
	if float(target.hp) >= maximum: u.job = {"kind": "idle"}; return
	var reach := float(cfg.construction.engineerWorkRangeTiles) + (float(cfg.structures[target.kind].footprintRadiusTiles) + 0.2 if target.has("cell") else 0.0)
	if u.pos.distance_to(entity_position(target)) > reach:
		if u.route.is_empty(): move_to(u, entity_position(target))
		return
	u.route.clear()
	if float(u.work) <= 0:
		if not _pay(u.owner, {"ore": int(cfg.construction.repairOrePerCycle)}): return
		u.work = float(cfg.construction.repairCycleSeconds)
	var elapsed := minf(delta, float(u.work))
	u.work -= elapsed
	target.hp = minf(maximum, float(target.hp) + float(cfg.construction.repairHealthPerSecond) * elapsed)

func cargo_amount(u: Dictionary) -> int:
	var total := 0
	for amount in u.cargo.values(): total += int(amount)
	return total

func can_board(unit: Dictionary, vehicle_id: int) -> bool:
	if not units.has(vehicle_id) or int(unit.vehicle) != 0 or not unit.kind in ["operator", "engineer", "marine", "flamer", "lancer"]: return false
	var vehicle: Dictionary = units[vehicle_id]
	if not cfg.units[vehicle.kind].has("driverSeats"): return false
	if vehicle.owner != unit.owner: return int(vehicle.driver) == 0 and vehicle.passengers.is_empty()
	return int(vehicle.driver) == 0 or vehicle.passengers.size() < int(cfg.units[vehicle.kind].passengerSeats)

func unload_vehicle(vehicle: Dictionary, all_occupants: bool) -> void:
	var ids: Array = vehicle.passengers.duplicate()
	vehicle.passengers.clear()
	if all_occupants or ids.is_empty():
		if int(vehicle.driver) != 0: ids.append(int(vehicle.driver))
		vehicle.driver = 0
	var index := 0
	for id in ids:
		if not units.has(int(id)): continue
		var unit: Dictionary = units[int(id)]
		var cell := nearest_free(HexGrid.cell(vehicle.pos) + HexGrid.DIRECTIONS[index % 6])
		unit.pos = HexGrid.world(cell); unit.vehicle = 0; unit.job = {"kind": "idle"}; unit.home = unit.pos; unit.route.clear(); unit.target = 0
		index += 1
	update_visibility()

func unit_area(unit: Dictionary, illumination: bool) -> Dictionary:
	var d: Dictionary = cfg.units[unit.kind]
	var cell := HexGrid.cell(unit.pos)
	var result := flood(cell, int(d.illuminationRangeTiles if illumination else d.visionRangeTiles))
	var forward_range := int(d.get("forwardIlluminationRangeTiles" if illumination else "visionForwardRangeTiles", 0))
	if forward_range > 0:
		var direction := Vector2(-sin(float(unit.heading)), -cos(float(unit.heading)))
		result.merge(flood(cell, forward_range, direction, float(d.forwardConeDegrees)), true)
	return result

func _update_occupants(delta: float) -> void:
	for vehicle in units.values():
		if not cfg.units[vehicle.kind].has("driverSeats"): continue
		var crew: Array = vehicle.passengers.duplicate()
		if int(vehicle.driver) != 0: crew.append(int(vehicle.driver))
		for id in crew:
			if not units.has(int(id)): continue
			var passenger: Dictionary = units[int(id)]
			passenger.pos = vehicle.pos; passenger.cooldown = maxf(0, float(passenger.cooldown) - delta)
			if vehicle.kind != "scout" or int(id) == int(vehicle.driver) or int(vehicle.driver) == 0: continue
			var weapon = cfg.units[passenger.kind].get("weapon")
			if weapon == null: continue
			var proxy: Dictionary = passenger.duplicate(true)
			proxy.route = []; proxy.job = vehicle.job.duplicate(true)
			proxy.home = vehicle.home; proxy.vision_override = unit_area(vehicle, false); proxy.stance = vehicle.stance
			if vehicle.job.kind == "attack": proxy.target = vehicle.target
			if proxy.job.kind == "attack" or proxy.stance in ["aggressive", "defensive"]:
				_fire(proxy, str(weapon), delta)
				passenger.cooldown = proxy.cooldown; passenger.target = proxy.target
				if not proxy.route.is_empty(): vehicle.route = proxy.route

func _mine(u: Dictionary, delta: float) -> void:
	var job: Dictionary = u.job
	var source := HexGrid.unkey(job.source)
	var facility := int(job.get("facility", 0))
	if facility != 0 and not structures.has(facility): job.facility = 0; facility = 0
	if facility == 0:
		for s in structures.values():
			if s.kind == "extractor" and s.built and s.cell == source:
				if s.owner != u.owner: return
				facility = int(s.id)
				job.facility = facility
				break
	if job.delivering:
		var destination := int(job.deposit)
		if not structures.has(destination):
			destination = _deposit_destination(u)
			job.deposit = destination
			if destination: move_to(u, HexGrid.world(structures[destination].cell))
		if destination == 0: return
		var s: Dictionary = structures[destination]
		if u.pos.distance_to(HexGrid.world(s.cell)) <= int(cfg.structures[s.kind].footprintRadiusTiles) + 1.2:
			_deposit_cargo(u, s)
			if cargo_amount(u) == 0:
				job.delivering = false
				move_to(u, HexGrid.world(nearest_free(source)))
		return
	var definition: Dictionary = cfg.units[u.kind]
	var free := int(definition.get("cargoCapacity", 0)) - cargo_amount(u)
	var resource := str(tiles.get(source, {}).get("resource", ""))
	var amount := int(tiles.get(source, {}).get("amount", 0))
	var facility_running := true
	if facility != 0:
		var s: Dictionary = structures[facility]
		resource = _output_resource(s)
		amount = int(s.buffer)
		facility_running = bool(s.powered) and s.enabled and _wants_power(s)
	if free <= 0 or (amount == 0 and (facility == 0 or not facility_running)):
		if cargo_amount(u) > 0:
			job.delivering = true
			job.deposit = 0
		return
	if u.pos.distance_to(HexGrid.world(source)) > 1.3:
		if u.route.is_empty(): move_to(u, HexGrid.world(nearest_free(source)))
		return
	u.route.clear()
	u.work += delta
	if float(u.work) < float(cfg.economy.workerCycleSeconds): return
	u.work = 0.0
	var count := int(cfg.economy.engineerItemsPerCycle if u.kind == "engineer" else cfg.economy.operatorItemsPerCycle)
	count = mini(free, mini(count, amount))
	if resource != "" and count > 0:
		u.cargo[resource] = int(u.cargo.get(resource, 0)) + count
		if facility != 0: structures[facility].buffer -= count
		elif resource != "nacre": tiles[source].amount -= count

func _deposit_destination(u: Dictionary) -> int:
	var best := 0
	var distance := INF
	for s in structures.values():
		if not s.built or s.owner != u.owner or not s.kind in ["anchor", "depot"]: continue
		if int(u.cargo.get("nacre", 0)) > 0 and s.kind != "anchor": continue
		var d: float = u.pos.distance_to(HexGrid.world(s.cell))
		if d < distance: distance = d; best = s.id
	return best

func _build(u: Dictionary, delta: float) -> void:
	var id := int(u.job.target)
	if not structures.has(id): u.job = {"kind": "idle"}; return
	var s: Dictionary = structures[id]
	if s.built: u.job = {"kind": "idle"}; return
	if HexGrid.cell(u.pos) in footprint(s):
		if u.route.is_empty(): move_to(u, _work_position(s, u.pos))
		return
	if u.pos.distance_to(HexGrid.world(s.cell)) > int(cfg.structures[s.kind].footprintRadiusTiles) + 1.4:
		if u.route.is_empty():
			command(u.owner, {"action": "cancel_build", "target": id})
		return
	if not s.started:
		var wait_for_units := false
		for cell in footprint(s):
			if blocked(cell, id): command(u.owner, {"action": "cancel_build", "target": id}); return
			for other in units.values():
				if HexGrid.cell(other.pos) != cell: continue
				if other.owner != u.owner: command(u.owner, {"action": "cancel_build", "target": id}); return
				var clear_position := _work_position(s, other.pos)
				other.job = {"kind": "move"}; other.home = clear_position; other.target = 0
				move_to(other, clear_position)
				wait_for_units = true
		if wait_for_units: return
		s.started = true
		_rebuild_navigation()
	u.route.clear()
	s.hp = minf(float(cfg.structures[s.kind].health), float(s.hp) + float(cfg.construction.engineerHealthPerSecond) * delta)
	if s.hp >= float(cfg.structures[s.kind].health):
		s.built = true
		emit_feedback("ready", entity_position(s), {"owner": s.owner, "label": str(s.kind).to_upper() + " ONLINE", "target": s.id}, [int(s.owner)])
		u.job = {"kind": "idle"}

func _work_position(s: Dictionary, from: Vector2) -> Vector2:
	var best := from
	var distance := INF
	for c in HexGrid.disk(s.cell, int(cfg.structures[s.kind].footprintRadiusTiles) + 1):
		if c in footprint(s) or blocked(c): continue
		var p := HexGrid.world(c)
		if from.distance_to(p) < distance: distance = from.distance_to(p); best = p
	return best

func placement_issue(owner: int, kind: String, cell: Vector2i) -> String:
	if not cfg.structures.has(kind): return "Unknown structure"
	for c in HexGrid.disk(cell, int(cfg.structures[kind].footprintRadiusTiles)):
		if not tiles.has(c) or not known.get(owner, {}).has(c): return "Reveal the entire footprint first"
		if blocked(c): return "Footprint is obstructed"
		for s in structures.values():
			if c in footprint(s): return "A structure or blueprint occupies this site"
	if kind == "extractor" and tiles[cell].resource == "": return "An Extractor requires a resource patch"
	for resource in cfg.structures[kind].cost:
		if int(resources(owner).get(resource, 0)) < int(cfg.structures[kind].cost[resource]): return "Not enough %s" % resource.capitalize()
	return ""

func _production(s: Dictionary, delta: float) -> void:
	if not s.built: return
	if float(s.get("configuration_remaining", 0)) > 0: s.configuration_remaining = maxf(0, float(s.configuration_remaining) - delta)
	if s.kind == "medusa":
		s.passive += delta
		if float(s.passive) >= float(cfg.lightless.medusaPassiveScavengerSeconds) and _population("scavenger") < int(cfg.units.scavenger.basePopulationCap):
			s.passive = 0.0
			add_unit("scavenger", HexGrid.world(nearest_free(s.cell)), -1)
	if s.owner < 0: return
	if int(cfg.structures[s.kind].powerDemand) > 0 and not s.powered: return
	var rate := float(cfg.power.brownout.productionRateMultiplier) if s.brownout else 1.0
	if not s.operators.is_empty():
		var job: Dictionary = s.operators[0]
		job.progress += delta * rate
		var duration := float(cfg.personnel.anchorOperatorSeconds if s.kind == "anchor" else cfg.personnel.cradleOperatorSeconds)
		if job.progress >= duration:
			var id := add_unit("operator", HexGrid.world(nearest_free(s.cell)), s.owner)
			if int(job.destination) != 0 and structures.has(int(job.destination)):
				units[id].job = {"kind": "crew_wait", "factory": int(job.destination), "order": int(job.vehicle_order)} if job.has("vehicle_order") else {"kind": "equip", "target": int(job.destination)}
				move_to(units[id], HexGrid.world(nearest_free(structures[int(job.destination)].cell)))
			emit_feedback("ready", units[id].pos, {"owner": s.owner, "label": "OPERATOR READY", "target": id}, [int(s.owner)])
			s.operators.pop_front()
	if s.kind == "factory" and not s.vehicles.is_empty():
		var job: Dictionary = s.vehicles[0]
		job.progress = minf(float(cfg.units[job.kind].productionSeconds), float(job.progress) + delta * rate)
		if float(job.progress) >= float(cfg.units[job.kind].productionSeconds):
			var exit_position := _work_position(s, entity_position(s))
			if not blocked(HexGrid.cell(exit_position)):
				var id := add_unit(str(job.kind), exit_position, int(s.owner))
				emit_feedback("ready", units[id].pos, {"owner": s.owner, "label": str(job.kind).to_upper() + " READY", "target": id}, [int(s.owner)])
				s.vehicle_assignments[int(job.serial)] = id; s.vehicles.pop_front()
	for kit in s.kits:
		if kit.done: continue
		kit.progress += delta * rate
		if float(kit.progress) >= float(cfg.personnel.kits[kit.kind].seconds):
			kit.done = true
			emit_feedback("ready", entity_position(s), {"owner": s.owner, "label": str(kit.kind).to_upper() + " KIT READY", "target": s.id}, [int(s.owner)])
		break
	if not s.kind in ["extractor", "foundry", "refinery", "synthesizer"]: return
	var recipe: Dictionary = cfg.economy.recipes[s.kind]
	var buffer_cap := int(cfg.economy.extractorBufferCapacity if s.kind == "extractor" else cfg.economy.processorBufferCapacity)
	var produced := int(recipe.get("outputUnits", 0))
	if s.kind != "extractor": produced = int(recipe.outputs.values()[0])
	if s.cycle <= 0:
		if s.buffer + produced > buffer_cap: return
		if s.kind == "extractor":
			if tiles[s.cell].resource == "" or int(tiles[s.cell].amount) <= 0: return
		elif not _pay(s.owner, recipe.inputs): return
		s.cycle = float(recipe.cycleSeconds)
	s.cycle -= delta * rate
	if s.cycle <= 0:
		if s.kind == "extractor":
			produced = mini(produced, int(tiles[s.cell].amount))
			if tiles[s.cell].resource != "nacre": tiles[s.cell].amount -= produced
		s.buffer += produced

func _population(kind: String) -> int:
	var total := 0
	for u in units.values():
		if u.kind == kind: total += 1
	return total

func _output_resource(s: Dictionary) -> String:
	if s.kind == "extractor": return str(tiles[s.cell].resource)
	if cfg.economy.recipes.has(s.kind): return str(cfg.economy.recipes[s.kind].outputs.keys()[0])
	return ""

func _wants_power(s: Dictionary) -> bool:
	if s.kind == "factory": return not s.vehicles.is_empty() and float(s.vehicles[0].progress) < float(cfg.units[s.vehicles[0].kind].productionSeconds)
	if s.kind == "fabricator":
		if s.upgrades.is_empty(): return false
		for u in units.values():
			if u.job.kind == "research" and int(u.job.target) == int(s.id) and u.pos.distance_to(entity_position(s)) <= 1.4: return true
		return false
	if s.kind in ["anchor", "cradle", "armory", "factory", "fabricator"]:
		if not s.operators.is_empty() or not s.vehicles.is_empty() or not s.upgrades.is_empty(): return true
		for kit in s.kits:
			if not kit.done: return true
		return false
	if cfg.economy.recipes.has(s.kind):
		if s.cycle > 0: return true
		var recipe: Dictionary = cfg.economy.recipes[s.kind]
		var cap := int(cfg.economy.extractorBufferCapacity if s.kind == "extractor" else cfg.economy.processorBufferCapacity)
		var produced := int(recipe.get("outputUnits", 0)) if s.kind == "extractor" else int(recipe.outputs.values()[0])
		if s.buffer + produced > cap: return false
		if s.kind == "extractor": return tiles[s.cell].amount > 0
		for resource in recipe.inputs:
			if int(resources(s.owner).get(resource, 0)) < int(recipe.inputs[resource]): return false
	return true

func _update_power(delta: float) -> void:
	var pending: Array = []
	for s in structures.values():
		s.grid_capacity = 0; s.grid_demand = 0
		if not s.built or not s.enabled or s.owner < 0: s.powered = false; continue
		if s.kind in ["generator", "reactor"]:
			s.fuel = maxf(0, float(s.fuel) - delta)
			if s.fuel <= 0:
				var fuel: Dictionary = cfg.power.generatorFuel if s.kind == "generator" else cfg.power.reactorFuel
				if _pay(s.owner, {str(fuel.resource): int(fuel.unitsPerCycle)}): s.fuel = float(fuel.cycleSeconds)
		if int(cfg.structures[s.kind].powerDemand) > 0 or int(cfg.structures[s.kind].powerCapacity) > 0: pending.append(s.id)
		else: s.powered = true
	while not pending.is_empty():
		var group: Array = [pending.pop_front()]
		var index := 0
		while index < group.size():
			var a: Dictionary = structures[group[index]]
			var reach_a := int(cfg.structures[a.kind].footprintRadiusTiles) + int(cfg.structures[a.kind].electricalRangeBeyondFootprintTiles)
			for other in pending.duplicate():
				var b: Dictionary = structures[other]
				var reach_b := int(cfg.structures[b.kind].footprintRadiusTiles) + int(cfg.structures[b.kind].electricalRangeBeyondFootprintTiles)
				if a.owner == b.owner and HexGrid.distance(a.cell, b.cell) <= reach_a + reach_b:
					pending.erase(other)
					group.append(other)
			index += 1
		var supply := 0
		var demand := 0
		var was_blackout := false
		for id in group:
			var s: Dictionary = structures[id]
			if not s.kind in ["generator", "reactor"] or s.fuel > 0: supply += int(cfg.structures[s.kind].powerCapacity)
			if _wants_power(s): demand += int(cfg.structures[s.kind].powerDemand)
			was_blackout = was_blackout or bool(s.blackout)
		var blackout := supply == 0 or (demand > supply and (was_blackout or demand >= floori(supply * float(cfg.power.blackoutRatio))))
		for id in group:
			structures[id].grid_capacity = supply
			structures[id].grid_demand = demand
			structures[id].powered = not blackout
			structures[id].blackout = blackout
			structures[id].brownout = not blackout and demand > supply

func _fire(attacker: Dictionary, weapon_name: String, delta: float) -> bool:
	var weapon: Dictionary = cfg.weapons[weapon_name]
	if attacker.has("cell"): attacker.cooldown = maxf(0, float(attacker.cooldown) - delta)
	var origin := entity_position(attacker)
	var target: Dictionary = entity(int(attacker.get("target", 0)))
	if not target.is_empty() and int(target.get("vehicle", 0)) != 0: target = {}
	var explicit_attack: bool = attacker.get("manual_target", false) or attacker.get("job", {}).get("kind", "") == "attack"
	if explicit_attack and target.is_empty():
		attacker.target = 0; attacker.manual_target = false
		if attacker.has("pos"): attacker.job = {"kind": "idle"}; attacker.route.clear()
		return false
	if attacker.has("cell") and not target.is_empty() and (not TargetRules.targetable(self, attacker, target) or origin.distance_to(entity_position(target)) > float(weapon.rangeTiles) + (int(cfg.structures[target.kind].footprintRadiusTiles) + float(cfg.combat.structureAimAllowanceTiles) if target.has("cell") else 0)):
		attacker.target = 0; attacker.manual_target = false; target = {}; explicit_attack = false
	var defensive: bool = attacker.get("stance", "") == "defensive" and not explicit_attack
	if not target.is_empty() and attacker.owner >= 0 and not TargetRules.targetable(self, attacker, target):
		if attacker.has("pos") and attacker.has("last_target_position"):
			var last: Array = attacker.last_target_position
			var last_position := Vector2(float(last[0]), float(last[1]))
			if not defensive or attacker.home.distance_to(last_position) <= float(cfg.combat.defensiveLeashTiles): move_to(attacker, last_position)
		attacker.target = 0
		target = {}
	if defensive and not target.is_empty() and attacker.home.distance_to(entity_position(target)) > float(cfg.combat.defensiveLeashTiles):
		attacker.target = 0; target = {}
		move_to(attacker, attacker.home)
	if target.is_empty() or (target.owner == attacker.owner and not explicit_attack):
		target = {}
		var distance := float(weapon.rangeTiles) + float(cfg.combat.targetSearchMarginTiles)
		for candidate in units.values() + structures.values():
			if candidate.owner == attacker.owner: continue
			if int(candidate.get("vehicle", 0)) != 0: continue
			if not TargetRules.targetable(self, attacker, candidate): continue
			if defensive and attacker.home.distance_to(entity_position(candidate)) > float(cfg.combat.defensiveLeashTiles): continue
			var d := origin.distance_to(entity_position(candidate))
			if d < distance: distance = d; target = candidate
	if target.is_empty():
		if attacker.has("pos") and int(attacker.get("target", 0)) != 0:
			attacker.target = 0
			if attacker.job.kind == "attack": attacker.job = {"kind": "idle"}
			elif attacker.stance == "defensive" or attacker.job.kind == "move": move_to(attacker, attacker.home)
		return false
	var position := entity_position(target)
	attacker.target = target.id
	attacker.last_target_position = [position.x, position.y]
	var distance := origin.distance_to(position)
	var target_radius := int(cfg.structures[target.kind].footprintRadiusTiles) + float(cfg.combat.structureAimAllowanceTiles) if target.has("cell") else 0.0
	if distance > float(weapon.rangeTiles) + target_radius:
		if attacker.has("pos") and (attacker.job.kind == "attack" or attacker.stance in ["aggressive", "attack"] or (defensive and attacker.job.kind == "idle")):
			if attacker.route.is_empty() and not attacker.get("buried", false): move_to(attacker, position)
		return false
	var line := HexGrid.line(HexGrid.cell(origin), HexGrid.cell(position))
	for i in range(1, maxi(1, line.size() - 1)):
		if blocks_sight(line[i]): return false
	if float(attacker.cooldown) > 0: return true
	if attacker.has("heading"): attacker.heading = atan2(origin.x - position.x, origin.y - position.y)
	attacker.cooldown = float(weapon.intervalSeconds)
	if attacker.get("brownout", false): attacker.cooldown *= float(cfg.power.brownout.turretAttackIntervalMultiplier)
	var source := units.get(int(attacker.get("vehicle", 0)), attacker) as Dictionary
	var shot := {"height": float(cfg.presentation.muzzleHeights.get(source.kind, 0.54)), "from": origin, "to": position, "laser": weapon_name.contains("laser"), "weapon": weapon_name, "attacker": source.id}
	shots.append(shot)
	emit_feedback("fire", position, shot, feedback_audience(attacker))
	if weapon.mechanism == "cone":
		var direction: Vector2 = (position - origin).normalized()
		for candidate in units.values() + structures.values():
			if candidate.id == attacker.id or not TargetRules.area_can_damage(self, candidate): continue
			if candidate.owner == attacker.owner and not weapon.get("friendlyFire", false): continue
			var offset: Vector2 = entity_position(candidate) - origin
			if offset.length() > float(weapon.rangeTiles) or direction.dot(offset.normalized()) < cos(deg_to_rad(float(weapon.coneDegrees) / 2)): continue
			var obstructed := false
			var candidate_line := HexGrid.line(HexGrid.cell(origin), HexGrid.cell(entity_position(candidate)))
			for i in range(1, maxi(1, candidate_line.size() - 1)):
				if blocks_sight(candidate_line[i]): obstructed = true; break
			if not obstructed: _weapon_damage(candidate, weapon)
	else: _weapon_damage(target, weapon)
	return true

func _weapon_damage(target: Dictionary, weapon: Dictionary) -> void:
	if int(target.get("vehicle", 0)) != 0: return
	if weapon.get("mechanism", "unit_target") != "unit_target" and not TargetRules.area_can_damage(self, target): return
	var actual := TargetRules.damage(self, target, weapon)
	emit_feedback("hit", entity_position(target), {"target": target.id, "amount": actual, "shielded": TargetRules.shield_bonus(self, target) > 0, "biological": target.owner < 0 or (target.has("pos") and bool(cfg.units[target.kind].get("biological", false)))}, feedback_audience(target))
	target.hp -= actual
	if actual > 0 and target.has("last_damage"): target.last_damage = tick
	if target.hp <= 0: _destroy(target)

func _destroy(e: Dictionary) -> void:
	emit_feedback("destroy", entity_position(e), {"target": e.id, "owner": e.owner, "biological": e.owner < 0 or (e.has("pos") and bool(cfg.units[e.kind].get("biological", false)))}, feedback_audience(e))
	if e.has("cell"):
		structures.erase(e.id)
		if e.kind == "anchor": eliminate(int(e.owner))
		if e.kind == "medusa":
			medusa_dead = true
			tiles[Vector2i.ZERO].resource = "nacre"
			tiles[Vector2i.ZERO].amount = 2147483647
			for u in units.values():
				if u.owner == -1: u.stance = "attack"; u.job = {"kind": "idle"}; u.target = 0; u.route.clear()
		_rebuild_navigation()
	else:
		if cfg.units[e.kind].has("driverSeats"): unload_vehicle(e, true)
		units.erase(e.id)

func eliminate(owner: int) -> void:
	if not players.has(owner): return
	players[owner].alive = false
	players[owner].extracting = false
	for unit in units.values():
		if unit.owner == owner and cfg.units[unit.kind].has("driverSeats"): unload_vehicle(unit, true)
	for u in units.values():
		if u.owner != owner: continue
		if int(u.vehicle) != 0:
			if units.has(int(u.vehicle)): u.pos = units[int(u.vehicle)].pos
			u.vehicle = 0
		u.driver = 0
	if players.size() > 1:
		var alive: Array = []
		for id in players:
			if players[id].alive: alive.append(id)
		if alive.size() == 1: ended = true; result = "Player %d wins by elimination" % (int(alive[0]) + 1)
	elif owner == 0:
		ended = true
		result = "Expedition lost"

func blocks_sight(cell: Vector2i) -> bool:
	if not tiles.has(cell) or tiles[cell].cliff: return true
	for s in structures.values():
		if not s.started: continue
		if cell in footprint(s) and (s.kind == "wall" or (s.kind == "gate" and not s.open)): return true
	return false

func flood(start: Vector2i, range_value: int, cone_direction: Vector2 = Vector2.ZERO, cone_degrees: float = 360) -> Dictionary:
	var reached: Dictionary = {start: true}
	var frontier: Array = [start]
	var distances: Dictionary = {start: 0}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if int(distances[cell]) >= range_value or (cell != start and blocks_sight(cell)): continue
		for direction in HexGrid.DIRECTIONS:
			var other: Vector2i = cell + direction
			if cone_direction != Vector2.ZERO:
				var offset := HexGrid.world(other) - HexGrid.world(start)
				if offset.normalized().dot(cone_direction) < cos(deg_to_rad(cone_degrees * 0.5)): continue
			if tiles.has(other) and not reached.has(other): reached[other] = true; distances[other] = int(distances[cell]) + 1; frontier.append(other)
	return reached

func update_visibility() -> void:
	for owner in players:
		visible[owner] = {}
		illuminated[owner] = {}
		if not known.has(owner): known[owner] = {}
	for s in structures.values():
		if not s.built or s.owner < 0: continue
		var d: Dictionary = cfg.structures[s.kind]
		for c in footprint(s):
			visible[s.owner].merge(flood(c, int(d.visionRangeBeyondFootprintTiles)), true)
			if int(d.illuminationRangeBeyondFootprintTiles) > 0 and s.powered:
				var reach := int(d.illuminationRangeBeyondFootprintTiles)
				if s.brownout: reach = floori(reach * float(cfg.power.brownout.illuminationRangeMultiplier))
				illuminated[s.owner].merge(flood(c, reach), true)
	for u in units.values():
		if u.owner < 0 or u.vehicle != 0: continue
		var d: Dictionary = cfg.units[u.kind]
		if d.has("driverSeats") and u.driver == 0: continue
		var c := HexGrid.cell(u.pos)
		visible[u.owner].merge(unit_area(u, false), true)
		if int(d.illuminationRangeTiles) > 0: illuminated[u.owner].merge(unit_area(u, true), true)
	RadarSystem.update(self)
	for owner in players: known[owner].merge(visible[owner], true)
	for cell in point_ids:
		dark_navigation.set_point_weight_scale(point_ids[cell], float(cfg.lightless.darkPathLightPenalty) if is_lit(cell) else 1.0)

func unknown_contacts(owner: int) -> Array[Vector2i]:
	## Public UI contract: contacts contain coordinates, never enemy IDs or counts.
	var result: Array[Vector2i] = []
	for cell in detected.get(owner, {}):
		var identified := false
		for unit in units.values():
			if unit.owner != owner and HexGrid.cell(unit.pos) == cell and TargetRules.identifiable(self, unit, owner): identified = true; break
		if not identified: result.append(cell)
	return result

func _update_gloom(delta: float) -> void:
	var support: Dictionary = {}
	var sources: Array = []
	for s in structures.values():
		if s.owner >= 0 or not s.built: continue
		var radius_value := int(cfg.structures[s.kind].get("gloomRangeBeyondFootprintTiles", 0)) + int(cfg.structures[s.kind].footprintRadiusTiles)
		if radius_value <= 0: continue
		var area: Dictionary = {}
		for cell in HexGrid.disk(s.cell, radius_value):
			if tiles.has(cell): area[cell] = true
		support.merge(area, true)
		sources.append({"structure": s, "area": area})
	for cell in gloom.keys():
		if is_lit(cell): gloom[cell] -= float(cfg.gloom.illuminationDamagePerSecond) * delta
		if not support.has(cell): gloom[cell] -= float(cfg.gloom.unsupportedWitherPerSecond) * delta
		if gloom[cell] <= 0: gloom.erase(cell)
	gloom_spread_time += delta
	if gloom_spread_time < float(cfg.gloom.spreadIntervalSeconds): return
	gloom_spread_time = fmod(gloom_spread_time, float(cfg.gloom.spreadIntervalSeconds))
	for source in sources:
		for i in range(int(cfg.gloom.newTilesPerStructurePerInterval)):
			var candidates: Array = []
			for cell in source.area:
				if gloom.has(cell) or is_lit(cell): continue
				var connected: bool = cell in footprint(source.structure)
				for direction in HexGrid.DIRECTIONS:
					if gloom.has(cell + direction): connected = true; break
				if connected: candidates.append(cell)
			if not candidates.is_empty(): gloom[candidates[random.randi_range(0, candidates.size() - 1)]] = float(cfg.gloom.tileHealth)

func snapshot(owner: int) -> Dictionary:
	var exported_units: Array = []
	var exported_structures: Array = []
	for u in units.values():
		if u.owner != owner and not TargetRules.identifiable(self, u, owner): continue
		var d: Dictionary = u.duplicate(true)
		d.pos = [u.pos.x, u.pos.y]
		d.home = [u.home.x, u.home.y]
		d.erase("route")
		exported_units.append(d)
	for s in structures.values():
		if s.owner != owner and not known.get(owner, {}).has(s.cell): continue
		var d: Dictionary = s.duplicate(true)
		d.cell = [s.cell.x, s.cell.y]
		exported_structures.append(d)
	var cells: Array = []
	for cell in known.get(owner, {}):
		cells.append([cell.x, cell.y, bool(visible[owner].has(cell)), is_lit(cell), float(gloom.get(cell, 0)), int(tiles[cell].amount), bool(tiles[cell].cliff), bool(tiles[cell].get("rubble", false))])
	var exported_feedback: Array = []
	for event in feedback_for(owner):
		var copy: Dictionary = event.duplicate(true); copy.erase("audience")
		for key in ["at", "from", "to"]:
			if copy.has(key): copy[key] = [copy[key].x, copy[key].y]
		exported_feedback.append(copy)
	return {"feedback": exported_feedback, "feedback_serial": feedback_serial, "contacts": detected.get(owner, {}).keys().map(func(cell): return [cell.x, cell.y]), "tick": tick, "time_seconds": time_seconds, "units": exported_units, "structures": exported_structures, "players": players, "cells": cells, "ended": ended, "result": result, "medusa_dead": medusa_dead, "speed": speed, "paused": paused}

func apply_snapshot(data: Dictionary, owner: int) -> void:
	tick = int(data.tick)
	feedback_serial = int(data.get("feedback_serial", 0)); feedback_events.clear()
	for event in data.get("feedback", []):
		var copy: Dictionary = event.duplicate(true); copy.audience = [owner]
		for key in ["at", "from", "to"]:
			if copy.has(key): copy[key] = Vector2(float(copy[key][0]), float(copy[key][1]))
		feedback_events.append(copy)
	time_seconds = float(data.get("time_seconds", 0))
	units.clear()
	structures.clear()
	players.clear()
	for id in data.players: players[int(id)] = data.players[id]
	for d in data.units:
		d.pos = Vector2(float(d.pos[0]), float(d.pos[1]))
		d.home = Vector2(float(d.home[0]), float(d.home[1]))
		d.route = []
		units[int(d.id)] = d
	for d in data.structures:
		d.cell = Vector2i(int(d.cell[0]), int(d.cell[1]))
		structures[int(d.id)] = d
	detected[owner] = {}
	for contact in data.get("contacts", []): detected[owner][Vector2i(int(contact[0]), int(contact[1]))] = true
	known[owner] = {}
	visible[owner] = {}
	illuminated.clear()
	illuminated[owner] = {}
	gloom.clear()
	for c in data.cells:
		var cell := Vector2i(int(c[0]), int(c[1]))
		known[owner][cell] = true
		if c[2]: visible[owner][cell] = true
		if c[3]: illuminated[owner][cell] = true
		if float(c[4]) > 0: gloom[cell] = float(c[4])
		if tiles.has(cell):
			tiles[cell].amount = int(c[5])
			if c.size() > 6: tiles[cell].cliff = bool(c[6]); tiles[cell].rubble = bool(c[7])
	ended = bool(data.ended)
	result = str(data.result)
	medusa_dead = bool(data.medusa_dead)
	paused = bool(data.get("paused", false))
	speed = float(data.get("speed", 1))
	if medusa_dead:
		tiles[Vector2i.ZERO].resource = "nacre"


class TargetRules:
	extends RefCounted
	## Pure queries: no targeting, damage, UI, or renderer may invent its own visibility rule.
	## WorldState owns mutation. These helpers also work on host state before serialization.

	static func identifiable(world: RefCounted, target: Dictionary, owner: int) -> bool:
		if int(target.get("vehicle", 0)) != 0: return false
		if target.owner == owner: return true
		var cell := HexGrid.cell(world.entity_position(target))
		if not world.visible.get(owner, {}).has(cell): return false
		var rules: Dictionary = world.cfg.targeting.unitRules.get(target.kind, {})
		if rules.get("requiresIllumination", false) and not world.is_lit(cell): return false
		if target.get("buried", false) and not world.detected.get(owner, {}).has(cell): return false
		return true

	static func targetable(world: RefCounted, attacker: Dictionary, target: Dictionary) -> bool:
		if target.is_empty() or int(target.get("vehicle", 0)) != 0: return false
		var cell := HexGrid.cell(world.entity_position(target))
		var rules: Dictionary = world.cfg.targeting.unitRules.get(target.kind, {})
		if rules.get("requiresIllumination", false) and not world.is_lit(cell): return false
		# The existing CPU controller has separate discovery work still pending.
		if attacker.owner < 0: return true
		var sight: Dictionary = attacker.get("vision_override", world.visible.get(attacker.owner, {}))
		var seen := sight.has(cell)
		var contact: bool = world.detected.get(attacker.owner, {}).has(cell)
		if target.get("buried", false):
			var definition: Dictionary = world.cfg.structures[attacker.kind] if attacker.has("cell") else world.cfg.units[attacker.kind]
			var weapon_name = definition.get("weapon")
			if weapon_name != null and world.cfg.weapons[weapon_name].mechanism != "unit_target": return false
			return contact and (seen or attacker.has("cell"))
		if rules.get("requiresIllumination", false): return seen
		return seen or (attacker.has("cell") and contact)

	static func area_can_damage(world: RefCounted, target: Dictionary) -> bool:
		if int(target.get("vehicle", 0)) != 0: return false
		return not (target.get("buried", false) and world.cfg.targeting.buriedImmuneToArea)

	static func shield_bonus(world: RefCounted, target: Dictionary) -> int:
		if not target.has("cell"): return 0
		for shield in world.structures.values():
			if shield.kind != "rampart" or shield.owner != target.owner or not shield.built or not shield.enabled or not shield.powered: continue
			if shield.id == target.id and not world.cfg.combat.rampartProtectsSelf: continue
			if target.kind == "rampart" and shield.id != target.id and not world.cfg.combat.rampartProtectsOtherRamparts: continue
			var reach := int(world.cfg.combat.rampartRangeBeyondFootprintTiles) + int(world.cfg.structures.rampart.footprintRadiusTiles)
			for cell in world.footprint(target):
				if HexGrid.distance(cell, shield.cell) <= reach: return int(world.cfg.combat.rampartArmorBonus)
		return 0 # Identical Rampart bonuses overlap but never add together.

	static func armor(world: RefCounted, target: Dictionary) -> float:
		var definition: Dictionary = world.cfg.structures[target.kind] if target.has("cell") else world.cfg.units[target.kind]
		var result := float(definition.armor) + shield_bonus(world, target)
		if world.players.has(target.owner) and world.players[target.owner].upgrades.has(target.kind): result += float(world.cfg.upgrades.fabricatorArmor.armorPerPurchase)
		return result

	static func damage(world: RefCounted, target: Dictionary, weapon: Dictionary) -> float:
		var raw := float(weapon.damagePerHit) + (float(weapon.get("bonusDamageAgainstStructures", 0)) if target.has("cell") else 0.0)
		var minimum := 0.0 if world.cfg.combat.minimumDamageMode == "zero_floor" else float(world.cfg.combat.minimumDamagePerHit)
		return minf(float(target.hp), maxf(minimum, raw - armor(world, target)))


class RadarSystem:
	extends RefCounted
	## Radar exposes occupied tiles only. It never reveals terrain, unit IDs, or counts.
	## Call after vision/power/crew changes; snapshot contacts separately from entities.

	static func update(world: RefCounted) -> void:
		world.detected.clear()
		for owner in world.players:
			var coverage: Dictionary = {}
			for sensor in world.structures.values():
				if sensor.owner != owner or not sensor.built or not sensor.enabled or not sensor.powered: continue
				var definition: Dictionary = world.cfg.structures[sensor.kind]
				var reach := int(definition.get("detectionRangeBeyondFootprintTiles", 0))
				if reach <= 0: continue
				for cell in world.footprint(sensor):
					for covered in HexGrid.disk(cell, reach): coverage[covered] = true
			for sensor in world.units.values():
				if sensor.owner != owner or int(sensor.vehicle) != 0: continue
				var definition: Dictionary = world.cfg.units[sensor.kind]
				if definition.has("driverSeats") and int(sensor.driver) == 0: continue
				var reach := int(definition.get("detectionRangeTiles", 0))
				if reach > 0:
					for covered in HexGrid.disk(HexGrid.cell(sensor.pos), reach): coverage[covered] = true
			var contacts: Dictionary = {}
			for unit in world.units.values():
				if unit.owner == owner or int(unit.vehicle) != 0: continue
				if world.cfg.targeting.unitRules.get(unit.kind, {}).get("radarInvisible", false): continue
				var cell := HexGrid.cell(unit.pos)
				if coverage.has(cell): contacts[cell] = true
			world.detected[owner] = contacts


class BurrowRules:
	extends RefCounted
	## Request, transition and weapon selection form one capability. Transition state
	## lives on the unit, so save/snapshot transport does not need a second timer store.
	static func request(world: RefCounted, unit: Dictionary, buried: bool) -> bool:
		if not world.cfg.units[unit.kind].has("buriedWeapon") or unit.get("transition", "") != "" or bool(unit.get("buried", false)) == buried: return false
		unit.transition = "burrow" if buried else "emerge"
		unit.transition_remaining = float(world.cfg.combat.thresherBurrowSeconds if buried else world.cfg.combat.thresherEmergeSeconds)
		unit.route.clear(); unit.target = 0; unit.job = {"kind": "idle"}
		return true

	static func update(world: RefCounted, unit: Dictionary, delta: float) -> bool:
		if unit.get("transition", "") == "": return false
		unit.transition_remaining = maxf(0, float(unit.transition_remaining) - delta)
		if float(unit.transition_remaining) <= 0:
			unit.buried = unit.transition == "burrow"; unit.transition = ""
			world.update_visibility()
		return true

	static func weapon(world: RefCounted, unit: Dictionary) -> Variant:
		var definition: Dictionary = world.cfg.units[unit.kind]
		return definition.get("buriedWeapon") if unit.get("buried", false) else definition.get("weapon")


class GateRules:
	extends RefCounted
	## Only routed passage opens a door automatically. A manually opened door stays
	## open. Automatic doors wait for route traffic and occupants before closing.
	static func update(world: RefCounted, delta: float) -> void:
		var changed := false
		for gate in world.structures.values():
			if gate.kind != "gate" or not gate.built: continue
			if gate.has("opening_remaining"):
				gate.opening_remaining = maxf(0, float(gate.opening_remaining) - delta)
				if gate.opening_remaining <= 0:
					gate.erase("opening_remaining"); gate.open = true
					gate.close_remaining = float(world.cfg.construction.gateCloseDelaySeconds); changed = true
			if not gate.open or not gate.get("auto_close", false) or gate.locked: continue
			var occupied := false
			var cells: Array = world.footprint(gate)
			for unit in world.units.values():
				if int(unit.vehicle) != 0: continue
				if HexGrid.cell(unit.pos) in cells: occupied = true; break
				if unit.owner != gate.owner: continue
				for point in unit.route.slice(0, 2):
					if HexGrid.cell(point) in cells: occupied = true; break
			if occupied: gate.close_remaining = float(world.cfg.construction.gateCloseDelaySeconds)
			else: gate.close_remaining = float(gate.get("close_remaining", world.cfg.construction.gateCloseDelaySeconds)) - delta
			if gate.close_remaining <= 0: gate.open = false; gate.auto_close = false; changed = true
		if changed: world._rebuild_navigation(); world.update_visibility()


func feedback_audience(entity_data: Dictionary) -> Array:
	## Capture eligibility at event time. Damage never reveals a radar-only enemy.
	var audience: Array = []
	var observed: Dictionary = units.get(int(entity_data.get("vehicle", 0)), entity_data)
	for owner in players:
		if entity_data.owner == owner or TargetRules.identifiable(self, observed, owner): audience.append(owner)
	return audience

func emit_feedback(kind: String, at: Vector2, payload: Dictionary, audience: Array) -> void:
	## Presentation-only bounded log. Independent consumers keep their own serial cursor;
	## advancing simulation or replacing a snapshot does not erase unseen frame events.
	if audience.is_empty(): return
	feedback_serial += 1
	var event: Dictionary = payload.duplicate(true)
	event.merge({"serial": feedback_serial, "tick": tick, "kind": kind, "at": at, "audience": audience}, true)
	feedback_events.append(event)
	while feedback_events.size() > int(cfg.presentation.feedback.eventHistoryLimit): feedback_events.pop_front()

func feedback_for(owner: int, after: int = 0) -> Array:
	return feedback_events.filter(func(event): return int(event.serial) > after and owner in event.audience)

class FeedbackRules:
	extends RefCounted
	static func profile(config: Dictionary, weapon: String) -> Dictionary:
		var settings: Dictionary = config.presentation.feedback
		return settings.profiles[str(settings.weaponProfiles.get(weapon, "rifle"))]


class RouteOrders:
	extends RefCounted
	## Persistent routing owns the intended defensive position, not combat targets.
	## Attack interruptions may temporarily replace the route; manual orders replace
	## this job entirely. Arrays in jobs remain directly JSON-serializable.
	static func update(world: RefCounted, unit: Dictionary, delta: float) -> void:
		var rules: Dictionary = world.cfg.movement.routeOrders
		unit.job.repath = maxf(0, float(unit.job.repath) - delta)
		if unit.job.kind == "escort":
			var target: Dictionary = world.entity(int(unit.job.target))
			if target.is_empty(): unit.job = {"kind": "idle"}; unit.route.clear(); unit.home = unit.pos; return
			var distance := float(rules.escortDistanceTiles) + (float(world.cfg.structures[target.kind].footprintRadiusTiles) if target.has("cell") else 0.0)
			distance += int(unit.job.get("ring", 0)) * float(rules.escortDistanceTiles)
			var offset := Vector2(float(unit.job.offset[0]), float(unit.job.offset[1]))
			if unit.job.get("relative", false):
				var heading := float(target.get("heading", 0))
				offset = Vector2(offset.x * cos(heading) + offset.y * sin(heading), -offset.x * sin(heading) + offset.y * cos(heading))
			unit.home = world.entity_position(target) + offset * distance
			unit.job.goal = [unit.home.x, unit.home.y]
		else:
			var point: Array = unit.job.b if int(unit.job.leg) == 1 else unit.job.a
			var waypoint := Vector2(float(point[0]), float(point[1]))
			if int(unit.target) != 0: unit.job.interrupted = true
			var anchor := Vector2(float(unit.job.anchor[0]), float(unit.job.anchor[1]))
			if unit.job.interrupted and int(unit.target) == 0 and unit.pos.distance_to(anchor) <= float(rules.arrivalRadiusTiles): unit.job.interrupted = false
			if unit.job.interrupted:
				unit.home = anchor
				# Finish a permitted last-known-position search before returning to the
				# patrol anchor. The combat resolver already applies the defensive leash.
				var searching: bool = not unit.route.is_empty() and unit.route.back().distance_to(anchor) > float(rules.arrivalRadiusTiles)
				unit.job.goal = [unit.route.back().x, unit.route.back().y] if searching else [anchor.x, anchor.y]
			else:
				if unit.pos.distance_to(waypoint) <= float(rules.arrivalRadiusTiles):
					unit.job.leg = 1 - int(unit.job.leg); unit.route.clear(); unit.job.repath = 0.0
					point = unit.job.b if int(unit.job.leg) == 1 else unit.job.a
					waypoint = Vector2(float(point[0]), float(point[1]))
				unit.job.anchor = [unit.pos.x, unit.pos.y]; unit.home = unit.pos
				unit.job.goal = [waypoint.x, waypoint.y]
		if int(unit.target) != 0: return
		var goal := Vector2(float(unit.job.goal[0]), float(unit.job.goal[1]))
		if unit.pos.distance_to(goal) <= float(rules.arrivalRadiusTiles): unit.route.clear(); return
		if float(unit.job.repath) <= 0 and (unit.route.is_empty() or unit.route.back().distance_to(goal) > float(rules.arrivalRadiusTiles)):
			world.move_to(unit, goal)
			# A moving target causes frequent replans. Returning to the current hex's
			# center on each one can trap a follower in a tiny back-and-forth loop.
			if unit.route.size() > 1 and HexGrid.cell(unit.route[0]) == HexGrid.cell(unit.pos):
				var clear := true
				for fraction in [0.25, 0.5, 0.75]:
					if world.blocked(HexGrid.cell(unit.pos.lerp(unit.route[1], fraction))): clear = false; break
				if clear: unit.route.pop_front()
			unit.job.repath = float(rules.repathSeconds)
