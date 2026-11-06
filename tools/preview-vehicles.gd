extends SceneTree

# Render the real game HUD and models with a small vehicle review fixture.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted = true
	game._start_game(472, 1)
	game.state.paused = true; game.paused_button.text = "Resume"
	var anchor: Dictionary = game.state.structures[int(game.state.players[0].anchor)]
	var center: Vector2i = anchor.cell - anchor.cell.sign() * 6
	for cell in HexGrid.disk(center, 8):
		if game.state.tiles.has(cell):
			game.state.tiles[cell].cliff = false
			game.state.known[0][cell] = true
	if "--controls" in OS.get_cmdline_user_args():
		var crew: Array = []
		for i in range(3): crew.append(game.state.add_unit("engineer", HexGrid.world(anchor.cell + Vector2i(2 + i, -1)), 0))
		game.renderer.initialize(game.state, 0)
		game.camera.focus = Vector3(HexGrid.world(anchor.cell).x, 0, HexGrid.world(anchor.cell).y)
		game.camera.distance = 17; game.camera.target_distance = 17; game.camera._update_transform()
		game.selection = crew; game._assign_group(1); game._update_hud()
		for i in range(8): await process_frame
		game.set_process(false); game.camera.set_process(false)
		var site: Vector2i = anchor.cell + Vector2i(0, -2)
		game._choose_build("depot"); game.placement_strip.show()
		game.placement_text.text = "PLACING DEPOT  /  20 Ore\nCLEAR SITE  /  SHIFT: repeat   ESC: cancel"
		game.renderer.selection = crew; game.renderer.show_preview(site, true, "depot", true); game.renderer.refresh_entities()
		for i in range(3): await process_frame
		RenderingServer.force_draw(); DirAccess.make_dir_recursive_absolute("res://build/visual-review")
		root.get_texture().get_image().save_png("res://build/visual-review/controls-placement.png")
		game._toggle_build(); game.placement_strip.hide(); game.group_bar.hide(); game.renderer.show_preview(site, false)
		for i in range(3): await process_frame
		RenderingServer.force_draw(); root.get_texture().get_image().save_png("res://build/visual-review/controls-build-menu.png")
		game.audio.stop(); game.queue_free(); await process_frame
		print("Controls review captured"); quit(); return
	if "--combat" in OS.get_cmdline_user_args():
		for unit_id in game.state.units.keys():
			if game.state.units[unit_id].owner < 0: game.state.units.erase(unit_id)
		var origin := HexGrid.world(center)
		var lance: int = game.state.add_structure("lance", center + Vector2i(0, 2), 0)
		game.state.add_structure("rampart", center + Vector2i(1, 2), 0)
		game.state.add_structure("generator", center + Vector2i(-1, 2), 0)
		game.state.add_structure("generator", center + Vector2i(-2, 2), 0)
		game.state.add_structure("floodlight", center + Vector2i(-2, 0), 0)
		var marine: int = game.state.add_unit("marine", origin + Vector2(-2.3, 0.3), 0)
		var flamer: int = game.state.add_unit("flamer", origin + Vector2(1.1, 0), 0)
		var ravager: int = game.state.add_unit("ravager", origin + Vector2(-0.1, -2.3), -1)
		var victim: int = game.state.add_unit("scavenger", origin + Vector2(1.4, -1.8), -1)
		for i in range(5): game.state.add_unit("scavenger", origin + Vector2(0.3 + i * 0.36, -1.15), -1)
		game.state._update_power(0.05); game.state.update_visibility()
		game.camera.focus = Vector3(origin.x, 0, origin.y)
		game.camera.distance = 14; game.camera.target_distance = 14; game.camera._update_transform()
		game.renderer.initialize(game.state, 0)
		for i in range(8): await process_frame
		game.tactical._process(0.001)
		game.state.units[marine].target = ravager; game.state.units[marine].job = {"kind": "attack"}
		game.state.units[flamer].target = victim; game.state.units[flamer].job = {"kind": "attack"}
		game.state.structures[lance].target = ravager
		game.state._fire(game.state.units[marine], "marine_rifle", 0.05)
		game.state._fire(game.state.units[flamer], "flamer_flame", 0.05)
		game.state._fire(game.state.structures[lance], "lance_laser", 0.05)
		game.state._weapon_damage(game.state.structures[lance], game.state.cfg.weapons.ravager_melee)
		game.state._weapon_damage(game.state.units[victim], game.state.cfg.weapons.lancer_laser)
		game.selection = [lance]; game._update_hud()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/visual-review")
		root.get_texture().get_image().save_png("res://build/visual-review/combat-feedback.png")
		game.audio.stop(); game.queue_free(); await process_frame
		print("Combat feedback review captured"); quit(); return
	if "--sensors" in OS.get_cmdline_user_args():
		for unit_id in game.state.units.keys():
			if game.state.units[unit_id].owner < 0: game.state.units.erase(unit_id)
		var radar: int = game.state.add_structure("radar", center, 0)
		game.state.add_structure("rampart", center + Vector2i(1, 0), 0)
		game.state.add_structure("lance", center + Vector2i(0, 1), 0)
		game.state.add_structure("generator", center + Vector2i(-1, 1), 0)
		game.state.add_structure("generator", center + Vector2i(-1, 0), 0)
		game.state.add_unit("ravager", HexGrid.world(center - anchor.cell.sign() * 5), -1)
		game.state._update_power(0.05); game.state.update_visibility()
		game.renderer.initialize(game.state, 0)
		game.camera.focus = Vector3(HexGrid.world(center).x, 0, HexGrid.world(center).y)
		game.camera.distance = 22; game.camera.target_distance = 22; game.camera._update_transform()
		game.selection = [radar]; game._update_hud()
		for i in range(8): await process_frame
		RenderingServer.force_draw()
		DirAccess.make_dir_recursive_absolute("res://build/visual-review")
		root.get_texture().get_image().save_png("res://build/visual-review/sensors.png")
		game.audio.stop(); game.queue_free(); await process_frame
		print("Sensor review captured"); quit(); return
	var types := ["scout", "ranger", "excavator", "reaper", "cremator", "javelin"]
	var ids: Array = []
	for i in range(types.size()):
		var cell: Vector2i = center + Vector2i((i % 3) * 2 - 2, (i / 3) * 2 - 1)
		var id: int = game.state.add_unit(types[i], HexGrid.world(cell), 0)
		var driver: int = game.state.add_unit("operator", HexGrid.world(cell), 0)
		game.state.units[id].driver = driver
		game.state.units[driver].vehicle = id
		game.state.units[driver].job = {"kind": "riding"}
		ids.append(id)
	var passenger: int = game.state.add_unit("marine", game.state.units[ids[0]].pos, 0)
	game.state.units[passenger].vehicle = ids[0]
	game.state.units[ids[0]].passengers.append(passenger)
	game.state.update_visibility()
	game.renderer.initialize(game.state, 0)
	game.camera.focus = Vector3(HexGrid.world(center).x, 0, HexGrid.world(center).y)
	game.camera.distance = 17; game.camera.target_distance = 17
	game.camera._update_transform()
	game.selection = [ids[0]]; game._update_hud()
	for i in range(8): await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://build/visual-review")
	image.save_png("res://build/visual-review/vehicles.png")
	game.audio.stop(); game.queue_free()
	await process_frame
	print("Vehicle review captured")
	quit()
