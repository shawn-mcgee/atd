class_name WorldState
extends RefCounted

var cfg: Dictionary
var mission: Dictionary = {}
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
var structure_memory: Dictionary = {}
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
var navigation := MovementGraph.new()
var dark_navigation := MovementGraph.new()
var point_ids: Dictionary = {}
var structure_cells: Dictionary = {}
var corpse: Variant = null
var gloom_spread_time := 0.0
var lightless_chyme := 0
var lightless_brain_time := 0.0
var lightless_expansion_time := 0.0
var lightless_income_time := 0.0
var _sight_blockers: Dictionary = {}
var _sight_areas: Dictionary = {}
var _sight_topology_valid := false
var _sight_unions: Array = []
var _opponents: Dictionary = {}
var _power_signature: Array = []
var _power_groups: Array = []
var _open_movement_cells: Dictionary = {}
var _clearance_neighborhoods: Dictionary = {}
var _dark_clearance_neighborhoods: Dictionary = {}
var _separation_signature: Array = []
var _radar_coverage: Dictionary = {}
const SEPARATION_OFFSETS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]

func _init(settings: Dictionary = {}) -> void:
	cfg = settings

func reset(map_seed: int, count: int = 1) -> void:
	mission.clear()
	_sight_areas.clear(); _sight_blockers.clear(); _sight_unions.clear(); _sight_topology_valid = false
	_opponents.clear(); _power_signature.clear(); _power_groups.clear(); _open_movement_cells.clear(); _clearance_neighborhoods.clear(); _dark_clearance_neighborhoods.clear(); _separation_signature.clear()
	_radar_coverage.clear()
	seed_value = map_seed
	random.seed = map_seed
	radius = int(cfg.map.radiusTiles)
	tick = 0
	time_seconds = 0
	gloom_spread_time = 0
	lightless_chyme = int(cfg.lightless.startingChyme)
	lightless_brain_time = 0.0; lightless_expansion_time = 0.0; lightless_income_time = 0.0
	next_id = 1
	feedback_events.clear(); feedback_serial = 0
	ended = false
	result = ""
	medusa_dead = false
	corpse = null
	paused = false
	speed = 1.0
	for collection in [tiles, units, structures, players, visible, detected, illuminated, known, structure_memory, gloom, point_ids, structure_cells]: collection.clear()
	for cell in HexGrid.disk(Vector2i.ZERO, radius):
		tiles[cell] = {"cliff": random.randf() < float(cfg.map.cliffTileFraction), "resource": "", "amount": 0, "rock_health": float(cfg.map.cliffHealth)}
	var inset := radius - int(cfg.map.anchorEdgeInsetTiles)
	var corners: Array[Vector2i] = []
	for direction in HexGrid.DIRECTIONS: corners.append(direction * inset)
	var medusa_corner := random.randi_range(0, corners.size() - 1)
	var medusa_spawn: Vector2i = corners[medusa_corner]
	var selected: Array[int] = []
	var best_score := -1
	var choices: Array = []
	for mask in range(1, 64):
		if mask & (1 << medusa_corner): continue
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
		players[owner] = {"resources": cfg.map.startingResources.duplicate(true), "alive": true, "anchor": 0, "upgrades": {}, "extracting": false, "remaining": 0.0, "request_personnel": bool(cfg.personnel.personnelRequestDefaultEnabled)}
		known[owner] = {}
		for c in HexGrid.disk(spawn, 6):
			if tiles.has(c): tiles[c].cliff = false
		var anchor := add_structure("anchor", spawn, owner)
		players[owner].anchor = anchor
		add_unit("engineer", HexGrid.world(spawn + Vector2i(2, 0)), owner)
		add_unit("marine", HexGrid.world(spawn + Vector2i(2, -1)), owner)
		_field(spawn + Vector2i(-2, 3), "gas", 1)
		_field(spawn + Vector2i(3, -1), "ore", 3)
		for c in HexGrid.line(spawn, medusa_spawn):
			for nearby in HexGrid.disk(c, 1):
				if tiles.has(nearby): tiles[nearby].cliff = false
	for resource in ["ore", "gas"]:
		for i in range(int(cfg.map.additionalFieldsPerPlayer[resource]) * count):
			var center := Vector2i(random.randi_range(-radius + 4, radius - 4), random.randi_range(-radius + 4, radius - 4))
			if not tiles.has(center) or HexGrid.distance(center, medusa_spawn) < 5: continue
			var roll := random.randi_range(0, 5)
			_field(center, resource, 1 if roll < 3 else 3 if roll < 5 else 7, false)
	for c in HexGrid.disk(medusa_spawn, 3):
		if tiles.has(c): tiles[c].cliff = false
	add_structure("medusa", medusa_spawn, -1)
	for i in range(int(cfg.lightless.startingScavengers)):
		add_unit("scavenger", HexGrid.world(medusa_spawn + HexGrid.DIRECTIONS[i % 6] * 2), -1)
	for c in HexGrid.disk(medusa_spawn, int(cfg.structures.medusa.gloomRangeBeyondFootprintTiles) + int(cfg.structures.medusa.footprintRadiusTiles)):
		if tiles.has(c): gloom[c] = float(cfg.gloom.tileHealth)
	_rebuild_navigation()
	_update_power(0)
	update_visibility()

class Missions:
	extends RefCounted

	static func start(w: RefCounted, owner: int, key: String) -> String:
		if owner != 0 or w.players.size() != 1 or w.tick != 0 or not w.mission.is_empty(): return "Missions require a fresh single-player deployment"
		if not w.cfg.get("missions", {}).has(key): return "Unknown mission"
		var definition: Dictionary = w.cfg.missions[key]
		w.cfg = w.cfg.duplicate(true)
		w.cfg.map.radiusTiles = definition.radiusTiles
		w.cfg.map.anchorEdgeInsetTiles = definition.anchorEdgeInsetTiles
		w.cfg.map.startingResources = definition.startingResources.duplicate(true)
		if key == "extraction":
			w.cfg.match.extractionMinimumNacre = definition.extractionMinimumNacre
			w.cfg.match.extractionSeconds = definition.extractionSeconds
			w.cfg.structures.medusa.health = definition.medusaHealth
		w.reset(w.seed_value, 1)
		w.mission = {"id": key, "delivered": {}, "wave_remaining": 0.0, "initial_marines": 1 + int(definition.extraMarines)}
		# Scenario setup is authoritative and seeded. Peaceful contracts have no
		# colony; extraction has a small central nest and bounded timed assaults.
		for id in w.units.keys():
			if w.units[id].owner < 0: w.units.erase(id)
		for id in w.structures.keys():
			if w.structures[id].owner < 0: w.structures.erase(id)
		w.gloom.clear()
		var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
		for c in HexGrid.disk(anchor.cell, int(definition.clearRadiusTiles)):
			if w.tiles.has(c): w.tiles[c].cliff = false
		for i in range(int(definition.extraEngineers)):
			w.add_unit("engineer", HexGrid.world(anchor.cell + Vector2i(1, 1 + i)), 0)
		for i in range(int(definition.extraMarines)):
			w.add_unit("marine", HexGrid.world(anchor.cell + Vector2i(3, i - 2)), 0)
		if key == "extraction":
			for c in HexGrid.disk(Vector2i.ZERO, int(definition.nestClearRadiusTiles)): w.tiles[c].cliff = false
			for c in HexGrid.line(anchor.cell, Vector2i.ZERO):
				for adjacent in HexGrid.disk(c, 1):
					if w.tiles.has(adjacent): w.tiles[adjacent].cliff = false
			var nest: int = w.add_structure("medusa", Vector2i.ZERO, -1)
			w.structures[nest].hp = float(definition.medusaHealth)
			for i in range(int(definition.nestScavengers)):
				w.add_unit("scavenger", HexGrid.world(HexGrid.DIRECTIONS[i % 6] * int(definition.nestSpawnRadiusTiles)), -1)
		w._rebuild_navigation(); w._update_power(0); w.update_visibility()
		return "Mission deployed"

	static func requirements(w: RefCounted) -> Array:
		if w.mission.is_empty(): return []
		var d: Dictionary = w.cfg.missions[w.mission.id]
		var checks: Array = []
		if d.has("deliveryTarget"):
			var amount := int(w.mission.delivered.get(d.deliveryResource, 0))
			checks.append({"done": amount >= int(d.deliveryTarget), "text": "Deliver %s: %d / %d" % [str(d.deliveryResource).capitalize(), amount, int(d.deliveryTarget)]})
		for kind in d.get("requiredStructures", []):
			var online := false
			for s in w.structures.values():
				if s.owner == 0 and s.kind == kind and s.built and (int(w.cfg.structures[kind].powerDemand) == 0 or s.powered): online = true
			checks.append({"done": online, "text": "Complete %s%s" % [str(kind).capitalize(), " with power" if int(w.cfg.structures[kind].powerDemand) > 0 else ""]})
		if d.has("additionalMarinesRequired"):
			var count := 0
			for u in w.units.values():
				if u.owner == 0 and u.kind == "marine": count += 1
			checks.append({"done": count >= int(w.mission.initial_marines) + int(d.additionalMarinesRequired), "text": "Equip an additional Marine"})
		return checks

	static func update(w: RefCounted, delta: float) -> void:
		if w.mission.is_empty() or w.ended: return
		if not w.players[0].alive: return
		var d: Dictionary = w.cfg.missions[w.mission.id]
		if w.mission.id == "extraction":
			if not w.players[0].extracting: return
			w.mission.wave_remaining -= delta
			if float(w.mission.wave_remaining) <= 0:
				w.mission.wave_remaining += float(d.assaultIntervalSeconds)
				for i in range(int(d.assaultWaveSize)):
					var id: int = w.add_unit("scavenger", HexGrid.world(HexGrid.DIRECTIONS[i % 6] * int(d.nestSpawnRadiusTiles)), -1)
					w.units[id].stance = "attack"
			return
		var checks := requirements(w)
		if not checks.is_empty() and checks.all(func(item): return item.done):
			w.ended = true; w.result = "%s complete" % str(d.title)

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
	_opponents.clear()
	var id := next_id
	next_id += 1
	var definition: Dictionary = cfg.units[kind]
	units[id] = {"id": id, "kind": kind, "pos": position, "owner": owner, "hp": float(definition.health), "job": {"kind": "idle"}, "route": [], "cargo": {}, "cooldown": 0.0, "work": 0.0, "stance": str(definition.get("defaultStance", cfg.lightless.startingStance)), "home": position, "last_damage": -999, "target": 0, "driver": 0, "vehicle": 0, "heading": 0.0}
	units[id].passengers = []
	units[id].orders = []
	return id

