extends RefCounted
## Coordinated transport/gathering orders. Direct orders revoke membership.
var groups: Array[Dictionary] = []
var next_id := 1
var foot := preload("res://scripts/foot_expeditions.gd").new()
var patrols := preload("res://scripts/expedition_patrol.gd").new()
const MAINTENANCE_RANGE := 14.0

func alive(unit) -> bool:
	return is_instance_valid(unit) and unit.hp > 0

func interrupt(unit: ExpeditionUnit) -> void:
	patrols.states.erase(unit.get_instance_id())
	foot.interrupt(unit)
	for group in groups.duplicate():
		if group.vehicle == unit:
			finish(group)
		elif group.members.has(unit):
			group.members.erase(unit); unit.complex_id = 0

func finish(group: Dictionary) -> void:
	for unit in group.members + [group.vehicle]:
		if not is_instance_valid(unit): continue
		unit.complex_id = 0
		if unit.order.begins_with("convoy_"):
			unit.order = "idle"; unit.path.clear(); unit.target = null; unit.goal = unit.position
	groups.erase(group)

func start(game, selection: Array, resource: Dictionary = {}, structure: ExpeditionStructure = null, destination: Vector3 = Vector3.ZERO) -> bool:
	var vehicles: Array = []
	var members: Array = []
	for unit in selection:
		if not unit is ExpeditionUnit or not alive(unit): continue
		if unit.kind == "jeep": vehicles.append(unit)
		elif not unit.is_vehicle() and unit.aboard == null: members.append(unit)
	if vehicles.size() != 1: return false
	var vehicle: ExpeditionUnit = vehicles[0]
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
	var members: Array = []
	for unit in selection:
		if not unit is ExpeditionUnit or not alive(unit): continue
		if unit.kind == "jeep": vehicles.append(unit)
		elif not unit.is_vehicle() and unit.aboard == null: members.append(unit)
	for vehicle in vehicles:
		for unit in vehicle.passengers + ([vehicle.driver] if vehicle.has_driver() else []):
			if alive(unit) and not members.has(unit): members.append(unit)
	return {"vehicles": vehicles, "members": members}

func expedition_available(selection: Array) -> bool:
	var roster := expedition_roster(selection)
	var engineers := 0
	for unit in roster.members:
		if unit.kind == "engineer": engineers += 1
	return engineers >= maxi(1, roster.vehicles.size()) and roster.members.size() >= roster.vehicles.size() * 2

