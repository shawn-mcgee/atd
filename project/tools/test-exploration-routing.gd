extends SceneTree
const Hex = preload("res://engine/hex_grid.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error(message)

func _initialize() -> void: call_deferred("run")

func planning_group(game, selection: Array, unknown: Array) -> Dictionary:
	var exploration = game.complex_commands.exploration
	for group in exploration.groups.duplicate(): exploration.finish(group)
	game.explored.clear()
	for cell in game.navigation.cells: game.explored[cell] = "ground"
	for cell in unknown: game.explored.erase(cell)
	exploration.rebuild_unseen(game)
	check(game.complex_commands.start_expedition(game, selection, {}, selection[0].position), "exploration starts on a reachable tile")
	var group: Dictionary = exploration.groups[-1]
	group.start_reached = true; group.phase = "planning"
	exploration.reset_plan(group)
	return group

func arrival_loop(game, kind: String) -> void:
	game.units.clear()
	var actor: SimUnit = game.add_unit(kind, Vector3.ZERO)
	var selection: Array = [actor]
	var driver: SimUnit
	if actor.is_vehicle():
		driver = game.add_unit("marine", actor.position); selection.append(driver)
	var first := Vector2i(15, 0); var second := Vector2i(30, 0)
	var group := planning_group(game, selection, [first, second])
	if driver != null: actor.board(driver)
	var exploration = game.complex_commands.exploration
	check(exploration.choose_destination(game, group, actor) == 1 and group.survey_cell == first, "%s chooses the nearest unknown tile" % kind)
	exploration.tick(game, 0.1)
	var destination: Vector3 = group.destination
	# Headlights or another party may reveal the destination before arrival.
	game.explored[first] = "ground"
	exploration.tick(game, 0.1)
	check(group.phase == "exploring" and group.destination == destination and actor.moving(), "%s keeps moving when its destination is revealed early" % kind)
	var arrived := false; var advanced := false
	for i in range(400):
		game.advance_movement(0.1); game.rebuild_light(); exploration.tick(game, 0.1)
		if actor.position.distance_to(destination) < 0.25: arrived = true
		if group.phase == "exploring" and group.survey_cell == second:
			advanced = true
			check(arrived, "%s reaches its current destination before choosing another" % kind)
			break
	check(arrived and advanced and actor.position.distance_to(Vector3.ZERO) > 25, "%s makes sustained scouting progress instead of turning in place" % kind)
	exploration.finish(group)

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	game.units.clear(); game.creatures.clear(); game.rocks.clear(); game.structures.clear(); game.resource_nodes.clear()
	game.navigation = game.Navigation.new(); game.rebuild_navigation()
	game.light = game.Illumination.new(); game.light.configure(game.navigation)
	var start := Hex.to_world(Vector2i(12, 0), 1); var end := Hex.to_world(Vector2i(15, 0), 1)
	var route: PackedVector3Array = game.navigation.path(start, end)
	check(not route.is_empty(), "a clear scouting route is available")
	route.clear()
	check(not game.navigation.path(start, end).is_empty(), "clearing a returned route cannot erase the cached route")
	route = game.navigation.path(start, end)
	var another: PackedVector3Array = game.navigation.path(start, end)
	route.clear()
	check(not another.is_empty() and not game.navigation.path(start, end).is_empty(), "cache hits give each mover an independent route")
	var exploration = game.complex_commands.exploration
	var unit: SimUnit = game.add_unit("marine", Hex.to_world(Vector2i(10, 0), 1))
	var group := planning_group(game, [unit], [Vector2i(11, 0), Vector2i(9, 0)])
	check(exploration.choose_destination(game, group, unit) == 1 and group.survey_cell == Vector2i(9, 0), "equally near tiles prefer the tile closer to the map center")
	group = planning_group(game, [unit], [Vector2i(8, 0), Vector2i(11, 0)])
	check(exploration.choose_destination(game, group, unit) == 1 and group.survey_cell == Vector2i(11, 0), "nearest distance takes priority over distance to the map center")
	unit.position = Vector3.ZERO
	group = planning_group(game, [unit], [Vector2i(1, 0), Vector2i(0, 1)])
	check(exploration.choose_destination(game, group, unit) == 1 and group.survey_cell == Vector2i(0, 1), "remaining equal-distance ties use a stable cell order")
	exploration.finish(group)
	var blocked := Vector2i(1, 0)
	game.rocks.append({"position": Hex.to_world(blocked, 1), "cell": blocked, "radius": 0.95, "height": 3.0})
	game.rebuild_navigation()
	group = planning_group(game, [unit], [blocked, Vector2i(4, 0)])
	check(exploration.choose_destination(game, group, unit) == 1 and group.survey_cell == Vector2i(4, 0), "scouts skip blocked unknown tiles and travel to a reachable tile")
	game.explored[Vector2i(4, 0)] = "ground"; exploration.reset_plan(group); group.phase = "planning"
	exploration.tick(game, 0.1)
	check(group.phase == "waiting" and not unit.moving(), "only inaccessible unknown tiles cause a quiet wait instead of scanning in place")
	game.rocks.clear(); game.rebuild_navigation(); exploration.tick(game, 0.1)
	check(group.phase == "exploring" and group.survey_cell == blocked, "opening terrain makes previously inaccessible tiles eligible again")
	exploration.finish(group)
	var raised := Vector2i(2, 0)
	game.add_structure("platform", Hex.to_world(raised, 1)); game.rebuild_navigation()
	group = planning_group(game, [unit], [raised, Vector2i(4, 0)])
	check(exploration.choose_destination(game, group, unit) == 1 and group.survey_cell == Vector2i(4, 0), "unreachable raised tiles do not trap ground scouts")
	exploration.finish(group); game.structures.clear(); game.rebuild_navigation()
	arrival_loop(game, "marine"); arrival_loop(game, "scout")
	game.dispose()
	print("EXPLORATION_ROUTING_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
