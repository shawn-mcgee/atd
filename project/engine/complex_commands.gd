extends RefCounted
## Coordinated transport/gathering orders. Direct orders revoke membership.
var groups: Array[Dictionary] = []
var next_id := 1
var foot := preload("res://engine/foot_expeditions.gd").new()
var patrols := preload("res://engine/expedition_patrol.gd").new()
var exploration := preload("res://engine/exploration_expeditions.gd").new()
var scouts := preload("res://engine/expedition_scouts.gd").new()
const MAINTENANCE_RANGE := 14.0
const DRIVER_RANK = SimUnit.DRIVER_RANK
const MINING_DRIVER_RANK = SimUnit.MINING_DRIVER_RANK

func alive(unit) -> bool:
	return SimEntity.valid(unit) and unit.hp > 0

func interrupt(unit: SimUnit) -> void:
	patrols.states.erase(unit.simulation_id)
	exploration.interrupt(unit)
	scouts.interrupt(unit)
	foot.interrupt(unit)
	for group in groups.duplicate():
		if group.vehicle == unit:
			finish(group)
		elif group.members.has(unit):
			group.members.erase(unit); unit.complex_id = 0

func finish(group: Dictionary) -> void:
	for unit in group.members + [group.vehicle]:
		if not SimEntity.valid(unit): continue
		unit.complex_id = 0
		if unit.order.begins_with("convoy_"):
			unit.order = "idle"; unit.path.clear(); unit.target = null; unit.goal = unit.position
	groups.erase(group)

func start(game, selection: Array, resource: Dictionary = {}, structure: SimStructure = null, destination: Vector3 = Vector3.ZERO) -> bool:
	var vehicles: Array = []
	var members: Array = []
	for unit in selection:
		if not unit is SimUnit or not alive(unit): continue
		if unit.kind == "jeep": vehicles.append(unit)
		elif not unit.is_vehicle() and unit.aboard == null: members.append(unit)
	if vehicles.size() != 1: return false
	var vehicle: SimUnit = vehicles[0]
	for unit in vehicle.passengers + ([vehicle.driver] if vehicle.has_driver() else []):
		if not members.has(unit): members.append(unit)
	if members.is_empty(): return false
	var workers := 0
	for unit in members:
		if unit.kind == "engineer": workers += 1
	if not resource.is_empty() and (workers == 0 or members.size() < 2):
		game.notify("Expedition needs an engineer and a separate driver"); return true
	for unit in members + [vehicle]: interrupt(unit)
	var mode := "gather" if not resource.is_empty() else "structure" if structure != null else "travel"
	var point: Vector3 = resource.position if mode == "gather" else structure.position if mode == "structure" else destination
	var group := {"id": next_id, "vehicle": vehicle, "members": members, "resource": resource, "mode": mode, "structure": structure, "destination": point,
		"maintenance": structure != null and needs_work(game, structure), "phase": "assemble", "leg": "outbound", "clock": 0.0, "driver": null, "riders": [], "receiver": null}
	next_id += 1
	for unit in members + [vehicle]: unit.complex_id = group.id
	groups.append(group); assemble(game, group, "outbound", true)
	game.notify("Coordinated %s / boarding crew, escorts follow / direct orders detach units" % mode)
	return true

func expedition_roster(selection: Array) -> Dictionary:
	var vehicles: Array = []
	var scout_vehicles: Array = []
	var members: Array = []
	for unit in selection:
		if not unit is SimUnit or not alive(unit): continue
		if unit.kind == "jeep": vehicles.append(unit)
		elif unit.kind == "scout": scout_vehicles.append(unit)
		elif not unit.is_vehicle() and unit.aboard == null: members.append(unit)
	for vehicle in vehicles + scout_vehicles:
		for unit in vehicle.passengers + ([vehicle.driver] if vehicle.has_driver() else []):
			if alive(unit) and not members.has(unit): members.append(unit)
	return {"vehicles": vehicles, "scouts": scout_vehicles, "members": members}

func expedition_available(selection: Array) -> bool:
	return exploration.available(expedition_roster(selection))

func expedition_tasks() -> Array:
	return groups.filter(func(group): return group.mode == "gather") + foot.groups + exploration.groups + scouts.groups

