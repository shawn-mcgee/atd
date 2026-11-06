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
	if "--relay" in OS.get_cmdline_user_args():
		await relay_review(game, anchor); return
	if "--fog" in OS.get_cmdline_user_args():
		await fog_review(game, anchor)
		return
	for cell in HexGrid.disk(center, 8):
		if game.state.tiles.has(cell):
			game.state.tiles[cell].cliff = false
			game.state.known[0][cell] = true
	if "--walls" in OS.get_cmdline_user_args():
		await wall_review(game, center); return
	if "--buildings" in OS.get_cmdline_user_args():
		await building_review(game, center)
		return
	if "--memory" in OS.get_cmdline_user_args():
		var enemy_id: int = game.state.add_structure("womb", center, -1)
		game.state.visible[0] = {center: true}; game.state.known[0][center] = true
		game.state._remember_structures()
		game.state.visible[0].clear(); game.state.time_seconds += 15
		game.state._destroy(game.state.structures[enemy_id])
		game.renderer.initialize(game.state, 0)
		var point := HexGrid.world(center)
		game.camera.focus = Vector3(point.x, 0, point.y)
		game.camera.distance = 15; game.camera.target_distance = 15; game.camera._update_transform()
		game.selection = [enemy_id]; game._update_hud()
		game.set_process(false); game.camera.set_process(false)
		for i in range(10): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/visual-review")
		root.get_texture().get_image().save_png("res://build/visual-review/structure-memory.png")
		quit(); return
	if "--controls" in OS.get_cmdline_user_args():
		var crew: Array = []
		for i in range(3): crew.append(game.state.add_unit("engineer", HexGrid.world(anchor.cell + Vector2i(2 + i, -1)), 0))
		game.state.add_unit("marine", HexGrid.world(anchor.cell) + Vector2(0, -0.45), 0)
		game.renderer.initialize(game.state, 0)
		game.camera.focus = Vector3(HexGrid.world(anchor.cell).x, 0, HexGrid.world(anchor.cell).y)
		game.camera.distance = 17; game.camera.target_distance = 17; game.camera._update_transform()
		game.selection = crew; game._assign_group(1); game._update_hud()
		for i in range(8): await process_frame
		game.set_process(false); game.camera.set_process(false)
		var map_center: Vector2 = game.tactical.minimap_rect().get_center()
		var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = map_center
		root.push_input(press, true)
		await process_frame
		var motion := InputEventMouseMotion.new(); motion.position = map_center + Vector2(12, -8); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
		if not game.minimap_dragging or Vector2(game.camera.focus.x, game.camera.focus.z).distance_to(game.tactical.minimap_world(motion.position)) >= 0.01:
			printerr("Native minimap drag did not capture/pan"); quit(1); return
		var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = Vector2(500, 300)
		root.push_input(release, true)
		await process_frame
		if game.minimap_dragging or game.selection != crew:
			printerr("Native minimap release changed selection or retained capture"); quit(1); return
		var order := InputEventMouseButton.new(); order.button_index = MOUSE_BUTTON_RIGHT; order.pressed = true; order.shift_pressed = true; order.position = game.tactical.map_point(Vector2(12, 9))
		root.push_input(order, true)
		for i in range(4): await process_frame
		if game.state.units[crew[0]].orders.is_empty():
			printerr("Native Shift minimap command did not append an order"); quit(1); return
		for id in crew: game.state.units[id].orders.clear()
		game.pending_orders.clear(); game._focus_anchor()
		var site: Vector2i = anchor.cell + Vector2i(0, -2)
		game._choose_build("depot"); game.placement_strip.show()
		game.placement_text.text = "PLACING ORE DEPOT  /  20 Ore\nCLEAR SITE  /  SHIFT: queue + repeat   ESC: cancel"
		game._update_cursor()
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

