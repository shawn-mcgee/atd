extends RefCounted
## Local separation forces. Allies may yield/overlap; hostile contacts stay solid.
const Crowd = preload("res://core/crowd.gd")
const Hex = preload("res://core/hex_cells.gd")
const Nav = preload("res://core/navigation.gd")
const MAX_NEIGHBORS := 6

static func _native_legal(game, crowd: Crowd, body: Crowd.Body, point: Array, blocked: Dictionary, open_static: bool, reach: int) -> bool:
	return bool(crowd.backend.call("contact", body.id, Vector2i(int(point[0]), int(point[2])), reach)) and (open_static or Nav.segment_clear(game, body.actor.position, point, body.radius, blocked))

static func _choose_native(game, actor: Dictionary, intended: Array, speed: int, data: Dictionary, waypoint: Array, stop_range: int, crowd: Crowd, body: Crowd.Body) -> Array:
	var state: Dictionary = actor.avoidance
	var vq := int(intended[0]) - body.q; var vr := int(intended[2]) - body.r
	var length: int = game.integer_sqrt(vq * vq + vq * vr + vr * vr)
	if length == 0: return intended
	var hz := int(game.content.settings.tick_hz)
	var open_static := Nav.center_clear(game, Hex.from_point(actor.position), body.radius + speed + Hex.SCALE + 4, Nav.static_field(data))
	var reach := body.radius + length + 2
	var passing := int(state.get("pass_ticks", 0)) > 0
	state.pass_ticks = maxi(0, int(state.get("pass_ticks", 0)) - 1)
	var proposed: Vector2i = crowd.backend.call("preferred", body.id, Vector2i(vq, vr), Vector2i(int(waypoint[0]), int(waypoint[2])), speed, stop_range, hz, passing)
	var point := [proposed.x, 0, proposed.y]
	if _native_legal(game, crowd, body, point, data.blocked, open_static, reach):
		state.wait = 0
		return point
	if point != intended and _native_legal(game, crowd, body, intended, data.blocked, open_static, reach): return intended
	var side := int(state.get("side", 1))
	if side == 0: side = 1
	var perpendicular := _scaled(game, -vq - 2 * vr, 2 * vq + vr, length)
	for bend in [side * 8, side * 64, -side * 8, -side * 64]:
		var delta := _scaled(game, vq * 4 + int(perpendicular.x) * int(bend), vr * 4 + int(perpendicular.y) * int(bend), length)
		if absi(int(bend)) == 64: delta = Vector2i(int(perpendicular.x) * signi(int(bend)), int(perpendicular.y) * signi(int(bend)))
		point = [body.q + int(delta.x), 0, body.r + int(delta.y)]
		if not _native_legal(game, crowd, body, point, data.blocked, open_static, reach): continue
		state.side = signi(int(bend)); state.wait = 0
		return point
	state.wait = int(state.get("wait", 0)) + 1
	return actor.position

static func _separate_native(game, actor: Dictionary, crowd: Crowd, body: Crowd.Body) -> void:
	var distance := maxi(1, int(Hex.SCALE / int(game.content.settings.tick_hz) / 2))
	var pressure := int(crowd.backend.call("pressure", body.id, Vector2i(body.q, body.r)))
	if pressure == 0: return
	var data: Dictionary = game.navigation_field()
	if Nav.center_clear(game, Hex.from_point(actor.position), body.radius + distance + Hex.SCALE + 4, Nav.static_field(data)):
		if bool(crowd.backend.call("settle", actor, int(game.content.settings.tick_hz))):
			game.invalidate_unit_caches(body.owner)
			game.invalidate_light(actor)
			game.update_friendly(actor)
		return
	var best: Array = actor.position
	for direction in 6:
		var axis: Array = Hex.NEIGHBORS[(direction + body.id) % 6]
		var offset := _scaled(game, int(axis[0]), int(axis[1]), distance)
		var point := [body.q + int(offset.x), 0, body.r + int(offset.y)]
		if actor.avoidance.has("settled_goal") and game.distance_squared(point, actor.avoidance.settled_goal) > Hex.SCALE * Hex.SCALE: continue
		var score := int(crowd.backend.call("pressure", body.id, Vector2i(int(point[0]), int(point[2]))))
		if score < pressure and _native_legal(game, crowd, body, point, data.blocked, false, body.radius + distance + 2): pressure = score; best = point
	if best != actor.position:
		actor.velocity = [int(best[0]) - body.q, 0, int(best[2]) - body.r]
		game._face(actor, best)
		game.invalidate_unit_caches(body.owner)
		game.invalidate_light(actor)
		actor.position = best
		game.update_friendly(actor)

