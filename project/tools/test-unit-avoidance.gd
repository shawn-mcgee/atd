extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error(message)

func _initialize() -> void: call_deferred("run")

func reset(game) -> void:
	for unit in game.units:
		unit.aboard = null; unit.driver = null; unit.passengers.clear(); unit.target = null
	game.units.clear(); game.structures.clear(); game.soft_spacing.velocities.clear()
	game.rebuild_navigation()

func actor(game, kind: String, point: Vector3) -> SimUnit:
	var unit: SimUnit = game.add_unit(kind, point)
	if unit.is_vehicle(): unit.board(game.add_unit("marine", point))
	return unit

func advance(game, movers: Array, frames: int = 600) -> Dictionary:
	var minimum := INF; var clear := true
	for frame in range(frames):
		game.advance_movement(1.0 / 60.0)
		for i in range(movers.size()):
			clear = clear and not game.navigation.blocked(movers[i].position)
			for j in range(i + 1, movers.size()):
				if absf(movers[i].position.y - movers[j].position.y) > 0.6: continue
				var gap: float = movers[i].position.distance_to(movers[j].position) - game.soft_spacing.radius(movers[i]) - game.soft_spacing.radius(movers[j])
				minimum = minf(minimum, gap)
	return {"gap": minimum, "clear": clear}

func traffic(game, first_kind: String, second_kind: String, start_a: Vector3, end_a: Vector3, start_b: Vector3, end_b: Vector3, label: String) -> void:
	reset(game)
	var a := actor(game, first_kind, start_a); var b := actor(game, second_kind, start_b)
	game.set_order(a, "move", end_a); game.set_order(b, "move", end_b)
	var result := advance(game, [a, b])
	if result.gap < -0.02 or a.position.distance_to(end_a) > 2 or b.position.distance_to(end_b) > 2: print("TRAFFIC_DIAGNOSTIC: ", label, " gap=", result.gap, " positions=", a.position, " / ", b.position)
	check(result.gap >= -0.02 and result.clear, label + " keeps bodies apart throughout travel")
	check(a.position.distance_to(end_a) < 2 and b.position.distance_to(end_b) < 2, label + " reaches both destinations without a standoff")

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	game.creatures.clear(); game.rocks.clear(); game.structures.clear()
	game.navigation = game.Navigation.new(); game.rebuild_navigation()
	traffic(game, "marine", "marine", Vector3(-8, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 0), Vector3(-8, 0, 0), "oncoming infantry")
	traffic(game, "jeep", "jeep", Vector3(-8, 0, 0), Vector3(8, 0, 0), Vector3(8, 0, 0), Vector3(-8, 0, 0), "oncoming vehicles")
	traffic(game, "scout", "engineer", Vector3(-8, 0, 0), Vector3(8, 0, 0), Vector3(-4, 0, 0), Vector3(10, 0, 0), "overtaking mixed traffic")
	traffic(game, "marine", "marine", Vector3(-6, 0, 0), Vector3(6, 0, 0), Vector3(0, 0, -6), Vector3(0, 0, 6), "crossing infantry")
	reset(game)
	var mover := actor(game, "marine", Vector3(-8, 0, 0))
	var idle := actor(game, "engineer", Vector3.ZERO)
	var goal := Vector3(8, 0, 0); var idle_goal := idle.goal
	idle.order_queue.append({"order": "move", "point": Vector3(3, 0, 3), "target": null})
	game.set_order(mover, "move", goal)
	var result := advance(game, [mover, idle])
	check(result.gap >= -0.02 and mover.position.distance_to(goal) < 0.5, "a mover passes an idle ally without contact")
	check(idle.position.length() > 0.25 and idle.position.length() < 3 and idle.order == "idle" and idle.goal == idle_goal and not idle.moving() and idle.order_queue.size() == 1, "idle allies honor make-room requests without losing their order or queued work")
	reset(game)
	mover = actor(game, "marine", Vector3(-8, 0, 0)); var worker := actor(game, "engineer", Vector3.ZERO)
	game.add_resource_patch("minerals", Vector3.ZERO, 100); game.resource_nodes[-1].discovered = true
	game.issue_order(worker, "harvest", Vector3.ZERO); game.set_order(mover, "move", goal)
	result = advance(game, [mover, worker])
	check(result.gap >= -0.02 and worker.position == Vector3.ZERO and worker.order == "harvest" and mover.position.distance_to(goal) < 0.5, "working allies keep their task while traffic passes around them")
	reset(game)
	var transport := actor(game, "jeep", Vector3.ZERO)
	var passenger := actor(game, "engineer", Vector3(-8, 0, 0))
	game.set_order(passenger, "board", transport.position, transport)
	for frame in range(240):
		game.advance_movement(1.0 / 60.0); game.process_order(passenger, 1.0 / 60.0)
		if passenger.aboard != null: break
	check(passenger.aboard == transport and transport.position == Vector3.ZERO, "boarding requests do not make the target vehicle move away")
	reset(game)
	mover = actor(game, "marine", Vector3(-8, 0, 0))
	var parked: SimUnit = game.add_unit("jeep", Vector3.ZERO)
	game.set_order(mover, "move", goal)
	result = advance(game, [mover, parked])
	check(result.gap >= -0.02 and parked.position == Vector3.ZERO and mover.position.distance_to(goal) < 0.5, "movers steer around unpiloted vehicles while parked vehicles stay fixed")
	reset(game)
	game.add_structure("wall", Vector3(0, 0, 1.7320508075688772)); game.rebuild_navigation()
	mover = actor(game, "marine", Vector3(-8, 0, 0)); parked = game.add_unit("jeep", Vector3.ZERO)
	game.set_order(mover, "move", goal)
	result = advance(game, [mover, parked])
	if not result.clear or result.gap < -0.02 or mover.position.distance_to(goal) >= 0.5: print("WALL_TRAFFIC_DIAGNOSTIC: ", result, " position=", mover.position, " goal=", mover.goal, " path=", mover.path, " index=", mover.path_index)
	check(result.clear and result.gap >= -0.02 and mover.position.distance_to(goal) < 0.5, "passing traffic chooses clear terrain rather than being pushed into a wall")
	reset(game)
	var crowd: Array[SimUnit] = []
	for z in [-3, 0, 3]:
		var unit := actor(game, "marine", Vector3(-8, 0, z)); crowd.append(unit); game.set_order(unit, "move", goal)
	result = advance(game, crowd, 1000)
	check(result.gap >= -0.02 and crowd.all(func(unit): return unit.position.distance_to(goal) < 2.5), "a shared destination settles nearby without collisions or an orbiting queue")
	reset(game)
	game.add_structure("platform", Vector3.ZERO); game.rebuild_navigation()
	var upper := actor(game, "jeep", Vector3(0, 3, 0)); var lower := actor(game, "jeep", Vector3(1.7320508075688772, 0, 0))
	var upper_start := upper.position; var lower_start := lower.position
	advance(game, [upper, lower], 120)
	check(upper.position == upper_start and lower.position == lower_start, "units on different terrain levels do not push each other sideways")
	reset(game); game.dispose()
	print("UNIT_AVOIDANCE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