func add_structure(kind: String, cell: Vector2i, owner: int, built: bool = true, depot_type: String = "ore") -> int:
	_open_movement_cells.clear(); _clearance_neighborhoods.clear(); _dark_clearance_neighborhoods.clear(); _separation_signature.clear()
	_opponents.clear()
	_sight_topology_valid = false; _sight_areas.clear()
	var id := next_id
	next_id += 1
	structures[id] = {"id": id, "kind": kind, "cell": cell, "owner": owner, "hp": float(cfg.structures[kind].health) if built else float(cfg.construction.startingHealth), "built": built, "started": built, "depot_type": depot_type, "enabled": true, "powered": false, "brownout": false, "blackout": false, "open": false, "locked": false, "buffer": 0, "cycle": 0.0, "batch": {}, "operators": [], "kits": [], "vehicles": [], "upgrades": [], "fuel": 0.0, "cooldown": 0.0, "passive": 0.0}
	structures[id].configuration_remaining = 0.0
	structures[id].personnel_source = 0
	structures[id].request_personnel = bool(players.get(owner, {}).get("request_personnel", cfg.personnel.personnelRequestDefaultEnabled))
	structures[id].vehicle_assignments = {}
	if owner < 0 and kind in ["medusa", "womb"]:
		structures[id].spawn_queue = []
		if kind == "womb": structures[id].unit_type = "scavenger"
	for occupied in footprint(structures[id]):
		if not structure_cells.has(occupied): structure_cells[occupied] = []
		structure_cells[occupied].append(id)
	if owner >= 0 and kind in ["armory", "factory", "cradle"]:
		var source := personnel_source(owner, cell)
		if not source.is_empty(): structures[id].personnel_source = source.id
	return id

func footprint(s: Dictionary) -> Array[Vector2i]:
	return HexGrid.disk(s.cell, int(cfg.structures[s.kind].footprintRadiusTiles))

func blocked(cell: Vector2i, ignore: int = 0) -> bool:
	if not tiles.has(cell) or HexGrid.distance(cell) >= radius or tiles[cell].cliff: return true
	for id in structure_cells.get(cell, []):
		var s: Dictionary = structures.get(id, {})
		if s.is_empty() or s.id == ignore or not s.started: continue
		if s.kind == "gate" and s.open: continue
		return true
	return false

func _index_structures() -> void:
	_open_movement_cells.clear(); _clearance_neighborhoods.clear(); _dark_clearance_neighborhoods.clear(); _separation_signature.clear()
	structure_cells.clear()
	for structure in structures.values():
		for cell in footprint(structure):
			if not structure_cells.has(cell): structure_cells[cell] = []
			structure_cells[cell].append(int(structure.id))

func _rebuild_navigation() -> void:
	_sight_topology_valid = false; _sight_areas.clear()
	_index_structures()
	if point_ids.size() == tiles.size() and navigation.get_point_count() == tiles.size():
		# The hex topology is static. Construction, doors and excavation only
		# change admission; retain the native graph and its existing edges.
		navigation.edge_cache.clear(); dark_navigation.edge_cache.clear()
		for cell in point_ids:
			var disabled := blocked(cell)
			var point: int = point_ids[cell]
			if navigation.is_point_disabled(point) != disabled: navigation.set_point_disabled(point, disabled)
			if dark_navigation.is_point_disabled(point) != disabled: dark_navigation.set_point_disabled(point, disabled)
		return
	navigation.clear(); navigation.edge_cache.clear()
	dark_navigation.clear(); dark_navigation.edge_cache.clear()
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

func _route_path(u: Dictionary, start: Vector2i, finish: Vector2i, partial: bool = false) -> PackedVector2Array:
	if not point_ids.has(start) or not point_ids.has(finish): return PackedVector2Array()
	var graph := dark_navigation if u.owner < 0 and u.job.kind != "attack" else navigation
	var admitted: Array[int] = []
	for gate in structures.values():
		if gate.kind != "gate" or gate.owner != u.owner or not gate.built or gate.locked or gate.open: continue
		for cell in footprint(gate):
			if point_ids.has(cell): graph.set_point_disabled(point_ids[cell], false); admitted.append(point_ids[cell])
	graph.query_world = weakref(self); graph.query_unit = u
	graph.neighbor_filter_enabled = RouteNavigation.clearance(self, u) >= HexGrid.RADIUS * 0.5
	var path := graph.get_point_path(point_ids[start], point_ids[finish], partial)
	graph.neighbor_filter_enabled = false; graph.query_unit = {}; graph.query_world = null
	for id in admitted: graph.set_point_disabled(id, true)
	return path

func move_to(u: Dictionary, destination: Vector2) -> void:
	var start := nearest_free(HexGrid.cell(u.pos))
	var finish := nearest_free(HexGrid.cell(destination))
	var path := _route_path(u, start, finish, true)
	if not path.is_empty() and HexGrid.cell(path[path.size() - 1]) == finish and not blocked(HexGrid.cell(destination)) and RouteNavigation.clear_segment(self, u, destination, destination, true):
		path[path.size() - 1] = destination
	RouteNavigation.assign(self, u, path)

func _move(u: Dictionary, delta: float) -> bool:
	if u.vehicle != 0 or u.get("buried", false) or u.get("transition", "") != "": return false
	if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0: return false
	var budget := float(cfg.units[u.kind].speedTilesPerSecond) * delta
	var moved := false
	while budget > 0 and not u.route.is_empty():
		var goal: Vector2 = u.route[0]
		var distance: float = u.pos.distance_to(goal)
		if distance <= float(cfg.movement.pathfinding.waypointToleranceTiles) and u.route.size() > 1:
			u.route.pop_front(); continue
		var travel := minf(budget, distance)
		var proposed: Vector2 = u.pos.move_toward(goal, travel)
		for gate in structures.values():
			if gate.kind != "gate" or gate.open or not gate.built: continue
			if RouteNavigation.hex_distance_squared(u.pos, proposed, gate.cell) >= pow(RouteNavigation.clearance(self, u), 2): continue
			if gate.owner == u.owner and not gate.locked:
				if not gate.has("opening_remaining"): gate.opening_remaining = float(cfg.construction.gateOpenSeconds); gate.auto_close = true
				return moved
			u.route.clear(); return moved
		if not RouteNavigation.clear_segment(self, u, u.pos, proposed):
			u.route.clear(); return moved
		if distance > 0.00001:
			var direction: Vector2 = goal - u.pos
			u.heading = atan2(-direction.x, -direction.y)
			u.pos = proposed; moved = true
		budget -= travel
		if travel >= distance: u.route.pop_front()
	return moved

func clearance_obstacles(cell: Vector2i, reach: int, avoid_light: bool) -> Array[Vector2i]:
	var cache: Dictionary = _dark_clearance_neighborhoods if avoid_light else _clearance_neighborhoods
	var key := Vector3i(cell.x, cell.y, reach)
	if not cache.has(key):
		var obstacles: Array[Vector2i] = []
		for nearby in HexGrid.disk(cell, reach):
			if blocked(nearby) or (avoid_light and is_lit(nearby)): obstacles.append(nearby)
		cache[key] = obstacles
	return cache[key]

func open_movement_cell(cell: Vector2i) -> bool:
	if not _open_movement_cells.has(cell):
		var clear := not blocked(cell)
		if clear:
			for direction in HexGrid.DIRECTIONS:
				if blocked(cell + direction): clear = false; break
		_open_movement_cells[cell] = clear
	return _open_movement_cells[cell]

func activity(e: Dictionary) -> Dictionary:
	# Read-only status shared by local inspection and owner-filtered snapshots.
	if e.has("activity"): return e.activity.duplicate(true)
	return ActivityRules.inspect(self, e)

