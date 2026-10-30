extends SceneTree
## Headless long-session diagnostics; timing stays outside the simulation engine.
## --minutes=15 (default) simulates 15 late-pressure minutes and three retirements.
class TimedNavigation extends "res://engine/expedition_navigation.gd":
	var queries := 0
	var elapsed_usec := 0
	var slowest_usec := 0
	var slowest := []
	func path(a: Vector3, b: Vector3, illumination: RefCounted = null, friendly: bool = true) -> PackedVector3Array:
		var stamp := Time.get_ticks_usec()
		var result := super.path(a, b, illumination, friendly)
		var cost := Time.get_ticks_usec() - stamp
		queries += 1; elapsed_usec += cost
		if cost > slowest_usec: slowest_usec = cost; slowest = [a,b,illumination != null,friendly,result.size()]
		return result
class TimedExploration extends "res://engine/exploration_expeditions.gd":
	var plans := 0
	var usec := 0
	func prepare_plan(game, group: Dictionary, leader: SimUnit) -> void:
		var stamp := Time.get_ticks_usec(); super.prepare_plan(game, group, leader)
		plans += 1; usec += Time.get_ticks_usec() - stamp
class TimedSimulation extends "res://engine/simulation.gd":
	var soaking := false
	func _init() -> void:
		navigation = TimedNavigation.new()
		complex_commands.exploration = TimedExploration.new()
	func heal_near_hq(dt: float) -> void:
		# HQ healing otherwise clamps the diagnostic scout back to normal HP.
		if not soaking: super.heal_near_hq(dt)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var minutes := 15
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = maxi(1, int(arg.trim_prefix("--minutes=")))
	for cycle in range(3):
		var world := TimedSimulation.new(); world.initialize(42)
		world.core.hp = 1000000
		var ref: WeakRef = weakref(world); var nav_ref: WeakRef = weakref(world.navigation)
		print("START ",cycle," objects=",Performance.get_monitor(Performance.OBJECT_COUNT)," bytes=",OS.get_static_memory_usage())
		for age in [20.0,900.0]:
			world.elapsed = age
			var start := Time.get_ticks_usec(); var maximum := 0
			for tick in range(120):
				var stamp := Time.get_ticks_usec(); world.step(); maximum = maxi(maximum,Time.get_ticks_usec()-stamp)
				if tick % 20 == 0: await process_frame
			print("TICKS age=",age," total_ms=",(Time.get_ticks_usec()-start)/1000.0," max_ms=",maximum/1000.0," routes=",world.navigation.queries," route_ms=",world.navigation.elapsed_usec/1000.0," slowest_ms=",world.navigation.slowest_usec/1000.0," query=",world.navigation.slowest)
		if cycle == 0:
			world.soaking = true
			var actor: SimUnit = world.units[0]
			actor.hp = 1000000 # Keep the diagnostic scout working throughout the soak.
			world.complex_commands.start_expedition(world,[actor],{},actor.position)
			var group: Dictionary = world.complex_commands.exploration.groups[-1]
			group.start_reached = true; group.phase = "planning"
			var stamp := Time.get_ticks_usec()
			world.complex_commands.exploration.choose_destination(world,group,actor)
			print("EXPLORE plan_ms=",(Time.get_ticks_usec()-stamp)/1000.0," candidates=",group.plan_queue.size())
			for minute in range(minutes):
				var start := Time.get_ticks_usec(); var maximum := 0
				for tick in range(600):
					var queries: int = world.navigation.queries; var routes: int = world.navigation.elapsed_usec
					stamp = Time.get_ticks_usec(); world.step(); var cost := Time.get_ticks_usec()-stamp; maximum = maxi(maximum,cost)
					if cost > 100000: print("SPIKE t=",world.elapsed," total_ms=",cost/1000.0," routes=",world.navigation.queries-queries," route_ms=",(world.navigation.elapsed_usec-routes)/1000.0," worst_ms=",world.navigation.slowest_usec/1000.0," worst=",world.navigation.slowest)
					if tick % 100 == 0: await process_frame
				print("LONG minute=",minute+1," elapsed=",world.elapsed," ms=",(Time.get_ticks_usec()-start)/1000.0," max_ms=",maximum/1000.0," plans=",world.complex_commands.exploration.plans," plan_ms=",world.complex_commands.exploration.usec/1000.0," known=",world.explored.size()," entities=",world.entities.size()," objects=",Performance.get_monitor(Performance.OBJECT_COUNT)," bytes=",OS.get_static_memory_usage())
		world.dispose(); world = null
		await process_frame
		print("DISPOSE ",cycle," world_alive=",ref.get_ref()!=null," nav_alive=",nav_ref.get_ref()!=null," objects=",Performance.get_monitor(Performance.OBJECT_COUNT)," bytes=",OS.get_static_memory_usage())
	quit()
