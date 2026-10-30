extends RefCounted
## Resource expeditions for engineers and their infantry guard, without transport.
var groups: Array[Dictionary] = []
var next_id := -1

func start(game, members: Array, resource: Dictionary) -> bool:
	for unit in members: game.complex_commands.interrupt(unit)
	var group := {"id": next_id, "members": members.duplicate(), "resource": resource, "phase": "work", "clock": 0.0}
	next_id -= 1; groups.append(group)
	for unit in members:
		unit.complex_id = group.id; unit.work_clock = 0
	game.notify("On-foot expedition / engineers gather and deliver to the nearest receiver / infantry guard")
	return true

func interrupt(unit: SimUnit) -> void:
	for group in groups:
		if group.members.has(unit): group.members.erase(unit); unit.complex_id = 0

func finish(group: Dictionary) -> void:
	for unit in group.members:
		if not SimEntity.valid(unit): continue
		unit.complex_id = 0; unit.order = "idle"; unit.path.clear(); unit.target = null
	groups.erase(group)

func tick(game, dt: float) -> void:
	for group in groups.duplicate():
		var workers: Array = []
		for unit in group.members.duplicate():
			if not SimEntity.valid(unit) or unit.hp <= 0: group.members.erase(unit); continue
			if unit.kind == "engineer": workers.append(unit)
		if workers.is_empty(): finish(group); continue
		group.clock += dt
		if group.phase == "work":
			for unit in workers:
				game.complex_commands.issue(game, unit, "foot_gather", group.resource.position)
				if game.resource_fields.within_reach(unit, group.resource.position, game):
					unit.path.clear(); unit.work_clock += dt
					if unit.work_clock >= game.Config.value("simulation", "harvest_seconds") and unit.cargo_total() < unit.capacity and game.resource_fields.available(game, group.resource):
						unit.work_clock -= game.Config.value("simulation", "harvest_seconds"); game.resource_fields.harvest(game, unit, group.resource)
			if not game.resource_fields.available(game, group.resource) or workers.any(func(unit): return unit.cargo_total() >= unit.capacity): group.phase = "return"
		if group.phase == "return":
			var remaining := 0
			var deliverable := false
			for unit in group.members:
				if unit.cargo_total() == 0: continue
				var receiver = game.cargo_receiver(unit)
				if receiver != null:
					deliverable = true
					if unit.position.distance_to(receiver.position) < 4.2:
						unit.path.clear(); unit.order = "convoy_foot_deposit"; game.deposit_cargo(unit, receiver)
					else: game.complex_commands.issue(game, unit, "foot_return", receiver.position, receiver)
				else: unit.path.clear(); unit.order = "convoy_waiting_for_depot"
				remaining += unit.cargo_total()
			var leader: SimUnit = workers[0]
			for unit in workers:
				if unit.cargo_total() > 0: leader = unit; break
			for unit in group.members:
				if unit.cargo_total() == 0 and unit != leader: game.complex_commands.issue(game, unit, "foot_escort", leader.position, leader)
			if not deliverable and game.economy.space(group.resource.kind) <= 0:
				if not group.has("home_destination"): group.home_destination = game.free_spawn(game.HOME)
				var home := true
				for unit in group.members:
					if unit.position.distance_to(game.HOME) >= 12:
						home = false; game.complex_commands.issue(game, unit, "foot_return", group.home_destination)
				if home: finish(group)
				continue
			if remaining == 0:
				if not game.resource_fields.available(game, group.resource):
					var next_patch: Dictionary = game.resource_fields.next_patch(game, group.resource)
					if next_patch.is_empty(): finish(group); continue
					group.resource = next_patch
				group.phase = "work"
		else:
			for unit in group.members:
				if unit.kind == "engineer": continue
				if workers[0].position.distance_to(group.resource.position) > 6: game.complex_commands.issue(game, unit, "foot_escort", workers[0].position, workers[0])
				else: game.complex_commands.patrols.update(game, unit, group.resource.position, dt, "foot_patrol")

func describe(unit: SimUnit) -> String:
	for group in groups:
		if group.id == unit.complex_id: return "On-foot expedition / " + ("returning cargo" if group.phase == "return" else "gathering")
	return ""
