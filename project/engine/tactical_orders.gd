extends RefCounted
const LEASH := 8.0

func issue(game, unit: SimUnit, order: String, point: Vector3, target: SimEntity = null, append: bool = false) -> bool:
	if unit.aboard != null: return false
	if append and order == "patrol" and unit.order == "patrol":
		var route: PackedVector3Array = game.navigation.path(unit.patrol_points[-1], point)
		if route.is_empty(): return false
		unit.patrol_points.append(route[-1]); return true
	if append and order == "patrol" and not unit.order_queue.is_empty() and unit.order_queue[-1].order == "patrol":
		if not unit.order_queue[-1].has("extra_points"): unit.order_queue[-1].extra_points = []
		unit.order_queue[-1].extra_points.append(point); return true
	var command := {"order": order, "point": point, "target": weakref(target) if target != null else null}
	if append and (unit.order != "idle" or unit.moving()):
		unit.order_queue.append(command); return true
	unit.order_queue.clear()
	return begin(game, unit, command)

func begin(game, unit: SimUnit, command: Dictionary) -> bool:
	var target: SimEntity = command.target.get_ref() if command.target != null else null
	if command.target != null and (not SimEntity.valid(target) or target.hp <= 0): return false
	unit.combat_target = null; unit.patrol_points.clear()
	unit.combat_last_seen = target.position if SimEntity.valid(target) else command.point
	unit.defense_point = command.point
	if command.order == "patrol":
		unit.patrol_points.assign([unit.position, command.point]); unit.patrol_index = 1
		unit.patrol_points.append_array(command.get("extra_points", []))
	if command.order == "harvest":
		var resource: Dictionary = game.resource_at(command.point)
		if resource.is_empty(): return false
		unit.harvest_origin = resource.position; unit.harvest_kind = resource.kind
	var accepted: bool = game.set_order(unit, command.order, command.point, target)
	if accepted and command.order in ["attack_move", "patrol"]:
		unit.defense_point = unit.path[-1]
		if command.order == "patrol": unit.patrol_points[1] = unit.path[-1]
	return accepted

func tick(game, dt: float) -> void:
	for unit in game.units:
		if unit.hp <= 0 or unit.aboard != null: continue
		advance_queue(game, unit)
		if unit.order not in ["attack", "attack_move", "defend", "patrol"]: continue
		if unit.kind not in ["marine", "flamer"]:
			if not unit.moving(): unit.order = "idle"
			continue
		if unit.order == "attack":
			if not valid(unit.target): finish(unit); continue
			unit.combat_target = unit.target
		else:
			if unit.order == "defend" and valid(unit.target): unit.defense_point = unit.target.position
			elif unit.order == "defend" and unit.target != null: unit.target = null
			var anchor: Vector3 = unit.defense_point if unit.order == "defend" else unit.patrol_points[unit.patrol_index] if unit.order == "patrol" else unit.defense_point
			if valid(unit.combat_target):
				if unit.order in ["defend", "patrol"] and unit.combat_target.position.distance_to(anchor) > LEASH: unit.combat_target = null
			if not valid(unit.combat_target):
				unit.combat_target = game.visible_target(unit.position, 14)
				if valid(unit.combat_target) and unit.order in ["defend", "patrol"] and unit.combat_target.position.distance_to(anchor) > LEASH: unit.combat_target = null
			if not valid(unit.combat_target):
				var destination: Vector3 = anchor
				if unit.order == "defend": destination += Vector3(cos(unit.formation_slot * 2.4), 0, sin(unit.formation_slot * 2.4)) * 3
				if unit.position.distance_to(destination) < 1:
					if unit.order == "attack_move": finish(unit)
					elif unit.order == "patrol": unit.patrol_index = (unit.patrol_index + 1) % unit.patrol_points.size(); unit.travel(unit.patrol_points[unit.patrol_index], game.navigation)
				elif not unit.moving() or unit.goal.distance_to(destination) > 1: unit.travel(destination, game.navigation)
				continue
		var enemy: SimEntity = unit.combat_target
		if not valid(enemy): continue
		var visible: bool = not enemy is SimPredator or game.light.sample(enemy.position) >= 0.065
		if not visible:
			unit.combat_target = null
			if unit.order == "attack":
				if unit.position.distance_to(unit.combat_last_seen) < 1: finish(unit)
				elif not unit.moving(): unit.travel(unit.combat_last_seen, game.navigation)
			continue
		unit.combat_last_seen = enemy.position
		var reach := 5.5 if unit.kind == "flamer" else 11.0
		if unit.position.distance_to(enemy.position) <= reach and game.navigation.can_see(unit.position, enemy.position): unit.path.clear()
		else:
			unit.work_clock -= dt
			if unit.work_clock <= 0: unit.travel(enemy.position, game.navigation); unit.work_clock = 0.5

func valid(actor) -> bool:
	return SimEntity.valid(actor) and actor.hp > 0

func advance_queue(game, unit: SimUnit) -> void:
	if unit.order == "idle" and unit.aboard == null and not unit.order_queue.is_empty():
		var command: Dictionary = unit.order_queue.pop_front()
		begin(game, unit, command)

func finish(unit: SimUnit) -> void:
	unit.order = "idle"; unit.target = null; unit.combat_target = null; unit.path.clear()
