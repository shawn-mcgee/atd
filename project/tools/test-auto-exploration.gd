extends SceneTree
const Hex = preload("res://scripts/hex_grid.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func step(game, dt: float = 0.2) -> void:
	game.advance_movement(dt); game.rebuild_light(); game.complex_commands.tick(game, dt)

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.minimap.set_process(false); game.begin_run(); game.audio_enabled = false
	for creature in game.creatures: creature.hp = 0
	game.cleanup_dead(); game.director.groups.clear()
	var command = game.complex_commands
	var exploration = command.exploration
	var scout: ExpeditionUnit = game.add_unit("scout", Vector3(12, 0, -4))
	var engineer: ExpeditionUnit = game.add_unit("engineer", scout.position + Vector3(1, 0, 0))
	check(command.start_expedition(game, [scout, engineer], {}, game.DEPOSIT), "auto-exploration accepts a starting location on the real canyon map")
	var group: Dictionary = exploration.groups[-1]
	var arrived := false; var left_start := false; var stayed_free := true
	var before: int = game.minimap.explored.size()
	for i in range(12000):
		step(game)
		if not arrived and group.start_reached:
			arrived = true
			check(scout.position.distance_to(game.DEPOSIT) < 0.8, "the expedition reaches the clicked location before beginning its autonomous sweep")
		if arrived and scout.position.distance_to(game.DEPOSIT) > 25: left_start = true
		if game.navigation.blocked(scout.position):
			if stayed_free: print("BLOCKED_SCOUT position=", scout.position, " solid=", game.navigation.solid_at(scout.position), " phase=", group.phase, " goal=", scout.goal, " path=", scout.path)
			stayed_free = false
		if i % 1000 == 0:
			print("AUTO_SCOUT tick=", i, " charted=", game.minimap.explored.size(), "/", game.minimap.cells.size(), " phase=", group.phase, " position=", scout.position)
			await process_frame
		if group.phase == "complete": break
	check(arrived and left_start and game.minimap.explored.size() > before, "the expedition keeps sweeping distant territory after surveying the starting area")
	check(stayed_free, "the automatic sweep uses navigable canyon routes rather than crossing cliffs")
	check(group.phase == "complete" and game.minimap.explored.size() == game.minimap.cells.size() and game.minimap.scouting_percent() == 100, "a crewed scout reveals every map tile, including blocked cliff tiles viewed from nearby ground")
	check(not scout.moving() and exploration.describe(scout).contains("100% scouted"), "the expedition stops and reports completion only at actual 100 percent coverage")
	# Truly inaccessible territory must remain unknown and be retried when access changes.
	exploration.finish(group)
	game.structures.clear(); game.rocks.clear()
	for unit in game.units:
		if unit != scout and unit != engineer: unit.position = Vector3(80, 0, -30); unit.path.clear()
	var opening := -1
	for q in range(-8, 9):
		for r in range(-8, 9):
			if maxi(absi(q), maxi(absi(r), absi(q + r))) != 8: continue
			var cell := Vector2i(q, r)
			if cell == Vector2i(-8, 0): opening = game.rocks.size()
			game.rocks.append({"cell": cell, "position": Hex.to_world(cell, preload("res://scripts/expedition_terrain.gd").CELL), "radius": 2.0, "height": 6.0})
	game.rebuild_navigation()
	scout.position = Vector3(-50, 0, 0); scout.path.clear(); engineer.position = scout.position
	game.minimap.explored.erase(Vector2i.ZERO); game.rebuild_light()
	check(command.start_expedition(game, [scout], {}, scout.position), "an already crewed scout can start a new sweep")
	group = exploration.groups[-1]
	for i in range(30): step(game)
	check(group.phase == "waiting" and not game.minimap.explored.has(Vector2i.ZERO) and group.scouted_percent < 100, "an inaccessible last tile does not cause a false 100 percent completion or repeated movement into walls")
	var revision: int = game.navigation.revision
	game.rocks.remove_at(opening); game.rebuild_navigation()
	check(game.navigation.revision > revision, "opening terrain invalidates the cached reachability information")
	for i in range(600):
		step(game)
		if group.phase == "complete": break
	check(group.phase == "complete" and game.minimap.explored.has(Vector2i.ZERO), "the waiting expedition resumes automatically when a route to the remaining tile opens")
	print("AUTO_EXPLORATION_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
