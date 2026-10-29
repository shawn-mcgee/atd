extends SceneTree
## Render actual mission snapshots without waiting for wall-clock simulation.
func _initialize() -> void:
	call_deferred("capture")

func advance(game, seconds: float) -> void:
	for i in range(ceili(seconds / 0.1)):
		game.simulation_tick(0.1)
		if i % 30 == 0: await process_frame

func capture() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.audio_enabled = false
	var mode := "base"
	if "--briefing" in OS.get_cmdline_user_args(): mode = "briefing"
	elif "--outpost" in OS.get_cmdline_user_args(): mode = "outpost"
	elif "--headlights" in OS.get_cmdline_user_args(): mode = "headlights"
	elif "--emergency" in OS.get_cmdline_user_args(): mode = "emergency"
	elif "--engineer" in OS.get_cmdline_user_args(): mode = "engineer"
	elif "--factory" in OS.get_cmdline_user_args(): mode = "factory"
	elif "--convoy" in OS.get_cmdline_user_args(): mode = "convoy"
	elif "--terrain" in OS.get_cmdline_user_args(): mode = "terrain"
	elif "--fortifications" in OS.get_cmdline_user_args(): mode = "fortifications"
	elif "--exploration" in OS.get_cmdline_user_args(): mode = "exploration"
	elif "--mining-scouts" in OS.get_cmdline_user_args(): mode = "mining-scouts"
	elif "--creatures" in OS.get_cmdline_user_args(): mode = "creatures"
	elif "--probes" in OS.get_cmdline_user_args(): mode = "probes"
	if mode != "briefing": game.begin_run()
	if mode == "engineer": game.select_actor(game.units[0])
	if mode == "creatures":
		for creature in game.creatures: creature.hp = 0
		game.cleanup_dead(); game.director.groups.clear()
		var index := 0
		for kind in ["runner", "stalker", "brute"]:
			var creature: ExpeditionPredator = game.add_creature(Vector3(-5 + index * 5, 0, -16), 99, kind, index)
			var tag := Label3D.new(); tag.text = game.Rules.PREDATORS[kind].name
			tag.position.y = 2.8; tag.font_size = 28; tag.pixel_size = 0.014; tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			creature.add_child(tag); index += 1
		game.focus = Vector3(0, 0, -16); game.camera_zoom = 19; game.select_actor(null)
	if mode == "probes":
		await advance(game, 24)
		while game.elapsed < 50:
			await advance(game, 0.1)
			if game.creatures.any(func(creature): return creature.visible and creature.position.distance_to(game.HOME) < 23): break
		game.focus = Vector3(4, 0, -2); game.camera_zoom = 40; game.select_actor(null)
	if mode == "exploration":
		var scout: ExpeditionUnit = game.add_unit("scout", Vector3(6, 0, -12))
		game.complex_commands.start_expedition(game, [scout, game.units[2], game.units[3], game.units[4]], {}, Vector3(28, 0, -18))
		while game.elapsed < 45 and not game.complex_commands.exploration.groups.is_empty():
			await advance(game, 0.2)
			if game.complex_commands.exploration.groups[0].start_reached: break
		await advance(game, 8)
		game.focus = scout.position; game.camera_zoom = 36; game.select_actor(scout)
	if mode == "mining-scouts":
		var scout: ExpeditionUnit = game.add_unit("scout", game.DEPOSIT + Vector3(-10, 0, 0))
		var miner: ExpeditionUnit = game.add_unit("engineer", game.DEPOSIT + Vector3(-2, 0, 0))
		var pilot: ExpeditionUnit = game.add_unit("marine", scout.position + Vector3(0, 0, 1))
		var resource: Dictionary = game.resource_at(game.DEPOSIT); resource.discovered = true
		game.complex_commands.start_expedition(game, [scout, miner, pilot], resource)
		await advance(game, 8)
		game.focus = game.DEPOSIT; game.camera_zoom = 36; game.select_actor(scout)
	if mode in ["terrain", "fortifications"]:
		var tile: ExpeditionStructure = game.add_structure("platform", Vector3(-40, 0, -12))
		game.add_structure("platform", tile.position + game.Terrain.direction(1) * game.Terrain.SPACING)
		game.add_structure("platform", tile.position + game.Terrain.direction(2) * game.Terrain.SPACING)
		game.add_structure("ramp", tile.position - game.Terrain.direction(0) * game.Terrain.SPACING, true, 0)
		var wall: ExpeditionStructure = game.add_structure("wall", Vector3(-40, 0, -24))
		for index in [0, 1, 2, 3]: game.add_structure("gate" if index == 0 else "wall", wall.position + game.Terrain.direction(index) * game.Terrain.SPACING)
		game.rebuild_navigation()
		game.focus = Vector3.ZERO if mode == "terrain" else Vector3(-40, 0, -17)
		game.camera_zoom = 185 if mode == "terrain" else 32
		game.select_actor(game.core if mode == "terrain" else tile)
	if mode == "convoy":
		game.select_actor(game.core); game.scan(); game.select_actor(game.jeep)
		game.complex_commands.start(game, [game.jeep, game.units[0], game.units[1], game.units[2], game.units[3], game.units[4]], game.resource_at(game.DEPOSIT))
		await advance(game, 30)
		game.focus = game.DEPOSIT; game.camera_zoom = 32
		game.select_actor(game.jeep)
	if mode == "factory":
		for b in game.structures:
			if b.kind == "barracks": game.select_actor(b); break
	if mode in ["outpost", "headlights", "emergency"]:
		game.select_actor(game.core); game.scan(); game.select_actor(game.jeep); game.board_squad()
		await advance(game, 15)
		game.set_order(game.jeep, "move", game.DEPOSIT + Vector3(0, 0, 5))
		await advance(game, 5 if mode == "headlights" else 14)
		game.focus = game.jeep.position
		game.camera_zoom = 40
		if mode == "emergency":
			game.select_actor(game.jeep); game.unload(); game.unload()
		if mode == "outpost":
			game.select_actor(game.jeep); game.unload()
			var engineer: ExpeditionUnit
			for unit in game.units:
				if unit.kind == "engineer" and unit.aboard == null: engineer = unit; break
			game.select_actor(engineer)
			game.order_build("generator", game.DEPOSIT + Vector3(-3.5, 0, 3))
			await advance(game, 16)
			game.order_build("floodlight", game.DEPOSIT)
			await advance(game, 12)
			engineer.harvest_kind = "minerals"; engineer.harvest_origin = game.DEPOSIT
			game.set_order(engineer, "harvest", game.DEPOSIT)
			await advance(game, 35)
			game.select_actor(game.jeep)
	if "--orbit" in OS.get_cmdline_user_args(): game.orbit_camera(Vector2(-160, -20))
	if "--focus" in OS.get_cmdline_user_args():
		game.select_actor(game.units[0])
		game.set_order(game.units[0], "board", game.jeep.position, game.jeep)
	if "--power" in OS.get_cmdline_user_args():
		game.select_actor(game.units[0])
		game.mouse_world = game.Hex.snap(game.HOME + Vector3(10, 0, -5), 2)
		game.choose_build("floodlight")
		game.ghost.visible = true; game.ghost.position = game.mouse_world + Vector3.UP * 0.12
		game.update_power_placement()
	if "--live" in OS.get_cmdline_user_args():
		game.set_process(true)
		var begin := Time.get_ticks_msec()
		var frames := 0
		var maximum_process := 0.0
		var timings: Array[float] = []
		while Time.get_ticks_msec() - begin < 6000:
			await process_frame
			frames += 1
			# Exclude setup and first-use shader compilation from steady-state timing.
			if Time.get_ticks_msec() - begin > 1000:
				var timing := float(Performance.get_monitor(Performance.TIME_PROCESS))
				maximum_process = maxf(maximum_process, timing)
				timings.append(timing)
		game.set_process(false)
		timings.sort()
		print("LIVE_SMOKE fps=", frames / 6.0, " steady_peak_process_ms=", maximum_process * 1000, " p95_process_ms=", timings[int(timings.size() * 0.95)] * 1000)
	game.update_camera()
	game.rebuild_light(); game.refresh_visual_lights(); game.refresh_ui(); game.update_focus_lines()
	game.minimap.refresh()
	if mode in ["terrain", "fortifications"]:
		game.light.sources.clear(); game.light.add_source(Vector3.ZERO, 150); game.refresh_visual_lights()
	if mode == "creatures":
		game.light.sources.clear(); game.light.add_source(game.focus, 25); game.refresh_visual_lights()
		for creature in game.creatures: creature.visible = true
	game.occluded_units.sync(game.light)
	if "--wall-drag" in OS.get_cmdline_user_args():
		game.select_actor(game.units[0]); game.choose_build("wall")
		game.economy.minerals = 20
		game.focus = Vector3(1, 0, -11); game.camera_zoom = 38; game.update_camera()
		game.wall_placement.begin(Vector2.ZERO, Vector3(-7, 0, -13))
		game.wall_placement.update_preview(game, Vector3(18, 0, -18))
		game.ghost.visible = false; game.refresh_ui(); game.update_power_placement()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var suffix := ("-power" if "--power" in OS.get_cmdline_user_args() else "") + ("-orbit" if "--orbit" in OS.get_cmdline_user_args() else "")
	if "--wall-drag" in OS.get_cmdline_user_args(): suffix += "-wall-drag"
	var path := "res://art_source/.build/expedition-%s%s.png" % [mode, suffix]
	root.get_texture().get_image().save_png(path)
	print("PREVIEW_SAVED ", path, " t=", game.elapsed)
	quit()
