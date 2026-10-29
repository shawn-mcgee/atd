extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run()
	game.rocks.clear(); game.rebuild_navigation()
	var center := Vector3(25, 0, -12)
	var guard: ExpeditionUnit = game.add_unit("marine", center + Vector3(8, 0, 1))
	guard.complex_id = 123
	var patrol = game.complex_commands.patrols
	patrol.update(game, guard, center, 0.05, "patrol")
	var first_goal := guard.goal
	var fixed := true
	for i in range(10):
		game.advance_movement(0.05); patrol.update(game, guard, center, 0.05, "patrol")
		if guard.goal != first_goal: fixed = false
	check(fixed and guard.moving(), "patrol keeps a fixed destination while walking instead of chasing a moving circle")
	var watches := 0
	var watch_time := 0.0
	var longest_watch := 0.0
	var maximum_step := 0.0
	var minimum_radius := INF
	var goals: Dictionary = {}
	for i in range(800):
		var previous := guard.position
		game.advance_movement(0.05); patrol.update(game, guard, center, 0.05, "patrol")
		maximum_step = maxf(maximum_step, previous.distance_to(guard.position))
		minimum_radius = minf(minimum_radius, guard.position.distance_to(center))
		goals[guard.goal] = true
		if not guard.moving():
			watch_time += 0.05
			longest_watch = maxf(longest_watch, watch_time)
		else:
			if watch_time >= 1.5: watches += 1
			watch_time = 0.0
		if i % 100 == 0: await process_frame
	check(watches >= 3 and longest_watch >= 1.5, "patrol pauses to watch at successive perimeter points")
	check(goals.size() >= 6 and minimum_radius > 4.4, "patrol progresses around the perimeter without cutting through the gathering area")
	check(maximum_step <= 3.5 * 0.05 + 0.001, "patrol movement stays within infantry walking speed without jumps")
	var other: ExpeditionUnit = game.add_unit("flamer", guard.position + Vector3(0, 0, 0.2))
	other.complex_id = 123
	patrol.update(game, other, center, 0.05, "foot_patrol")
	check(other.goal.distance_to(guard.goal) > 1.4, "nearby patrols reserve different watch points")
	var wall: ExpeditionStructure = game.add_structure("wall", center + Vector3(5.5, 0, 0))
	game.rebuild_navigation()
	var third: ExpeditionUnit = game.add_unit("marine", center + Vector3(8, 0, 0))
	third.complex_id = 123
	patrol.update(game, third, center, 0.05, "patrol")
	check(not game.navigation.blocked(third.goal) and third.goal.distance_to(wall.position) > 2, "patrol skips watch points covered by structures")
	game.set_order(guard, "move", Vector3(30, 0, -5))
	check(not patrol.states.has(guard.get_instance_id()), "direct orders immediately discard old patrol state")
	print("EXPEDITION_PATROL_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