func wall_review(game, center: Vector2i) -> void:
	game.set_process(false); game.set_physics_process(false); game.camera.set_process(false)
	for offset in [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(-2, 1), Vector2i(0, 1), Vector2i(1, 1)]: game.state.add_structure("wall", center + offset, 0)
	game.state.add_structure("generator", center + Vector2i(-3, 2), 0)
	game.state.add_structure("floodlight", center + Vector2i(-3, 3), 0)
	game.state._rebuild_navigation(); game.state._update_power(0); game.state.update_visibility()
	var worker: int = game.state.add_unit("engineer", HexGrid.world(center + Vector2i(-1, 3)), 0)
	game.renderer.initialize(game.state, 0)
	var point := HexGrid.world(center + Vector2i(0, 1))
	game.camera.focus = Vector3(point.x, 0, point.y); game.camera.distance = 15; game.camera.target_distance = 15; game.camera._update_transform()
	game.selection = [worker]; game.renderer.selection = [worker]; game.tactical.selected = [worker]; game._update_hud()
	game._choose_build("wall")
	var start := HexGrid.world(center + Vector2i(-2, -2)); var finish := HexGrid.world(center + Vector2i(2, -2))
	var screen: Vector2 = game.camera.unproject_position(Vector3(start.x, 0, start.y))
	var hover := InputEventMouseMotion.new(); hover.position = screen
	root.push_input(hover, true); await process_frame
	var press := InputEventMouseButton.new(); press.position = screen; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	root.push_input(press, true); await process_frame
	if not game.wall_dragging:
		printerr("Wall drag did not capture pointer at ", screen, "; hovered: ", root.gui_get_hovered_control())
		RenderingServer.force_draw(); DirAccess.make_dir_recursive_absolute("res://build/visual-review"); root.get_texture().get_image().save_png("res://build/visual-review/wall-line.png")
		quit(1); return
	screen = game.camera.unproject_position(Vector3(finish.x, 0, finish.y))
	var motion := InputEventMouseMotion.new(); motion.position = screen; motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true); await process_frame
	var plan: Dictionary = game.state.wall_line_plan(0, game.wall_start, game.wall_end)
	game.renderer.show_preview(Vector2i.ZERO, false); game.renderer.show_wall_line(plan.sites)
	game.placement_strip.show(); game.placement_text.text = "WALL LINE / %d CLEAR / %s\nRELEASE: place   SHIFT: append + repeat   ESC: cancel" % [plan.count, game._cost_text(plan.cost)]
	for i in range(4): await process_frame
	RenderingServer.force_draw(); DirAccess.make_dir_recursive_absolute("res://build/visual-review")
	root.get_texture().get_image().save_png("res://build/visual-review/wall-line.png")
	var release := InputEventMouseButton.new(); release.position = screen; release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true); await process_frame
	game._physics_process(0.05)
	var sites := 0
	for s in game.state.structures.values():
		if s.kind == "wall" and not s.built: sites += 1
	if sites != 5 or game.wall_dragging: printerr("Wall drag did not place all five cells: ", sites); quit(1); return
	game.audio.stop(); game.queue_free(); await process_frame
	print("Native wall drag passed; wall preview captured"); quit()

func relay_review(game, anchor: Dictionary) -> void:
	game.set_process(false); game.camera.set_process(false)
	var inward := Vector2i.ZERO
	for direction in HexGrid.DIRECTIONS:
		if inward == Vector2i.ZERO or HexGrid.distance(anchor.cell + direction) < HexGrid.distance(anchor.cell + inward): inward = direction
	var relay: int = game.state.add_structure("relay", anchor.cell + inward * 7, 0)
	game.state.add_structure("floodlight", anchor.cell + inward * 15, 0)
	for source in game.state.structures.values():
		for cell in HexGrid.disk(source.cell, 2):
			if game.state.tiles.has(cell): game.state.tiles[cell].cliff = false
	game.state._update_power(0); game.state.update_visibility()
	game.renderer.initialize(game.state, 0)
	var point := HexGrid.world(game.state.structures[relay].cell)
	game.camera.focus = Vector3(point.x, 0, point.y); game.camera.distance = 27; game.camera.target_distance = 27; game.camera._update_transform()
	game.selection = [relay]; game.tactical.selected = [relay]; game.renderer.selection = [relay]
	DirAccess.make_dir_recursive_absolute("res://build/visual-review")
	for mode in ["on", "off"]:
		if mode == "off": game.state.command(0, {"action": "toggle", "target": relay})
		game._update_hud(); game.renderer.refresh_tiles(); game.renderer.refresh_entities()
		game.tactical.queue_redraw()
		for i in range(4): await process_frame
		RenderingServer.force_draw(); root.get_texture().get_image().save_png("res://build/visual-review/relay-%s.png" % mode)
	game.audio.stop(); game.queue_free(); await process_frame
	print("Relay on/off coverage captured"); quit()

