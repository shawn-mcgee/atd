extends SceneTree
## Render the actual 2D scene; fixtures enter gameplay through core APIs.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
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
	game.queue_redraw()
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://art_source/.build"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/top-down-" + mode + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("PREVIEW: ", path, " / ", error_string(error))
	game.queue_free(); await process_frame
	quit(0 if error == OK else 1)