func task_for_member(unit: SimUnit) -> Dictionary:
	for group in expedition_tasks():
		if group.id != unit.complex_id: continue
		if not group.has("owners"): return group
		# A perimeter scout reinforces one of its active mining convoys.
		var owners: Array = group.owners.filter(func(owner): return groups.has(owner) or foot.groups.has(owner))
		owners.sort_custom(func(a, b): return a.members.size() < b.members.size())
		if not owners.is_empty(): return owners[0]
	return {}

func join_member(game, selection: Array, member: SimUnit) -> bool:
	if not is_expedition(member): return false
	var group := task_for_member(member)
	if group.is_empty(): return false
	return join_expedition(game, selection, group, member)

func join_resource(game, selection: Array, resource: Dictionary) -> bool:
	if resource.is_empty() or not resource.discovered or resource.remaining <= 0: return false
	var smallest: Dictionary = {}
	var anchor: SimUnit
	var count := 2147483647
	for group in groups + foot.groups:
		if group.get("mode", "gather") != "gather" or group.resource != resource: continue
		var members: Array = group.members.filter(func(unit): return alive(unit))
		if members.is_empty(): continue
		var candidate: SimUnit = group.get("vehicle", members[0])
		if not alive(candidate): continue
		var size := expedition_selection([candidate]).size()
		if size < count: smallest = group; anchor = candidate; count = size
	if smallest.is_empty(): return false
	return join_expedition(game, selection, smallest, anchor)

func join_expedition(game, selection: Array, group: Dictionary, anchor: SimUnit) -> bool:
	var existing := expedition_selection([anchor])
	var roster := expedition_roster(selection)
	# A vehicle takes its crew, including a pilot still walking to its seat.
	for vehicle in roster.vehicles + roster.scouts:
		var source := task_for_member(vehicle)
		if source.has("seats"):
			for unit in source.seats:
				if source.seats[unit] == vehicle and alive(unit) and not roster.members.has(unit): roster.members.append(unit)
		elif source.get("vehicle") == vehicle and alive(source.get("driver")) and not roster.members.has(source.driver):
			roster.members.append(source.driver)
		for support in scouts.groups:
			if support.vehicle == vehicle and alive(support.driver) and not roster.members.has(support.driver): roster.members.append(support.driver)
	var additions: Array = []
	for unit in roster.members + roster.vehicles + roster.scouts:
		if not existing.has(unit) and not additions.has(unit): additions.append(unit)
	if additions.is_empty(): return true
	var combined: Array = existing + additions
	var exploring := group.has("seats")
	var combined_roster := expedition_roster(combined)
	if (exploring and not exploration.available(combined_roster)) or (not exploring and not mining_available(combined)):
		game.notify("Cannot join / each vehicle needs a driver and mining needs separate working engineers"); return true
	if not exploring and additions.any(func(unit): return unit.is_vehicle()):
		# Extra haulers need their own work loops. Link the resulting tasks so the
		# whole selected reinforcement stays in this expedition for later joins.
		if start_expedition(game, combined, group.resource):
			var ids: Dictionary = {}
			for unit in combined: ids[unit.complex_id] = true
			var expedition_id := next_id; next_id += 1
			for task in expedition_tasks():
				if ids.has(task.id): task.expedition_id = expedition_id
		return true
	for unit in additions:
		interrupt(unit)
		if unit.aboard != null: unit.aboard.disembark(unit, game.free_spawn(unit.aboard.position))
		unit.complex_id = group.id; unit.path.clear(); unit.target = null; unit.goal = unit.position; unit.work_clock = 0
		if unit.is_vehicle(): group.vehicles.append(unit)
		else: group.members.append(unit)
		unit.order = "convoy_explore" if exploring else "convoy_join"
	if exploring:
		exploration.assign_seats(game, group)
	elif group.get("phase") == "assemble" and group.has("vehicle"):
		assemble(game, group, group.leg)
	game.notify("Joined expedition / %d units added" % additions.size())
	return true

func mining_available(selection: Array) -> bool:
	var roster := expedition_roster(selection)
	var engineers := 0
	for unit in roster.members:
		if unit.kind == "engineer": engineers += 1
	return engineers >= maxi(1, roster.vehicles.size()) and roster.members.size() >= maxi(1, roster.vehicles.size()) + roster.vehicles.size() + roster.scouts.size()

