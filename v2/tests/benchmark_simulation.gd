extends SceneTree
func _initialize():
	var content = preload("res://core/content.gd").new(); content.load_file("res://content/default.json")
	var game = preload("res://core/simulation.gd").new()
	game.initialize(content.data, [{"id":1,"faction":"human","controller":"human"},{"id":9,"faction":"lightless","controller":"human"}],42)
	for tick in 600: game.step([])
	var steps:=0; var copies:=0; var hashes:=0; var samples: Array = []
	for tick in 60:
		var t:=Time.get_ticks_usec(); game.step([]); var elapsed := Time.get_ticks_usec()-t; steps+=elapsed; samples.append(elapsed)
		t=Time.get_ticks_usec(); game.checkpoint(); copies+=Time.get_ticks_usec()-t
		t=Time.get_ticks_usec(); game.state_hash(); hashes+=Time.get_ticks_usec()-t
	samples.sort()
	print("ATD_SIMULATION_BENCHMARK " + JSON.stringify({"step_us":steps/60,"checkpoint_us":copies/60,"hash_us":hashes/60,"step_p95_us":samples[56],"actors":game.state.actors.size(),"veil":game.state.veil.cells.size()}))
	quit()
