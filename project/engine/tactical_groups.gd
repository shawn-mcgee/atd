extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
## Shared tactical missions: crew, escorts, vulnerable personnel, and scanner contacts.
const DRIVER_RANK := {"marine": 0, "flamer": 1, "engineer": 2}
static var LEASH: float = float(Config.value("tactics", "leash"))
var groups: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var next_id := -50000

func alive(actor) -> bool:
	return SimEntity.valid(actor) and actor.hp > 0

func roster(selection: Array) -> Dictionary:
	var vehicles: Array = []
	var members: Array = []
	var expanded: Array = selection.duplicate()
	for group in groups:
		if not selection.any(func(actor): return actor is SimUnit and actor.is_vehicle() and group.vehicles.has(actor)): continue
		for unit in group.members + group.vehicles:
			if not expanded.has(unit): expanded.append(unit)
	for actor in expanded:
		if not actor is SimUnit or not alive(actor): continue
		if actor.is_vehicle():
			vehicles.append(actor)
			for person in actor.passengers + ([actor.driver] if actor.has_driver() else []):
				if alive(person) and not members.has(person): members.append(person)
		elif actor.aboard == null and not members.has(actor): members.append(actor)
	return {"vehicles": vehicles, "members": members}

func available(selection: Array) -> bool:
	var crew := roster(selection)
	return crew.members.any(func(unit): return unit.kind in ["marine", "flamer"]) or (not crew.vehicles.is_empty() and crew.members.size() >= crew.vehicles.size())

func interrupt(unit: SimUnit) -> void:
	for task in pending.duplicate():
		if task.units.has(unit): pending.erase(task)
	for group in groups.duplicate():
		if not group.members.has(unit) and not group.vehicles.has(unit): continue
		var detached: Array = [unit]
		if unit.is_vehicle(): detached.append_array(unit.passengers + ([unit.driver] if unit.has_driver() else []))
		for person in detached:
			group.members.erase(person); group.vehicles.erase(person); group.seats.erase(person)
			person.complex_id = 0; person.combat_target = null
		if group.members.is_empty(): finish(group)

func finish(group: Dictionary) -> void:
	for unit in group.members + group.vehicles:
		if not alive(unit): continue
		unit.complex_id = 0; unit.combat_target = null; unit.target = null; unit.path.clear(); unit.goal = unit.position
		if unit.aboard == null: unit.order = "idle"
	groups.erase(group)

func start(game, selection: Array, mode: String, point: Vector3, target: SimEntity = null, append: bool = false) -> bool:
	var crew := roster(selection)
	if not available(selection): return false
	var participants: Array = crew.members + crew.vehicles
	if append and mode == "patrol":
		for group in groups:
			if group.mode == "patrol" and participants.any(func(unit): return group.members.has(unit) or group.vehicles.has(unit)):
				group.points.append(point); return true
	if append and participants.any(func(unit): return unit.aboard == null and (unit.order != "idle" or not unit.order_queue.is_empty())):
		if mode == "patrol" and not pending.is_empty() and pending[-1].mode == "patrol" and pending[-1].units == participants:
			pending[-1].extra_points.append(point); return true
		pending.append({"units": participants, "mode": mode, "point": point, "target": weakref(target) if target != null else null, "extra_points": []}); return true
	var seats: Dictionary = {}
	var pilots: Dictionary = {}
	var available_people: Array = crew.members.filter(func(unit): return unit.aboard == null)
	available_people.sort_custom(func(a, b): return DRIVER_RANK[a.kind] < DRIVER_RANK[b.kind])
	# Validate every driver before interrupting an existing task.
	for vehicle in crew.vehicles:
		if vehicle.has_driver(): seats[vehicle.driver] = vehicle; pilots[vehicle] = vehicle.driver
		elif available_people.is_empty():
			var riders: Array = vehicle.passengers.filter(func(person): return alive(person))
			if riders.is_empty(): game.notify("Tactical group needs one driver per vehicle"); return false
			seats[riders[0]] = vehicle; pilots[vehicle] = riders[0]
		else:
			var pilot: SimUnit = available_people.pop_front()
			seats[pilot] = vehicle; pilots[vehicle] = pilot
		for person in vehicle.passengers: seats[person] = vehicle
	# Engineers take protected passenger seats; armed infantry remain outside as escorts.
	for person in available_people:
		if person.kind != "engineer": continue
		for vehicle in crew.vehicles:
			var taken: int = seats.values().count(vehicle)
			if taken < vehicle.seat_capacity(): seats[person] = vehicle; break
	for vehicle in crew.vehicles:
		var pilot: SimUnit = pilots[vehicle]
		if not vehicle.has_driver() and pilot.aboard == vehicle: vehicle.disembark(pilot, game.free_spawn(vehicle.position))
	for unit in participants:
		game.complex_commands.interrupt(unit); interrupt(unit); unit.order_queue.clear(); unit.combat_target = null
		unit.complex_id = next_id; unit.path.clear(); unit.patrol_points.clear()
		if unit.aboard == null: unit.order = "cohort_assemble"
	var leader: SimUnit = crew.vehicles[0] if not crew.vehicles.is_empty() else crew.members[0]
	var group := {"id": next_id, "mode": mode, "members": crew.members, "vehicles": crew.vehicles, "seats": seats, "pilots": pilots, "destination": point, "target": weakref(target) if target != null else null, "points": [leader.position, point], "index": 1, "enemy": null, "combat_anchor": leader.position, "clock": 0.0, "contacts": {}, "investigate": Vector3.INF, "investigate_until": 0.0}
	next_id -= 1; groups.append(group)
	game.notify("Coordinated %s / engineers board, infantry escort / direct orders detach units" % mode.replace("_", " "))
	return true