func start_expedition(game, selection: Array, resource: Dictionary = {}, destination: Vector3 = Vector3.INF) -> bool:
	var roster := expedition_roster(selection)
	if resource.is_empty():
		if not destination.is_finite(): return false
		return exploration.start(game, roster, destination)
	if not resource.get("discovered", false) or resource.get("remaining", 0) <= 0:
		game.notify("Choose a scanned resource patch with resources remaining"); return false
	if not mining_available(selection):
		game.notify("Mining needs engineers / each vehicle also needs a separate driver"); return false
	if not roster.scouts.is_empty(): return scouts.start_mining(game, roster, resource)
	if roster.vehicles.is_empty(): return foot.start(game, roster.members, resource)
	if roster.vehicles.size() == 1: return start(game, selection, resource)
	var pool: Array = roster.members.duplicate()
	var assignments: Array[Array] = []
	# Reserve working engineers before pilots so the driver preference cannot consume miners.
	for vehicle in roster.vehicles: assignments.append([vehicle])
	for assigned in assignments:
		for unit in pool:
			if unit.kind == "engineer": assigned.append(unit); pool.erase(unit); break
	pool.sort_custom(func(a, b): return MINING_DRIVER_RANK[a.kind] < MINING_DRIVER_RANK[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
	for assigned in assignments: assigned.insert(1, pool.pop_front())
	pool.sort_custom(func(a, b):
		var ranks := {"engineer": 0, "marine": 1, "flamer": 2}
		return ranks[a.kind] < ranks[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
	var index := 0
	for unit in pool:
		assignments[index % assignments.size()].append(unit); index += 1
	for unit in roster.members + roster.vehicles: interrupt(unit)
	for unit in roster.members:
		if unit.aboard != null: unit.aboard.disembark(unit, game.free_spawn(unit.aboard.position))
	for assigned in assignments: start(game, assigned, resource)
	game.notify("Expedition / %d convoys / each crew gathers and returns independently" % assignments.size())
	return true

func issue(game, unit: SimUnit, order: String, point: Vector3, target: SimEntity = null) -> void:
	unit.order = "convoy_" + order; unit.target = target
	if unit.goal.distance_to(point) > 1.0 or not unit.moving(): unit.travel(point, game.navigation)

func assemble(game, group: Dictionary, leg: String, assign_seats: bool = false) -> void:
	var vehicle: SimUnit = group.vehicle
	vehicle.path.clear(); vehicle.order = "convoy_boarding"
	# Assign priorities once when accepting a new task. Subsequent legs retain
	# the driver and boarded passengers, including throughout depot stops.
	for unit in group.members:
		if assign_seats and unit.aboard == vehicle and group.mode != "travel": vehicle.disembark(unit, game.free_spawn(vehicle.position))
	var ranked: Array = group.members.duplicate()
	var driver_ranks: Dictionary = MINING_DRIVER_RANK if group.mode == "gather" else DRIVER_RANK
	ranked.sort_custom(func(a, b):
		return driver_ranks[a.kind] < driver_ranks[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
	var drivers := ranked.duplicate()
	if group.mode == "gather" or (group.mode == "structure" and group.maintenance):
		for unit in drivers:
			if unit.kind == "engineer": drivers.erase(unit); break
	if not vehicle.has_driver() and drivers.is_empty():
		finish(group); game.notify("Work crew needs a driver and a separate working engineer"); return
	group.driver = vehicle.driver if vehicle.has_driver() else drivers[0]
	ranked.erase(group.driver)
	ranked.sort_custom(func(a, b):
		var ranks := {"engineer": 0, "marine": 1, "flamer": 2}
		return ranks[a.kind] < ranks[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
	group.riders = [group.driver]
	for unit in vehicle.passengers:
		if group.members.has(unit): group.riders.append(unit); ranked.erase(unit)
	for unit in ranked.slice(0, 4 - group.riders.size()): group.riders.append(unit)
	group.phase = "assemble"; group.leg = leg; group.clock = 0.0
	for unit in group.members:
		if unit.aboard == null: issue(game, unit, "board" if group.riders.has(unit) else "escort", vehicle.position, vehicle)

func tick(game, dt: float) -> void:
	patrols.prune(game.units)
	foot.tick(game, dt)
	for group in groups.duplicate():
		if not alive(group.vehicle): finish(group); continue
		for unit in group.members.duplicate():
			if not alive(unit): group.members.erase(unit)
		if group.members.is_empty():
			finish(group); continue
		if group.mode == "structure" and not alive(group.structure): finish(group); continue
		if not alive(group.driver) or not group.members.has(group.driver):
			assemble(game, group, group.leg)
			if not groups.has(group): continue
		if group.mode == "gather" and group.resource.remaining <= 0 and group.phase == "outbound":
			var next_patch: Dictionary = game.resource_fields.next_patch(game, group.resource)
			if not next_patch.is_empty(): group.resource = next_patch; group.destination = next_patch.position
		group.clock += dt
		var vehicle: SimUnit = group.vehicle
		if group.phase == "assemble":
			var ready := true
			for unit in group.riders:
				if not alive(unit) or not group.members.has(unit): continue
				if unit.aboard == vehicle: continue
				ready = false
				issue(game, unit, "board", vehicle.position, vehicle)
				if unit.position.distance_to(vehicle.position) < 3.8 and (unit == group.driver or vehicle.has_driver()): vehicle.board(unit)
			if ready:
				group.phase = group.leg
				if group.leg == "outbound": issue(game, vehicle, "outbound", group.destination)
				else: head_home(game, group)
		elif group.phase == "outbound":
			var reach := 4.0 if group.mode == "structure" else 0.8 if group.mode == "travel" else 3.0
			if vehicle.position.distance_to(group.destination) < reach:
				if group.mode == "travel":
					vehicle.path.clear()
					var arrived := true
					for unit in group.members:
						if unit.aboard == null and unit.position.distance_to(group.destination) > 6: arrived = false
					if arrived: finish(group); continue
				else:
					vehicle.path.clear(); vehicle.order = "convoy_gathering" if group.mode == "gather" else "convoy_defending"
					for unit in vehicle.passengers.duplicate():
						if group.members.has(unit): vehicle.disembark(unit, game.free_spawn(vehicle.position))
					group.phase = "work"; group.clock = 0.0
			else: issue(game, vehicle, "outbound", group.destination)
		elif group.phase == "work" and group.mode == "structure":
			if group.maintenance and not needs_work(game, group.structure):
				var next = nearby_work(game, group.structure, group.vehicle.position)
				if next != null:
					group.structure = next; group.destination = next.position
					game.notify("Crew continuing to nearby " + game.Rules.title(next.kind))
				else:
					finish(group)
					game.notify("Local repairs complete / crew holding position")
					continue
				assemble(game, group, "outbound"); continue
			for unit in group.members:
				if unit.aboard != null or unit.kind != "engineer": continue
				issue(game, unit, "repair", group.structure.position, group.structure)
				if unit.position.distance_to(group.structure.position) < 4:
					unit.path.clear(); unit.work_clock += dt
					var building: SimStructure = group.structure
					if not building.complete:
						building.progress += dt / float(game.Rules.STRUCTURES[building.kind].time)
						if building.progress >= 1:
								if not game.complete_construction(building): building.progress = 0.99
					elif building.hp < float(game.Rules.STRUCTURES[building.kind].hp) and unit.work_clock >= 1 and game.economy.spend({"minerals": 1}):
						unit.work_clock = 0; building.hp = minf(float(game.Rules.STRUCTURES[building.kind].hp), building.hp + 8)
					building.state_changed()
		elif group.phase == "work" and group.mode == "gather":
			var workers := 0
			for unit in group.members:
				if unit.aboard != null or unit.kind != "engineer": continue
				workers += 1
				if unit.cargo_total() > 0:
					if unit.position.distance_to(vehicle.position) < 5: game.transfer_cargo(unit, vehicle)
					elif unit.cargo_total() >= unit.capacity:
						issue(game, unit, "transfer", vehicle.position, vehicle); continue
				issue(game, unit, "gather", group.resource.position)
				if unit.position.distance_to(group.resource.position) < 3.5:
					unit.path.clear(); unit.work_clock += dt
					if unit.work_clock >= 0.7 and unit.cargo_total() < unit.capacity and group.resource.remaining > 0:
						unit.work_clock -= 0.7; game.resource_fields.harvest(game, unit, group.resource)
			if workers == 0:
				game.notify("Expedition ended / no available engineers"); finish(group); continue
			if vehicle.cargo_total() >= vehicle.capacity or group.resource.remaining <= 0: assemble(game, group, "return")
		elif group.phase == "return":
			# Newly completed outpost receivers can shorten an in-progress delivery.
			var receiver = receiver_for(game, group)
			group.receiver = receiver
			if receiver == null: head_home(game, group)
			elif vehicle.position.distance_to(receiver.position) < 4.0:
				vehicle.path.clear(); vehicle.order = "convoy_deposit"
				game.deposit_cargo(vehicle, receiver)
				for unit in group.members:
					if unit.aboard == vehicle or unit.position.distance_to(receiver.position) < 4.2: game.deposit_cargo(unit, receiver)
				head_home(game, group)
			else: issue(game, vehicle, "return", receiver.position, receiver)
		elif group.phase == "home":
			if not group.finish_home and receiver_for(game, group) != null:
				group.phase = "return"; head_home(game, group)
			elif vehicle.position.distance_to(group.home_destination) < 0.8:
				vehicle.path.clear(); vehicle.order = "convoy_waiting_for_depot"
				if group.finish_home or game.economy.space(group.resource.kind) <= 0:
					for unit in group.members:
						if unit.aboard == vehicle: vehicle.disembark(unit, game.free_spawn(game.HOME))
					finish(group); game.notify("Expedition home / crew unloaded / undeliverable cargo retained"); continue
			else: issue(game, vehicle, "home", group.home_destination)
		if not groups.has(group): continue
		# Walking escorts follow the convoy; dismounted infantry patrol the patch.
		for unit in group.members:
			if unit.aboard != null: continue
			if group.phase == "work" and unit.kind != "engineer":
				if group.mode == "gather": patrols.update(game, unit, group.destination, dt, "patrol")
				else:
					var angle: float = unit.formation_slot * 2.4
					issue(game, unit, "defend", group.destination + Vector3(cos(angle), 0, sin(angle)) * 5)
			elif group.phase != "work" and not (group.phase == "assemble" and group.riders.has(unit)):
				var point: Vector3 = vehicle.position - vehicle.facing * 3 + vehicle.facing.cross(Vector3.UP) * float(unit.formation_slot % 3 - 1) * 1.5
				if group.phase == "return" and alive(group.receiver) and vehicle.position.distance_to(group.receiver.position) < 4.0: point = group.receiver.position
				if group.phase == "home": point = group.home_destination
				issue(game, unit, "escort", point, vehicle)
	exploration.tick(game, dt)
	scouts.tick(game, dt)

func head_home(game, group: Dictionary) -> void:
	var vehicle: SimUnit = group.vehicle
	group.receiver = receiver_for(game, group)
	if group.receiver != null:
		issue(game, vehicle, "return", group.receiver.position, group.receiver); return
	var remaining: int = vehicle.cargo_total()
	for unit in group.members: remaining += unit.cargo_total()
	var target_full: bool = game.economy.space(group.resource.kind) <= 0
	if remaining == 0 and not target_full:
		if group.resource.remaining <= 0: finish(group); return
		assemble(game, group, "outbound"); return
	# Other-resource leftovers need not block another trip for the target resource.
	var primary := 0
	for unit in group.members + [vehicle]: primary += unit.cargo if group.resource.kind == "minerals" else unit.gas_cargo
	if not target_full and group.resource.remaining > 0 and primary == 0 and vehicle.cargo_total() < vehicle.capacity:
		assemble(game, group, "outbound"); return
	group.phase = "home"
	group.finish_home = target_full or group.resource.remaining <= 0 or (primary == 0 and vehicle.cargo_total() >= vehicle.capacity)
	group.home_destination = game.free_spawn(game.HOME + Vector3(0, 0, -10))
	issue(game, vehicle, "home", group.home_destination)

func receiver_for(game, group: Dictionary):
	var vehicle: SimUnit = group.vehicle
	var result: SimStructure
	var distance := INF
	for kind in ["minerals", "gas"]:
		if game.economy.space(kind) <= 0: continue
		var amount := 0
		for unit in group.members + [vehicle]: amount += unit.cargo if kind == "minerals" else unit.gas_cargo
		if amount == 0: continue
		var receiver: SimStructure = game.find_receiver(vehicle.position, kind)
		if receiver != null and vehicle.position.distance_to(receiver.position) < distance:
			result = receiver; distance = vehicle.position.distance_to(receiver.position)
	return result

func describe(unit: SimUnit) -> String:
	var exploration_description: String = exploration.describe(unit)
	if not exploration_description.is_empty(): return exploration_description
	var scout_description: String = scouts.describe(unit)
	if not scout_description.is_empty(): return scout_description
	var foot_description: String = foot.describe(unit)
	if not foot_description.is_empty(): return foot_description
	for group in groups:
		if group.id != unit.complex_id: continue
		var task: String = {"gather": "Gathering expedition", "structure": "Structure support", "travel": "Group transport"}[group.mode]
		var phase: String = {"assemble": "boarding", "outbound": "travelling", "work": "working", "return": "returning cargo", "home": "parking at HQ"}[group.phase]
		return task + " / " + phase
	return unit.order.replace("convoy_", "").replace("_", " ")

func expedition_selection(selection: Array) -> Array:
	# Explicit expedition targeting or a scanned resource order retasks the crew.
	var result: Array = selection.duplicate()
	var ids: Dictionary = {}
	for unit in selection:
		if unit is SimUnit and unit.complex_id != 0: ids[unit.complex_id] = true
	var tasks: Array = foot.groups.duplicate() + exploration.groups.duplicate()
	for group in groups:
		if group.mode == "gather": tasks.append(group)
	# Scout support and its miners form one expedition even while haulers deliver.
	var changed := true
	while changed:
		changed = false
		var families: Dictionary = {}
		for task in expedition_tasks():
			if ids.has(task.id) and task.has("expedition_id"): families[task.expedition_id] = true
		for task in expedition_tasks():
			if families.has(task.get("expedition_id")) and not ids.has(task.id): ids[task.id] = true; changed = true
		for scout_group in scouts.groups:
			if not ids.has(scout_group.id) and not scout_group.owners.any(func(owner): return ids.has(owner.id)): continue
			if not ids.has(scout_group.id): ids[scout_group.id] = true; changed = true
			for owner in scout_group.owners:
				if not ids.has(owner.id): ids[owner.id] = true; changed = true
	for scout_group in scouts.groups:
		if ids.has(scout_group.id):
			for unit in [scout_group.vehicle, scout_group.driver]:
				if not result.has(unit): result.append(unit)
	for group in tasks:
		if not ids.has(group.id): continue
		var crew: Array = group.members.duplicate()
		if group.has("vehicle"): crew.append(group.vehicle)
		if group.has("vehicles"): crew.append_array(group.vehicles)
		for unit in crew:
			if alive(unit) and not result.has(unit): result.append(unit)
	return result

func is_expedition(unit) -> bool:
	if not alive(unit) or not unit is SimUnit or unit.complex_id == 0: return false
	for group in exploration.groups + scouts.groups + foot.groups:
		if group.id == unit.complex_id: return true
	for group in groups:
		if group.id == unit.complex_id and group.mode == "gather": return true
	return false

func needs_work(game, building: SimStructure) -> bool:
	return alive(building) and (not building.complete or building.hp < float(game.Rules.STRUCTURES[building.kind].hp))

func nearby_work(game, origin: SimStructure, from_point: Vector3 = Vector3.INF) -> SimStructure:
	var result: SimStructure
	var distance := MAINTENANCE_RANGE
	if not from_point.is_finite(): from_point = origin.position
	for building in game.structures:
		if building == origin or not needs_work(game, building): continue
		var candidate: float = origin.position.distance_to(building.position)
		if candidate <= distance:
			var route: PackedVector3Array = game.navigation.path(from_point, building.position)
			if route.is_empty() or absf(route[-1].y - building.position.y) > 0.5 or game.Footprints.reach(building, route[-1]) >= 4: continue
			result = building; distance = candidate
	return result