class ActivityRules:
	extends RefCounted

	static func waiting(a: Dictionary, reason: String) -> Dictionary:
		a.phase = "waiting"; a.blocker = reason; return a

	static func inspect(w: RefCounted, e: Dictionary) -> Dictionary:
		var a := {"task": "idle", "phase": "idle", "blocker": "", "target": 0, "resource": "", "progress": -1.0}
		if e.get("remembered", false): a.task = "remembered"; return a
		if e.has("cell"): return structure(w, e, a)
		var job: Dictionary = e.job
		var kind := str(job.kind)
		a.task = kind; a.target = int(job.get("target", 0))
		a.phase = "moving" if not e.route.is_empty() else "working"
		if int(e.vehicle) != 0: a.task = "riding"; a.target = int(e.vehicle); return a
		if w.cfg.units[e.kind].has("driverSeats") and int(e.driver) == 0: return waiting(a, "no_driver")
		if e.get("transition", "") != "": a.task = str(e.transition); return a
		if e.get("buried", false): return waiting(a, "buried")
		if int(e.target) != 0 and float(e.cooldown) > 0: a.task = "attack"; a.target = int(e.target); a.phase = "working"; return a
		if kind == "idle": a.phase = "idle"; return a
		if kind == "crew_wait": a.target = int(job.factory); return waiting(a, "vehicle_pending")
		if kind == "mine" and not job.get("delivering", false):
			var cell := HexGrid.unkey(job.source)
			var facility: Dictionary = w.structures.get(int(job.get("facility", 0)), {})
			a.target = int(facility.get("id", 0)); a.cell = [cell.x, cell.y]
			a.resource = w._output_resource(facility) if not facility.is_empty() else str(w.tiles.get(cell, {}).get("resource", ""))
			if facility.is_empty() and int(w.tiles.get(cell, {}).get("amount", 0)) == 0: return waiting(a, "depleted")
			if e.pos.distance_to(HexGrid.world(cell)) > 1.3:
				return waiting(a, "no_route") if e.route.is_empty() else a
			if not facility.is_empty() and int(facility.buffer) == 0:
				if not facility.enabled: return waiting(a, "switched_off")
				if not facility.powered: return waiting(a, "no_power")
				var production := structure(w, facility, a.duplicate(true))
				if production.blocker == "no_resources":
					a.blocker_resource = production.get("blocker_resource", "")
					return waiting(a, "no_resources")
				return waiting(a, "output_pending")
			a.progress = clampf(float(e.work) / float(w.cfg.economy.workerCycleSeconds), 0, 1)
		elif kind == "deposit" or kind == "mine":
			a.task = "deposit"
			a.target = int(job.get("deposit", 0)) if kind == "mine" else int(job.get("target", 0))
			if not w.structures.has(a.target): a.target = w._deposit_destination(e)
			var depot: Dictionary = w.structures.get(a.target, {})
			if depot.is_empty(): return waiting(a, "no_dropoff")
			if e.pos.distance_to(w.entity_position(depot)) > int(w.cfg.structures[depot.kind].footprintRadiusTiles) + 1.2:
				return waiting(a, "no_route") if e.route.is_empty() else a
			var accepts := false
			for resource in e.cargo:
				if int(e.cargo[resource]) <= 0: continue
				if resource == "nacre" and depot.kind != "anchor": continue
				accepts = true
				if int(w.resources(e.owner).get(resource, 0)) < w.capacity(e.owner, resource): return a
				a.resource = resource
			return waiting(a, "storage_full" if accepts else "anchor_required")
		elif kind in ["build", "repair", "research", "equip", "board", "load_cargo", "escort"]:
			var target: Dictionary = w.entity(a.target)
			if target.is_empty(): return waiting(a, "target_lost")
			var reach := float(w.cfg.economy.interactionRangeTiles)
			if target.has("cell"): reach = int(w.cfg.structures[target.kind].footprintRadiusTiles) + (1.2 if kind == "equip" else 1.4)
			if kind == "repair": reach = float(w.cfg.construction.engineerWorkRangeTiles) + (int(w.cfg.structures[target.kind].footprintRadiusTiles) + 0.2 if target.has("cell") else 0.0)
			if kind != "escort" and e.pos.distance_to(w.entity_position(target)) > reach: return waiting(a, "no_route") if e.route.is_empty() else a
			if kind == "build":
				a.progress = clampf(float(target.hp) / float(w.cfg.structures[target.kind].health), 0, 1)
				if not target.started:
					for cell in w.footprint(target):
						if w.blocked(cell, target.id): return waiting(a, "site_blocked")
						for other in w.units.values():
							if int(other.vehicle) == 0 and HexGrid.cell(other.pos) == cell: return waiting(a, "site_occupied")
			elif kind == "repair":
				a.progress = float(target.hp) / float(w.cfg.structures[target.kind].health if target.has("cell") else w.cfg.units[target.kind].health)
				if float(e.work) <= 0 and int(w.resources(e.owner).get("ore", 0)) < int(w.cfg.construction.repairOrePerCycle): a.resource = "ore"; return waiting(a, "no_resources")
			elif kind == "research":
				if target.upgrades.is_empty(): return waiting(a, "no_research")
				if not target.powered: return waiting(a, "no_power")
				a.progress = float(target.upgrades[0].progress) / float(w.cfg.upgrades.fabricatorArmor.engineerWorkSeconds)
			elif kind == "equip":
				if w.cargo_amount(e) > 0: return waiting(a, "unload_cargo")
				if target.kits.is_empty(): return waiting(a, "no_kit")
				if not target.kits[0].done: return waiting(a, "kit_pending")
			elif kind == "load_cargo" and w.cargo_amount(target) >= int(w.cfg.units[target.kind].cargoCapacity): return waiting(a, "cargo_full")
		elif kind == "attack":
			a.target = int(e.target)
			var enemy: Dictionary = w.observed_entity(int(e.target), int(e.owner))
			if e.route.is_empty() and not enemy.is_empty() and not enemy.get("remembered", false):
				var line := HexGrid.line(HexGrid.cell(e.pos), HexGrid.cell(w.entity_position(enemy)))
				for i in range(1, maxi(1, line.size() - 1)):
					if w.known.get(e.owner, {}).has(line[i]) and w.blocks_sight(line[i]): a.cell = [line[i].x, line[i].y]; return waiting(a, "line_blocked")
		return a

	static func structure(w: RefCounted, e: Dictionary, a: Dictionary) -> Dictionary:
		a.task = "standby"
		if e.owner < 0: return a
		if not e.built:
			a.task = "build"; a.progress = float(e.hp) / float(w.cfg.structures[e.kind].health)
			for unit in w.units.values():
				if unit.owner == e.owner and unit.job.kind == "build" and int(unit.job.target) == int(e.id):
					var worker: Dictionary = inspect(w, unit)
					a.phase = worker.phase; a.blocker = worker.blocker; return a
			return waiting(a, "no_engineer")
		if not e.enabled: return waiting(a, "switched_off")
		if int(w.cfg.structures[e.kind].powerDemand) > 0 and not e.powered: return waiting(a, "no_power")
		if float(e.get("configuration_remaining", 0)) > 0: a.task = "configure"; a.phase = "working"; return a
		if w.cfg.economy.recipes.has(e.kind):
			a.task = "produce"; a.resource = w._output_resource(e)
			var recipe: Dictionary = w.cfg.economy.recipes[e.kind]
			var cap := int(w.cfg.economy.extractorBufferCapacity if e.kind == "extractor" else w.cfg.economy.processorBufferCapacity)
			var batch := int(recipe.get("outputUnits", 0)) if e.kind == "extractor" else int(recipe.outputs.values()[0])
			if float(e.cycle) > 0: a.phase = "working"; a.progress = 1.0 - float(e.cycle) / float(recipe.cycleSeconds); return a
			if int(e.buffer) + batch > cap: return waiting(a, "buffer_full")
			if e.kind == "extractor":
				if int(w.tiles[e.cell].amount) <= 0: return waiting(a, "depleted")
			else:
				for resource in recipe.inputs:
					if int(w.resources(e.owner).get(resource, 0)) < int(recipe.inputs[resource]): a.blocker_resource = resource; return waiting(a, "no_resources")
			a.phase = "working"
		elif e.kind == "fabricator" and not e.upgrades.is_empty():
			a.task = "research"
			for unit in w.units.values():
				if unit.owner == e.owner and unit.job.kind == "research" and int(unit.job.target) == int(e.id) and unit.pos.distance_to(w.entity_position(e)) <= int(w.cfg.structures[e.kind].footprintRadiusTiles) + 1.4: a.phase = "working"; return a
			return waiting(a, "no_engineer")
		elif not e.vehicles.is_empty() or not e.operators.is_empty() or not e.kits.is_empty():
			a.task = "produce"; a.phase = "working"
			if e.vehicles.is_empty() and e.operators.is_empty() and not e.kits.is_empty() and e.kits.all(func(kit): return kit.done): return waiting(a, "kit_pickup")
			if not e.vehicles.is_empty() and float(e.vehicles[0].progress) >= float(w.cfg.units[e.vehicles[0].kind].productionSeconds): return waiting(a, "exit_blocked")
		return a

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

func command(owner: int, order: Dictionary, from_queue: bool = false) -> String:
	if ended or not players.has(owner) or (not players[owner].alive and not from_queue): return "Player cannot issue orders"
	var action := str(order.get("action", ""))
	if action == "start_mission":
		return Missions.start(self, owner, str(order.get("mission", "")))
	if order.has("queued") and not order.queued is bool: return "Invalid queue flag"
	if not order.get("ids", []) is Array or order.get("ids", []).size() > 128: return "Invalid unit selection"
	var required: Dictionary = {"move": ["x", "z"], "patrol": ["x", "z"], "escort": ["target"], "mine": ["q", "r"], "attack": ["target"], "equip": ["target"], "board": ["target"], "load_cargo": ["target"], "excavate": ["q", "r"], "build": ["q", "r"], "build_line": ["q", "r", "end_q", "end_r"]}
	for field in required.get(action, []):
		if not order.has(field) or not (order[field] is int or order[field] is float) or not is_finite(float(order[field])): return "Invalid order coordinates or target"
	if action == "attack":
		var observed := observed_entity(int(order.target), owner)
		if from_queue and observed.is_empty(): return "Target is no longer visible"
		if observed.get("remembered", false): return "Rediscover this structure before targeting it"
	if action in ["build", "kit", "vehicle"] and not order.get("kind") is String: return "Missing production type"
	if action == "stance" and not order.get("stance") is String: return "Invalid stance"
	var ids: Array = order.get("ids", [])
	for raw_id in ids:
		if not (raw_id is int or raw_id is float): return "Invalid unit selection"
	if action == "global_personnel":
		if not order.get("enabled") is bool: return "Invalid personnel setting"
		players[owner].request_personnel = order.enabled
		for facility in structures.values():
			if facility.owner == owner: facility.request_personnel = order.enabled
		return "Global Operator requests enabled" if order.enabled else "Global Operator requests disabled"
	if bool(order.get("queued", false)) and action in ["move", "attack", "mine", "repair", "deposit", "work", "equip", "board", "load_cargo", "excavate", "patrol", "escort", "unload"]:
		if order.has("target"):
			var target := observed_entity(int(order.target), owner)
			if target.is_empty() or target.get("remembered", false): return "Select a visible target"
			if action != "attack" and action != "board" and target.owner != owner: return "Select a friendly target"
		if action in ["mine", "excavate"] and not known.get(owner, {}).has(Vector2i(int(order.q), int(order.r))): return "Select a revealed tile"
		var queued := 0
		for raw_id in ids:
			var unit: Dictionary = units.get(int(raw_id), {})
			if unit.is_empty() or unit.owner != owner or int(unit.vehicle) != 0: continue
			if unit.orders.size() >= int(cfg.movement.orderQueueLimit): continue
			var next := order.duplicate(true); next.erase("queued"); next.ids = [unit.id]
			unit.orders.append(next); queued += 1
		return "Order queued for %d units" % queued if queued > 0 else "No eligible units or order queue full"
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
				if not from_queue: unit.orders.clear()
				var finish: Vector2 = unit.route.back()
				unit.job = {"kind": "patrol", "a": [unit.pos.x, unit.pos.y], "b": [finish.x, finish.y], "leg": 1, "anchor": [unit.pos.x, unit.pos.y], "interrupted": false, "repath": 0.0}
				unit.home = finish
			else:
				if not from_queue: unit.orders.clear()
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
			if not vehicle.is_empty() and vehicle.owner == owner and cfg.units[vehicle.kind].has("driverSeats"):
				if not from_queue: vehicle.orders.clear()
				unload_vehicle(vehicle, false)
		return "Occupants unloaded; passengers leave before the driver"
	if action == "excavate":
		var cell := Vector2i(int(order.get("q", 99999)), int(order.get("r", 99999)))
		if not known[owner].has(cell) or not tiles.has(cell) or not tiles[cell].cliff or HexGrid.distance(cell) >= radius: return "Select a revealed cliff inside the map boundary"
		for raw_id in ids:
			var unit := units.get(int(raw_id), {}) as Dictionary
			if not unit.is_empty() and unit.owner == owner and unit.kind == "excavator":
				if not from_queue: unit.orders.clear()
				unit.job = {"kind": "excavate", "source": HexGrid.key(cell)}; move_to(unit, HexGrid.world(nearest_free(cell)))
		return "Cliff clearing ordered; a driver is required"
	if action == "load_cargo":
		var vehicle := units.get(int(order.get("target", 0)), {}) as Dictionary
		if vehicle.is_empty() or vehicle.owner != owner or not cfg.units[vehicle.kind].has("driverSeats") or int(cfg.units[vehicle.kind].cargoCapacity) == 0: return "Choose a friendly cargo vehicle"
		for raw_id in ids:
			var worker := units.get(int(raw_id), {}) as Dictionary
			if not worker.is_empty() and worker.owner == owner and worker.kind in ["operator", "engineer"] and int(worker.vehicle) == 0:
				if not from_queue: worker.orders.clear()
				worker.job = {"kind": "load_cargo", "target": vehicle.id}; move_to(worker, vehicle.pos)
		return "Load cargo ordered; workers retain cargo if the vehicle is full"
	if action == "board" and (not units.has(int(order.target)) or not cfg.units[units[int(order.target)].kind].has("driverSeats")): return "Choose a vehicle to board"
	if action == "stop":
		for raw_id in ids:
			if units.has(int(raw_id)) and units[int(raw_id)].owner == owner:
				var u: Dictionary = units[int(raw_id)]
				u.orders.clear()
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
			if not from_queue: u.orders.clear()
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
			if not from_queue: u.orders.clear()
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
	if action == "build_line":
		var builder := _build_engineer(owner, ids)
		if builder.is_empty(): return "Select an Engineer"
		var start := Vector2i(int(order.q), int(order.r))
		var finish := Vector2i(int(order.end_q), int(order.end_r))
		var plan := wall_line_plan(owner, start, finish)
		if not plan.issue.is_empty(): return str(plan.issue)
		var placed := 0
		for site in plan.sites:
			if not site.valid: continue
			var queued: bool = bool(order.get("queued", false)) or placed > 0
			if queued and builder.orders.size() >= int(cfg.movement.orderQueueLimit): break
			var result := command(owner, {"action": "build", "kind": "wall", "ids": [builder.id], "q": site.cell.x, "r": site.cell.y, "queued": queued})
			if result == "Blueprint placed": placed += 1
		return "%d wall blueprints placed; blocked, unaffordable or excess cells skipped" % placed
	if action == "build":
		var kind := str(order.kind)
		if not cfg.structures.has(kind) or kind in ["anchor", "medusa", "womb", "gland", "chyme_gland", "stoma"]: return "Unavailable structure"
		var builder := _build_engineer(owner, ids)
		if builder.is_empty(): return "Select an Engineer"
		if bool(order.get("queued", false)) and builder.orders.size() >= int(cfg.movement.orderQueueLimit): return "Order queue full"
		var cell := Vector2i(int(order.q), int(order.r))
		for c in HexGrid.disk(cell, int(cfg.structures[kind].footprintRadiusTiles)):
			if not known[owner].has(c) or not tiles.has(c): return "Entire footprint must be revealed"
		var issue := placement_issue(owner, kind, cell)
		if issue != "": return issue
		if not _pay(owner, cfg.structures[kind].cost): return "Not enough resources"
		var id := add_structure(kind, cell, owner, false, str(order.get("depot_type", "ore")))
		if bool(order.get("queued", false)):
			builder.orders.append({"action": "work", "target": id, "ids": [builder.id]})
		else:
			if not from_queue: builder.orders.clear()
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
		var auto_personnel := bool(order.get("personnel", players[owner].request_personnel))
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
		if order.has("enabled"):
			players[owner].request_personnel = bool(order.enabled)
			for facility in structures.values():
				if facility.owner == owner: facility.request_personnel = bool(order.enabled)
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
				if not from_queue: units[int(raw_id)].orders.clear()
				units[int(raw_id)].job = {"kind": "research" if s.built and s.kind == "fabricator" else "build", "target": target_id}
				move_to(units[int(raw_id)], _work_position(s, units[int(raw_id)].pos))
		return "Engineers assigned"
	if action == "extract" and s.kind == "anchor":
		if int(resources(owner).get("nacre", 0)) < int(cfg.match.extractionMinimumNacre): return "Deliver %d Nacre first" % int(cfg.match.extractionMinimumNacre)
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
		var auto_personnel := bool(order.get("personnel", players[owner].request_personnel))
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
	if action == "toggle":
		s.enabled = not s.enabled
		_update_power(0); update_visibility()
		return ("Relay switched on" if s.enabled else "Relay switched off") if s.kind == "relay" else "Power toggled"
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

