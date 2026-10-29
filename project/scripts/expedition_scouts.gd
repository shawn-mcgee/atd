extends RefCounted
## Scout drivers stay aboard while their vehicles watch a mining perimeter.
const RADIUS := 10.0
const SCAN_RANGE := 22.0
var groups: Array[Dictionary] = []

func start_mining(game, roster: Dictionary, resource: Dictionary) -> bool:
	var command = game.complex_commands
	var workers_needed := maxi(1, roster.vehicles.size())
	var workers: Array = roster.members.filter(func(unit): return unit.kind == "engineer")
	if workers.size() < workers_needed or roster.members.size() < workers_needed + roster.vehicles.size() + roster.scouts.size():
		game.notify("Mining needs a working engineer per jeep (or one on foot), plus a separate driver for every vehicle"); return false
	# Reserve miners before assigning scout pilots, so a scout never takes the only worker.
	var pool: Array = roster.members.duplicate()
	for unit in workers.slice(0, workers_needed): pool.erase(unit)
	var pairs: Array[Dictionary] = []
	for scout in roster.scouts:
		pool.sort_custom(func(a, b): return command.MINING_DRIVER_RANK[a.kind] < command.MINING_DRIVER_RANK[b.kind] if a.kind != b.kind else a.formation_slot < b.formation_slot)
		pairs.append({"vehicle": scout, "driver": pool.pop_front()})
	var miners: Array = roster.members.duplicate()
	for pair in pairs: miners.erase(pair.driver)
	var old_groups: Array = command.groups.duplicate() + command.foot.groups.duplicate()
	for unit in roster.members + roster.vehicles + roster.scouts: command.interrupt(unit)
	for unit in roster.members:
		if unit.aboard != null: unit.aboard.disembark(unit, game.free_spawn(unit.aboard.position))
	if not command.start_expedition(game, roster.vehicles + miners, resource): return false
	var owners: Array = []
	for group in command.groups + command.foot.groups:
		if not old_groups.has(group): owners.append(group)
	for pair in pairs:
		var group := {"id": command.next_id, "vehicle": pair.vehicle, "driver": pair.driver, "resource": resource, "owners": owners}
		command.next_id += 1; groups.append(group)
		pair.vehicle.complex_id = group.id; pair.driver.complex_id = group.id
	game.notify("Mining expedition / scouts patrol and scan the perimeter / miners retain their working engineers")
	return true

func finish(group: Dictionary) -> void:
	for unit in [group.vehicle, group.driver]:
		if not is_instance_valid(unit): continue
		unit.complex_id = 0
		if unit.aboard == null: unit.order = "idle"; unit.path.clear(); unit.target = null; unit.goal = unit.position
	groups.erase(group)

func interrupt(unit: ExpeditionUnit) -> void:
	for group in groups.duplicate():
		if group.vehicle == unit or group.driver == unit: finish(group)

func tick(game, dt: float) -> void:
	var command = game.complex_commands
	for group in groups.duplicate():
		var active: bool = group.owners.any(func(owner): return command.groups.has(owner) or command.foot.groups.has(owner))
		if not active or not command.alive(group.vehicle) or not command.alive(group.driver): finish(group); continue
		var scout: ExpeditionUnit = group.vehicle
		var pilot: ExpeditionUnit = group.driver
		if pilot.aboard != scout:
			if pilot.aboard != null: finish(group); continue
			command.issue(game, pilot, "scout_board", scout.position, scout)
			if pilot.position.distance_to(scout.position) < 3.8: scout.board(pilot)
			continue
		command.patrols.update(game, scout, group.resource.position, dt, "scout_patrol", RADIUS)

func describe(unit: ExpeditionUnit) -> String:
	for group in groups:
		if group.id == unit.complex_id: return "Mining perimeter / " + ("patrolling and scanning" if group.vehicle.has_driver() else "boarding scout driver")
	return ""
