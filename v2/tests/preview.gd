extends SceneTree
var frames := 0
var view

func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	view = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(view)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 8 and "--arena" in OS.get_cmdline_user_args(): view._local()
	if frames == 8 and "--mission" in OS.get_cmdline_user_args():
		var content = view._content()
		content.data.settings.mission.threshold = 10
		content.data.settings.mission.repair_ticks = 2
		content.data.units.engineer.capabilities.move.speed = 15
		content.data.units.engineer.capabilities.mission_worker.mining_amount = 10
		content.data.units.engineer.capabilities.mission_worker.mining_interval_ticks = 1
		content.data.units.marine.capabilities.weapon.damage = 1000
		content.data.units.marine.capabilities.weapon.range = 24
		content.data.units.marine.capabilities.perception.radius = 24
		view.session._prepare(content.data, [{"id": 1, "faction": "human", "controller": "human"}, {"id": 2, "faction": "lightless", "controller": "human"}], 42)
		view.session._begin()
		view.set_process(false)
		view.selected.assign([2])
		view._context_order(7, [])
		_advance(12)
		view.selected.assign([3])
		view._order({"kind": "attack", "target": 4})
		_advance(3)
		view.selected.assign([2])
		view._context_order(0, view.session.rollback.simulation.state.mission.fields["4"].position)
		_advance(65)
		view._start_extraction()
		_advance(4)
		view.selected.assign([7])
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--construction" in OS.get_cmdline_user_args():
		view.faction.select(1)
		if "--nest-loss" in OS.get_cmdline_user_args():
			var content = view._content()
			content.data.units.marine.capabilities.weapon.damage = 1000
			content.data.units.marine.capabilities.weapon.range = 24
			content.data.units.marine.capabilities.perception.radius = 24
			view.session._prepare(content.data, [{"id": 1, "faction": "lightless", "controller": "human"}, {"id": 2, "faction": "human", "controller": "human"}], 42)
			view.session._begin()
		else: view._local()
		view.set_process(false)
		view.selected.assign([1])
		view._order({"kind": "train", "definition": "mother"})
		_advance(83)
		for actor in view.session.rollback.simulation.state.actors:
			if actor.definition == "mother": view.selected.assign([int(actor.id)])
		view._refresh_hud()
		view._begin_build()
		view._preview_build([-8 * 1024, 0, -2 * 1024])
		if "--womb" in OS.get_cmdline_user_args():
			view._place_build([-8 * 1024, 0, -2 * 1024])
			_advance(60)
		if "--nest-loss" in OS.get_cmdline_user_args():
			var rollback = view.session.rollback
			rollback.receive(2, int(rollback.simulation.state.tick) + rollback.input_delay, [{"kind": "attack", "actors": [6], "target": 1}])
			_advance(4)
		view._sync_meshes()
		view._refresh_hud()
	if frames == 30:
		RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)
	return false

func _advance(count: int) -> void:
	var rollback = view.session.rollback
	for tick in count:
		var future := int(rollback.simulation.state.tick) + int(rollback.input_delay)
		if rollback.human_ids.has(2) and not rollback.frames.get(future, {}).has(2): rollback.receive(2, future, [])
		view.session.advance()

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var path := "res://test-results/arena.png" if "--arena" in OS.get_cmdline_user_args() else "res://test-results/configurator.png"
	if "--mission" in OS.get_cmdline_user_args(): path = "res://test-results/mission.png"
	if "--construction" in OS.get_cmdline_user_args():
		path = "res://test-results/womb.png" if "--womb" in OS.get_cmdline_user_args() else "res://test-results/construction.png"
		if "--nest-loss" in OS.get_cmdline_user_args(): path = "res://test-results/nest-loss.png"
	root.get_texture().get_image().save_png(path)
	quit()