func structure_visible(owner: int, structure: Dictionary) -> bool:
	if structure.get("remembered", false): return false
	var sight: Dictionary = visible.get(owner, {})
	for cell in footprint(structure):
		if sight.has(cell): return true
	return false

func observed_entity(id: int, owner: int) -> Dictionary:
	var current := entity(id)
	if not current.is_empty():
		if current.owner == owner: return current
		if current.has("cell"):
			if structure_visible(owner, current): return current
		elif TargetRules.identifiable(self, current, owner): return current
	return structure_memory.get(owner, {}).get(id, {})

func observed_structures(owner: int) -> Array:
	var result: Array = []
	var live: Dictionary = {}
	for structure in structures.values():
		if structure.owner == owner or structure_visible(owner, structure):
			result.append(structure); live[int(structure.id)] = true
	for id in structure_memory.get(owner, {}):
		if not live.has(id): result.append(structure_memory[owner][id])
	return result

func _remember_structures() -> void:
	for owner in players:
		if not structure_memory.has(owner): structure_memory[owner] = {}
		var records: Dictionary = structure_memory[owner]
		# A hidden demolition is not observable. Clear its old silhouette only
		# when a previously occupied part of its footprint is scouted again.
		for id in records.keys():
			var record: Dictionary = records[id]
			var revisited := false
			for cell in footprint(record):
				if visible.get(owner, {}).has(cell): revisited = true; break
			if revisited: records.erase(id)
		for structure in structures.values():
			if structure.owner == owner or not structure_visible(owner, structure): continue
			var record: Dictionary = structure.duplicate(true)
			record.remembered = true; record.last_seen_tick = tick; record.last_seen_seconds = time_seconds
			records[int(structure.id)] = record

func entity_position(e: Dictionary) -> Vector2:
	return e.pos if e.has("pos") else HexGrid.world(e.cell)

func step(delta: float) -> void:
	if ended or paused: return
	_opponents.clear()
	tick += 1
	time_seconds += delta
	shots.clear()
	GateRules.update(self, delta)
	_update_power(delta)
	RadarSystem.update(self)
	if mission.is_empty(): LightlessColony.update(self, delta)
	for s in structures.values(): _production(s, delta)
	for id in units.keys():
		if units.has(id):
			var unit: Dictionary = units[id]
			if unit.owner >= 0 and int(unit.vehicle) == 0:
				if unit.job.get("automatic", false) and not unit.orders.is_empty():
					unit.job = {"kind": "idle"}; unit.route.clear(); unit.target = 0
				while unit.job.kind == "idle" and not unit.orders.is_empty():
					var next: Dictionary = unit.orders.pop_front()
					command(int(unit.owner), next, true)
			_unit_step(unit, delta)
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
	Missions.update(self, delta)


func _unit_step(u: Dictionary, delta: float) -> void:
	if u.vehicle != 0: return
	if u.owner >= 0 and u.kind == "engineer": _idle_engineer_work(u, delta)
	if u.owner < 0 and u.kind == "mother":
		LightlessColony.mother_step(self, u, delta); return
	if BurrowRules.update(self, u, delta): return
	if u.owner < 0 and cfg.units[u.kind].has("buriedWeapon") and not u.get("buried", false) and u.job.kind == "idle":
		BurrowRules.request(self, u, true); return
	if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0: return
	u.cooldown = maxf(0, float(u.cooldown) - delta)
	if u.owner >= 0 and u.stance == "neutral" and u.job.kind == "idle" and u.route.is_empty(): return
	if u.owner < 0: u.job.repath_remaining = maxf(0, float(u.job.get("repath_remaining", 0)) - delta)
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
	if u.owner < 0 and u.job.kind == "attack": LightlessTactics.prepare_attack(self, u)
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
		elif facility.upgrades.is_empty(): u.job = {"kind": "idle"}; u.route.clear()
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
				if int(vehicle.driver) == 0: vehicle.driver = u.id; vehicle.owner = u.owner; _opponents.clear()
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
		if u.route.is_empty() and not gloom.has(HexGrid.cell(u.pos)) and float(u.job.get("repath_remaining", 0)) <= 0:
			LightlessTactics.retreat(self, u)
		_move(u, delta)
		if u.route.is_empty() and float(u.hp) >= float(cfg.units[u.kind].health): u.job = {"kind": "idle"}
		return
	if u.job.kind == "attack":
		LightlessTactics.prepare_attack(self, u)
		if not _fire(u, str(cfg.units[u.kind].weapon), delta): _move(u, delta)
		return
	if u.job.kind == "idle": u.job = {"kind": "probe", "pressure": 0.0, "damage_tick": int(u.last_damage)}
	if int(u.last_damage) > int(u.job.get("damage_tick", -999)):
		u.job = {"kind": "retreat"}; u.target = 0; u.route.clear()
		LightlessTactics.retreat(self, u)
		return
	var goal := LightlessTactics.known_anchor(self, u.pos)
	if u.route.is_empty() and not goal.is_empty(): move_to(u, entity_position(goal))
	var candidate: Dictionary = {}
	var nearest := INF
	var vision := _cached_sight(HexGrid.cell(u.pos), int(cfg.units[u.kind].visionRangeTiles))
	for e in _enemy_entities(int(u.owner)):
		if e.owner < 0 or int(e.get("vehicle", 0)) != 0: continue
		var extent := int(cfg.structures[e.kind].footprintRadiusTiles) if e.has("cell") else 0
		var reach := float(cfg.units[u.kind].visionRangeTiles) + extent + HexGrid.RADIUS * 2
		if u.pos.distance_squared_to(entity_position(e)) > reach * reach: continue
		var seen := vision.has(HexGrid.cell(entity_position(e)))
		if e.has("cell"):
			for cell in footprint(e):
				if vision.has(cell): seen = true; break
		if not seen: continue
		var d: float = u.pos.distance_to(entity_position(e))
		if d < nearest: nearest = d; candidate = e
	# The CPU already knows Anchor locations. A light perimeter must not create
	# a permanent blind spot between its shorter vision and the Anchor's light.
	if candidate.is_empty() and not goal.is_empty() and not u.route.is_empty() and is_lit(HexGrid.cell(u.route[0])):
		candidate = goal
	if not candidate.is_empty():
		if int(u.target) != int(candidate.id): u.job.pressure = 0.0
		u.target = candidate.id
		u.job.pressure += delta
		if float(u.job.pressure) >= float(cfg.lightless.probeResistanceWindowSeconds):
			var target_id := int(candidate.id)
			var nearby := units.values().filter(func(other): return other.owner < 0 and cfg.units[other.kind].get("weapon") != null and other.pos.distance_to(u.pos) <= float(cfg.lightless.probePressureSignalRangeTiles))
			for other in nearby:
				if other.kind == "stalker" and nearby.size() < 2: continue
				if other.stance == "probe" and other.job.kind in ["idle", "probe"]:
					other.target = target_id; other.job = {"kind": "attack"}; other.route.clear()
			return
	else: u.target = 0; u.job.pressure = 0.0
	# Probes test from the dark edge. Committed attacks may cross illumination.
	if not u.route.is_empty() and not is_lit(HexGrid.cell(u.route[0])): _move(u, delta)

