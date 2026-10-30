extends RefCounted
## Fixed-tick gameplay. No scene tree, rendering, input polling or wall-clock time.
const Hex = preload("res://engine/hex_grid.gd")
const Navigation = preload("res://engine/expedition_navigation.gd")
const Illumination = preload("res://engine/illumination.gd")
const Unit = preload("res://engine/expedition_unit.gd")
const Structure = preload("res://engine/expedition_structure.gd")
const Predator = preload("res://engine/predator.gd")
const Director = preload("res://engine/predator_director.gd")
const Rules = preload("res://engine/expedition_rules.gd")
const Economy = preload("res://engine/expedition_economy.gd")
const Power = preload("res://engine/expedition_power.gd")
const SoftSpacing = preload("res://engine/soft_unit_spacing.gd")
const ComplexCommands = preload("res://engine/complex_commands.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
const StateCodec = preload("res://engine/state_codec.gd")
const TICK := 0.1
const HOME := Vector3.ZERO
const MINT := Color("7bf4d0")
const AMBER := Color("efbd77")
const BUILD_KINDS := ["floodlight", "generator", "repeater", "turret", "wall", "gate", "depot", "gas_tank", "barracks", "garage", "scanner", "platform", "ramp", "extractor", "laser_turret", "flame_turret"]
var layout := preload("res://engine/scenario_layout.gd").new()
var scenario_seed := 0
var turret_system := preload("res://engine/turret_system.gd").new()
var tactical_groups := preload("res://engine/tactical_groups.gd").new()
var tactics := preload("res://engine/tactical_orders.gd").new()
var mission := preload("res://engine/hive_mission.gd").new()
var resource_fields := preload("res://engine/resource_fields.gd").new()
var vehicles := preload("res://engine/vehicle_systems.gd").new()
var mesa_cells: Dictionary = {}
var economy := Economy.new()
var power := Power.new()
var wrecks: Array[Dictionary] = []
var resource_nodes: Array[Dictionary] = []
var placement_direction := 0
var navigation := Navigation.new()
var light := Illumination.new()
var director := Director.new()
var units: Array[SimUnit] = []
var soft_spacing := SoftSpacing.new()
var construction_clearance := preload("res://engine/construction_clearance.gd").new()
var complex_commands := ComplexCommands.new()
var gate_passage := preload("res://engine/gate_passage.gd").new()
var next_formation_slot := 0
var structures: Array[SimStructure] = []
var creatures: Array[SimPredator] = []
var selected: Array[SimEntity] = []
var rocks: Array[Dictionary] = []
var core: SimStructure
var jeep: SimUnit
var home_depot: SimStructure
var elapsed := 0.0
var started := false
var paused := false
var ended := false
var victorious := false
var tick_number := 0
var outpost_established := false
var returned_materials := 0
var sensor_activity := 0.0
var low_fuel_warned := false
var next_entity_id := 1
var entities: Dictionary = {}
var explored: Dictionary = {}
var sensor_blips: Array[Dictionary] = []
var events: Array[Dictionary] = []
var event_serial := 0
var append_command := false
var pending_commands: Array[Dictionary] = []
var command_log: Array[Dictionary] = []
var survey_revision := -1
var survey_hash := 0
var survey_count := -1
var survey_points: Dictionary = {}
var survey_types: Dictionary = {}

func initialize(seed_value: int = 1) -> void:
	layout.generate(navigation.terrain, seed_value)
	scenario_seed = layout.seed_value
	layout.make_landscape(self)
	layout.setup_base(self)
	layout.setup_resources(self)
	mission.setup(self)
	economy.recalculate(structures); power.tick(structures, economy, 0)
	rebuild_navigation(); rebuild_light()
	director.populate(self)
	record_exploration()
	started = true

func register_entity(entity: SimEntity) -> void:
	entity.simulation_id = next_entity_id; next_entity_id += 1
	entities[entity.simulation_id] = entity

func add_resource_patch(kind: String, point: Vector3, amount: int) -> void:
	resource_nodes.append({"kind": kind, "position": navigation.terrain.surface(point), "remaining": amount, "discovered": false})

func add_natural_obstacle(point: Vector3, variation: int) -> void:
	point = Hex.snap(point, Terrain.CELL)
	if not Terrain.contains(point, 1) or point.distance_to(HOME) < 10: return
	if layout.fields.any(func(field): return point.distance_to(field.position) < 5): return
	var cell := Hex.to_axial(point, Terrain.CELL)
	for obstacle in rocks:
		if obstacle.cell == cell: return
	rocks.append({"position": navigation.terrain.surface(point), "radius": Terrain.CELL * 0.82, "height": 4.0 + posmod(variation, 3) * 0.4, "cell": cell})

func enqueue(command: Dictionary) -> void:
	var entry := command.duplicate(true)
	entry.tick = int(entry.get("tick", tick_number))
	if entry.has("actors"): entry.actors = entry.actors.map(func(id): return int(id))
	if entry.has("target"): entry.target = int(entry.target)
	if entry.has("direction"): entry.direction = int(entry.direction)
	entry.sequence = int(entry.get("sequence", command_log.size()))
	pending_commands.append(entry); command_log.append(entry.duplicate(true))
	pending_commands.sort_custom(func(a, b): return int(a.tick) < int(b.tick) or (int(a.tick) == int(b.tick) and int(a.sequence) < int(b.sequence)))

func step() -> void:
	if paused or ended or not started: return
	while not pending_commands.is_empty() and int(pending_commands[0].tick) <= tick_number:
		apply_command(pending_commands.pop_front())
	for i in range(6): advance_movement(TICK / 6.0)
	simulation_tick(TICK, false)
	if tick_number % 2 == 0: record_exploration()
	check_mission()
	for id in entities.keys():
		if entities[id].disposed: entities.erase(id)

func snapshot() -> Dictionary:
	var actors: Array = []
	for id in entities: actors.append(StateCodec.actor_state(entities[id]))
	return {"version": 1, "seed": scenario_seed, "tick": tick_number, "elapsed": elapsed,
		"ended": ended, "victorious": victorious, "next_id": next_entity_id,
		"actors": actors, "economy": StateCodec.encode(economy), "power": StateCodec.encode(power),
		"resources": StateCodec.encode(resource_nodes), "rocks": StateCodec.encode(rocks),
		"mission": StateCodec.encode(mission), "director": StateCodec.encode(director),
		"complex": StateCodec.encode(complex_commands), "tactical_groups": StateCodec.encode(tactical_groups),
		"spacing": StateCodec.encode(soft_spacing), "gates": StateCodec.encode(gate_passage),
		"explored": StateCodec.encode(explored), "terrain": StateCodec.encode(navigation.terrain),
		"pending": StateCodec.encode(pending_commands), "wrecks": StateCodec.encode(wrecks),
		"formation": next_formation_slot, "low_fuel_warned": low_fuel_warned, "outpost": outpost_established, "returned": returned_materials, "sensor": sensor_activity}

func state_hash() -> String:
	return JSON.stringify(snapshot(), "", true, true).sha256_text()

func replay_data() -> Dictionary:
	return {"version": 1, "seed": scenario_seed, "commands": StateCodec.encode(command_log)}

func load_replay(data: Dictionary) -> void:
	assert(not started, "Load a replay into a fresh Simulation")
	assert(int(data.version) == 1, "Unsupported replay version")
	initialize(int(data.seed))
	for command in StateCodec.decode(data.commands): enqueue(command)

func dispose() -> void:
	# State objects may point at each other (driver/vehicle, target/attacker).
	# Explicitly sever those links when replacing a simulation.
	for entity in entities.values():
		entity.target = null; entity.focus_target = null
		if entity is SimUnit:
			entity.driver = null; entity.aboard = null; entity.combat_target = null
			entity.passengers.clear(); entity.order_queue.clear()
	units.clear(); structures.clear(); creatures.clear(); selected.clear(); wrecks.clear()
	complex_commands.groups.clear(); complex_commands.foot.groups.clear(); complex_commands.exploration.groups.clear()
	complex_commands.scouts.groups.clear(); complex_commands.patrols.states.clear()
	tactical_groups.groups.clear(); tactical_groups.pending.clear()
	mission.carrier = null; mission.hive = null; mission.beacon = null; mission.item = null
	core = null; home_depot = null; jeep = null
	power.links.clear(); power.grids.clear(); navigation.terrain.structures.clear()
	navigation.obstacles.clear(); navigation.geometry_obstacles.clear(); navigation.records.clear()
	entities.clear()

func apply_command(command: Dictionary) -> void:
	selected.clear()
	for id in command.get("actors", []):
		var actor = entities.get(int(id))
		if SimEntity.valid(actor): selected.append(actor)
	append_command = command.get("append", false)
	var point: Vector3 = command.get("point", Vector3.ZERO)
	var target: SimEntity = entities.get(int(command.get("target", 0)))
	placement_direction = int(command.get("direction", 0))
	match command.kind:
		"context": contextual_order(point, target, append_command)
		"build": order_build(command.building, point)
		"walls": order_wall_line(command.start, point)
		"train": train_unit(command.unit)
		"expedition":
			var crew := complex_commands.expedition_selection(selected)
			var resource := resource_at(point) if command.get("mining", false) else {}
			if not command.get("mining", false) or (not resource.is_empty() and resource.discovered and resource.remaining > 0):
				for unit in crew:
					if unit is SimUnit: unit.order_queue.clear()
				complex_commands.start_expedition(self, crew, resource, point)
		"tactical":
			tactical_order(command.mode, point, target, append_command)
		"repair":
			if target is SimStructure:
				for unit in selected_engineers(): issue_order(unit, "repair" if target.complete else "build", target.position, target, append_command)
		_:
			if command.kind in ["board_squad", "unload", "load_nearest", "return_home", "stock_depot", "escort", "toggle_auto_recharge", "destroy_selected", "toggle_repeater", "reload_selected_turrets", "toggle_turret_reload", "stop_selected", "cancel_training", "toggle_gate_lock", "toggle_gate"]:
				call(command.kind)
	selected.clear()

func tactical_order(mode: String, point: Vector3, target: SimEntity = null, append: bool = false) -> void:
	var ordered: Array = selected.duplicate()
	if ordered.any(func(actor): return actor is SimUnit and actor.is_vehicle() and complex_commands.is_expedition(actor)):
		ordered = complex_commands.expedition_selection(ordered)
	var crew := tactical_groups.roster(ordered)
	var focus_actor: SimEntity = target if mode in ["attack", "defend"] else null
	if mode != "drill" and (crew.members.size() > 1 or not crew.vehicles.is_empty()) and tactical_groups.start(self, ordered, mode, point, focus_actor, append): return
	for unit in ordered:
		if not unit is SimUnit: continue
		if mode == "drill" and unit.kind == "drill": issue_order(unit, "drill", Hex.snap(point, Terrain.CELL), null, append)
		elif unit.kind in ["marine", "flamer"]: issue_order(unit, mode, point, focus_actor, append)

func notify(message: String) -> void:
	event_serial += 1
	events.append({"serial": event_serial, "tick": tick_number, "type": "message", "text": message})
	if events.size() > 128: events.pop_front()

func finish(won: bool, reason: String) -> void:
	ended = true; victorious = won; notify(reason)

func shot(a: Vector3, b: Vector3, color: Color, shooter: SimEntity = null) -> void:
	event_serial += 1
	events.append({"serial": event_serial, "tick": tick_number, "type": "shot", "a": a, "b": b, "color": color,
		"shooter": shooter.simulation_id if shooter != null else 0, "weapon": shooter.kind if shooter != null else ""})
	if events.size() > 128: events.pop_front()

func update_scanner_contacts() -> void:
	sensor_blips.clear()
	var cells: Dictionary = {}
	var sources: Array[Vector3] = []
	for building in structures:
		if building.kind == "scanner" and building.complete and building.powered: sources.append(building.position)
	for unit in units:
		if unit.kind == "scout" and unit.hp > 0 and unit.has_driver(): sources.append(unit.position)
	for source in sources:
		for creature in creatures:
			if creature.hp <= 0 or creature.position.distance_to(source) > complex_commands.scouts.SCAN_RANGE: continue
			var cell := Hex.to_axial(creature.position, Terrain.CELL)
			if not cells.has(cell):
				cells[cell] = true; sensor_blips.append({"position": Hex.to_world(cell, Terrain.CELL)})
func update_fortifications() -> void:
	var occupied: Dictionary = {}
	for building in structures:
		if building.kind in ["wall", "gate"]:
			var cell := Hex.to_axial(building.position, Terrain.CELL)
			occupied[Vector3i(cell.x, cell.y, roundi(building.position.y * 10))] = building
	for building in structures:
		if building.kind not in ["wall", "gate"]: continue
		var neighbors: Array[Vector3] = []
		var cell := Hex.to_axial(building.position, Terrain.CELL)
		for offset in Hex.NEIGHBORS:
			var key := Vector3i(cell.x + offset.x, cell.y + offset.y, roundi(building.position.y * 10))
			if occupied.has(key): neighbors.append(occupied[key].position - building.position)
		if neighbors == building.connections: continue
		building.connect_fortification(neighbors); building.state_changed()

func add_unit(kind: String, point: Vector3) -> SimUnit:
	var unit := Unit.new()
	unit.setup(kind, navigation.terrain.surface(point))
	unit.formation_slot = next_formation_slot; next_formation_slot += 1
	register_entity(unit); units.append(unit)
	return unit

func add_structure(kind: String, point: Vector3, finished: bool = true, direction_index: int = -1) -> SimStructure:
	var structure := Structure.new()
	point = navigation.terrain.surface(Hex.snap(point, Terrain.CELL))
	if kind in ["platform", "ramp"]: point.y = 0
	structure.setup(kind, point, finished, placement_direction if direction_index < 0 else direction_index)
	register_entity(structure); structures.append(structure)
	if kind in ["wall", "gate"]: update_fortifications()
	return structure

func add_creature(point: Vector3, group: int, kind: String = "stalker", variation: int = 0) -> SimPredator:
	var creature := Predator.new()
	creature.setup(navigation.terrain.surface(point), group, kind, variation)
	creature.visible = light.sample(creature.position) > 0.065
	register_entity(creature); creatures.append(creature)
	return creature

func rebuild_navigation() -> void:
	navigation.terrain.structures.assign(structures.filter(func(building): return building.kind in ["platform", "ramp"]))
	update_fortifications()
	var blockers: Array[Dictionary] = rocks.duplicate()
	for b in structures:
		if not b.complete: continue
		if b.kind == "gate" and b.gate_open: continue
		if b.kind in ["platform", "ramp"]: continue
		var auto_gate: bool = b.kind == "gate" and b.powered and not b.gate_locked
		for tile in Footprints.points(b):
			blockers.append({"position": tile, "radius": Terrain.CELL * 0.58, "auto_gate": auto_gate, "owner": b})
		if b.kind in ["wall", "gate"]:
			for offset in b.connections: blockers.append({"position": b.position, "end": b.position + offset * 0.5, "radius": 0.32, "auto_gate": auto_gate})
	navigation.rebuild(blockers)
	for unit in units:
		if unit.moving() and navigation.affects_path(unit.position, unit.path, unit.path_index): unit.travel(unit.goal, navigation)
	for creature in creatures:
		if navigation.affects_path(creature.position, creature.path, creature.path_index): creature.path.clear(); creature.repath = 0

func rebuild_light() -> void:
	light.sources.clear()
	for b in structures:
		if not b.complete or b.hp <= 0: continue
		if b.kind == "core":
			light.add_source(b.position, 4, Vector3.ZERO, -1, 0.2, false)
			if b.powered and b.enabled: light.add_source(b.position, b.light_radius, Vector3.ZERO, -1, b.light_intensity)
		if b.kind == "floodlight" and b.powered and b.enabled: light.add_source(b.position, 13)
	for unit in units:
		if unit.aboard != null or unit.hp <= 0: continue
		if unit.is_vehicle():
			light.add_source(unit.position, 4, Vector3.ZERO, -1, 0.2, false)
			if unit.has_driver() and unit.battery > 0:
				light.add_source(unit.position, 5)
				light.add_source(unit.position, 18, unit.facing, cos(deg_to_rad(52)))
		else: light.add_source(unit.position, 2.6, Vector3.ZERO, -1, 0.45, false)
	for wreck in wrecks:
		light.add_source(wreck.node.position, 4, Vector3.ZERO, -1, float(wreck.life) / 30.0 * 0.2, false)

	resource_fields.discover(self)

func advance_movement(dt: float) -> void:
	gate_passage.update(self, dt)
	for unit in units: unit.escort_speed_limit = INF
	for unit in units:
		if unit.hp <= 0 or unit.aboard != null or unit.order not in ["escort", "convoy_escort"]: continue
		if SimEntity.valid(unit.target) and unit.target is SimUnit and unit.target.is_vehicle():
			unit.target.escort_speed_limit = minf(unit.target.escort_speed_limit, float(Rules.UNITS[unit.kind].speed))
	complex_commands.exploration.apply_speed_limits(self)
	tactical_groups.apply_speed_limits(self)
	for unit in units: unit.tick_move(dt)
	soft_spacing.apply(units, navigation, dt)
	for creature in creatures: creature.move_tick(dt)
	for unit in units:
		if unit.aboard == null: unit.position.y = navigation.terrain.height(unit.position)
	for creature in creatures: creature.position.y = navigation.terrain.height(creature.position)

func simulation_tick(dt: float, advance_motion: bool = true) -> void:
	if ended: return
	if advance_motion: advance_movement(dt)
	elapsed += dt; tick_number += 1
	sensor_activity = maxf(0, sensor_activity - dt)
	economy.recalculate(structures); power.tick(structures, economy, dt)
	if economy.gas <= 15 and power.fuel_rate > 0 and not low_fuel_warned:
		low_fuel_warned = true; notify("Methane reserve low / send engineers to the methane signal and deliver to a Methane Tank")
	elif economy.gas >= 30: low_fuel_warned = false
	vehicles.tick(self, dt)
	tactics.tick(self, dt)
	tactical_groups.tick(self, dt)
	for unit in units: process_order(unit, dt)
	complex_commands.tick(self, dt)
	for b in structures:
		b.cooldown = maxf(0, b.cooldown - dt)
		if b.complete and not b.queue.is_empty():
			b.production_progress += dt
			var kind: String = b.queue[0]
			if b.production_progress >= float(Rules.UNITS[kind].time):
				var spawn_point := free_spawn(b.position)
				add_unit(kind, spawn_point); b.queue.pop_front(); b.production_progress = 0
				notify("%s ready%s" % [Rules.title(kind), " / needs a driver" if kind in ["jeep", "scout"] else ""])
	var operating_light := false
	for b in structures:
		if b.kind == "floodlight" and b.complete and b.powered and b.position.distance_to(layout.fields[0].position) < 12: operating_light = true
	if operating_light and not outpost_established:
		outpost_established = true; notify("Mining perimeter illuminated / order an engineer to gather materials")
	if outpost_established and not director.outpost_group_created:
		director.outpost_group_created = true; director.add_group(layout.fields[0].position, 1)
		for i in range(4): director.spawn_member(self, director.groups[-1], true)
	if tick_number % 4 == 0: director.tick(self, dt * 4)
	mission.tick(self, dt)
	rebuild_light(); combat_tick(dt); cleanup_dead(); rebuild_light()
	for creature in creatures: creature.visible = light.sample(creature.position) > 0.065
	mission.hive.visible = mission.hive_discovered and light.sample(mission.hive.position) > 0.05
	if tick_number % 5 == 0: update_scanner_contacts()
	for i in range(wrecks.size() - 1, -1, -1):
		wrecks[i].life -= dt
		if float(wrecks[i].life) <= 0:
			wrecks[i].node.queue_free(); wrecks.remove_at(i)

func issue_order(unit: SimUnit, order: String, point: Vector3, target: SimEntity = null, append: bool = false) -> bool:
	return tactics.issue(self, unit, order, point, target, append)

func set_order(unit: SimUnit, order: String, point: Vector3, target: SimEntity = null) -> bool:
	if unit.aboard != null: return false
	complex_commands.interrupt(unit)
	tactical_groups.interrupt(unit)
	if unit.is_vehicle() and not unit.has_driver():
		notify("%s needs a driver / board infantry first" % Rules.title(unit.kind)); return false
	unit.order = order; unit.target = target; unit.work_clock = 0
	if not unit.travel(point, navigation): unit.order = "idle"; notify("No clear route to that location"); return false
	return true

func process_order(unit: SimUnit, dt: float) -> void:
	if unit.aboard != null: return
	tactics.advance_queue(self, unit)
	var target := unit.target
	if unit.order in ["build", "repair", "board", "escort", "stock", "deliver", "deposit", "to_carrier", "close_gate"] and not SimEntity.valid(target): unit.order = "idle"; return
	if unit.order in ["build", "repair", "close_gate", "stock", "deliver", "deposit"] and not unit.moving():
		var reach := 4.2 if unit.order in ["stock", "deliver", "deposit"] else 4.0
		if (Footprints.reach(target, unit.position) if target is SimStructure else unit.position.distance_to(target.position)) >= reach: unit.travel(target.position, navigation)
	if unit.order in ["board", "escort"]:
		unit.work_clock -= dt
		if unit.work_clock <= 0:
			unit.work_clock = 0.8
			var lane := float(unit.formation_slot % 3) - 1.0
			var rank := float((unit.formation_slot / 3) % 2)
			var point: Vector3 = target.position if unit.order == "board" else target.position - target.facing * (2.5 + rank) + target.facing.cross(Vector3.UP) * lane * 1.5
			if unit.goal.distance_to(point) > 1.5 or not unit.moving(): unit.travel(point, navigation)
		if unit.order == "board" and unit.position.distance_to(target.position) < 3.8:
			if target.board(unit): selected.erase(unit)
			else: unit.order = "escort"
	elif unit.order == "build" and Footprints.reach(target, unit.position) < 4:
		unit.path.clear()
		if target.complete: continue_maintenance(unit, target); return
		target.progress += dt / float(Rules.STRUCTURES[target.kind].time)
		if target.progress >= 1:
			if complete_construction(target): continue_maintenance(unit, target)
			else: target.progress = 0.99
		target.state_changed()
	elif unit.order == "repair" and Footprints.reach(target, unit.position) < 4:
		unit.path.clear(); unit.work_clock += dt
		if unit.work_clock >= 1:
			unit.work_clock = 0
			if target.hp >= float(Rules.STRUCTURES[target.kind].hp): continue_maintenance(unit, target)
			elif economy.spend({"minerals": 1}): target.hp = minf(float(Rules.STRUCTURES[target.kind].hp), target.hp + 8)
	elif unit.order == "harvest": process_harvest(unit, dt)
	elif unit.order == "to_carrier":
		if unit.position.distance_to(target.position) < 3.8:
			unit.path.clear(); transfer_cargo(unit, target)
			if unit.cargo_total() > 0: send_to_receiver(unit)
			else: set_order(unit, "harvest", unit.harvest_origin)
		else:
			unit.work_clock -= dt
			if unit.work_clock <= 0: unit.travel(target.position, navigation); unit.work_clock = 1
	elif unit.order in ["stock", "deliver", "deposit"] and unit.position.distance_to(target.position) < 4.2:
		unit.path.clear(); deposit_cargo(unit, target)
		if unit.order == "deposit" and unit.cargo_total() == 0: set_order(unit, "harvest", unit.harvest_origin)
		elif unit.cargo_total() == 0: unit.order = "idle"
	elif unit.order == "close_gate" and unit.position.distance_to(target.position) < 4:
		unit.path.clear(); unit.work_clock += dt
		if unit.work_clock >= 2 and set_gate(target, false, true): unit.order = "idle"
	elif unit.order == "move" and not unit.moving(): unit.order = "idle"

func complete_construction(building: SimStructure) -> bool:
	if building.complete: return true
	var clearance: Dictionary = construction_clearance.plan(self, building)
	building.waiting_for_clearance = not clearance.ready
	if not clearance.ready: return false
	var destinations: Dictionary = {}
	for actor: SimUnit in clearance.moves:
		if actor.moving(): destinations[actor] = actor.goal
		actor.position = clearance.moves[actor]
		soft_spacing.velocities.erase(actor.simulation_id)
		actor.motion_velocity = Vector3.ZERO
		if not actor.moving(): actor.path.clear(); actor.goal = actor.position
	for actor in units:
		if actor.aboard != null: actor.position = actor.aboard.position
	building.complete = true; building.progress = 0
	if building == mission.beacon: building.hp = float(Rules.STRUCTURES[building.kind].hp)
	rebuild_navigation()
	for actor: SimUnit in destinations: actor.travel(destinations[actor], navigation)
	economy.recalculate(structures); power.tick(structures, economy, 0); rebuild_light()
	building.state_changed(); notify("%s complete" % Rules.title(building.kind))
	return true

func continue_maintenance(unit: SimUnit, building: SimStructure) -> void:
	if not unit.order_queue.is_empty(): unit.order = "idle"; unit.path.clear(); return
	var next := complex_commands.nearby_work(self, building, unit.position)
	if next != null and set_order(unit, "repair" if next.complete else "build", next.position, next): return
	unit.order = "idle"; unit.path.clear(); unit.target = null
	unit.goal = unit.position; unit.work_clock = 0

func consume_materials(_point: Vector3, cost: int) -> bool:
	return economy.spend({"minerals": cost})

func valid_site(kind: String, point: Vector3, direction_index: int = -1) -> bool:
	var direction := placement_direction if direction_index < 0 else direction_index
	if not Rules.STRUCTURES.has(kind) or kind == "core": return false
	point = navigation.terrain.surface(point)
	if not Terrain.contains(point, 1) or light.sample(point) < 0.055: return false
	if kind in ["platform", "ramp"] and point.y > 0.1: return false
	if kind not in ["platform", "ramp"]:
		if minf(absf(point.y), absf(point.y - Terrain.LEVEL)) > 0.1: return false
		for i in range(6):
			if absf(navigation.terrain.height(point + Terrain.direction(i) * (Terrain.CELL * 0.75)) - point.y) > 0.1: return false
	if kind == "ramp":
		var forward := Terrain.direction(direction)
		var footprint := [Hex.to_axial(point, Terrain.CELL), Hex.to_axial(point - forward * Terrain.SPACING, Terrain.CELL)]
		for b in structures:
			if footprint.has(Hex.to_axial(b.position, Terrain.CELL)): return false
		for rock in rocks:
			if rock.has("cell") and footprint.has(rock.cell): return false
		if navigation.terrain.height(point + forward * (Terrain.SPACING * 0.5 + 0.2)) < Terrain.LEVEL - 0.1: return false
		for i in range(8):
			var sample := point + forward * (-Terrain.SPACING * 1.5 + float(i) / 7 * Terrain.SPACING * 1.9)
			if not Terrain.contains(sample, 1) or navigation.terrain.height(sample) > 0.1: return false
			for rock in rocks:
				if sample.distance_to(rock.position) < float(rock.radius) + 0.6: return false
			for b in structures:
				if b.kind not in ["platform", "ramp"] and sample.distance_to(b.position) < 2: return false
	var occupied := Footprints.cells(kind, point, direction)
	for cell in occupied:
		var tile := Hex.to_world(cell, Terrain.CELL)
		if not Terrain.contains(tile, 1) or absf(navigation.terrain.height(tile) - point.y) > 0.1: return false
		for b in structures:
			if b.kind == "platform" and kind not in ["platform", "ramp"]: continue
			if absf(b.position.y - point.y) < 0.2 and Footprints.cells(b.kind, b.position, b.build_direction).has(cell): return false
		for rock in rocks:
			if rock.get("cell") == cell: return false
	if kind == "extractor":
		var resource := resource_at(point)
		if resource.is_empty() or not resource.discovered or resource.remaining <= 0: return false
	elif kind not in ["platform", "ramp"] and not resource_at(point).is_empty(): return false
	return true

func order_build(kind: String, point: Vector3) -> SimStructure:
	var engineers := selected_engineers()
	if engineers.is_empty(): notify("Select an engineer on foot to build"); return null
	point = navigation.terrain.surface(Hex.snap(point, Terrain.CELL))
	if not valid_site(kind, point): notify("Ramp: high end must join raised ground / T rotates" if kind == "ramp" else "Use illuminated, clear terrain"); return null
	if not economy.spend(Rules.cost(kind)): notify("Insufficient banked materials or methane"); return null
	var site := add_structure(kind, point, false); site.funded = true
	rebuild_navigation(); issue_order(engineers[0], "build", point, site, append_command)
	notify("%s funded from global reserves / engineer en route" % Rules.title(kind))
	return site

func order_wall_line(start: Vector3, endpoint: Vector3) -> int:
	if not start.is_finite() or not endpoint.is_finite(): return 0
	var engineers := selected_engineers()
	if engineers.is_empty(): notify("Select an engineer on foot to build"); return 0
	var sites: Array[SimStructure] = []
	for point in Hex.line(start, endpoint, Terrain.CELL):
		point = navigation.terrain.surface(point)
		if not valid_site("wall", point): continue
		if not economy.spend(Rules.cost("wall")): break
		var site := add_structure("wall", point, false); site.funded = true
		sites.append(site)
	if sites.is_empty(): notify("No affordable walls on illuminated, clear terrain"); return 0
	# Keep the engineer working from the beginning; nearby maintenance chains the line.
	rebuild_navigation()
	for i in range(sites.size()):
		issue_order(engineers[0], "build", sites[i].position, sites[i], i > 0 or append_command)
	notify("%d wall segments funded / %d materials / blocked cells skipped" % [sites.size(), sites.size() * int(Rules.cost("wall").minerals)])
	return sites.size()

func visible_target(point: Vector3, radius: float) -> SimPredator:
	var best: SimPredator
	var distance := radius * radius
	for creature in creatures:
		if creature.hp <= 0: continue
		var candidate := point.distance_squared_to(creature.position)
		if candidate >= distance or light.sample(creature.position) < 0.065: continue
		if navigation.can_see(point, creature.position):
			distance = candidate
			best = creature
	return best

func combat_tick(_dt: float) -> void:
	for unit in units:
		if unit.kind not in ["marine", "flamer"] or unit.aboard != null or unit.cooldown > 0: continue
		var enemy: SimEntity = unit.combat_target if tactics.valid(unit.combat_target) else visible_target(unit.position, 5.5 if unit.kind == "flamer" else 11)
		if enemy != null and (unit.position.distance_to(enemy.position) > (5.5 if unit.kind == "flamer" else 11) or not navigation.can_see(unit.position, enemy.position) or (enemy is SimPredator and light.sample(enemy.position) < 0.065)): enemy = null
		if enemy != null:
			unit.focus_target = enemy
			if unit.kind == "flamer":
				if not enemy is SimPredator: enemy.hp -= 18
				for other in creatures:
					if other.position.distance_to(enemy.position) < 2.7 and light.sample(other.position) > 0.065 and navigation.can_see(unit.position, other.position): other.hurt(18)
			else:
				if enemy is SimPredator: enemy.hurt(10)
				else: enemy.hp -= 10
			unit.cooldown = 0.85 if unit.kind == "flamer" else 0.65
			shot(unit.position + Vector3.UP * 1.2, enemy.position + Vector3.UP * 0.7, Color("f28a42") if unit.kind == "flamer" else AMBER, unit)
	turret_system.tick(self, _dt)
	for creature in creatures:
		var target := creature.target
		if creature.hp <= 0 or not SimEntity.valid(target) or target.hp <= 0 or creature.cooldown > 0 or creature.state not in ["probing", "assault", "hunting"]: continue
		if not director.attack_allowed(self, target): continue
		if target is SimUnit and target.aboard != null: continue
		if creature.position.distance_to(target.position) < 3 and navigation.can_see(creature.position, target.position):
			target.hp -= float(Rules.PREDATORS[creature.kind].damage); creature.cooldown = float(Rules.PREDATORS[creature.kind].attack_delay)
			shot(creature.position + Vector3.UP * 0.7, target.position + Vector3.UP, Color("d66b82"), creature)

func cleanup_dead() -> void:
	var changed := false
	for i in range(creatures.size() - 1, -1, -1):
		if creatures[i].hp <= 0:
			creatures[i].queue_free(); creatures.remove_at(i)
	for i in range(units.size() - 1, -1, -1):
		var unit := units[i]
		if unit.hp > 0: continue
		mission.drop(unit)
		complex_commands.interrupt(unit)
		if unit.is_vehicle():
			var occupants: Array[SimUnit] = unit.passengers.duplicate()
			if unit.has_driver(): occupants.push_front(unit.driver)
			for j in range(occupants.size()):
				unit.disembark(occupants[j], free_spawn(unit.position + Vector3(2 + j, 0, 1)))
				occupants[j].hp -= 30
			unit.update_light_state()
			wrecks.append({"node": unit, "life": 30.0})
		else:
			if SimEntity.valid(unit.aboard):
				var vehicle := unit.aboard
				vehicle.disembark(unit, vehicle.position)
			unit.queue_free()
		selected.erase(unit); units.remove_at(i); notify("%s lost" % Rules.title(unit.kind))
	for i in range(structures.size() - 1, -1, -1):
		var b := structures[i]
		if b.hp > 0: continue
		if b == mission.beacon:
			b.hp = 1; b.complete = false; b.progress = 0; mission.extraction = 0; b.state_changed(); changed = true; continue
		selected.erase(b); structures.remove_at(i); b.queue_free(); changed = true
		notify("%s destroyed" % Rules.title(b.kind))
	if changed: rebuild_navigation(); economy.recalculate(structures); power.tick(structures, economy, 0)

func check_mission() -> void:
	if ended: return
	if not SimEntity.valid(core) or core.hp <= 0 or not structures.has(core): finish(false, "Command Center destroyed.")

func selected_vehicles() -> Array[SimUnit]:
	var result: Array[SimUnit] = []
	for actor in selected:
		if SimEntity.valid(actor) and actor is SimUnit and actor.is_vehicle() and actor.hp > 0: result.append(actor)
	return result

func toggle_auto_recharge() -> void:
	var vehicles_selected := selected_vehicles()
	if vehicles_selected.is_empty(): return
	var enable := not vehicles_selected.all(func(unit): return unit.auto_recharge)
	for vehicle in vehicles_selected: vehicle.auto_recharge = enable
	vehicles.tick(self, 0)

func selected_jeep() -> SimUnit:
	for actor in selected:
		if SimEntity.valid(actor) and actor is SimUnit and actor.is_vehicle() and actor.hp > 0: return actor
	return null

func selected_infantry() -> Array[SimUnit]:
	var result: Array[SimUnit] = []
	for actor in selected:
		if SimEntity.valid(actor) and actor is SimUnit and not actor.is_vehicle() and actor.aboard == null and actor.hp > 0: result.append(actor)
	return result

func selected_engineers() -> Array[SimUnit]:
	var result: Array[SimUnit] = []
	for unit in selected_infantry():
		if unit.kind == "engineer": result.append(unit)
	return result

func board_squad() -> void:
	var vehicle := selected_jeep()
	var infantry := selected_infantry()
	if vehicle == null and not infantry.is_empty(): vehicle = nearest_vehicle(infantry[0].position, true)
	if vehicle == null: notify("Select infantry or a vehicle with a free seat"); return
	complex_commands.interrupt(vehicle)
	vehicle.path.clear(); vehicle.order = "idle"
	if not infantry.is_empty():
		for unit in infantry: issue_order(unit, "board", vehicle.position, vehicle, append_command)
		return
	var seats := vehicle.seat_capacity() - vehicle.occupied_seats()
	for unit in units:
		if seats <= 0: break
		if not unit.is_vehicle() and unit.aboard == null and unit.hp > 0 and unit.position.distance_to(vehicle.position) < 24:
			issue_order(unit, "board", vehicle.position, vehicle, append_command); seats -= 1
	notify("First boarder drives; remaining seats carry passengers")

func unload() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	complex_commands.interrupt(vehicle); tactical_groups.interrupt(vehicle)
	vehicle.path.clear(); vehicle.order = "idle"
	if not vehicle.passengers.is_empty():
		var passengers: Array[SimUnit] = vehicle.passengers.duplicate()
		for i in range(passengers.size()): vehicle.disembark(passengers[i], free_spawn(vehicle.position + Vector3((i % 2) * 2 - 1, 0, 3 + i)))
		notify("Passengers dismounted / driver stays aboard; U again to unload driver")
	elif vehicle.has_driver():
		vehicle.disembark(vehicle.driver, free_spawn(vehicle.position + Vector3(2, 0, 2)))
		notify("Driver dismounted / headlights off; emergency beacon remains")
	# Keep the vehicle selected so a second U always acts on the same vehicle.

func load_nearest() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	var loaded := 0
	for unit in units:
		if not unit.is_vehicle() and unit.aboard == null and unit.position.distance_to(vehicle.position) < 5: loaded += transfer_cargo(unit, vehicle)
	notify("Collected %d carried resources from nearby personnel" % loaded)

func return_home() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	var receiver := find_receiver(vehicle.position, "minerals" if vehicle.cargo > 0 else "gas", true)
	if receiver != null: issue_order(vehicle, "deliver", receiver.position, receiver, append_command)

func stock_depot() -> void:
	var vehicle := selected_jeep()
	if vehicle == null: return
	var receiver := find_receiver(vehicle.position, "minerals" if vehicle.cargo > 0 else "gas")
	if receiver != null: issue_order(vehicle, "stock", receiver.position, receiver, append_command)
	else: notify("Build a Material Depot or Methane Tank for that resource")

func escort() -> void:
	for actor in selected_infantry():
		var vehicle := nearest_vehicle(actor.position)
		if vehicle != null: issue_order(actor, "escort", vehicle.position, vehicle, append_command)

func destroy_selected() -> void:
	for actor in selected.duplicate():
		if actor is SimUnit or (actor is SimStructure and actor != mission.hive): actor.hp = 0
	cleanup_dead(); check_mission()

func toggle_repeater() -> void:
	for actor in selected:
		if actor is SimStructure and actor.kind == "repeater": actor.enabled = not actor.enabled
	power.tick(structures, economy, 0); rebuild_light()

func selected_turrets() -> Array[SimStructure]:
	var result: Array[SimStructure] = []
	for actor in selected:
		if actor is SimStructure and Rules.TURRETS.has(actor.kind): result.append(actor)
	return result

func reload_selected_turrets() -> void:
	var started_reload := 0
	for turret in selected_turrets():
		if turret_system.reload(self, turret): started_reload += 1
	notify("Reloading %d turrets" % started_reload if started_reload > 0 else "Reload requires an operating ammunition turret and sufficient reserves")

func toggle_turret_reload() -> void:
	var turrets := selected_turrets()
	if turrets.is_empty(): return
	var enable := not turrets[0].auto_reload
	for turret in turrets: turret.auto_reload = enable

func stop_selected() -> void:
	for actor in selected:
		if actor is SimUnit and actor.aboard == null:
			complex_commands.interrupt(actor); tactical_groups.interrupt(actor)
			actor.path.clear(); actor.order_queue.clear(); actor.combat_target = null
			actor.order = "idle"
			actor.target = null

func nearest_vehicle(point: Vector3, free_seat: bool = false) -> SimUnit:
	var result: SimUnit
	var distance := INF
	for unit in units:
		if not unit.is_vehicle() or unit.hp <= 0 or (free_seat and unit.occupied_seats() >= unit.seat_capacity()): continue
		var candidate := point.distance_to(unit.position)
		if candidate < distance: distance = candidate; result = unit
	return result

func free_spawn(anchor: Vector3) -> Vector3:
	for radius in [3.5, 5.0, 7.0]:
		for i in range(12):
			var point: Vector3 = anchor + Vector3(cos(i * TAU / 12), 0, sin(i * TAU / 12)) * float(radius)
			if not Terrain.contains(point, 1) or navigation.blocked(navigation.terrain.surface(point)): continue
			var clear := true
			for unit in units:
				if unit.aboard == null and unit.position.distance_to(point) < (3.0 if unit.is_vehicle() else 1.1): clear = false; break
			if clear: return navigation.terrain.surface(point)
	return navigation.graph.get_point_position(navigation.graph.get_closest_point(anchor))

func resource_at(point: Vector3) -> Dictionary:
	var cell := Hex.to_axial(point, Terrain.CELL)
	for resource in resource_nodes:
		if Hex.to_axial(resource.position, Terrain.CELL) == cell: return resource
	return {}

func process_harvest(unit: SimUnit, dt: float) -> void:
	if unit.cargo_total() >= unit.capacity:
		var carrier := nearest_vehicle(unit.position)
		if carrier != null and carrier.position.distance_to(unit.position) < 8 and carrier.cargo_total() < carrier.capacity: set_order(unit, "to_carrier", carrier.position, carrier)
		else: send_to_receiver(unit)
		return
	if not resource_fields.within_reach(unit, unit.harvest_origin):
		if not unit.moving(): unit.travel(unit.harvest_origin, navigation)
		return
	unit.path.clear(); unit.work_clock += dt
	if unit.work_clock < 0.7: return
	unit.work_clock -= 0.7
	var resource := resource_at(unit.harvest_origin)
	if resource.is_empty() or int(resource.remaining) <= 0:
		if unit.cargo_total() > 0: send_to_receiver(unit)
		else: unit.order = "idle"
		return
	resource_fields.harvest(self, unit, resource)

func transfer_cargo(source: SimUnit, target: SimUnit) -> int:
	var available := target.capacity - target.cargo_total()
	var minerals := mini(available, source.cargo)
	var mined := mini(minerals, source.mined_cargo)
	available -= minerals
	var gas := mini(available, source.gas_cargo)
	source.cargo -= minerals; source.mined_cargo -= mined; source.gas_cargo -= gas
	target.cargo += minerals; target.mined_cargo += mined; target.gas_cargo += gas
	return minerals + gas

func find_receiver(point: Vector3, resource: String, home_only: bool = false) -> SimStructure:
	var result: SimStructure
	var distance := INF
	for b in structures:
		if not b.complete or b.hp <= 0 or b.kind not in ["core", "depot" if resource == "minerals" else "gas_tank"]: continue
		if home_only and b.position.distance_to(HOME) > 16: continue
		var candidate := point.distance_to(b.position)
		if candidate < distance: distance = candidate; result = b
	return result

func send_to_receiver(unit: SimUnit) -> void:
	var receiver := find_receiver(unit.position, "minerals" if unit.cargo > 0 else "gas")
	if receiver != null: set_order(unit, "deposit", receiver.position, receiver)
	else: unit.path.clear(); notify("No receiving structure for carried resources")

func deposit_cargo(unit: SimUnit, receiver: SimStructure) -> void:
	if not receiver.complete: return
	if receiver.kind in ["depot", "core"]:
		var accepted: int = economy.deposit("minerals", unit.cargo)
		var mined := mini(accepted, unit.mined_cargo)
		unit.cargo -= accepted; unit.mined_cargo -= mined
		if receiver.position.distance_to(HOME) < 16: returned_materials += mined
	if receiver.kind in ["gas_tank", "core"]:
		var accepted: int = economy.deposit("gas", unit.gas_cargo)
		unit.gas_cargo -= accepted
	# Mixed cargo proceeds to the other appropriate receiving structure.
	if unit.cargo_total() > 0:
		var next := cargo_receiver(unit, unit.order == "deliver")
		if next != null and next != receiver:
			unit.target = next
			if unit.aboard == null: unit.travel(next.position, navigation)
		elif next == null: unit.path.clear()

func cargo_receiver(unit: SimUnit, home_only: bool = false) -> SimStructure:
	var result: SimStructure
	var distance := INF
	for kind in ["minerals", "gas"]:
		if (unit.cargo if kind == "minerals" else unit.gas_cargo) <= 0 or economy.space(kind) <= 0: continue
		var receiver := find_receiver(unit.position, kind, home_only)
		if receiver != null and unit.position.distance_to(receiver.position) < distance:
			result = receiver; distance = unit.position.distance_to(receiver.position)
	return result

func selected_factory() -> SimStructure:
	for actor in selected:
		if actor is SimStructure and actor.complete and actor.kind in ["barracks", "garage", "core"]: return actor
	return null

func selected_gate() -> SimStructure:
	for actor in selected:
		if actor is SimStructure and actor.complete and actor.kind == "gate": return actor
	return null

func train_unit(kind: String) -> bool:
	if not Rules.UNITS.has(kind): return false
	var factory := selected_factory()
	if factory == null or not Rules.PRODUCTION[factory.kind].has(kind): notify("Select HQ for engineers/scouts, Barracks for infantry, or Garage for vehicles"); return false
	if factory.queue.size() >= 5: notify("Production queue is full"); return false
	if not economy.spend(Rules.cost(kind)): notify("Insufficient global materials or methane"); return false
	factory.queue.append(kind); notify("%s queued" % Rules.title(kind)); return true

func cancel_training() -> void:
	var factory := selected_factory()
	if factory == null or factory.queue.is_empty(): return
	var kind: String = factory.queue.pop_back()
	economy.minerals += int(Rules.cost(kind).minerals); economy.gas += float(Rules.cost(kind).gas)
	if factory.queue.is_empty(): factory.production_progress = 0

func cost_label(kind: String) -> String:
	var cost := Rules.cost(kind)
	return "%d MAT%s" % [cost.minerals, " + %d CH4" % cost.gas if int(cost.gas) > 0 else ""]

func set_gate(gate: SimStructure, opened: bool, manual: bool = false, automatic: bool = false) -> bool:
	if gate.kind != "gate" or not gate.complete: return false
	if gate.gate_open == opened:
		if not automatic: gate.gate_auto_opened = false
		return true
	if opened and gate.gate_locked: notify("Gate is locked / K unlocks it"); return false
	if opened and not gate.powered: notify("Gate requires a powered grid to open"); return false
	if not opened:
		if not gate.powered:
			var worker := false
			for unit in units:
				if unit.kind == "engineer" and unit.aboard == null and unit.position.distance_to(gate.position) < 4: worker = true
			if not manual or not worker: return false
		for unit in units:
			if unit.aboard == null and unit.position.distance_to(gate.position) < 2.1: notify("Gate obstructed by personnel or a vehicle"); return false
		for creature in creatures:
			if creature.position.distance_to(gate.position) < 2.1: return false
	gate.gate_open = opened; gate.gate_auto_opened = automatic and opened; gate.gate_clear_time = 0
	gate.state_changed(); rebuild_navigation(); return true

func toggle_gate_lock() -> void:
	var gate := selected_gate()
	if gate == null: return
	if not gate.gate_locked and gate.gate_open and not set_gate(gate, false): return
	gate.gate_locked = not gate.gate_locked; gate.gate_auto_opened = false
	rebuild_navigation()

func toggle_gate() -> void:
	var gate := selected_gate()
	if gate == null: return
	if gate.gate_open and not gate.powered:
		var engineer: SimUnit
		var distance := 16.0
		for unit in units:
			if unit.kind == "engineer" and unit.aboard == null and unit.position.distance_to(gate.position) < distance: engineer = unit; distance = unit.position.distance_to(gate.position)
		if engineer != null: set_order(engineer, "close_gate", gate.position, gate)
		else: notify("Bring an engineer to manually close the gate")
	else: set_gate(gate, not gate.gate_open)

func report_activity(point: Vector3) -> void:
	for b in structures:
		if b.kind == "scanner" and b.complete and b.powered and point.distance_to(b.position) < 28: sensor_activity = 14
	for unit in units:
		if unit.kind == "scout" and unit.hp > 0 and unit.has_driver() and point.distance_to(unit.position) < 28: sensor_activity = 14

func contextual_order(point: Vector3, actor: SimEntity = null, append: bool = false) -> void:
	if not append:
		for member in selected:
			if member is SimUnit: member.order_queue.clear()
	var resource := resource_at(point) if actor == null else {}
	if not append and actor is SimUnit and complex_commands.join_member(self, selected, actor):
		return
	if not append and actor == null and complex_commands.join_resource(self, selected, resource):
		return
	# Only an explicit resource order can retask an expedition implicitly. A plain
	# terrain right-click is a direct move and permanently interrupts auto-scouting.
	if not append and actor == null and not resource.is_empty() and resource.discovered and resource.remaining > 0 and selected.any(func(unit): return complex_commands.is_expedition(unit)):
		complex_commands.start_expedition(self, complex_commands.expedition_selection(selected), resource, point)
		return
	var mixed_crew := selected.any(func(unit): return unit is SimUnit and not unit.is_vehicle() and unit.aboard == null)
	if not append and mixed_crew and actor != mission.hive and actor != mission.beacon and (actor == null or actor is SimStructure) and complex_commands.start(self, selected, {}, actor as SimStructure, point):
		return
	var index := 0
	for unit in selected:
		if not SimEntity.valid(unit) or not selected.has(unit) or not unit is SimUnit or unit.aboard != null: continue
		if actor == mission.hive or (not SimEntity.valid(mission.carrier) and point.distance_to(mission.item.position) < 3 and (mission.dropped or mission.hive.hp <= 0)):
			if not unit.is_vehicle(): issue_order(unit, "take_core", mission.item.position, null, append)
		elif actor is SimPredator and unit.kind in ["marine", "flamer"]: issue_order(unit, "attack", actor.position, actor, append)
		elif actor is SimUnit and actor.is_vehicle() and not unit.is_vehicle(): issue_order(unit, "board", actor.position, actor, append)
		elif actor is SimStructure and unit.kind == "engineer" and actor.kind == "gate" and actor.gate_open and not actor.powered:
			issue_order(unit, "close_gate", actor.position, actor, append)
		elif actor is SimStructure and unit.kind == "engineer" and (not actor.complete or actor.hp < float(Rules.STRUCTURES[actor.kind].hp)):
			issue_order(unit, "build" if not actor.complete else "repair", actor.position, actor, append)
		elif actor is SimStructure and actor.kind in ["depot", "gas_tank", "core"]:
			issue_order(unit, "stock", actor.position, actor, append)
		elif not resource.is_empty() and resource.discovered and unit.kind == "engineer":
			issue_order(unit, "harvest", resource.position, null, append)
		else:
			var offset := Vector3((index % 3 - 1) * 1.5, 0, (index / 3) * 1.5) if selected.size() > 1 else Vector3.ZERO
			if actor is SimUnit and actor != unit: issue_order(unit, "escort", point + offset, actor, append)
			else: issue_order(unit, "move", point + offset, actor, append)
			index += 1


func record_exploration() -> void:
	# The HUD and expeditions can ask during the same tick. Survey an unchanged
	# light field only once, and never resample already charted cells.
	var field_hash := hash(light.sources)
	if survey_revision == navigation.revision and survey_hash == field_hash and survey_count == explored.size(): return
	if survey_revision != navigation.revision:
		survey_revision = navigation.revision
		for cell in navigation.cells:
			var point: Vector3 = navigation.friendly_graph.get_point_position(navigation.cells[cell])
			survey_points[cell] = point
			survey_types[cell] = "cliff" if navigation.solid_cells.has(cell) else "raised" if point.y > 2.9 else "ramp" if point.y > 0.1 else "ground"
			if explored.has(cell): explored[cell] = survey_types[cell]
	var exposure: Dictionary = {}
	for source in light.sources:
		var center := Hex.to_axial(source.position, Terrain.CELL)
		var reach := ceili(float(source.radius) / (Terrain.CELL * 1.5)) + 1
		for q in range(-reach, reach + 1):
			for r in range(maxi(-reach, -q - reach), mini(reach, -q + reach) + 1):
				var cell := center + Vector2i(q, r)
				if explored.has(cell) or not survey_points.has(cell): continue
				var strength: float = light.source_strength(survey_points[cell], source)
				if strength <= 0: continue
				var total: float = float(exposure.get(cell, 0.0)) + strength
				if total > 0.05: explored[cell] = survey_types[cell]
				else: exposure[cell] = total
	survey_hash = field_hash; survey_count = explored.size()

func scouting_percent() -> float:
	return 100.0 * explored.size() / maxi(1, navigation.cells.size())