func apply_speed_limits(_game) -> void:
	for group in groups:
		var speed := INF
		for person in group.members:
			if alive(person) and person.aboard == null: speed = minf(speed, float(person.STATS[person.kind].speed))
		for unit in group.vehicles + group.members:
			if alive(unit) and unit.aboard == null: unit.escort_speed_limit = minf(unit.escort_speed_limit, speed)

func issue(game, unit: SimUnit, mode: String, destination: Vector3, target: SimEntity = null, hold: bool = false) -> void:
	unit.order = "cohort_" + mode; unit.target = target
	if hold: unit.path.clear(); return
	if unit.goal.distance_to(destination) > 0.8 or (not unit.moving() and unit.position.distance_to(destination) > 0.9): unit.travel(destination, game.navigation)

func tick(game, dt: float) -> void:
	for task in pending.duplicate():
		task.units = task.units.filter(func(unit): return alive(unit))
		if task.units.is_empty(): pending.erase(task); continue
		if task.units.any(func(unit): return unit.aboard == null and (unit.order != "idle" or not unit.order_queue.is_empty())): continue
		pending.erase(task)
		var target: SimEntity = task.target.get_ref() if task.target != null else null
		if task.target != null and not alive(target): continue
		if start(game, task.units, task.mode, task.point, target): groups[-1].points.append_array(task.extra_points)
	for group in groups.duplicate():
		group.members = group.members.filter(func(unit): return alive(unit) and unit.complex_id == group.id)
		group.vehicles = group.vehicles.filter(func(unit): return alive(unit) and unit.complex_id == group.id)
		if group.members.is_empty(): finish(group); continue
		group.clock += dt
		for vehicle in group.vehicles:
			if vehicle.has_driver() or (alive(group.pilots.get(vehicle)) and group.members.has(group.pilots.get(vehicle))): continue
			var replacements: Array = group.members.filter(func(person): return person.aboard == vehicle or (person.aboard == null and not group.seats.has(person)))
			replacements.sort_custom(func(a, b): return DRIVER_RANK[a.kind] < DRIVER_RANK[b.kind])
			if not replacements.is_empty():
				var replacement: SimUnit = replacements[0]
				if replacement.aboard == vehicle: vehicle.disembark(replacement, game.free_spawn(vehicle.position))
				group.pilots[vehicle] = replacement; group.seats[replacement] = vehicle
		var boarding := false
		for person in group.seats.keys():
			var vehicle = group.seats[person]
			if not alive(person) or not alive(vehicle) or not group.members.has(person) or not group.vehicles.has(vehicle): group.seats.erase(person); continue
			if person.aboard == vehicle: continue
			boarding = true; issue(game, person, "board", vehicle.position, vehicle)
			if person.position.distance_to(vehicle.position) < 3.8 and (vehicle.has_driver() or group.pilots.get(vehicle) == person): vehicle.board(person)
		if boarding:
			for vehicle in group.vehicles: vehicle.path.clear()
			continue
		var walkers: Array = group.members.filter(func(unit): return unit.aboard == null)
		if group.mode == "patrol":
			for unit in group.members + group.vehicles: unit.patrol_points.assign(group.points)
		var leader: SimUnit = group.vehicles[0] if not group.vehicles.is_empty() else walkers.filter(func(unit): return unit.kind != "engineer")[0] if walkers.any(func(unit): return unit.kind != "engineer") else group.members[0]
		var protected: SimEntity = group.target.get_ref() if group.target != null else null
		if group.mode == "defend" and alive(protected): group.destination = protected.position
		if group.mode == "attack" and not alive(protected): finish(group); continue
		var destination: Vector3 = protected.position if group.mode == "defend" and alive(protected) else group.points[group.index] if group.mode == "patrol" else group.destination
		var anchor: Vector3 = destination if group.mode == "defend" else leader.position
		var enemy: SimEntity = protected if group.mode == "attack" else group.enemy.get_ref() if group.enemy != null else null
		if not alive(enemy) or (enemy is SimPredator and game.light.sample(enemy.position) < 0.065): enemy = null
		if enemy != null and group.mode in ["defend", "patrol"] and enemy.position.distance_to(group.combat_anchor) > LEASH: enemy = null
		if enemy == null and group.mode != "attack":
			for person in walkers:
				if person.kind not in ["marine", "flamer"]: continue
				var candidate: SimPredator = game.visible_target(person.position, 14)
				if candidate != null and (group.mode == "attack_move" or candidate.position.distance_to(anchor) <= LEASH): enemy = candidate; group.combat_anchor = anchor; break
		group.enemy = weakref(enemy) if enemy != null else null
		if enemy == null: investigate(game, group, leader, anchor)
		var travel_to: Vector3 = destination
		if enemy != null:
			travel_to = enemy.position + (leader.position - enemy.position).normalized() * 7 if not group.vehicles.is_empty() else enemy.position
		elif group.investigate.is_finite(): travel_to = group.investigate
		var arrived: bool = leader.position.distance_to(destination) < (4.0 if protected is SimStructure else 1.5)
		if enemy == null and not group.investigate.is_finite() and arrived:
			if group.mode in ["attack_move", "attack"]: finish(group); continue
			if group.mode == "patrol": group.index = (int(group.index) + 1) % group.points.size(); travel_to = group.points[group.index]
		for vehicle in group.vehicles:
			issue(game, vehicle, group.mode, travel_to, null, vehicle.position.distance_to(travel_to) < 1.2)
		for person in walkers:
			if group.mode == "defend" and person == protected:
				issue(game, person, "protected", person.position, null, true); continue
			var offset := Vector3(cos(person.formation_slot * 2.4), 0, sin(person.formation_slot * 2.4)) * (2.0 if person.kind == "engineer" else 3.5)
			if person.kind == "engineer" and (travel_to - leader.position).length() > 0.1: offset = -(travel_to - leader.position).normalized() * 2
			var point: Vector3 = (destination if group.mode == "defend" and arrived else leader.position) + offset
			if group.vehicles.is_empty() and person == leader: point = travel_to
			if person.kind in ["marine", "flamer"] and enemy != null:
				person.combat_target = enemy
				var range_value: float = game.Config.value("simulation", person.kind + "_range")
				issue(game, person, "engage", enemy.position, enemy, person.position.distance_to(enemy.position) <= range_value and game.navigation.can_see(person.position, enemy.position))
			else: person.combat_target = null; issue(game, person, "escort", point, leader if person != leader else null, person.position.distance_to(point) < 1)