func _healing(delta: float) -> void:
	for u in units.values():
		if not cfg.units[u.kind].get("biological", false) or u.vehicle != 0 or float(u.hp) >= float(cfg.units[u.kind].health): continue
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
	var positions := PackedVector2Array()
	var identifiers := PackedInt64Array()
	var radii := PackedFloat64Array()
	for u in units.values():
		if int(u.vehicle) != 0 or u.get("buried", false): continue
		positions.append(u.pos)
		radii.append(float(cfg.units[u.kind].collisionRadiusTiles))
		identifiers.append(-int(u.id) if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0 else int(u.id))
	var signature: Array = [positions, identifiers, radii, delta, cfg.movement.separationTilesPerSecond]
	if signature == _separation_signature: return
	_separation_signature = signature
	var buckets: Dictionary = {}
	for u in units.values():
		if int(u.vehicle) != 0 or u.get("buried", false): continue
		var key := Vector2i(floori(u.pos.x), floori(u.pos.y))
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(u)
	for u in units.values():
		if int(u.vehicle) != 0 or u.get("buried", false): continue
		if cfg.units[u.kind].has("driverSeats") and int(u.driver) == 0: continue
		var key := Vector2i(floori(u.pos.x), floori(u.pos.y))
		var push := Vector2.ZERO
		for neighbor in SEPARATION_OFFSETS:
			if not buckets.has(key + neighbor): continue
			for other in buckets[key + neighbor]:
				if other.id == u.id: continue
				var offset: Vector2 = u.pos - other.pos
				var desired := float(cfg.units[u.kind].collisionRadiusTiles) + float(cfg.units[other.kind].collisionRadiusTiles)
				var length_squared := offset.length_squared()
				if length_squared >= desired * desired: continue
				var distance := sqrt(length_squared)
				var direction := offset / distance if distance > 0.001 else Vector2.RIGHT * (1 if int(u.id) > int(other.id) else -1)
				push += direction * (desired - distance)
		var proposed: Vector2 = u.pos + push.limit_length(float(cfg.movement.separationTilesPerSecond) * delta)
		if push.length_squared() > 0.000001 and RouteNavigation.clear_segment(self, u, u.pos, proposed):
			u.pos = proposed; _separation_signature.clear()

func _deposit_cargo(u: Dictionary, depot: Dictionary) -> void:
	var delivered := 0
	for resource in u.cargo.keys():
		if resource == "nacre" and depot.kind != "anchor": continue
		var amount := mini(int(u.cargo[resource]), maxi(0, capacity(u.owner, resource) - int(resources(u.owner).get(resource, 0))))
		resources(u.owner)[resource] = int(resources(u.owner).get(resource, 0)) + amount
		if not mission.is_empty() and u.owner == 0:
			mission.delivered[resource] = int(mission.delivered.get(resource, 0)) + amount
		u.cargo[resource] -= amount; delivered += amount
	if delivered > 0: emit_feedback("deposit", entity_position(depot), {"amount": delivered, "owner": u.owner, "target": depot.id}, [int(u.owner)])

func _repair(u: Dictionary, delta: float) -> void:
	var target := entity(int(u.job.target))
	if target.is_empty(): u.job = {"kind": "idle"}; return
	var maximum := float(cfg.structures[target.kind].health) if target.has("cell") else float(cfg.units[target.kind].health)
	if float(target.hp) >= maximum: u.job = {"kind": "idle"}; return
	var reach := float(cfg.construction.engineerWorkRangeTiles) + (float(cfg.structures[target.kind].footprintRadiusTiles) + 0.2 if target.has("cell") else 0.0)
	if u.pos.distance_to(entity_position(target)) > reach:
		if u.job.get("automatic", false) and u.route.is_empty(): u.job = {"kind": "idle"}; return
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
	var result := _cached_sight(cell, int(d.illuminationRangeTiles if illumination else d.visionRangeTiles))
	var forward_range := int(d.get("forwardIlluminationRangeTiles" if illumination else "visionForwardRangeTiles", 0))
	if forward_range > 0:
		result = result.duplicate()
		var direction := Vector2(-sin(float(unit.heading)), -cos(float(unit.heading)))
		result.merge(_cached_sight(cell, forward_range, direction, float(d.forwardConeDegrees)), true)
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
				if facility == 0 and int(tiles.get(source, {}).get("amount", 0)) <= 0 and not u.orders.is_empty(): u.job = {"kind": "idle"}; u.route.clear()
				else: move_to(u, HexGrid.world(nearest_free(source)))
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
		elif facility == 0 and amount == 0 and not u.orders.is_empty(): u.job = {"kind": "idle"}; u.route.clear()
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

func _build_engineer(owner: int, ids: Array) -> Dictionary:
	for raw_id in ids:
		var unit: Dictionary = units.get(int(raw_id), {})
		if not unit.is_empty() and unit.owner == owner and unit.kind == "engineer" and int(unit.vehicle) == 0: return unit
	return {}

func wall_line_plan(owner: int, start: Vector2i, finish: Vector2i) -> Dictionary:
	var result := {"sites": [], "count": 0, "cost": {}, "issue": ""}
	if not players.has(owner) or HexGrid.distance(start) >= radius or HexGrid.distance(finish) >= radius:
		result.issue = "Keep the wall line inside the map"; return result
	var budget: Dictionary = resources(owner).duplicate()
	var cost: Dictionary = cfg.structures.wall.cost
	for cell in HexGrid.line(start, finish):
		var issue := placement_issue(owner, "wall", cell)
		if issue.is_empty():
			for resource in cost:
				if int(budget.get(resource, 0)) < int(cost[resource]): issue = "Not enough %s" % str(resource).capitalize(); break
		if issue.is_empty():
			for resource in cost:
				budget[resource] -= int(cost[resource])
				result.cost[resource] = int(result.cost.get(resource, 0)) + int(cost[resource])
			result.count += 1
		result.sites.append({"cell": cell, "valid": issue.is_empty(), "issue": issue})
	return result

func _idle_engineer_work(u: Dictionary, delta: float) -> void:
	if u.job.kind != "idle":
		if u.job.get("automatic", false) and u.job.kind == "repair" and float(u.work) <= 0 and int(resources(u.owner).get("ore", 0)) < int(cfg.construction.repairOrePerCycle):
			u.job = {"kind": "idle"}; u.route.clear()
		else: return
	if not u.orders.is_empty() or not u.route.is_empty() or not players[u.owner].alive: return
	u.auto_work_remaining = maxf(0, float(u.get("auto_work_remaining", 0)) - delta)
	if u.auto_work_remaining > 0: return
	u.auto_work_remaining = float(cfg.construction.idleEngineerSearchIntervalSeconds)
	var candidates: Array = []
	for s in structures.values():
		if s.owner != u.owner or float(s.hp) >= float(cfg.structures[s.kind].health): continue
		if s.built and int(resources(u.owner).get("ore", 0)) < int(cfg.construction.repairOrePerCycle): continue
		var reach := float(cfg.construction.idleEngineerSearchRangeTiles) + float(cfg.structures[s.kind].footprintRadiusTiles)
		var distance: float = u.pos.distance_squared_to(entity_position(s))
		if distance <= reach * reach: candidates.append({"structure": s, "distance": distance})
	candidates.sort_custom(func(a, b):
		if a.structure.built != b.structure.built: return not a.structure.built
		return int(a.structure.id) < int(b.structure.id) if a.distance == b.distance else a.distance < b.distance)
	for candidate in candidates:
		var s: Dictionary = candidate.structure
		var positions := HexGrid.disk(s.cell, int(cfg.structures[s.kind].footprintRadiusTiles) + 1)
		positions.sort_custom(func(a, b): return u.pos.distance_squared_to(HexGrid.world(a)) < u.pos.distance_squared_to(HexGrid.world(b)))
		for cell in positions:
			if cell in footprint(s) or blocked(cell): continue
			var path := _route_path(u, nearest_free(HexGrid.cell(u.pos)), cell)
			if path.is_empty(): continue
			u.job = {"kind": "repair" if s.built else "build", "target": s.id, "automatic": true}
			u.target = 0; u.work = 0
			RouteNavigation.assign(self, u, path)
			return

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
			if u.job.get("automatic", false): u.job = {"kind": "idle"}
			else: move_to(u, _work_position(s, u.pos))
		return
	if not s.started:
		var wait_for_units := false
		for cell in footprint(s):
			if blocked(cell, id): return
			for other in units.values():
				if int(other.vehicle) != 0: continue
				if HexGrid.cell(other.pos) != cell: continue
				wait_for_units = true
				# Let active traffic finish its orders. Only idle friendly bodies
				# may be asked to clear a site; occupancy never cancels paid work.
				if other.owner != u.owner or other.job.kind != "idle" or not other.orders.is_empty(): continue
				var clear_position := _work_position(s, other.pos)
				if clear_position == other.pos: continue
				other.job = {"kind": "move"}; other.home = clear_position; other.target = 0
				move_to(other, clear_position)
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
		for id in structure_cells.get(c, []):
			if structures.has(id): return "A structure or blueprint occupies this site"
	if kind == "extractor" and tiles[cell].resource == "": return "An Extractor requires a resource patch"
	for resource in cfg.structures[kind].cost:
		if int(resources(owner).get(resource, 0)) < int(cfg.structures[kind].cost[resource]): return "Not enough %s" % resource.capitalize()
	return ""

func _production(s: Dictionary, delta: float) -> void:
	if not s.built: return
	if float(s.get("configuration_remaining", 0)) > 0: s.configuration_remaining = maxf(0, float(s.configuration_remaining) - delta)
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
		if u.owner < 0 and u.kind == kind: total += 1
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

func electrical_structure(kind: String) -> bool:
	var d: Dictionary = cfg.structures[kind]
	return kind == "relay" or int(d.powerDemand) > 0 or int(d.powerCapacity) > 0

func electrical_reach(kind: String) -> int:
	var d: Dictionary = cfg.structures[kind]
	return int(d.footprintRadiusTiles) + int(d.electricalRangeBeyondFootprintTiles)

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
		if electrical_structure(s.kind): pending.append(s.id)
		else: s.powered = true
	var signature: Array = []
	for id in pending:
		var s: Dictionary = structures[id]
		signature.append([id, s.owner, s.cell, electrical_reach(s.kind)])
	if signature != _power_signature:
		_power_signature = signature; _power_groups.clear()
		while not pending.is_empty():
			var group: Array = [pending.pop_front()]
			var index := 0
			while index < group.size():
				var a: Dictionary = structures[group[index]]
				var reach_a := electrical_reach(a.kind)
				for other in pending.duplicate():
					var b: Dictionary = structures[other]
					var reach_b := electrical_reach(b.kind)
					if a.owner == b.owner and HexGrid.distance(a.cell, b.cell) <= reach_a + reach_b:
						pending.erase(other)
						group.append(other)
				index += 1
			_power_groups.append(group)
	for group in _power_groups:
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
			if structures[id].kind == "relay":
				structures[id].powered = true; structures[id].blackout = false; structures[id].brownout = false