func fog_review(game, anchor: Dictionary) -> void:
	game.set_process(false); game.set_physics_process(false); game.camera.set_process(false)
	game.selection = [anchor.id]; game._update_hud()
	game.camera.distance = 18; game.camera.target_distance = 18; game.camera._update_transform()
	DirAccess.make_dir_recursive_absolute("res://build/visual-review")
	for sample in [0.0, 12.0]:
		game.renderer.display_time = sample; game.renderer.refresh_entities()
		for i in range(3): await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://build/visual-review/black-fog-%d.png" % int(sample))
	game.audio.stop(); game.queue_free(); await process_frame
	print("Black fog animation phases captured")
	quit()

func building_review(game, center: Vector2i) -> void:
	game.set_process(false); game.set_physics_process(false); game.camera.set_process(false)
	DirAccess.make_dir_recursive_absolute("res://build/visual-review")
	for i in range(3): await process_frame
	RenderingServer.force_draw(); root.get_texture().get_image().save_png("res://build/visual-review/industrial-expedition.png")
	game.state.units.clear(); game.state.structures.clear()
	var kinds := ["cradle", "armory", "factory", "foundry", "refinery", "synthesizer", "fabricator", "generator", "reactor", "relay", "radar", "floodlight", "sentry", "torch", "lance"]
	var ids: Array = []
	for i in range(kinds.size()):
		var cell := center + Vector2i((i % 5 - 2) * 3 - (i / 5 - 1), (i / 5 - 1) * 3)
		var id: int = game.state.add_structure(kinds[i], cell, 0)
		ids.append(id)
		var e: Dictionary = game.state.structures[id]
		e.powered = true; e.fuel = 20.0
		if kinds[i] in ["foundry", "refinery", "synthesizer"]: e.cycle = 2.0
		if kinds[i] == "factory": e.vehicles = [{"kind": "scout", "progress": 4.0}]
		if kinds[i] == "armory": e.kits = [{"kind": "marine", "progress": 10.0, "done": true}, {"kind": "flamer", "progress": 3.0, "done": false}, {"kind": "lancer", "progress": 0.0, "done": false}]
		if kinds[i] == "cradle": e.operators = [{"progress": 3.0}, {"progress": 0.0}, {"progress": 0.0}]
	for cell in HexGrid.disk(center, 16):
		if not game.state.tiles.has(cell): continue
		game.state.tiles[cell].cliff = false; game.state.tiles[cell].resource = ""
		game.state.known[0][cell] = true; game.state.visible[0][cell] = true
		if HexGrid.distance(cell, center) < 11: game.state.illuminated[0][cell] = true
	game.renderer.initialize(game.state, 0)
	var position := HexGrid.world(center)
	game.camera.focus = Vector3(position.x, 0, position.y)
	game.camera.distance = 25; game.camera.target_distance = 25; game.camera._update_transform()
	game.hud.hide(); game.renderer.display_time = 0.1
	game.renderer.refresh_entities()
	for id in ids:
		var label := Label3D.new(); label.text = str(game.state.structures[id].kind).to_upper()
		label.font_size = 28; label.pixel_size = 0.008; label.position = Vector3(0, 0.08, 1.35)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.modulate = Color("a9b2ae")
		game.renderer.bodies[id].add_child(label)
	for i in range(4): await process_frame
	RenderingServer.force_draw(); DirAccess.make_dir_recursive_absolute("res://build/visual-review")
	root.get_texture().get_image().save_png("res://build/visual-review/industrial-roster.png")
	# Same camera and facilities, now unpowered: compare state readability directly.
	for id in ids:
		game.state.structures[id].powered = false; game.state.structures[id].enabled = false
	game.renderer.refresh_entities()
	for i in range(3): await process_frame
	RenderingServer.force_draw(); root.get_texture().get_image().save_png("res://build/visual-review/industrial-offline.png")
	var armory: Dictionary = game.state.structures[ids[1]]
	armory.enabled = true; armory.powered = true
	var cradle: Dictionary = game.state.structures[ids[0]]
	cradle.enabled = true; cradle.powered = true
	position = HexGrid.world(armory.cell)
	game.camera.focus = Vector3(position.x - 1.6, 0, position.y + 0.3)
	game.camera.distance = 9; game.camera.target_distance = 9; game.camera._update_transform()
	game.renderer.refresh_entities()
	for i in range(3): await process_frame
	RenderingServer.force_draw(); root.get_texture().get_image().save_png("res://build/visual-review/industrial-queues.png")
	game.audio.stop(); game.queue_free(); await process_frame
	print("Building silhouettes, offline state, and physical queues captured")
	quit()