func start_expedition(game, selection: Array, resource: Dictionary) -> bool:
	if not expedition_available(selection):
		game.notify("Expedition needs engineers / each jeep needs its own driver and working engineer"); return false
	var roster := expedition_roster(selection)
	if roster.vehicles.is_empty(): return foot.start(game, roster.members, resource)
	if roster.vehicles.size() == 1: return start(game, selection, resource)
	var pool: Array = roster.members.duplicate()
	pool.sort_custom(func(a, b):
		var ranks := {"marine": 0, "flamer": 1, "engineer": 2}
		return ranks[a.kind] < ranks[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
	var assignments: Array[Array] = []
	# Reserve one driver and one working engineer per jeep before filling seats.
	for vehicle in roster.vehicles: assignments.append([vehicle, pool.pop_front()])
	for assigned in assignments:
		for unit in pool:
			if unit.kind == "engineer": assigned.append(unit); pool.erase(unit); break
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

func issue(game, unit: ExpeditionUnit, order: String, point: Vector3, target: Node3D = null) -> void:
	unit.order = "convoy_" + order; unit.target = target
	if unit.goal.distance_to(point) > 1.0 or not unit.moving(): unit.travel(point, game.navigation)

func assemble(game, group: Dictionary, leg: String, assign_seats: bool = false) -> void:
	var vehicle: ExpeditionUnit = group.vehicle
	vehicle.path.clear(); vehicle.order = "convoy_boarding"
	# Assign priorities once when accepting a new task. Subsequent legs retain
	# the driver and boarded passengers, including throughout depot stops.
	for unit in group.members:
		if assign_seats and unit.aboard == vehicle and group.mode != "travel": vehicle.disembark(unit, game.free_spawn(vehicle.position))
	var ranked: Array = group.members.duplicate()
	ranked.sort_custom(func(a, b):
		var ranks := {"marine": 0, "flamer": 1, "engineer": 2}
		return ranks[a.kind] < ranks[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
	group.driver = vehicle.driver if vehicle.has_driver() else ranked[0]
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
		group.clock += dt
		var vehicle: ExpeditionUnit = group.vehicle
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
					var building: ExpeditionStructure = group.structure
					if not building.complete:
						building.progress += dt / float(game.Rules.STRUCTURES[building.kind].time)
						if building.progress >= 1:
							building.progress = 0.99
							var clear := true
							for actor in game.units:
								if actor.aboard == null and actor.position.distance_to(building.position) < 1.9: clear = false
							if clear: building.complete = true; building.progress = 0; game.rebuild_navigation()
					elif building.hp < float(game.Rules.STRUCTURES[building.kind].hp) and unit.work_clock >= 1 and game.economy.spend({"minerals": 1}):
						unit.work_clock = 0; building.hp = minf(float(game.Rules.STRUCTURES[building.kind].hp), building.hp + 8)
					building.update_visual()
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
						unit.work_clock -= 0.7; group.resource.remaining -= 1
						if group.resource.kind == "minerals": unit.cargo += 1; unit.mined_cargo += 1
						else: unit.gas_cargo += 1
			if workers == 0:
				game.notify("Expedition ended / no available engineers"); finish(group); continue
			if vehicle.cargo_total() >= vehicle.capacity or group.resource.remaining <= 0: assemble(game, group, "return")
		elif group.phase == "return":
			var receiver = group.receiver
			if not alive(receiver) or not receiver.complete: head_home(game, group)
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

func head_home(game, group: Dictionary) -> void:
	var vehicle: ExpeditionUnit = group.vehicle
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
	var vehicle: ExpeditionUnit = group.vehicle
	var result: ExpeditionStructure
	var distance := INF
	for kind in ["minerals", "gas"]:
		if game.economy.space(kind) <= 0: continue
		var amount := 0
		for unit in group.members + [vehicle]: amount += unit.cargo if kind == "minerals" else unit.gas_cargo
		if amount == 0: continue
		var receiver: ExpeditionStructure = game.find_receiver(vehicle.position, kind, true)
		if receiver != null and vehicle.position.distance_to(receiver.position) < distance:
			result = receiver; distance = vehicle.position.distance_to(receiver.position)
	return result

func describe(unit: ExpeditionUnit) -> String:
	var foot_description: String = foot.describe(unit)
	if not foot_description.is_empty(): return foot_description
	for group in groups:
		if group.id != unit.complex_id: continue
		var task: String = {"gather": "Gathering expedition", "structure": "Structure support", "travel": "Group transport"}[group.mode]
		var phase: String = {"assemble": "boarding", "outbound": "travelling", "work": "working", "return": "returning cargo", "home": "parking at HQ"}[group.phase]
		return task + " / " + phase
	return unit.order.replace("convoy_", "").replace("_", " ")

func needs_work(game, building: ExpeditionStructure) -> bool:
	return alive(building) and (not building.complete or building.hp < float(game.Rules.STRUCTURES[building.kind].hp))

func nearby_work(game, origin: ExpeditionStructure, from_point: Vector3 = Vector3.INF) -> ExpeditionStructure:
	var result: ExpeditionStructure
	var distance := MAINTENANCE_RANGE
	if not from_point.is_finite(): from_point = origin.position
	for building in game.structures:
		if building == origin or not needs_work(game, building): continue
		var candidate: float = origin.position.distance_to(building.position)
		if candidate <= distance:
			var route: PackedVector3Array = game.navigation.path(from_point, building.position)
			if route.is_empty() or route[-1].distance_to(building.position) >= 4: continue
			result = building; distance = candidate
	return result