func _enemy_entities(owner: int) -> Array:
	if not _opponents.has(owner):
		var enemies: Array = []
		for e in units.values() + structures.values():
			if e.owner != owner: enemies.append(e)
		_opponents[owner] = enemies
	return _opponents[owner]

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
		var distance_squared := distance * distance
		for candidate in _enemy_entities(int(attacker.owner)):
			if candidate.owner == attacker.owner: continue
			if int(candidate.get("vehicle", 0)) != 0: continue
			var candidate_position := entity_position(candidate)
			var d_squared := origin.distance_squared_to(candidate_position)
			if d_squared >= distance_squared: continue
			if defensive and attacker.home.distance_to(entity_position(candidate)) > float(cfg.combat.defensiveLeashTiles): continue
			if not TargetRules.targetable(self, attacker, candidate): continue
			distance_squared = d_squared; target = candidate
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
			if not attacker.get("buried", false):
				if attacker.owner < 0: LightlessTactics.approach(self, attacker, target, weapon)
				elif attacker.route.is_empty(): move_to(attacker, position)
		return false
	var line := HexGrid.line(HexGrid.cell(origin), HexGrid.cell(position))
	for i in range(1, maxi(1, line.size() - 1)):
		if blocks_sight(line[i]):
			if attacker.has("pos") and attacker.owner < 0 and not attacker.get("buried", false): LightlessTactics.approach(self, attacker, target, weapon)
			return false
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
	_opponents.clear()
	emit_feedback("destroy", entity_position(e), {"target": e.id, "owner": e.owner, "biological": e.owner < 0 or (e.has("pos") and bool(cfg.units[e.kind].get("biological", false)))}, feedback_audience(e))
	if e.has("cell"):
		for owner in structure_memory:
			if e.owner == owner or structure_visible(owner, e): structure_memory[owner].erase(int(e.id))
		structures.erase(e.id)
		if e.kind == "anchor": eliminate(int(e.owner))
		if e.kind == "medusa":
			medusa_dead = true
			corpse = e.cell
			lightless_chyme += int(cfg.lightless.postMedusaChymeGrant)
			tiles[e.cell].resource = "nacre"
			tiles[e.cell].amount = 2147483647
			for u in units.values():
				if u.owner == -1 and not u.kind in ["mother", "father"]: u.stance = "attack"; u.job = {"kind": "idle"}; u.target = 0; u.route.clear()
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
	for id in structure_cells.get(cell, []):
		var s: Dictionary = structures.get(id, {})
		if s.is_empty(): continue
		if not s.started: continue
		if s.kind == "wall" or (s.kind == "gate" and not s.open): return true
	return false

func _refresh_sight_topology() -> void:
	var blockers: Dictionary = {}
	for cell in tiles:
		if tiles[cell].cliff: blockers[cell] = true
	for s in structures.values():
		if s.started and (s.kind == "wall" or (s.kind == "gate" and not s.open)):
			for cell in footprint(s): blockers[cell] = true
	if blockers != _sight_blockers: _sight_areas.clear(); _sight_unions.clear()
	_sight_blockers = blockers; _sight_topology_valid = true

func _cached_sight(cell: Vector2i, reach: int, direction: Vector2 = Vector2.ZERO, degrees: float = 360) -> Dictionary:
	if not _sight_topology_valid: _refresh_sight_topology()
	var key: Variant = Vector3i(cell.x, cell.y, reach) if direction == Vector2.ZERO else [cell, reach, direction, degrees]
	if not _sight_areas.has(key):
		# Bound memory when units explore many distinct cells/headings.
		if _sight_areas.size() >= 1024: _sight_areas.clear()
		_sight_areas[key] = flood(cell, reach, direction, degrees)
	return _sight_areas[key]

func _sight_union(sources: Dictionary) -> Dictionary:
	for cached in _sight_unions:
		if cached.sources == sources: return cached.area
	# Descending remaining range visits each traversable cell at its best range.
	# This is the exact union of the individual floods, including opaque sources.
	var buckets: Array = []
	var best: Dictionary = {}
	var reached: Dictionary = {}
	for cell in sources:
		var reach: int = sources[cell]
		while buckets.size() <= reach: buckets.append([])
		buckets[reach].append(cell); best[cell] = reach; reached[cell] = true
	for reach in range(buckets.size() - 1, 0, -1):
		for cell in buckets[reach]:
			if int(best[cell]) != reach: continue
			for direction in HexGrid.DIRECTIONS:
				var other: Vector2i = cell + direction
				if not tiles.has(other): continue
				reached[other] = true
				if _sight_blockers.has(other) or int(best.get(other, -1)) >= reach - 1: continue
				best[other] = reach - 1; buckets[reach - 1].append(other)
	if _sight_unions.size() >= players.size() * 2: _sight_unions.pop_front()
	_sight_unions.append({"sources": sources.duplicate(), "area": reached})
	return reached

func _sight_source(sources: Dictionary, cell: Vector2i, reach: int) -> void:
	sources[cell] = maxi(int(sources.get(cell, 0)), reach)

func flood(start: Vector2i, range_value: int, cone_direction: Vector2 = Vector2.ZERO, cone_degrees: float = 360) -> Dictionary:
	var reached: Dictionary = {start: true}
	var frontier: Array = [start]
	var distances: Dictionary = {start: 0}
	var cursor := 0
	while cursor < frontier.size():
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		if int(distances[cell]) >= range_value or (cell != start and blocks_sight(cell)): continue
		for direction in HexGrid.DIRECTIONS:
			var other: Vector2i = cell + direction
			if cone_direction != Vector2.ZERO:
				var offset := HexGrid.world(other) - HexGrid.world(start)
				if offset.normalized().dot(cone_direction) < cos(deg_to_rad(cone_degrees * 0.5)): continue
			if tiles.has(other) and not reached.has(other): reached[other] = true; distances[other] = int(distances[cell]) + 1; frontier.append(other)
	return reached

func structure_vision_range(s: Dictionary) -> int:
	var d: Dictionary = cfg.structures[s.kind]
	if d.has("unpoweredVisionRangeBeyondFootprintTiles") and (not s.powered or not s.enabled or s.blackout): return int(d.unpoweredVisionRangeBeyondFootprintTiles)
	return int(d.visionRangeBeyondFootprintTiles)

func update_visibility() -> void:
	_refresh_sight_topology()
	var old_light: Dictionary = {}
	for area in illuminated.values(): old_light.merge(area, true)
	# Preserve the latest visible state before replacing the previous sight map.
	# Otherwise damage since the last refresh would be lost as vision recedes.
	_remember_structures()
	var sight_sources: Dictionary = {}
	var light_sources: Dictionary = {}
	for owner in players:
		sight_sources[owner] = {}; light_sources[owner] = {}
		visible[owner] = {}
		illuminated[owner] = {}
		if not known.has(owner): known[owner] = {}
	for s in structures.values():
		if not s.built or s.owner < 0: continue
		var d: Dictionary = cfg.structures[s.kind]
		for c in footprint(s):
			_sight_source(sight_sources[s.owner], c, structure_vision_range(s))
			if int(d.illuminationRangeBeyondFootprintTiles) > 0 and s.powered and s.enabled and not s.blackout:
				var reach := int(d.illuminationRangeBeyondFootprintTiles)
				if s.brownout: reach = floori(reach * float(cfg.power.brownout.illuminationRangeMultiplier))
				_sight_source(light_sources[s.owner], c, reach)
	for u in units.values():
		if u.owner < 0 or u.vehicle != 0: continue
		var d: Dictionary = cfg.units[u.kind]
		if d.has("driverSeats") and u.driver == 0: continue
		var c := HexGrid.cell(u.pos)
		_sight_source(sight_sources[u.owner], c, int(d.visionRangeTiles))
		if int(d.illuminationRangeTiles) > 0: _sight_source(light_sources[u.owner], c, int(d.illuminationRangeTiles))
		for illumination in [false, true]:
			var reach := int(d.get("forwardIlluminationRangeTiles" if illumination else "visionForwardRangeTiles", 0))
			if reach > 0:
				var direction := Vector2(-sin(float(u.heading)), -cos(float(u.heading)))
				var destination: Dictionary = illuminated[u.owner] if illumination else visible[u.owner]
				destination.merge(_cached_sight(c, reach, direction, float(d.forwardConeDegrees)), true)
	for owner in players:
		visible[owner].merge(_sight_union(sight_sources[owner]), true)
		illuminated[owner].merge(_sight_union(light_sources[owner]), true)
	RadarSystem.update(self)
	for owner in players: known[owner].merge(visible[owner], true)
	_remember_structures()
	var new_light: Dictionary = {}
	for area in illuminated.values(): new_light.merge(area, true)
	if old_light != new_light: _dark_clearance_neighborhoods.clear()
	for cell in old_light:
		if not new_light.has(cell) and point_ids.has(cell): dark_navigation.set_point_weight_scale(point_ids[cell], 1.0)
	for cell in new_light:
		if not old_light.has(cell) and point_ids.has(cell): dark_navigation.set_point_weight_scale(point_ids[cell], float(cfg.lightless.darkPathLightPenalty))

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
		if u.owner == owner: d.activity = activity(u)
		if u.owner != owner: d.erase("orders")
		d.pos = [u.pos.x, u.pos.y]
		d.home = [u.home.x, u.home.y]
		d.erase("route")
		exported_units.append(d)
	for s in observed_structures(owner):
		var d: Dictionary = s.duplicate(true)
		if s.owner == owner: d.activity = activity(s)
		d.cell = [s.cell.x, s.cell.y]
		exported_structures.append(d)
	var cells: Array = []
	for cell in known.get(owner, {}):
		cells.append([cell.x, cell.y, bool(visible[owner].has(cell)), is_lit(cell), float(gloom.get(cell, 0)), int(tiles[cell].amount), bool(tiles[cell].cliff), bool(tiles[cell].get("rubble", false)), str(tiles[cell].resource)])
	var exported_feedback: Array = []
	for event in feedback_for(owner):
		var copy: Dictionary = event.duplicate(true); copy.erase("audience")
		for key in ["at", "from", "to"]:
			if copy.has(key): copy[key] = [copy[key].x, copy[key].y]
		exported_feedback.append(copy)
	return {"mission": mission.duplicate(true), "feedback": exported_feedback, "feedback_serial": feedback_serial, "contacts": detected.get(owner, {}).keys().map(func(cell): return [cell.x, cell.y]), "tick": tick, "time_seconds": time_seconds, "units": exported_units, "structures": exported_structures, "players": players, "cells": cells, "ended": ended, "result": result, "medusa_dead": medusa_dead, "speed": speed, "paused": paused}

func apply_snapshot(data: Dictionary, owner: int) -> void:
	_opponents.clear(); _sight_areas.clear(); _sight_unions.clear(); _sight_topology_valid = false
	corpse = null
	mission = data.get("mission", {}).duplicate(true)
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
	structure_memory.clear(); structure_memory[owner] = {}
	players.clear()
	for id in data.players: players[int(id)] = data.players[id]
	for d in data.units:
		d.pos = Vector2(float(d.pos[0]), float(d.pos[1]))
		d.home = Vector2(float(d.home[0]), float(d.home[1]))
		d.route = []
		d.orders = d.get("orders", [])
		units[int(d.id)] = d
	for d in data.structures:
		d.cell = Vector2i(int(d.cell[0]), int(d.cell[1]))
		if d.get("remembered", false): structure_memory[owner][int(d.id)] = d
		else: structures[int(d.id)] = d
	_index_structures()
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
			if c.size() > 8:
				tiles[cell].resource = str(c[8])
				if tiles[cell].resource == "nacre": corpse = cell
	ended = bool(data.ended)
	result = str(data.result)
	medusa_dead = bool(data.medusa_dead)
	paused = bool(data.get("paused", false))
	speed = float(data.get("speed", 1))


