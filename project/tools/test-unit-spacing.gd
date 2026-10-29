extends SceneTree
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ", description)
	else: failures += 1; push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func step_motion(game, frames: int) -> void:
	for i in range(frames): game.advance_movement(1.0 / 60.0)

func run_checks() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run()
	game.rocks.clear(); game.rebuild_navigation()
	var crowd: Array[ExpeditionUnit] = []
	for i in range(3): crowd.append(game.add_unit("marine", Vector3(20, 0, -10)))
	step_motion(game, 240)
	var separation := INF
	for i in range(crowd.size()):
		for j in range(i + 1, crowd.size()): separation = minf(separation, crowd[i].position.distance_to(crowd[j].position))
	check(separation > 0.9, "idle infantry sharing a point settle into separate nearby positions")
	var settled: Vector3 = crowd[0].position
	step_motion(game, 120)
	check(crowd[0].position.distance_to(settled) < 0.08, "settled units do not keep jittering or drifting")
	var parked: ExpeditionUnit = game.add_unit("jeep", Vector3(25, 0, 6))
	var bystander: ExpeditionUnit = game.add_unit("marine", parked.position)
	var original := parked.position
	step_motion(game, 240)
	check(parked.position == original and bystander.position.distance_to(parked.position) > 1.6, "infantry step clear while an unpiloted parked vehicle stays fixed")
	var first: ExpeditionUnit = game.add_unit("jeep", Vector3(32, 0, 15))
	var second: ExpeditionUnit = game.add_unit("jeep", first.position)
	first.board(game.units[4]); second.board(game.units[5])
	step_motion(game, 300)
	check(first.position.distance_to(second.position) > 2.4, "piloted vehicles gently separate when their destinations overlap")
	var a: ExpeditionUnit = game.add_unit("marine", Vector3(18, 0, 0))
	var b: ExpeditionUnit = game.add_unit("marine", Vector3(28, 0, 0))
	game.set_order(a, "move", b.position); game.set_order(b, "move", a.position)
	step_motion(game, 360)
	check(a.position.x > 26.5 and b.position.x < 19.5, "opposing infantry pass one another instead of becoming solid blockers")
	var destination := Vector3(18.3, 0, -4.7)
	game.set_order(a, "move", destination); game.set_order(b, "move", destination)
	step_motion(game, 360)
	check(a.position.distance_to(b.position) > 0.9 and a.position.distance_to(destination) < 2 and b.position.distance_to(destination) < 2, "units sharing a move destination arrive and spread out nearby")
	var wall: ExpeditionStructure = game.add_structure("wall", Vector3(20, 0, 15))
	game.rebuild_navigation()
	var p: ExpeditionUnit = game.add_unit("marine", wall.position + Vector3(0, 0, -2.5))
	var q: ExpeditionUnit = game.add_unit("marine", wall.position + Vector3(0, 0, -2.6))
	step_motion(game, 240)
	check(not game.navigation.blocked(p.position) and not game.navigation.blocked(q.position), "spacing corrections do not push units into building obstacles")
	var engineer: ExpeditionUnit = game.add_unit("engineer", game.DEPOSIT + Vector3(3.8, 0, 0))
	engineer.harvest_kind = "minerals"; engineer.harvest_origin = game.DEPOSIT
	engineer.order = "harvest"; engineer.path.clear()
	game.process_order(engineer, 0.1)
	check(engineer.moving(), "a worker nudged out of interaction range walks back to its task")
	var ids: Dictionary = {}
	for unit in game.units: ids[unit.formation_slot] = true
	check(ids.size() == game.units.size(), "followers receive distinct stable formation slots")
	print("UNIT_SPACING_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
