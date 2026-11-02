extends SceneTree
const Content = preload("res://core/content.gd")
const Rules = preload("res://core/match_rules.gd")
const Rollback = preload("res://net/rollback_session.gd")

func _initialize() -> void:
	var content = Content.new()
	if not content.load_file("res://content/default.json"): quit(1); return
	var players := Rules.participants([{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}])
	var session = Rollback.new()
	session.initialize(content.data, players, 42, 0)
	for index in 122:
		session.simulation._spawn("marine" if index % 2 == 0 else "scavenger", 1 if index % 2 == 0 else 9, [index % 8 * 512 - 2048, 0, index / 8 * 128 - 1024])
	session.checkpoints[0] = session.simulation.checkpoint()
	for tick in 60:
		for id in [1, 9]:
			if id == 9 and tick == 5: continue
			session.receive(id, tick, [])
	var started := Time.get_ticks_usec()
	for tick in 40: session.advance()
	var advance_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	session.receive(9, 5, [{"kind": "move", "actors": [5], "point": [0, 0, 0]}])
	var replay_us := Time.get_ticks_usec() - started
	print("ATD_BENCHMARK " + JSON.stringify({"actors": session.simulation.state.actors.size(), "advance_us_per_tick": advance_us / 40,
		"rollback_ticks": session.replayed_ticks, "rollback_us": replay_us, "error": session.error}))
	quit(0 if session.error.is_empty() else 1)
