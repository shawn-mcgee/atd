extends SceneTree
var frames := 0
var view

func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	view = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(view)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 2 and "--small" in OS.get_cmdline_user_args():
		root.content_scale_size = Vector2i(960, 640)
		root.size = Vector2i(960, 640)
	if frames == 8:
		for entry in [["--content", view.MENU_CONTENT], ["--multiplayer", view.MENU_MULTIPLAYER], ["--setup", view.MENU_SETUP], ["--guide", view.MENU_GUIDE]]:
			if entry[0] in OS.get_cmdline_user_args(): view.menu_tabs.current_tab = entry[1]
	if frames == 8 and "--arena" in OS.get_cmdline_user_args(): view._local()
	if frames == 8 and "--rally" in OS.get_cmdline_user_args():
		view._local()
		view.set_process(false)
		view.selected.assign([1])
		view._order({"kind": "rally", "point": [-4 * 1024, 0, 3 * 1024]})
		_advance(3)
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--paths" in OS.get_cmdline_user_args():
		view.faction.select(0)
		var content = view._content()
		content.data.settings.mission.enabled = false
		content.data.units.hq.capabilities.perception.radius = 12
		content.data.units.wall.footprint = []
		for r in range(-4, 5): content.data.units.wall.footprint.append([0, r])
		view.session.start_local(content.data, 42, "human")
		view.set_process(false)
		var game = view.session.rollback.simulation
		game._spawn("wall", 1, [-5 * 1024, 0, 0])
		game.entity(2).position = [-10 * 1024, 0, 3 * 1024]
		view.selected.assign([2])
		view._order({"kind": "move", "point": [1 * 1024, 0, 0]})
		_advance(3)
		view.camera.position.x -= 2
		view.selected.assign([2, 7])
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--walls" in OS.get_cmdline_user_args():
		view.faction.select(0)
		view._local()
		view.set_process(false)
		var game = view.session.rollback.simulation
		for cell in [[-6, 0], [-3, 0], [-1, 4]]:
			game._spawn("wall", 1, [int(cell[0]) * 1024, 0, int(cell[1]) * 1024])
			game.state.revealed["1"][view.Hex.key(cell)] = true
		_advance(3)
		view.selected.assign([1])
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--geometry" in OS.get_cmdline_user_args():
		var content = view._content()
		content.data.settings.mission.enabled = false
		content.data.settings.terrain = [[-6, -4], [-5, -4], [-5, -3]]
		content.data.units.wall.footprint = [[0, 0], [1, 0], [2, 0]]
		content.data.units.demo_cylinder = content.data.units.turret.duplicate(true)
		content.data.units.demo_cylinder.name = "Centered cylinder"
		content.data.units.demo_cylinder.capabilities = {"perception": {"radius": 3}}
		content.data.units.demo_cylinder.footprint = [[0, 0], [1, 0], [0, 1]]
		view.session.start_local(content.data, 42, "human")
		view.set_process(false)
		var game = view.session.rollback.simulation
		game._spawn("wall", 1, [-4 * 1024, 0, -2 * 1024])
		game._spawn("demo_cylinder", 1, [-4 * 1024, 0, 2 * 1024])
		view.selected.assign([2])
		view._order({"kind": "move", "point": [-2 * 1024, 0, -4 * 1024]})
		_advance(40)
		view.selected.assign([7, 8, 2])
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--visibility" in OS.get_cmdline_user_args():
		view.faction.select(0)
		view._local()
		view.set_process(false)
		view.selected.assign([3])
		view._order({"kind": "move", "point": [-1 * 1024, 0, 4 * 1024]})
		_advance(140)
		view._order({"kind": "move", "point": [-6 * 1024, 0, 2 * 1024]})
		_advance(140)
		view.selected.assign([1])
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--spawning" in OS.get_cmdline_user_args():
		view.faction.select(1)
		var content = view._content()
		content.data.units.nest.capabilities.passive_spawner.interval_ticks = 2
		content.data.units.nest.capabilities.passive_spawner.max_alive = 3
		view.session.start_local(content.data, 42, "lightless")
		view.set_process(false)
		_advance(7)
		view.selected.assign([1])
		view._sync_meshes()
		view._refresh_hud()
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
	if frames == 8 and "--illumination" in OS.get_cmdline_user_args():
		var content = view._content()
		content.data.settings.mission.enabled = false
		content.data.units.hq.capabilities.illumination.radius = 5
		view.session.start_local(content.data, 42, "human")
		view.set_process(false)
		var game = view.session.rollback.simulation
		for r in range(-2, 3): game._spawn("wall", 1, [-6 * 1024, 0, r * 1024])
		_advance(3)
		view.selected.assign([9])
		view.veil_overlay.show_illumination = true
		view.veil_overlay.show_perception = false
		view.veil_overlay.show_veil = false
		view._sync_meshes()
		view._refresh_hud()
	if frames == 8 and "--engineering" in OS.get_cmdline_user_args():
		view.faction.select(0)
		view._local()
		view.set_process(false)
		view.selected.assign([2])
		view._refresh_hud()
		view._begin_build()
		view._place_build([-6 * 1024, 0, 2 * 1024])
		_advance(45 if "--blueprint" in OS.get_cmdline_user_args() else 150)
		view.selected.assign([8])
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
	if "--content" in OS.get_cmdline_user_args(): path = "res://test-results/content-editor.png"
	if "--multiplayer" in OS.get_cmdline_user_args(): path = "res://test-results/multiplayer-menu.png"
	if "--setup" in OS.get_cmdline_user_args(): path = "res://test-results/match-setup.png"
	if "--guide" in OS.get_cmdline_user_args(): path = "res://test-results/guide.png"
	if "--mission" in OS.get_cmdline_user_args(): path = "res://test-results/mission.png"
	if "--paths" in OS.get_cmdline_user_args(): path = "res://test-results/paths.png"
	if "--rally" in OS.get_cmdline_user_args(): path = "res://test-results/rally.png"
	if "--walls" in OS.get_cmdline_user_args(): path = "res://test-results/walls.png"
	if "--geometry" in OS.get_cmdline_user_args(): path = "res://test-results/geometry.png"
	if "--visibility" in OS.get_cmdline_user_args(): path = "res://test-results/visibility.png"
	if "--illumination" in OS.get_cmdline_user_args(): path = "res://test-results/illumination.png"
	if "--engineering" in OS.get_cmdline_user_args(): path = "res://test-results/engineering-blueprint.png" if "--blueprint" in OS.get_cmdline_user_args() else "res://test-results/engineering.png"
	if "--spawning" in OS.get_cmdline_user_args(): path = "res://test-results/spawning.png"
	if "--construction" in OS.get_cmdline_user_args():
		path = "res://test-results/womb.png" if "--womb" in OS.get_cmdline_user_args() else "res://test-results/construction.png"
		if "--nest-loss" in OS.get_cmdline_user_args(): path = "res://test-results/nest-loss.png"
	if "--small" in OS.get_cmdline_user_args(): path = path.get_basename() + "-small.png"
	root.get_texture().get_image().save_png(path)
	quit()
