extends RefCounted
## Gentle render-frame separation. Units remain traversable, never solid obstacles.
var velocities: Dictionary = {}
const BUCKET_SIZE := 4.0 # Largest interaction: two jeeps plus the passing margin, 3.82m.

func radius(unit: ExpeditionUnit) -> float:
	return 1.35 if unit.kind == "jeep" else 0.9 if unit.kind == "scout" else 0.48

func mobility(unit: ExpeditionUnit) -> float:
	if unit.is_vehicle(): return 0.0 if not unit.has_driver() else 0.3
	return 0.4 if unit.order in ["build", "repair", "harvest", "close_gate"] and not unit.moving() else 1.0

func apply(units: Array, navigation: RefCounted, dt: float) -> void:
	var active: Array[ExpeditionUnit] = []
	var forces: Array[Vector3] = []
	var live: Dictionary = {}
	var buckets: Dictionary = {}
	for unit in units:
		if unit.hp <= 0 or unit.aboard != null: continue
		active.append(unit); forces.append(Vector3.ZERO); live[unit.get_instance_id()] = true
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
		for x in range(-1, 2):
			for z in range(-1, 2): neighbors.append_array(buckets.get(cell + Vector2i(x, z), []))
		for j: int in neighbors:
			if j <= i: continue
			var b := active[j]
			var desired := radius(a) + radius(b) + 0.12
			var delta := a.position - b.position; delta.y = 0
			if delta.length_squared() > (desired + 1.0) * (desired + 1.0): continue
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
			if a.motion_velocity.length_squared() > 0.1 and b.motion_velocity.length_squared() > 0.1 and a.motion_velocity.normalized().dot(b.motion_velocity.normalized()) < -0.6:
				# Oncoming traffic tries passing on its own right before overlapping.
				var strength := clampf((desired + 1.0 - distance) / (desired + 1.0), 0, 1) * 1.4
				forces[i] += a.motion_velocity.normalized().cross(Vector3.UP) * strength * ma / (ma + mb)
				forces[j] += b.motion_velocity.normalized().cross(Vector3.UP) * strength * mb / (ma + mb)
	for i in range(active.size()):
		var unit := active[i]
		var id := unit.get_instance_id()
		if mobility(unit) <= 0: velocities[id] = Vector3.ZERO; continue
		var desired_velocity := forces[i].limit_length(1.0 if unit.is_vehicle() else 2.2)
		var previous: Vector3 = velocities.get(id, Vector3.ZERO)
		var velocity := previous.lerp(desired_velocity, 1.0 - exp(-dt * 12))
		if velocity.length_squared() < 0.00001: velocity = Vector3.ZERO
		velocities[id] = velocity
		var offset := velocity * dt
		if offset.length_squared() < 0.0000001: continue
		var destination := unit.position + offset
		if not navigation.terrain.contains(destination): continue
		if navigation.clear_segment(unit.position, destination) and not navigation.blocked(destination): unit.position = destination
		else:
			for slide in [Vector3(offset.x, 0, 0), Vector3(0, 0, offset.z)]:
				destination = unit.position + slide
				if not navigation.blocked(destination) and navigation.clear_segment(unit.position, destination): unit.position = destination
