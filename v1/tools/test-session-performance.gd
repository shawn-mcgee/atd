extends SceneTree
const Simulation = preload("res://engine/simulation.gd")
const Hex = preload("res://engine/hex_grid.gd")
class CountedExploration extends "res://engine/exploration_expeditions.gd":
	var scanned := 0
	func next_cell(group: Dictionary) -> Vector2i:
		scanned += 1
		return super.next_cell(group)
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")

func nearest(game, actor: SimUnit) -> Vector2i:
	var best := Vector2i.ZERO; var distance := INF; var center := INF
	for cell in game.navigation.cells:
		if game.explored.has(cell): continue
		var point := Hex.to_world(cell, 1)
		var candidate := roundi(Vector2(point.x-actor.position.x, point.z-actor.position.z).length_squared()*1000)
		var middle: int = cell.x*cell.x+cell.x*cell.y+cell.y*cell.y
		if candidate < distance or (candidate == distance and (middle < center or (middle == center and (cell.x < best.x or (cell.x == best.x and cell.y < best.y))))):
			best = cell; distance = candidate; center = middle
	return best

func retired_world() -> Array:
	var world := Simulation.new(); world.initialize(42)
	var vehicle: SimUnit = world.add_unit("jeep", Vector3.ZERO)
	var driver: SimUnit = world.add_unit("marine", Vector3.ZERO); vehicle.board(driver)
	var refs := [weakref(world), weakref(world.navigation), weakref(vehicle), weakref(driver)]
	world.dispose()
	return refs

func run() -> void:
	var world := Simulation.new(); world.initialize(42)
	world.rocks.clear(); world.structures.clear(); world.navigation.terrain.natural_enabled = false
	world.rebuild_navigation()
	var e := CountedExploration.new(); world.complex_commands.exploration = e
	var actor: SimUnit = world.units[0]
	var exact := true; var bounded := true
	for point in [Vector3(0.8,0,0.1), Vector3(15.4,0,-9.6), Vector3(-24.1,0,32.4), Vector3(130,0,-14)]:
		actor.position = world.navigation.terrain.surface(point)
		world.explored.clear()
		for cell in world.navigation.cells:
			if Hex.to_world(cell,1).distance_to(point) < 5: world.explored[cell] = "ground"
		e.warm_cache(world)
		check(world.complex_commands.start_expedition(world,[actor],{},actor.position), "spatial exploration fixture starts")
		var group: Dictionary = e.groups[-1]
		var expected := nearest(world,actor)
		var result := 0; var calls := 0
		while result == 0 and calls < 100:
			var before := e.scanned; result = e.choose_destination(world,group,actor); calls += 1
			bounded = bounded and e.scanned-before <= e.PLAN_CELLS
		exact = exact and result == 1 and group.survey_cell == expected
		e.finish(group)
	check(exact, "spatial search matches exhaustive nearest-distance, center and axial ordering under offsets and map edges")
	actor.position = Vector3.ZERO; world.explored.clear()
	for cell in world.navigation.cells:
		if Hex.to_world(cell,1).length() < 45: world.explored[cell] = "ground"
	e.warm_cache(world)
	world.complex_commands.start_expedition(world,[actor],{},actor.position)
	var group: Dictionary = e.groups[-1]
	var result := e.choose_destination(world,group,actor)
	check(result == 0, "a far-away frontier yields planning work instead of scanning the map in one tick")
	var calls := 1
	while result == 0 and calls < 100:
		var before := e.scanned; result = e.choose_destination(world,group,actor); calls += 1
		bounded = bounded and e.scanned-before <= e.PLAN_CELLS
	check(bounded and result == 1 and group.survey_cell == nearest(world,actor), "budgeted planning resumes without losing exact nearest-tile ordering")
	e.finish(group)
	world.explored.clear(); e.warm_cache(world)
	world.rebuild_light(); world.record_exploration()
	check(e.known_count == world.explored.size() and not e.unseen.has(Hex.to_axial(world.core.position,1)), "normal discovery updates the remaining-cell index incrementally")
	world.dispose(); world = null
	var released := true
	for cycle in range(3):
		var refs := retired_world()
		await process_frame
		for ref in refs: released = released and ref.get_ref() == null
	check(released, "repeated restart disposal releases worlds, navigation graphs and boarded actor cycles")
	print("SESSION_PERFORMANCE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
