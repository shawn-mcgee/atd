extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func snapshot(game, enabled: bool) -> Image:
	game.occluded_units.visible = enabled; game.occluded_units.sync(game.light)
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func different_pixels(a: Image, b: Image, region: Rect2i = Rect2i()) -> int:
	var result := 0
	if region.size == Vector2i.ZERO: region = Rect2i(Vector2i.ZERO, a.get_size())
	region = region.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.08: result += 1
	return result

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run()
	var center := Vector3(-55, 0, -8)
	game.focus = center; game.camera_zoom = 20; game.update_camera()
	var unit: ExpeditionUnit = game.add_unit("engineer", center)
	var enemy: ExpeditionPredator = game.add_creature(center + Vector3(-4, 0, 0), 77)
	game.light.sources.clear(); game.light.add_source(center, 20); game.refresh_visual_lights()
	enemy.visible = true
	game.occluded_units.sync(game.light)
	var has_creature := false
	for entry in game.occluded_units.entries:
		if entry.actor == enemy and entry.proxy.visible: has_creature = true
	check(has_creature, "visible creatures receive the occlusion overlay")
	enemy.visible = false; game.occluded_units.sync(game.light)
	var hidden := true
	for entry in game.occluded_units.entries:
		if entry.actor == enemy and entry.proxy.visible: hidden = false
	check(hidden, "hidden creatures never produce an occlusion silhouette")
	var vehicle: ExpeditionUnit = game.add_unit("jeep", center + Vector3(6, 0, 0))
	vehicle.board(unit); game.occluded_units.sync(game.light)
	var aboard_hidden := true
	for entry in game.occluded_units.entries:
		if entry.actor == unit and entry.proxy.visible: aboard_hidden = false
	check(aboard_hidden, "boarded units never produce silhouettes")
	vehicle.disembark(unit, center)
	var world_only := true
	for entry in game.occluded_units.occluders:
		if entry.owner is ExpeditionUnit or entry.owner is ExpeditionPredator or entry.source is Label3D: world_only = false
	check(world_only, "occlusion depth pass contains terrain and structures, never actors or name labels")
	if DisplayServer.get_name() != "headless":
		# Compare world rendering only; minimap exploration can update between
		# captures and is unrelated to occlusion highlighting.
		game.ui.visible = false; game.minimap.set_process(false)
		var baseline := await snapshot(game, false)
		var exposed := await snapshot(game, true)
		var exposed_delta := different_pixels(baseline, exposed)
		print("EXPOSED_HIGHLIGHT_PIXELS ", exposed_delta)
		check(exposed_delta < 10, "exposed actors do not highlight their own overlapping body parts")
		var blocker: MeshInstance3D = game.Visual.box(game, Vector3(12, 5, 3), center + Vector3.UP * 1.3 + game.camera.global_basis.z * 3, Color("53636a"))
		game.occluded_units.register_occluder(blocker)
		baseline = await snapshot(game, false)
		var covered := await snapshot(game, true)
		var covered_delta := different_pixels(baseline, covered)
		print("COVERED_HIGHLIGHT_PIXELS ", covered_delta)
		check(covered_delta > 50, "terrain/structure occlusion produces a visible silhouette of the covered unit")
		covered.save_png("res://art_source/.build/occluded-unit.png")
		var screen: Vector2 = game.camera.unproject_position(enemy.position + Vector3.UP)
		var creature_region := Rect2i(Vector2i(screen) - Vector2i(35, 40), Vector2i(70, 80))
		enemy.visible = true
		baseline = await snapshot(game, false)
		var visible_creature := await snapshot(game, true)
		check(different_pixels(baseline, visible_creature, creature_region) > 50, "already visible creatures highlight through the occluder")
		enemy.visible = false
		baseline = await snapshot(game, false)
		var hidden_creature := await snapshot(game, true)
		check(different_pixels(baseline, hidden_creature, creature_region) == 0, "hidden creatures contribute no silhouette pixels behind the same occluder")
	print("OCCLUDED_UNIT_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