class MovementGraph:
	extends AStar2D
	var query_world: WeakRef
	var query_unit: Dictionary = {}
	var edge_cache: Dictionary = {}

	func _filter_neighbor(from_id: int, to_id: int) -> bool:
		var world = query_world.get_ref() if query_world != null else null
		if world == null: return false
		# Adjacent free hex centers have at least this much corner clearance.
		# Infantry need no extra graph filtering; larger bodies sometimes do.
		var radius := RouteNavigation.clearance(world, query_unit)
		if radius < HexGrid.RADIUS * 0.5: return false
		var key := "%d:%s:%d:%d" % [query_unit.owner, radius, mini(from_id, to_id), maxi(from_id, to_id)]
		if not edge_cache.has(key):
			edge_cache[key] = not RouteNavigation.clear_segment(world, query_unit, get_point_position(from_id), get_point_position(to_id), true)
		return bool(edge_cache[key])

class RouteNavigation:
	static var hex_polygons: Dictionary = {}
	# Hexes choose topology; swept body clearance and string-pulling choose actual
	# movement. This layer is shared by manual orders, work, combat and retreats.
	static func clearance(world: RefCounted, unit: Dictionary) -> float:
		return float(world.cfg.units[unit.kind].collisionRadiusTiles) + float(world.cfg.movement.pathfinding.clearancePaddingTiles)

	static func hex_distance_squared(a: Vector2, b: Vector2, cell: Vector2i) -> float:
		if not hex_polygons.has(cell):
			var points := PackedVector2Array()
			var center := HexGrid.world(cell)
			for i in range(6): points.append(center + Vector2.from_angle(deg_to_rad(30.0 + i * 60.0)) * HexGrid.RADIUS)
			hex_polygons[cell] = points
		var polygon: PackedVector2Array = hex_polygons[cell]
		if Geometry2D.is_point_in_polygon(a, polygon) or Geometry2D.is_point_in_polygon(b, polygon): return 0.0
		var nearest := INF
		for i in range(6):
			var c: Vector2 = polygon[i]
			var d: Vector2 = polygon[(i + 1) % 6]
			var points := Geometry2D.get_closest_points_between_segments(a, b, c, d)
			nearest = minf(nearest, points[0].distance_squared_to(points[1]))
			if nearest < 0.000000000001: return 0.0
		return nearest

	static func clear_segment(world: RefCounted, unit: Dictionary, a: Vector2, b: Vector2, gates: bool = false, avoid_light: bool = false) -> bool:
		var radius := clearance(world, unit)
		var start := HexGrid.cell(a); var finish := HexGrid.cell(b)
		if start == finish and radius < HexGrid.RADIUS and not avoid_light and world.open_movement_cell(start): return true
		var candidates: Dictionary = {}
		# A conservative neighborhood covers offset endpoints and wide bodies;
		# the exact capsule/hex test below rejects only actual intersections.
		var neighborhood := 1 if start == finish and radius < HexGrid.RADIUS else ceili(radius + HexGrid.RADIUS * 2)
		for cell in HexGrid.line(start, finish):
			for nearby in world.clearance_obstacles(cell, neighborhood, avoid_light): candidates[nearby] = true
		for cell in candidates:
			var solid: bool = world.blocked(cell)
			var lit: bool = avoid_light and world.is_lit(cell)
			if not solid and not lit: continue
			var center := HexGrid.world(cell)
			if center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center, a, b)) > pow(radius + HexGrid.RADIUS, 2): continue
			if lit and hex_distance_squared(a, b, cell) < 0.000001: return false
			if not solid: continue
			var distance := hex_distance_squared(a, b, cell)
			if distance >= radius * radius - 0.000001: continue
			var admitted := false
			if gates:
				for gate in world.structures.values():
					if gate.kind == "gate" and gate.built and gate.owner == unit.owner and not gate.locked and cell in world.footprint(gate): admitted = true; break
			if admitted: continue
			# Steering or a newly placed obstacle may leave a body too close to an
			# edge. Permit movement out of that overlap, never deeper through it.
			var initial := hex_distance_squared(a, a, cell)
			if initial > 0.000001 and distance >= initial - 0.000001 and hex_distance_squared(b, b, cell) > initial + 0.000001: continue
			return false
		return true

	static func assign(world: RefCounted, unit: Dictionary, path: PackedVector2Array) -> void:
		unit.route = []
		if path.is_empty(): return
		var dark: bool = unit.owner < 0 and unit.job.kind != "attack"
		if path.size() > 1 and HexGrid.cell(path[0]) == HexGrid.cell(unit.pos) and clear_segment(world, unit, unit.pos, path[1], true, dark): path.remove_at(0)
		var pins: Dictionary = {}
		for gate in world.structures.values():
			if gate.kind != "gate" or not gate.started: continue
			for i in range(path.size()):
				if HexGrid.cell(path[i]) != gate.cell: continue
				for index in range(maxi(0, i - 1), mini(path.size(), i + 2)):
					if index == 0 and HexGrid.cell(path[index]) == HexGrid.cell(unit.pos): continue
					pins[index] = true
		var origin: Vector2 = unit.pos
		var index := 0
		while index < path.size():
			var limit := index
			if world.cfg.movement.pathfinding.smoothingEnabled:
				limit = path.size() - 1
				for pin in range(index, path.size()):
					if pins.has(pin): limit = pin; break
			# A blocked distant shortcut is not evidence that every intervening
			# endpoint needs a separate sweep. Halving bounds retry work while
			# preserving the native route and mandatory gate waypoints.
			var chosen := limit
			while chosen > index and not clear_segment(world, unit, origin, path[chosen], true, dark):
				chosen = index + (chosen - index) / 2
			unit.route.append(path[chosen]); origin = path[chosen]; index = chosen + 1

class LightlessTactics:
	# Navigation and target decisions only; no renderer, input, or wall-clock state.
	static func known_anchor(world: RefCounted, position: Vector2) -> Dictionary:
		var result: Dictionary = {}
		var nearest := INF
		for structure in world.structures.values():
			if structure.owner < 0 or structure.kind != "anchor": continue
			var distance: float = position.distance_squared_to(world.entity_position(structure))
			if distance < nearest: nearest = distance; result = structure
		return result

	static func clear_shot(world: RefCounted, origin: Vector2, target: Vector2) -> bool:
		var line := HexGrid.line(HexGrid.cell(origin), HexGrid.cell(target))
		for i in range(1, maxi(1, line.size() - 1)):
			if world.blocks_sight(line[i]): return false
		return true

	static func prepare_attack(world: RefCounted, unit: Dictionary) -> void:
		var target: Dictionary = world.entity(int(unit.target))
		if target.is_empty() and unit.job.has("objective"):
			target = world.entity(int(unit.job.objective))
			if not target.is_empty(): unit.target = target.id; unit.route.clear(); unit.job.repath_remaining = 0.0
		if target.is_empty(): return
		var line := HexGrid.line(HexGrid.cell(unit.pos), HexGrid.cell(world.entity_position(target)))
		for i in range(1, maxi(1, line.size() - 1)):
			if not world.blocks_sight(line[i]): continue
			# Only discovered obstructions can become targets. The first blocker
			# is visible along this ray, but must also be within personal vision.
			if HexGrid.distance(HexGrid.cell(unit.pos), line[i]) > int(world.cfg.units[unit.kind].visionRangeTiles): return
			for structure in world.structures.values():
				if structure.owner < 0 or not structure.kind in ["wall", "gate"] or not line[i] in world.footprint(structure): continue
				if not unit.job.has("objective"): unit.job.objective = target.id
				unit.target = structure.id; unit.route.clear(); unit.job.repath_remaining = 0.0
				return
			return

	static func approach(world: RefCounted, unit: Dictionary, target: Dictionary, weapon: Dictionary) -> void:
		var center: Vector2 = world.entity_position(target)
		var radius := float(weapon.rangeTiles)
		if target.has("cell"): radius += int(world.cfg.structures[target.kind].footprintRadiusTiles) + float(world.cfg.combat.structureAimAllowanceTiles)
		if not unit.route.is_empty() and unit.route.back().distance_to(center) <= radius and clear_shot(world, unit.route.back(), center): return
		if float(unit.job.get("repath_remaining", 0)) > 0: return
		unit.route.clear()
		unit.job.repath_remaining = float(world.cfg.lightless.combatRepathSeconds)
		var start: Vector2i = world.nearest_free(HexGrid.cell(unit.pos))
		if not world.point_ids.has(start): return
		var candidates := HexGrid.disk(HexGrid.cell(center), ceili(radius) + 1)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i): return unit.pos.distance_squared_to(HexGrid.world(a)) < unit.pos.distance_squared_to(HexGrid.world(b)))
		for cell in candidates:
			var point := HexGrid.world(cell)
			if world.blocked(cell) or point.distance_to(center) > radius or not clear_shot(world, point, center): continue
			if not world.point_ids.has(cell): continue
			# Partial paths are not attack positions: accepting one recreates the
			# stationary crowd at an unreachable endpoint outside a base.
			var path: PackedVector2Array = world._route_path(unit, start, cell)
			if path.is_empty(): continue
			RouteNavigation.assign(world, unit, path)
			return

	static func retreat(world: RefCounted, unit: Dictionary) -> void:
		unit.job.repath_remaining = float(world.cfg.lightless.retreatRepathSeconds)
		var start: Vector2i = world.nearest_free(HexGrid.cell(unit.pos))
		if not world.point_ids.has(start): return
		var candidates: Array = world.gloom.keys()
		candidates.sort_custom(func(a: Vector2i, b: Vector2i): return unit.pos.distance_squared_to(HexGrid.world(a)) < unit.pos.distance_squared_to(HexGrid.world(b)))
		for cell in candidates:
			if world.blocked(cell) or world.is_lit(cell) or not world.point_ids.has(cell): continue
			var path: PackedVector2Array = world._route_path(unit, start, cell)
			if path.is_empty(): continue
			unit.route.clear()
			RouteNavigation.assign(world, unit, path)
			return

class TargetRules:
	extends RefCounted
	## Pure queries: no targeting, damage, UI, or renderer may invent its own visibility rule.
	## WorldState owns mutation. These helpers also work on host state before serialization.

	static func identifiable(world: RefCounted, target: Dictionary, owner: int) -> bool:
		if target.is_empty() or target.get("remembered", false): return false
		if int(target.get("vehicle", 0)) != 0: return false
		if target.owner == owner: return true
		if target.has("cell"): return world.structure_visible(owner, target)
		var cell := HexGrid.cell(world.entity_position(target))
		if not world.visible.get(owner, {}).has(cell): return false
		var rules: Dictionary = world.cfg.targeting.unitRules.get(target.kind, {})
		if rules.get("requiresIllumination", false) and not world.is_lit(cell): return false
		if target.get("buried", false) and not world.detected.get(owner, {}).has(cell): return false
		return true

	static func targetable(world: RefCounted, attacker: Dictionary, target: Dictionary) -> bool:
		if target.is_empty() or target.get("remembered", false) or int(target.get("vehicle", 0)) != 0: return false
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


