extends RefCounted
## Derived movement data. Never serialized; rebuilt after restore and membership changes.
const S := 1024

class Body:
	extends RefCounted
	var actor: Dictionary
	var id: int
	var owner: int
	var radius: int
	var q: int
	var r: int
	var vq: int
	var vr: int
	var bucket: Vector2i

class Group:
	extends RefCounted
	var buckets: Dictionary = {}
	var max_radius := 0

var bodies: Dictionary[int, Body] = {}
var groups: Dictionary[int, Group] = {}
var owners: Array[int] = []

@warning_ignore("integer_division")
static func coordinate(value: int) -> int:
	return value / (2 * S) - (1 if value < 0 and value % (2 * S) != 0 else 0)

func rebuild(actors: Array, definitions: Dictionary, velocities: Dictionary) -> void:
	bodies.clear(); groups.clear(); owners.clear()
	for actor: Dictionary in actors:
		var definition: Dictionary = definitions[actor.definition]
		if int(actor.hp) <= 0 or not definition.capabilities.has("move"): continue
		var body := Body.new()
		body.actor = actor; body.id = int(actor.id); body.owner = int(actor.owner)
		body.radius = int(round(float(definition.get("collision_radius", 0.2)) * S))
		body.q = int(actor.position[0]); body.r = int(actor.position[2])
		var velocity: Array = velocities.get(str(body.id), actor.get("velocity", [0, 0, 0]))
		body.vq = int(velocity[0]); body.vr = int(velocity[2])
		body.bucket = Vector2i(coordinate(body.q), coordinate(body.r))
		bodies[body.id] = body
		if not groups.has(body.owner):
			groups[body.owner] = Group.new()
			owners.append(body.owner)
		var group: Group = groups[body.owner]
		group.max_radius = maxi(group.max_radius, body.radius)
		if not group.buckets.has(body.bucket): group.buckets[body.bucket] = []
		group.buckets[body.bucket].append(body)
	owners.sort()

func moved(actor: Dictionary) -> void:
	var body: Body = bodies.get(int(actor.id))
	if body == null: return
	body.q = int(actor.position[0]); body.r = int(actor.position[2])
	var key := Vector2i(coordinate(body.q), coordinate(body.r))
	if key == body.bucket: return
	var group: Group = groups[body.owner]
	group.buckets[body.bucket].erase(body)
	if not group.buckets.has(key): group.buckets[key] = []
	group.buckets[key].append(body)
	body.bucket = key

@warning_ignore("integer_division")
func query(owner: int, q: int, r: int, reach: int, scan_limit: int = 0, offset: int = 0) -> Array[Body]:
	var result: Array[Body] = []
	var group: Group = groups.get(owner)
	if group == null: return result
	var radius := reach + group.max_radius
	var extent := (radius * 1183 + 1023) / 1024 + 2
	var center_q := coordinate(q); var center_r := coordinate(r)
	var min_q := coordinate(q - extent); var max_q := coordinate(q + extent)
	var min_r := coordinate(r - extent); var max_r := coordinate(r + extent)
	var span := maxi(maxi(center_q - min_q, max_q - center_q), maxi(center_r - min_r, max_r - center_r))
	var scanned := 0
	for ring in range(span + 1):
		for bq in range(maxi(min_q, center_q - ring), mini(max_q, center_q + ring) + 1):
			for br in range(maxi(min_r, center_r - ring), mini(max_r, center_r + ring) + 1):
				if maxi(absi(bq - center_q), absi(br - center_r)) != ring: continue
				var bucket: Array = group.buckets.get(Vector2i(bq, br), [])
				for i in bucket.size():
					var other: Body = bucket[(i + offset) % bucket.size()]
					scanned += 1
					var dq := q - other.q; var dr := r - other.r
					if int(other.actor.hp) > 0 and dq * dq + dq * dr + dr * dr <= radius * radius: result.append(other)
					if scan_limit > 0 and scanned >= scan_limit: return result
	return result

func hostiles(owner: int, q: int, r: int, reach: int, scan_limit: int = 0, offset: int = 0) -> Array[Body]:
	var result: Array[Body] = []
	for other in owners:
		if other == owner: continue
		var remaining := maxi(1, scan_limit - result.size()) if scan_limit > 0 else 0
		result.append_array(query(other, q, r, reach, remaining, offset))
		if scan_limit > 0 and result.size() >= scan_limit: break
	return result

@warning_ignore("integer_division")
static func contact_clear(body: Body, q: int, r: int, enemies: Array[Body]) -> bool:
	var vq := q - body.q; var vr := r - body.r
	var length := vq * vq + vq * vr + vr * vr
	for enemy in enemies:
		var eq := enemy.q - body.q; var er := enemy.r - body.r
		var limit := body.radius + enemy.radius + 2
		var start := eq * eq + eq * er + er * er
		var closest := start
		if length > 0:
			var dot2 := 2 * eq * vq + eq * vr + er * vq + 2 * er * vr
			var t := clampi(dot2 * 1048576 / (2 * length), 0, 1048576)
			var dq := eq - vq * t / 1048576; var dr := er - vr * t / 1048576
			closest = dq * dq + dq * dr + dr * dr
		if closest > limit * limit: continue
		var end_q := eq - vq; var end_r := er - vr
		if start < limit * limit and end_q * end_q + end_q * end_r + end_r * end_r > start and closest >= start: continue
		return false
	return true