func investigate(game, group: Dictionary, leader: SimUnit, anchor: Vector3) -> void:
	if group.investigate.is_finite():
		if group.clock >= group.investigate_until or leader.position.distance_to(group.investigate) < 2: group.investigate = Vector3.INF
		else: return
	for scout in group.vehicles:
		if scout.kind != "scout" or not scout.has_driver(): continue
		for creature in game.creatures:
			if creature.hp <= 0 or scout.position.distance_to(creature.position) > 28: continue
			var cell = game.Hex.to_axial(creature.position, game.Terrain.CELL * 4)
			if float(group.contacts.get(cell, -100)) + 20 > float(group.clock): continue
			var point: Vector3 = game.navigation.terrain.surface(game.Hex.to_world(cell, game.Terrain.CELL * 4))
			if game.navigation.blocked(point):
				var graph: AStar3D = game.navigation.friendly_graph
				var id := graph.get_closest_point(point)
				if id < 0: continue
				point = graph.get_point_position(id)
			if point.distance_to(anchor) > (12 if group.mode == "attack_move" else LEASH): continue
			group.contacts[cell] = group.clock; group.investigate = point; group.investigate_until = group.clock + 8
			game.notify("Scout investigating an approximate contact / weapons still require vision")
			return

func describe(unit: SimUnit) -> String:
	for group in groups:
		if group.members.has(unit) or group.vehicles.has(unit): return "Coordinated " + group.mode.replace("_", " ") + (" / investigating signal" if group.investigate.is_finite() else " / escort formation")
	return ""

func queued_count(unit: SimUnit) -> int:
	return pending.filter(func(task): return task.units.has(unit)).size()