@warning_ignore("integer_division")
static func _scaled(game, q: int, r: int, length: int) -> Vector2i:
	var size: int = game.integer_sqrt(q * q + q * r + r * r)
	if size == 0: return Vector2i.ZERO
	return Vector2i(q * length / size, r * length / size)

static func _nearest(body: Crowd.Body, candidates: Array[Crowd.Body], reach: int) -> Array[Crowd.Body]:
	var entries: Array = []
	for other in candidates:
		if other.id == body.id: continue
		var q := body.q - other.q; var r := body.r - other.r
		var distance := q * q + q * r + r * r
		var limit := body.radius + other.radius + reach
		if distance < limit * limit: entries.append([distance, other.id, other])
	# Native lexicographic sorting avoids an interpreted insertion loop for each
	# candidate. IDs break every distance tie before the body object is reached.
	entries.sort()
	var result: Array[Crowd.Body] = []
	for i in mini(MAX_NEIGHBORS, entries.size()): result.append(entries[i][2])
	return result

static func _legal(game, body: Crowd.Body, point: Array, blocked: Dictionary, enemies: Array[Crowd.Body], open_static: bool) -> bool:
	return Crowd.contact_clear(body, int(point[0]), int(point[2]), enemies) and (open_static or Nav.segment_clear(game, body.actor.position, point, body.radius, blocked))

@warning_ignore("integer_division")
static func choose(game, actor: Dictionary, intended: Array, speed: int, data: Dictionary, waypoint: Array, stop_range: int = 0) -> Array:
	if intended == actor.position: return intended
	var crowd: Crowd = game.movement_crowd()
	var body: Crowd.Body = crowd.body(int(actor.id))
	if crowd.backend != null: return _choose_native(game, actor, intended, speed, data, waypoint, stop_range, crowd, body)
	var state: Dictionary = actor.avoidance
	var vq := int(intended[0]) - body.q; var vr := int(intended[2]) - body.r
	var length: int = game.integer_sqrt(vq * vq + vq * vr + vr * vr)
	if length == 0: return intended
	var hz := int(game.content.settings.tick_hz)
	var horizon := maxi(1, hz / 2)
	var open_static := Nav.center_clear(game, Hex.from_point(actor.position), body.radius + speed + Hex.SCALE + 4, Nav.static_field(data))
	# Hard contacts are never limited by the soft neighbor budget.
	var enemies := crowd.hostiles(body.owner, body.q, body.r, body.radius + length + 2)
	var reach := speed * horizon + Hex.SCALE
	var candidates := crowd.query(body.owner, body.q, body.r, body.radius + reach, 24, body.id)
	candidates.append_array(crowd.hostiles(body.owner, body.q, body.r, body.radius + reach, 24, body.id))
	var nearby := _nearest(body, candidates, reach)
	var passing := int(state.get("pass_ticks", 0)) > 0
	state.pass_ticks = maxi(0, int(state.get("pass_ticks", 0)) - 1)
	var horizon_distance: int = mini(length * horizon, maxi(length, game.integer_sqrt(game.distance_squared(actor.position, waypoint)) - stop_range))
	var prediction := _scaled(game, vq, vr, horizon_distance)
	var perpendicular := _scaled(game, -vq - 2 * vr, 2 * vq + vr, length)
	var force_q := 0; var force_r := 0
	for other in nearby:
		if passing and other.owner == body.owner: continue
		var q := body.q - other.q; var r := body.r - other.r
		var distance2 := q * q + q * r + r * r
		var limit := body.radius + other.radius + 32
		if distance2 < limit * limit:
			# Separate in world space, so a moving pair doesn't repeatedly take
			# the same angled detour. Exact coincidences get opposite pair forces.
			var distance: int = game.integer_sqrt(distance2)
			if distance == 0:
				var axis: Array = Hex.NEIGHBORS[(mini(body.id, other.id) * 17 + maxi(body.id, other.id) * 31) % 6]
				var sign_value := 1 if body.id < other.id else -1
				force_q += int(axis[0]) * length * sign_value
				force_r += int(axis[1]) * length * sign_value
			else:
				var strength := (limit - distance) * length * 2 / limit
				force_q += q * strength / distance; force_r += r * strength / distance
			continue
		var relative_q := int(prediction.x) - other.vq * horizon
		var relative_r := int(prediction.y) - other.vr * horizon
		# Co-moving allies need no passing maneuver unless they are closing.
		var closing := -2 * q * relative_q - q * relative_r - r * relative_q - 2 * r * relative_r
		if closing <= 0: continue
		var closest := _predicted_distance(-q, -r, relative_q, relative_r)
		if closest >= limit * limit: continue
		var cross := -vq * r + vr * q
		var side := -signi(cross) if cross != 0 else 1
		var weight := (limit * limit - closest) * 512 / (limit * limit)
		force_q += int(perpendicular.x) * side * weight / 1024
		force_r += int(perpendicular.y) * side * weight / 1024
	var point: Array = intended
	if force_q != 0 or force_r != 0:
		var q := vq + force_q; var r := vr + force_r
		# Retain at least half the intended forward component. Soft pressure
		# must not reverse friendly traffic or trap it in orbiting detours.
		var forward2 := 2 * q * vq + q * vr + r * vq + 2 * r * vr
		var minimum := vq * vq + vq * vr + vr * vr
		if forward2 < minimum:
			q += vq * (minimum - forward2) / (2 * minimum)
			r += vr * (minimum - forward2) / (2 * minimum)
		var size: int = game.integer_sqrt(q * q + q * r + r * r)
		var delta := _scaled(game, q, r, length) if size > length else Vector2i(q, r)
		point = [body.q + int(delta.x), 0, body.r + int(delta.y)]
	if _legal(game, body, point, data.blocked, enemies, open_static):
		state.wait = 0
		return point
	# Try forward before sliding around geometry; allies are never hard blockers.
	if point != intended and _legal(game, body, intended, data.blocked, enemies, open_static): return intended
	var side := int(state.get("side", 1))
	if side == 0: side = 1
	for bend in [side * 8, side * 64, -side * 8, -side * 64]:
		var delta := _scaled(game, vq * 4 + int(perpendicular.x) * int(bend), vr * 4 + int(perpendicular.y) * int(bend), length)
		if absi(int(bend)) == 64: delta = Vector2i(int(perpendicular.x) * signi(int(bend)), int(perpendicular.y) * signi(int(bend)))
		point = [body.q + int(delta.x), 0, body.r + int(delta.y)]
		if not _legal(game, body, point, data.blocked, enemies, open_static): continue
		state.side = signi(int(bend)); state.wait = 0
		return point
	state.wait = int(state.get("wait", 0)) + 1
	return actor.position

