extends RefCounted
## Derived movement data. Never serialized; rebuilt after restore and membership changes.
const S := 1024
const BUCKET_BITS := 11 # Two tiles; arithmetic shifts floor negative coordinates.

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
	var seen := 0

class Group:
	extends RefCounted
	var buckets: Dictionary = {}
	var windows: Dictionary[Vector2i, Dictionary] = {}
	var max_radius := 0
	var min_q := 9223372036854775807
	var max_q := -9223372036854775807
	var min_r := 9223372036854775807
	var max_r := -9223372036854775807

	func include(body: Body) -> void:
		min_q = mini(min_q, body.q); max_q = maxi(max_q, body.q)
		min_r = mini(min_r, body.r); max_r = maxi(max_r, body.r)

var bodies: Dictionary[int, Body] = {}
var groups: Dictionary[int, Group] = {}
var owners: Array[int] = []
var _query_offsets: Dictionary[int, Array] = {}
var backend: RefCounted
var _epoch := 0

func _init(accelerated: bool = true) -> void:
	if accelerated and ClassDB.class_exists("ATDMovementKernel"):
		var candidate = ClassDB.instantiate("ATDMovementKernel") as RefCounted
		if int(candidate.call("abi_version")) == 16: backend = candidate

@warning_ignore("integer_division")
static func coordinate(value: int) -> int:
	return value >> BUCKET_BITS

func rebuild(actors: Array, definitions: Dictionary, velocities: Dictionary) -> void:
	groups.clear(); owners.clear()
	_epoch += 1
	if backend != null:
		bodies.clear()
		backend.call("prepare_actors", actors, definitions, velocities)
		var ids: PackedInt64Array = backend.call("owner_ids")
		for owner in ids: owners.append(owner)
		return
	for actor: Dictionary in actors:
		var definition: Dictionary = definitions[actor.definition]
		if int(actor.hp) <= 0 or not definition.capabilities.has("move"): continue
		var id := int(actor.id)
		var body: Body = bodies.get(id)
		if body == null:
			body = Body.new(); bodies[id] = body
		body.seen = _epoch
		body.actor = actor; body.id = int(actor.id); body.owner = int(actor.owner)
		body.radius = int(round(float(definition.get("collision_radius", 0.2)) * S))
		body.q = int(actor.position[0]); body.r = int(actor.position[2])
		var velocity = velocities.get(body.id, actor.get("velocity", Vector3i.ZERO))
		body.vq = int(velocity[0]); body.vr = int(velocity[2])
		body.bucket = Vector2i(coordinate(body.q), coordinate(body.r))
		if not owners.has(body.owner): owners.append(body.owner)
		if not groups.has(body.owner): groups[body.owner] = Group.new()
		var group: Group = groups[body.owner]
		group.include(body)
		group.max_radius = maxi(group.max_radius, body.radius)
		if not group.buckets.has(body.bucket): group.buckets[body.bucket] = []
		group.buckets[body.bucket].append(body)
	owners.sort()
	for id in bodies.keys():
		if bodies[id].seen != _epoch: bodies.erase(id)

func body(id: int) -> Body:
	var found: Body = bodies.get(id)
	if found != null or backend == null: return found
	var row: Array = backend.call("body_info", id)
	if row.is_empty(): return null
	found = Body.new(); found.actor = row[0]; found.id = id
	found.owner = int(row[1]); found.radius = int(row[2]); found.q = int(row[3]); found.r = int(row[4])
	found.vq = int(row[5]); found.vr = int(row[6]); found.bucket = Vector2i(coordinate(found.q), coordinate(found.r))
	bodies[id] = found
	return found

func moved(actor: Dictionary, native_updated: bool = false) -> void:
	var body: Body = bodies.get(int(actor.id))
	if backend != null:
		if not native_updated: backend.call("moved", int(actor.id), Vector2i(int(actor.position[0]), int(actor.position[2])))
		if body != null:
			body.q = int(actor.position[0]); body.r = int(actor.position[2])
			body.bucket = Vector2i(coordinate(body.q), coordinate(body.r))
		return
	if body == null: return
	body.q = int(actor.position[0]); body.r = int(actor.position[2])
	var group: Group = groups[body.owner]
	# Conservative bounds expand between rebuilds, so no moving body is omitted.
	group.include(body)
	var key := Vector2i(coordinate(body.q), coordinate(body.r))
	if key == body.bucket: return
	group.buckets[body.bucket].erase(body)
	if not group.buckets.has(key): group.buckets[key] = []
	if group.buckets[key].is_empty(): group.windows.clear()
	group.buckets[key].append(body)
	body.bucket = key

@warning_ignore("integer_division")
func query(owner: int, q: int, r: int, reach: int, scan_limit: int = 0, offset: int = 0) -> Array[Body]:
	var result: Array[Body] = []
	if backend != null:
		var ids: PackedInt64Array = backend.call("query", PackedInt64Array([owner, q, r, reach, scan_limit, offset]))
		for id in ids:
			var found := body(id)
			if found != null and int(found.actor.hp) > 0: result.append(found)
		return result
	var group: Group = groups.get(owner)
	if group == null: return result
	var radius := reach + group.max_radius
	var extent := (radius * 1183 + 1023) / 1024 + 2
	if q + extent < group.min_q or q - extent > group.max_q or r + extent < group.min_r or r - extent > group.max_r: return result
	var center_q := q >> BUCKET_BITS; var center_r := r >> BUCKET_BITS
	var min_q := (q - extent) >> BUCKET_BITS; var max_q := (q + extent) >> BUCKET_BITS
	var min_r := (r - extent) >> BUCKET_BITS; var max_r := (r + extent) >> BUCKET_BITS
	var span := maxi(maxi(center_q - min_q, max_q - center_q), maxi(center_r - min_r, max_r - center_r))
	if not _query_offsets.has(span):
		var offsets: Array[Vector2i] = []
		for ring in range(span + 1):
			for bq in range(-ring, ring + 1):
				for br in range(-ring, ring + 1):
					if maxi(absi(bq), absi(br)) == ring: offsets.append(Vector2i(bq, br))
		_query_offsets[span] = offsets
	var center := Vector2i(center_q, center_r)
	var rectangle := Vector4i(min_q, min_r, max_q, max_r)
	if not group.windows.has(center): group.windows[center] = {}
	var windows: Dictionary = group.windows[center]
	if not windows.has(rectangle):
		var window: Array = []
		for delta: Vector2i in _query_offsets[span]:
			var bq := center_q + delta.x; var br := center_r + delta.y
			if bq < min_q or bq > max_q or br < min_r or br > max_r: continue
			var bucket: Array = group.buckets.get(Vector2i(bq, br), [])
			if not bucket.is_empty(): window.append(bucket)
		windows[rectangle] = window
	# Bucket arrays remain live as bodies move. Entering an empty bucket invalidates
	# windows; movement between included buckets only updates their shared contents.
	var scanned := 0
	for bucket: Array in windows[rectangle]:
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
