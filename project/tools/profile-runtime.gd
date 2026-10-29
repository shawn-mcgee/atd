extends SceneTree
var game

func _initialize() -> void: call_deferred("run")

func report(label: String, samples: Array[float]) -> void:
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	print("PROFILE ", label, " mean_ms=", snappedf(total / samples.size(), 0.001), " p95_ms=", snappedf(samples[mini(samples.size() - 1, int(samples.size() * 0.95))], 0.001), " max_ms=", snappedf(samples[-1], 0.001))

func bench(label: String, action: Callable, count: int = 60) -> void:
	var samples: Array[float] = []
	for i in range(count):
		var begin := Time.get_ticks_usec()
		action.call()
		samples.append((Time.get_ticks_usec() - begin) / 1000.0)
	report(label, samples)

func run() -> void:
	game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.minimap.set_process(false); game.begin_run(); game.audio_enabled = false
	if "--large" in OS.get_cmdline_user_args():
		for i in range(60):
			game.add_unit("engineer" if i % 3 == 0 else "marine", Vector3(-70 + (i % 10) * 4, 0, -20 + (i / 10) * 4))
		for i in range(60):
			game.add_structure("wall", Vector3(-65 + (i % 15) * 4, 0, 20 + (i / 15) * 4))
		game.rebuild_navigation(); game.focus = Vector3(-45, 0, 5); game.camera_zoom = 75; game.update_camera()
	if "--expeditions" in OS.get_cmdline_user_args():
		var resource: Dictionary = game.resource_at(game.DEPOSIT); resource.discovered = true
		for i in range(4):
			var jeep = game.add_unit("jeep", Vector3(-8 + i * 5, 0, -12))
			var miner = game.add_unit("engineer", jeep.position + Vector3(1, 0, 0))
			var marine = game.add_unit("marine", jeep.position + Vector3(2, 0, 0))
			game.complex_commands.start_expedition(game, [jeep, miner, marine], resource)
		for i in range(2):
			var scout = game.add_unit("scout", Vector3(-20, 0, -8 - i * 4))
			var pilot = game.add_unit("engineer", scout.position + Vector3(1, 0, 0))
			game.complex_commands.start_expedition(game, [scout, pilot], {}, Vector3(-30, 0, -20))
		game.select_actor(game.complex_commands.groups[0].vehicle)
	for i in range(40): game._process(1.0 / 60)
	print("PROFILE_SCENE units=", game.units.size(), " structures=", game.structures.size(), " creatures=", game.creatures.size(), " lights=", game.light.sources.size(), " fog_materials=", game.fog_materials.size(), " occluders=", game.occluded_units.occluders.size(), " actor_meshes=", game.occluded_units.entries.size())
	bench("movement", func(): game.advance_movement(1.0 / 60))
	bench("lighting_upload", func(): game.rebuild_light(); game.refresh_visual_lights())
	bench("hud", func(): game.refresh_ui())
	bench("expedition_selection", func(): game.complex_commands.expedition_selection(game.selected))
	bench("occlusion_sync", func(): game.occluded_units.sync(game.light))
	bench("minimap_scan", func(): game.minimap.record_exploration(), 20)
	bench("minimap_refresh", func(): game.minimap.refresh(), 20)
	bench("commands_tick", func(): game.complex_commands.tick(game, 0.1))
	bench("power_tick", func(): game.power.tick(game.structures, game.economy, 0.1))
	bench("combat_targets", func():
		for unit in game.units:
			if unit.kind in ["marine", "flamer"]: game.visible_target(unit.position, 11))
	bench("simulation_tick", func(): game.simulation_tick(0.1, false), 80)
	bench("game_frame", func(): game._process(1.0 / 60), 300)
	if "--rendered" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		game.set_process(true); game.minimap.set_process(true)
		var samples: Array[float] = []
		var start := Time.get_ticks_msec(); var previous := Time.get_ticks_usec(); var frames := 0
		while Time.get_ticks_msec() - start < 8000:
			await process_frame
			var now := Time.get_ticks_usec()
			if Time.get_ticks_msec() - start > 1500: samples.append((now - previous) / 1000.0); frames += 1
			previous = now
		report("rendered_frame", samples)
		print("RENDER_STATS frames=", frames, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	quit()