class LightlessColony:
	extends RefCounted
	## Host-only colony economy. Paid queues and free timers share type capacity.
	static func cap(world: RefCounted, kind: String) -> int:
		var result := int(world.cfg.units[kind].basePopulationCap)
		for s in world.structures.values():
			if s.owner < 0 and s.kind == "womb" and s.built and s.get("unit_type", "") == kind: result += int(world.cfg.units[kind].wombPopulationIncrease)
		return result

	static func unlocked(world: RefCounted, source: Dictionary, kind: String) -> bool:
		if not world.cfg.units.has(kind) or not world.cfg.units[kind].has("manualSpawnSeconds"): return false
		if source.kind == "womb": return source.get("unit_type", "") == kind
		if source.kind != "medusa": return false
		if kind in ["scavenger", "mother", "father"]: return true
		for s in world.structures.values():
			if s.owner < 0 and s.kind == "womb" and s.built and s.get("unit_type", "") == kind: return true
		return false

	static func queue_spawn(world: RefCounted, source: Dictionary, kind: String) -> String:
		if source.is_empty() or not world.structures.has(source.get("id", 0)) or source.owner >= 0 or not source.built or not unlocked(world, source, kind): return "Spawn unavailable"
		if source.spawn_queue.size() >= int(world.cfg.lightless.manualQueueLimit): return "Spawn queue full"
		var cost := int(world.cfg.units[kind].manualSpawnCost.chyme)
		if world.lightless_chyme < cost: return "Not enough Chyme"
		world.lightless_chyme -= cost
		source.spawn_queue.append({"kind": kind, "progress": 0.0})
		return ""

	static func cancel_spawn(world: RefCounted, source: Dictionary, index: int) -> void:
		if not world.structures.has(source.get("id", 0)) or index < 0 or index >= source.get("spawn_queue", []).size(): return
		var job: Dictionary = source.spawn_queue[index]
		if float(job.progress) == 0: world.lightless_chyme += int(world.cfg.units[job.kind].manualSpawnCost.chyme)
		source.spawn_queue.remove_at(index)

	static func spawn(world: RefCounted, source: Dictionary, kind: String) -> bool:
		if world._population(kind) >= cap(world, kind): return false
		var cell: Vector2i = world.nearest_free(source.cell)
		if world.blocked(cell): return false
		var id: int = world.add_unit(kind, HexGrid.world(cell), -1)
		if world.medusa_dead and not kind in ["mother", "father"]: world.units[id].stance = "attack"
		return true

	static func update(world: RefCounted, delta: float) -> void:
		var sources: Array = []
		var medusa: Dictionary = {}
		var ids: Array = world.structures.keys(); ids.sort()
		for id in ids:
			var s: Dictionary = world.structures[id]
			if s.owner >= 0: continue
			if not s.built:
				if s.started:
					var duration := float(world.cfg.lightless.structureGestationSeconds)
					var health := float(world.cfg.structures[s.kind].health)
					s.hp = minf(health, float(s.hp) + (health - float(world.cfg.construction.startingHealth)) * delta / duration)
					if s.hp >= health: s.built = true
				continue
			if s.kind in ["medusa", "womb"]: sources.append(s)
			if s.kind == "medusa": medusa = s
		if not medusa.is_empty():
			world.lightless_income_time += delta
			var cycles := floori(world.lightless_income_time / float(world.cfg.lightless.medusaChymeCycleSeconds))
			world.lightless_income_time -= cycles * float(world.cfg.lightless.medusaChymeCycleSeconds)
			world.lightless_chyme += cycles * int(world.cfg.lightless.medusaChymePerCycle)
		# Resolve every ready manual order before any passive spawn, by source ID.
		for source in sources:
			if source.spawn_queue.is_empty(): continue
			var job: Dictionary = source.spawn_queue[0]
			if not unlocked(world, source, job.kind): continue
			var rate := float(world.cfg.lightless.postMedusaWombSpawnRateMultiplier) if world.medusa_dead and source.kind == "womb" else 1.0
			var duration := float(world.cfg.units[job.kind].manualSpawnSeconds)
			job.progress = minf(duration, float(job.progress) + delta * rate)
			if job.progress >= duration and spawn(world, source, job.kind): source.spawn_queue.pop_front()
		for source in sources:
			var kind := "scavenger" if source.kind == "medusa" else str(source.unit_type)
			var duration := float(world.cfg.lightless.medusaPassiveScavengerSeconds) if source.kind == "medusa" else float(world.cfg.units[kind].wombPassiveSpawnSeconds)
			var rate := float(world.cfg.lightless.postMedusaWombSpawnRateMultiplier) if world.medusa_dead and source.kind == "womb" else 1.0
			source.passive = minf(duration, float(source.passive) + delta * rate)
			if source.passive >= duration and spawn(world, source, kind): source.passive = 0.0
		world.lightless_expansion_time += delta
		world.lightless_brain_time += delta
		if world.lightless_brain_time >= float(world.cfg.lightless.brainDecisionIntervalSeconds):
			world.lightless_brain_time = fmod(world.lightless_brain_time, float(world.cfg.lightless.brainDecisionIntervalSeconds))
			develop(world, medusa)

	static func develop(world: RefCounted, medusa: Dictionary) -> void:
		var mother: Dictionary = {}
		for u in world.units.values():
			if u.owner < 0 and u.kind == "mother" and u.job.kind == "idle": mother = u; break
		# A surviving blueprint keeps its paid cost when its first Mother dies.
		if not mother.is_empty():
			for s in world.structures.values():
				if s.owner >= 0 or s.kind != "womb" or s.started: continue
				var assigned := false
				for u in world.units.values():
					if u.job.kind == "grow" and int(u.job.target) == int(s.id): assigned = true; break
				if not assigned and route_mother(world, mother, s): return
		if medusa.is_empty(): return
		var next_type := ""
		for kind in world.cfg.lightless.cpuWombPriority:
			var exists := false
			for s in world.structures.values():
				if s.owner < 0 and s.kind == "womb" and s.get("unit_type", "") == kind: exists = true; break
			if not exists: next_type = kind; break
		var reserve := int(world.cfg.lightless.cpuMinimumChymeReserve)
		var cost := int(world.cfg.structures.womb.cost.chyme)
		if next_type != "" and not mother.is_empty() and world.lightless_expansion_time >= float(world.cfg.lightless.cpuExpansionIntervalSeconds) and world.lightless_chyme >= reserve + cost:
			var cells: Array = world.gloom.keys()
			cells.sort_custom(func(a, b):
				var da: int = HexGrid.distance(a, medusa.cell); var db: int = HexGrid.distance(b, medusa.cell)
				return da < db if da != db else a.x < b.x if a.x != b.x else a.y < b.y)
			for cell in cells:
				if world.blocked(cell) or world.is_lit(cell) or world.tiles[cell].resource != "" or not world.structure_cells.get(cell, []).is_empty(): continue
				var path: PackedVector2Array = world._route_path(mother, world.nearest_free(HexGrid.cell(mother.pos)), cell)
				if path.is_empty() or HexGrid.cell(path[path.size() - 1]) != cell: continue
				world.lightless_chyme -= cost
				var id: int = world.add_structure("womb", cell, -1, false)
				world.structures[id].unit_type = next_type
				route_mother(world, mother, world.structures[id])
				world.lightless_expansion_time = 0.0
				return
		var pending_mothers := 0
		for s in world.structures.values():
			for job in s.get("spawn_queue", []):
				if job.kind == "mother": pending_mothers += 1
		if next_type != "" and world._population("mother") + pending_mothers < int(world.cfg.lightless.cpuDesiredMothers) and world.lightless_chyme >= reserve + int(world.cfg.units.mother.manualSpawnCost.chyme): queue_spawn(world, medusa, "mother")

	static func route_mother(world: RefCounted, mother: Dictionary, site: Dictionary) -> bool:
		var path: PackedVector2Array = world._route_path(mother, world.nearest_free(HexGrid.cell(mother.pos)), site.cell)
		if path.is_empty() or HexGrid.cell(path[path.size() - 1]) != site.cell: return false
		mother.job = {"kind": "grow", "target": site.id}
		RouteNavigation.assign(world, mother, path)
		return true

	static func mother_step(world: RefCounted, mother: Dictionary, delta: float) -> void:
		if mother.job.kind != "grow": return
		var site: Dictionary = world.structures.get(int(mother.job.target), {})
		if site.is_empty() or site.started: mother.job = {"kind": "idle"}; mother.route.clear(); return
		if mother.pos.distance_to(HexGrid.world(site.cell)) > float(world.cfg.movement.routeOrders.arrivalRadiusTiles):
			if mother.route.is_empty(): route_mother(world, mother, site)
			world._move(mother, delta); return
		for other in world.units.values():
			if other.id != mother.id and HexGrid.cell(other.pos) == site.cell: return
		world.units.erase(mother.id)
		site.started = true
		world._rebuild_navigation()

class RadarSystem:
	extends RefCounted
	## Radar exposes occupied tiles only. It never reveals terrain, unit IDs, or counts.
	## Call after vision/power/crew changes; snapshot contacts separately from entities.

	static func update(world: RefCounted) -> void:
		world.detected.clear()
		for owner in world.players:
			var sources: Array[Vector3i] = []
			for sensor in world.structures.values():
				if sensor.owner != owner or not sensor.built or not sensor.enabled or not sensor.powered: continue
				var definition: Dictionary = world.cfg.structures[sensor.kind]
				var reach := int(definition.get("detectionRangeBeyondFootprintTiles", 0))
				if reach <= 0: continue
				sources.append(Vector3i(sensor.cell.x, sensor.cell.y, reach + int(definition.footprintRadiusTiles)))
			for sensor in world.units.values():
				if sensor.owner != owner or int(sensor.vehicle) != 0: continue
				var definition: Dictionary = world.cfg.units[sensor.kind]
				if definition.has("driverSeats") and int(sensor.driver) == 0: continue
				var reach := int(definition.get("detectionRangeTiles", 0))
				if reach > 0:
					var cell := HexGrid.cell(sensor.pos)
					sources.append(Vector3i(cell.x, cell.y, reach))
			if not world._radar_coverage.has(owner) or world._radar_coverage[owner].sources != sources:
				var area: Dictionary = {}
				for source in sources:
					for cell in HexGrid.disk(Vector2i(source.x, source.y), source.z): area[cell] = true
				world._radar_coverage[owner] = {"sources": sources, "area": area}
			var coverage: Dictionary = world._radar_coverage[owner].area
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
				if RouteNavigation.hex_distance_squared(unit.pos, unit.pos, gate.cell) < pow(RouteNavigation.clearance(world, unit), 2): occupied = true; break
				if unit.owner != gate.owner: continue
				# Smoothing can make the next waypoint distant. Preserve the old
				# two-cell traffic window rather than holding doors for remote units.
				if HexGrid.distance(HexGrid.cell(unit.pos), gate.cell) > 2: continue
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
			unit.job.repath = float(rules.repathSeconds)
