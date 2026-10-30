extends SceneTree
## Uncapped rendered benchmark; run with --path project --script res://tools/benchmark-frames.gd.
var frames: Array[float] = []
class TimedNavigation extends "res://engine/expedition_navigation.gd":
	var route_usec := 0
	var route_count := 0
	var segment_usec := 0
	var weights_usec := 0
	func traversable_segment(a: Vector3, b: Vector3, illumination: RefCounted = null, friendly: bool = false) -> bool:
		var stamp := Time.get_ticks_usec()
		var result := super.traversable_segment(a, b, illumination, friendly)
		segment_usec += Time.get_ticks_usec() - stamp
		return result
	func cache_light_weights(illumination: RefCounted) -> void:
		var stamp := Time.get_ticks_usec(); super.cache_light_weights(illumination)
		weights_usec += Time.get_ticks_usec() - stamp
	func path(a: Vector3, b: Vector3, illumination: RefCounted = null, friendly: bool = true) -> PackedVector3Array:
		var stamp := Time.get_ticks_usec()
		var result := super.path(a, b, illumination, friendly)
		route_usec += Time.get_ticks_usec() - stamp; route_count += 1
		return result
class TimedSimulation extends "res://engine/simulation.gd":
	func _init() -> void: navigation = TimedNavigation.new()
	func step() -> void:
		navigation.route_usec = 0; navigation.route_count = 0; navigation.segment_usec = 0; navigation.weights_usec = 0
		var stamp := Time.get_ticks_usec()
		super.step()
		var cost := Time.get_ticks_usec() - stamp
		if cost > 4000: print("SLOW_TICK tick=%d total_ms=%.3f routes_ms=%.3f routes=%d segments_ms=%.3f weights_ms=%.3f" % [tick_number, cost / 1000.0, navigation.route_usec / 1000.0, navigation.route_count, navigation.segment_usec / 1000.0, navigation.weights_usec / 1000.0])

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var game = load("res://scenes/top_down.tscn").instantiate()
	game.simulation = TimedSimulation.new()
	game.initial_seed = 42; root.add_child(game); game.begin_run()
	if "--active" in OS.get_cmdline_user_args():
		for i in range(175): game.simulation.step()
	var quick := "--quick" in OS.get_cmdline_user_args()
	for mode in ["base", "surveyed", "pan", "orbit"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if mode == "surveyed":
			for cell in game.simulation.navigation.cells:
				game.simulation.explored[cell] = "cliff" if game.simulation.navigation.solid_cells.has(cell) else "ground"
			game.zoom = 8
		for i in range(45): await process_frame
		frames.clear()
		var stamp := Time.get_ticks_usec()
		var sample_start := stamp
		var i := 0
		while i < (1000 if quick else 3000) or Time.get_ticks_usec() - sample_start < (1000000 if quick else 5000000):
			if mode == "pan": game.focus = Vector2(sin(i * 0.002) * 30, cos(i * 0.002) * 20)
			if mode == "orbit": game.camera_angle = i * 0.002
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - stamp) / 1000.0); stamp = now; i += 1
		frames.sort()
		print("BENCHMARK %s frame_ms median=%.3f p95=%.3f p99=%.3f max=%.3f samples=%d draws=%d" % [mode, frames[int(frames.size() * 0.5)], frames[int(frames.size() * 0.95)], frames[int(frames.size() * 0.99)], frames[-1], frames.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	game.queue_free(); await process_frame; quit()

