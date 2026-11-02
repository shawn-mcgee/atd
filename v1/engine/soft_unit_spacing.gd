extends RefCounted
## Anticipatory sidestepping and overlap recovery; allies never block routes.
var velocities: Dictionary = {}
const BUCKET_SIZE := 12.0
const LOOKAHEAD := 1.4

func radius(unit: SimUnit) -> float:
	return 1.35 if unit.kind == "jeep" else 0.9 if unit.kind == "scout" else 0.48

func mobility(unit: SimUnit) -> float:
	if unit.is_vehicle(): return 0.0 if not unit.has_driver() else 0.3
	return 0.4 if unit.order in ["build", "repair", "harvest", "close_gate"] and not unit.moving() else 1.0

func can_yield(unit: SimUnit) -> bool:
	return not unit.is_vehicle() and not unit.moving() and unit.order in ["idle", "move"]

func arrival_point(unit: SimUnit, point: Vector3, units: Array, navigation: RefCounted) -> Vector3:
	var claims: Array[SimUnit] = []; var largest := radius(unit)
	for other: SimUnit in units:
		if other == unit or other.hp <= 0 or other.aboard != null or other.order != "move": continue
		claims.append(other); largest = maxf(largest, radius(other))
	if arrival_clear(unit, point, claims): return point
	var toward := unit.position - point
	var angle := atan2(toward.z, toward.x) if toward.length_squared() > 0.01 else unit.formation_slot * 2.4
	var spacing := maxf(1.5, radius(unit) + largest + 0.3)
	for ring in range(1, 4):
		for i in range(12):
			var heading := angle + i * TAU / 12
			var candidate: Vector3 = navigation.terrain.surface(point + Vector3(cos(heading), 0, sin(heading)) * spacing * ring)
			if navigation.blocked(candidate) or not arrival_clear(unit, candidate, claims): continue
			var route: PackedVector3Array = navigation.path(unit.position, candidate)
			if not route.is_empty() and route[-1].distance_to(candidate) < 0.3: return candidate
	return point

func arrival_clear(unit: SimUnit, point: Vector3, claims: Array[SimUnit]) -> bool:
	for other in claims:
		if absf(point.y - other.goal.y) > 0.6: continue
		if point.distance_to(other.goal) < radius(unit) + radius(other) + 0.25: return false
	return true

func allows_offset(unit: SimUnit, offset: Vector3, navigation: RefCounted) -> bool:
	var point: Vector3 = navigation.terrain.surface(unit.position + offset)
	if navigation.blocked(point) or not navigation.clear_segment(unit.position, point): return false
	# Never leave a valid terrain route on the wrong side of a wall or cliff.
	return not unit.moving() or navigation.clear_segment(point, unit.path[unit.path_index], true)

func suggest_passing(a: SimUnit, b: SimUnit, navigation: RefCounted, desired: float) -> Array[Vector3]:
	var relative := a.motion_velocity - b.motion_velocity; relative.y = 0
	var offset := b.position - a.position; offset.y = 0
	var squared := relative.length_squared()
	if squared < 0.01 or offset.dot(relative) <= 0: return [Vector3.ZERO, Vector3.ZERO]
	var time := offset.dot(relative) / squared
	if time > LOOKAHEAD or (offset - relative * time).length_squared() >= desired * desired: return [Vector3.ZERO, Vector3.ZERO]
	var ma := mobility(a) if a.moving() or can_yield(a) else 0.0
	var mb := mobility(b) if b.moving() or can_yield(b) else 0.0
	if a.target == b: mb = 0
	if b.target == a: ma = 0
	var side := relative.normalized().cross(Vector3.UP)
	if side.dot(offset) > 0.001: side = -side
	var side_b := -side
	var probe := minf(desired, 2.5)
	if ma > 0 and not allows_offset(a, side * probe, navigation):
		if allows_offset(a, -side * probe, navigation): side = -side
		else: ma = 0
	if mb > 0 and not allows_offset(b, side_b * probe, navigation):
		if allows_offset(b, -side_b * probe, navigation): side_b = -side_b
		else: mb = 0
	if ma + mb <= 0: return [Vector3.ZERO, Vector3.ZERO]
	var strength := 8.0 * clampf(1.2 - time / LOOKAHEAD, 0, 1)
	return [side * strength * ma / (ma + mb), side_b * strength * mb / (ma + mb)]

