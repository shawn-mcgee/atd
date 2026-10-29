extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false)
	var samples: Array[float] = []
	var completed := "--complete" in OS.get_cmdline_user_args()
	for i in range(8):
		var begin := Time.get_ticks_usec()
		game.add_structure("wall", Vector3(-50 + i * game.Terrain.SPACING, 0, 24), completed)
		game.rebuild_navigation()
		samples.append(float(Time.get_ticks_usec() - begin) / 1000)
		await process_frame
	print("PLACEMENT_MS ", samples)
	quit()
