extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
## Stable perimeter legs, with a short watch at each reachable waypoint.
static var POINTS: int = int(Config.value("patrol", "points"))
static var RADIUS: float = float(Config.value("patrol", "radius"))
var states: Dictionary = {}

func prune(units: Array) -> void:
	var active: Dictionary = {}
	for unit in units:
		if unit.hp > 0 and unit.aboard == null and unit.order in ["convoy_patrol", "convoy_foot_patrol", "convoy_scout_patrol"]: active[unit.simulation_id] = true
	for id in states.keys():
		if not active.has(id): states.erase(id)

func update(game, unit: SimUnit, center: Vector3, dt: float, order: String, radius: float = RADIUS) -> void:
	var id := unit.simulation_id
	unit.order = "convoy_" + order; unit.target = null
	if not states.has(id) or states[id].center.distance_to(center) > 0.5 or states[id].group != unit.complex_id or states[id].radius != radius:
		var offset := unit.position - center
		var index := posmod(int(round(atan2(offset.z, offset.x) / TAU * POINTS)), POINTS)
		states[id] = {"center": center, "radius": radius, "group": unit.complex_id, "index": index, "hold": -1.0, "stalled": 0.0, "previous": unit.position, "retry": 0.0}
		choose_leg(game, unit, states[id])
	var state: Dictionary = states[id]
	if state.retry > 0:
		state.retry -= dt
		if state.retry <= 0: choose_leg(game, unit, state)
		return
	if state.hold >= 0:
		unit.path.clear()
		var outward := unit.position - center
		unit.desired_yaw = atan2(-outward.x, -outward.z)
		state.hold -= dt
		if state.hold < 0:
			state.index = (int(state.index) + 1) % POINTS
			choose_leg(game, unit, state)
		return
	if unit.position.distance_to(unit.goal) < 0.45:
		unit.path.clear(); state.hold = 1.8 + float(unit.formation_slot % 3) * 0.3
		state.stalled = 0.0
		return
	if unit.position.distance_to(state.previous) < dt * 0.2: state.stalled += dt
	else: state.stalled = 0.0
	state.previous = unit.position
	# A changed obstacle or persistent crowd can invalidate a leg. Skip it once,
	# rather than resetting the same path every simulation tick.
	if state.stalled > 2.5:
		state.index = (int(state.index) + 1) % POINTS
		choose_leg(game, unit, state)

func choose_leg(game, unit: SimUnit, state: Dictionary) -> void:
	state.stalled = 0.0; state.previous = unit.position
	for step in range(POINTS):
		var index := (int(state.index) + step) % POINTS
		var angle := float(index) * TAU / POINTS
		var point: Vector3 = game.navigation.terrain.surface(state.center + Vector3(cos(angle), 0, sin(angle)) * float(state.radius))
		if not game.navigation.terrain.contains(point) or game.navigation.blocked(point): continue
		var occupied := false
		for other in states:
			if other != unit.simulation_id and states[other].has("goal") and states[other].goal.distance_to(point) < 1.4: occupied = true; break
		if occupied: continue
		var path: PackedVector3Array = game.navigation.path(unit.position, point)
		if path.is_empty() or path[path.size() - 1].distance_to(point) > 0.5: continue
		state.index = index; state.goal = point
		unit.goal = point; unit.path = path; unit.path_index = 0
		return
	# No usable watch point: hold and retry slowly, keeping the current position.
	unit.path.clear(); state.retry = 2.0