@warning_ignore("integer_division")
static func _predicted_distance(q: int, r: int, vq: int, vr: int) -> int:
	var length := vq * vq + vq * vr + vr * vr
	if length == 0: return q * q + q * r + r * r
	var dot2 := 2 * q * vq + q * vr + r * vq + 2 * r * vr
	if dot2 <= 0: return q * q + q * r + r * r
	if dot2 >= 2 * length:
		q -= vq; r -= vr
		return q * q + q * r + r * r
	var t := dot2 * 1048576 / (2 * length)
	q -= vq * t / 1048576; r -= vr * t / 1048576
	return q * q + q * r + r * r

@warning_ignore("integer_division")
static func _pressure(body: Crowd.Body, q: int, r: int, friends: Array[Crowd.Body]) -> int:
	var score := 0
	for other in friends:
		var limit := body.radius + other.radius
		var dq := q - other.q; var dr := r - other.r
		score += maxi(0, limit * limit - dq * dq - dq * dr - dr * dr) * 4096 / (limit * limit)
	return score

static func separate_idle(game, actor: Dictionary) -> void:
	var crowd: Crowd = game.movement_crowd()
	var body: Crowd.Body = crowd.body(int(actor.id))
	if crowd.backend != null:
		_separate_native(game, actor, crowd, body)
		return
	var distance := maxi(1, int(Hex.SCALE / int(game.content.settings.tick_hz) / 2))
	# Include every body that a settling step could touch. Decreasing this full
	# local pressure avoids cycling between changing nearest-neighbor subsets.
	var friends := crowd.query(body.owner, body.q, body.r, body.radius + distance)
	friends.erase(body)
	var pressure := _pressure(body, body.q, body.r, friends)
	if pressure == 0: return
	var data: Dictionary = game.navigation_field()
	var enemies := crowd.hostiles(body.owner, body.q, body.r, body.radius + distance + 2)
	var best: Array = actor.position
	for direction in 6:
		var axis: Array = Hex.NEIGHBORS[(direction + body.id) % 6]
		var offset := _scaled(game, int(axis[0]), int(axis[1]), distance)
		var point := [body.q + int(offset.x), 0, body.r + int(offset.y)]
		if actor.avoidance.has("settled_goal") and game.distance_squared(point, actor.avoidance.settled_goal) > Hex.SCALE * Hex.SCALE: continue
		var score := _pressure(body, int(point[0]), int(point[2]), friends)
		if score < pressure and _legal(game, body, point, data.blocked, enemies, false): pressure = score; best = point
	if best != actor.position:
		actor.velocity = [int(best[0]) - body.q, 0, int(best[2]) - body.r]
		game._face(actor, best)
		game.invalidate_unit_caches(body.owner)
		game.invalidate_light(actor)
		actor.position = best
		game.update_friendly(actor)