func apply(units: Array, navigation: RefCounted, dt: float) -> void:
	var active: Array[SimUnit] = []
	var forces: Array[Vector3] = []
	var live: Dictionary = {}
	var buckets: Dictionary = {}
	var maximum_speed := 0.0
	for unit in units:
		if unit.hp <= 0 or unit.aboard != null: continue
		active.append(unit); forces.append(Vector3.ZERO); live[unit.simulation_id] = true
		maximum_speed = maxf(maximum_speed, unit.motion_velocity.length())
	for id in velocities.keys():
		if not live.has(id): velocities.erase(id)
	for i in range(active.size()):
		var cell := Vector2i(floori(active[i].position.x / BUCKET_SIZE), floori(active[i].position.z / BUCKET_SIZE))
		if not buckets.has(cell): buckets[cell] = []
		buckets[cell].append(i)
	for i in range(active.size()):
		var a := active[i]
		var cell := Vector2i(floori(a.position.x / BUCKET_SIZE), floori(a.position.z / BUCKET_SIZE))
		var neighbors: Array = []
		var span := ceili((radius(a) + 1.35 + (a.motion_velocity.length() + maximum_speed) * LOOKAHEAD + 0.2) / BUCKET_SIZE)
		for x in range(-span, span + 1):
			for z in range(-span, span + 1): neighbors.append_array(buckets.get(cell + Vector2i(x, z), []))
		for j: int in neighbors:
			if j <= i: continue
			var b := active[j]
			if absf(a.position.y - b.position.y) > 0.6: continue
			var desired := radius(a) + radius(b) + 0.12
			var delta := a.position - b.position; delta.y = 0
			var reach := desired + (a.motion_velocity - b.motion_velocity).length() * LOOKAHEAD
			if delta.length_squared() > reach * reach: continue
			var passing := suggest_passing(a, b, navigation, desired)
			forces[i] += passing[0]; forces[j] += passing[1]
			var distance := delta.length()
			var ma := mobility(a); var mb := mobility(b)
			if ma + mb <= 0: continue
			if distance < desired:
				var direction: Vector3
				if distance > 0.001: direction = delta / distance
				else:
					var angle := float((a.formation_slot * 31 + b.formation_slot * 17 + 7) % 360) * PI / 180
					direction = Vector3(cos(angle), 0, sin(angle))
				var strength := (desired - distance) / desired * 4.0
				forces[i] += direction * strength * ma / (ma + mb)
				forces[j] -= direction * strength * mb / (ma + mb)
	for i in range(active.size()):
		var unit := active[i]
		var id := unit.simulation_id
		if mobility(unit) <= 0: velocities[id] = Vector3.ZERO; continue
		var desired_velocity := forces[i].limit_length((1.8 if unit.moving() else 1.0) if unit.is_vehicle() else 2.2)
		var previous: Vector3 = velocities.get(id, Vector3.ZERO)
		if not unit.moving() and not can_yield(unit): previous = previous.limit_length(desired_velocity.length())
		var velocity := previous.lerp(desired_velocity, 1.0 - exp(-dt * 12))
		if velocity.length_squared() < 0.00001: velocity = Vector3.ZERO
		velocities[id] = velocity
		var offset := velocity * dt
		var previous_position := unit.position - unit.motion_velocity * dt
		if unit.moving():
			var speed := minf(float(unit.STATS[unit.kind].speed), unit.escort_speed_limit)
			offset = ((unit.motion_velocity + velocity).limit_length(speed) - unit.motion_velocity) * dt
		if offset.length_squared() < 0.0000001: continue
		if not allows_offset(unit, offset, navigation): continue
		unit.position += offset
		if dt > 0: unit.motion_velocity = (unit.position - previous_position) / dt
		if not unit.moving():
			unit.desired_yaw = atan2(-velocity.x, -velocity.z); unit.turn(dt)
