extends SceneTree
## Render the actual 2D scene; fixtures enter gameplay through core APIs.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	if "--small" in OS.get_cmdline_user_args(): root.size = Vector2i(1100, 720)
	var game = load("res://scenes/top_down.tscn").instantiate()
	game.initial_seed = 42
	root.add_child(game); current_scene = game
	game.set_process(false)
	await process_frame
	var mode := "base"
	if "--briefing" not in OS.get_cmdline_user_args(): game.begin_run()
	else: mode = "briefing"
	if "--engineer" in OS.get_cmdline_user_args():
		mode = "engineer"; game.selected.assign([game.simulation.units[0]]); game.refresh_ui(); game.hud.show_tab("build")
	if "--outpost" in OS.get_cmdline_user_args():
		mode = "outpost"
		var sim = game.simulation
		sim.add_structure("generator", Vector3(5, 0, -4))
		sim.add_structure("barracks", Vector3(-6, 0, -3))
		sim.add_structure("repeater", Vector3(6, 0, -1))
		sim.add_structure("floodlight", Vector3(8, 0, -4))
		var jeep: SimUnit = sim.add_unit("jeep", Vector3(5, 0, 3))
		jeep.board(sim.add_unit("marine", jeep.position))
		sim.economy.recalculate(sim.structures); sim.power.tick(sim.structures, sim.economy, 0)
		sim.rebuild_navigation(); sim.rebuild_light(); sim.record_exploration(); sim.resource_fields.discover(sim)
		game.selected.assign([sim.units[0]]); game.refresh_ui()
	if "--gallery" in OS.get_cmdline_user_args():
		mode = "sprites"
		game.zoom = 25; game.focus = Vector2(0, -4)
		var sim = game.simulation
		for unit in sim.units: unit.position = Vector3(40, 0, 40)
		var kinds := ["core", "generator", "barracks", "garage", "depot", "gas_tank", "repeater", "floodlight", "scanner", "extractor", "turret", "laser_turret", "flame_turret", "wall", "gate", "platform", "ramp", "beacon"]
		for i in range(kinds.size()):
			var building: SimStructure = sim.add_structure(kinds[i], Vector3(-17 + (i % 6) * 6, 0, -13 + (i / 6) * 5))
			building.powered = true
		for i in range(9):
			var kind: String = ["engineer", "marine", "flamer", "scout", "jeep", "drill", "runner", "stalker", "brute"][i]
			if i < 6: sim.add_unit(kind, Vector3(-16 + i * 3.3, 0, 4))
			else:
				var enemy: SimPredator = sim.add_creature(Vector3(-16 + i * 3.3, 0, 4), 999, kind); enemy.visible = true
		for cell in sim.navigation.cells:
			var point: Vector3 = sim.Hex.to_world(cell, 1)
			if absf(point.x) < 23 and point.z > -20 and point.z < 8: sim.explored[cell] = "ground"
		sim.light.sources.clear(); sim.light.add_source(Vector3.ZERO, 100)
		sim.resource_fields.discover(sim)
		game.selected.clear(); game.selected_resource.clear(); game.refresh_ui()
	if "--combat" in OS.get_cmdline_user_args():
		mode = "combat"
		game.zoom = 48; game.focus = Vector2.ZERO
		var sim = game.simulation
		for unit in sim.units: unit.position = Vector3(40, 0, 40)
		for i in range(5):
			var kind: String = ["marine", "flamer", "turret", "laser_turret", "flame_turret"][i]
			var position := Vector3(-5, 0, -5 + i * 2.5)
			var actor: SimEntity = sim.add_unit(kind, position) if i < 2 else sim.add_structure(kind, position)
			if actor is SimStructure: actor.powered = true
			var enemy: SimPredator = sim.add_creature(Vector3(5, 0, position.z + 0.5), 999)
			enemy.visible = true
			sim.shot(actor.position + Vector3.UP * 1.2, enemy.position, Color("f28a42") if kind in ["flamer", "flame_turret"] else Color("e96fee") if kind == "laser_turret" else sim.AMBER, actor)
		for cell in sim.navigation.cells:
			var point: Vector3 = sim.Hex.to_world(cell, 1)
			if absf(point.x) < 12 and absf(point.z) < 9: sim.explored[cell] = "ground"
		sim.light.sources.clear(); sim.light.add_source(Vector3.ZERO, 100)
		game.sprites.tick(game, 0)
		game.selected.clear(); game.refresh_ui()
	if "--selection" in OS.get_cmdline_user_args():
		mode += "-selection"
		var gate: SimStructure = game.simulation.add_structure("gate", Vector3(0, 0, 4)); gate.powered = true
		game.selected.assign((game.simulation.units + game.simulation.structures + game.simulation.creatures).filter(func(actor): return actor.visible and actor.position.length() < 12))
		game.refresh_ui(); game.command_panel.visible = false
	if "--platforms" in OS.get_cmdline_user_args():
		mode += "-platforms"; game.zoom = 48; game.focus = Vector2(1, -1)
		for cell in [Vector2i(2, -2), Vector2i(3, -2), Vector2i(2, -1)]: game.simulation.add_structure("platform", game.Hex.to_world(cell, 1))
		game.simulation.rebuild_navigation(); game.simulation.rebuild_light(); game.simulation.record_exploration()
	if "--extractor" in OS.get_cmdline_user_args():
		mode = "extractor"; game.zoom = 44
		var sim = game.simulation
		var center: Vector3 = sim.Hex.to_world(Vector2i(6, -4), 1)
		for unit in sim.units: unit.position = Vector3(30, 0, 30)
		for i in range(7):
			var offsets: Array = [Vector2i.ZERO] + sim.Hex.NEIGHBORS
			sim.add_resource_patch("minerals" if i < 4 else "gas", center + sim.Hex.to_world(offsets[i], 1), 100 + i * 20)
			sim.resource_nodes[-1].discovered = true
		sim.add_structure("generator", center + Vector3(-5, 0, 0))
		sim.add_structure("floodlight", center + Vector3(0, 0, 4))
		var extractor: SimStructure = sim.add_structure("extractor", center)
		sim.rebuild_navigation(); sim.power.tick(sim.structures, sim.economy, 0); sim.rebuild_light(); sim.record_exploration()
		game.focus = Vector2(center.x, center.z)
		game.selected.assign([extractor]); game.selected_resource.clear(); game.refresh_ui()
	if "--resource" in OS.get_cmdline_user_args():
		game.simulation.resource_fields.discover(game.simulation)
		for patch in game.simulation.resource_nodes:
			if patch.discovered and patch.remaining > 0:
				game.selected.clear(); game.selected_resource = patch; break
		game.refresh_ui(); mode += "-resource"
	if "--cliffs" in OS.get_cmdline_user_args():
		mode += "-cliffs"; game.zoom = 48; game.focus = Vector2(1, -1)
		for cell in [Vector2i(2, -2), Vector2i(3, -2), Vector2i(2, -1)]:
			game.simulation.rocks.append({"position": game.Hex.to_world(cell, 1), "cell": cell, "radius": 0.82, "height": 4})
		game.simulation.rebuild_navigation(); game.simulation.record_exploration()
	if "--walls" in OS.get_cmdline_user_args():
		mode = "walls"; game.zoom = 50; game.focus = Vector2(-6.928203, 1.5)
		var walls: Array[SimStructure] = []
		for cell in [Vector2i(-5, 0), Vector2i(-4, 0), Vector2i(-3, 0), Vector2i(-4, 1), Vector2i(-4, 2)]:
			walls.append(game.simulation.add_structure("wall", game.Hex.to_world(cell, 1)))
		game.simulation.rebuild_navigation(); game.simulation.light.add_source(Vector3(-6.928203, 0, 1.5), 14); game.simulation.record_exploration()
		game.selected.assign(walls); game.refresh_ui()
	if "--gates" in OS.get_cmdline_user_args():
		mode = "batch7"; game.zoom = 64; game.focus = Vector2(-6, 0)
		var sim = game.simulation
		var examples: Array[SimStructure] = []
		for i in range(3):
			var gate: SimStructure = sim.add_structure("gate", sim.Hex.to_world(Vector2i(-6 + i * 2, 0), 1))
			gate.powered = true; gate.build_direction = i
			gate.gate_open = i != 0
			game.sprites.gates[gate.simulation_id] = [0.0, 0.5, 1.0][i]
			examples.append(gate)
		for cell in [Vector2i(-6, -2), Vector2i(-5, -2), Vector2i(-4, -2)]: examples.append(sim.add_structure("wall", sim.Hex.to_world(cell, 1)))
		sim.rebuild_navigation(); sim.light.add_source(Vector3(-6, 0, 0), 20); sim.record_exploration()
		game.selected.assign(examples); game.refresh_ui()
	if "--placement" in OS.get_cmdline_user_args():
		mode += "-placement"
		game.selected.assign([game.simulation.units[0]]); game.refresh_ui(); game.choose_build("garage")
		game.mouse_world = game.Hex.to_world(Vector2i(-4, 0), 1)
		game.placement_direction = 1 if "--rotated" in OS.get_cmdline_user_args() else 0
		game.simulation.light.add_source(game.mouse_world, 12); game.simulation.record_exploration()
	game.queue_redraw()
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://art_source/.build"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/top-down-" + mode + ("-small" if "--small" in OS.get_cmdline_user_args() else "") + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("PREVIEW: ", path, " / ", error_string(error))
	game.queue_free(); await process_frame
	quit(0 if error == OK else 1)
