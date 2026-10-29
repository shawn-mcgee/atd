extends SceneTree
## Run both headless (triangle fallback) and with graphics (real ID-buffer readback).
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ", description)
	else: failures += 1; push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func click_point(game, actor: Node3D, local_point: Vector3) -> Node3D:
	return await game.pick(game.camera.unproject_position(actor.global_transform * local_point))

func run_checks() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	await physics_frame
	await process_frame
	game.set_process(false); game.begin_run()
	game.focus = Vector3(25, 0, -15); game.camera_zoom = 24; game.update_camera()
	var engineer: ExpeditionUnit = game.add_unit("engineer", Vector3(21, 0, -15))
	var vehicle: ExpeditionUnit = game.add_unit("jeep", Vector3(28, 0, -15))
	var relay: ExpeditionStructure = game.add_structure("repeater", Vector3(25, 0, -24))
	await process_frame
	check(await click_point(game, engineer, Vector3(0, 1.9, 0)) == engineer, "clicking the visible engineer helmet selects the engineer")
	check(await click_point(game, engineer, Vector3(0.2, 0.3, 0.05)) == engineer, "clicking visible boots selects the engineer")
	check(await click_point(game, engineer, Vector3(0.4, 1.1, -0.7)) == engineer, "clicking the rifle selects the engineer")
	check(await click_point(game, vehicle, Vector3(0, 1.1, -1.0)) == vehicle, "clicking the jeep hood selects the jeep")
	check(await click_point(game, vehicle, Vector3(1.2, 0.45, 1.1)) == vehicle, "clicking a visible wheel selects the jeep")
	check(await click_point(game, relay, Vector3(0, 2.5, 0)) == relay, "clicking an elevated structure light selects the structure")
	var tag: Label3D
	for child in relay.get_children():
		if child is Label3D: tag = child; break
	var text_bounds := tag.get_aabb()
	var label_side := text_bounds.get_center() + Vector3(text_bounds.size.x * 0.4, 0, 0)
	var name_point: Vector3 = tag.global_position + game.camera.global_basis.scaled(tag.global_basis.get_scale()) * label_side
	check(await game.pick(game.camera.unproject_position(name_point)) == null, "structure name labels do not intercept model or terrain picking")
	var geometry_only := true
	for entry in game.picker.entries:
		if entry.source is Label3D: geometry_only = false
	check(geometry_only, "ID pass contains no structure-name label proxies")
	var clear_point := Vector3(25.3, 0, -5.2)
	var clear_screen: Vector2 = game.camera.unproject_position(clear_point)
	check(await game.pick(clear_screen) == null, "empty terrain does not select an unrelated nearby actor")
	var hit: Dictionary = game.terrain_raycast(clear_screen)
	check(not hit.is_empty() and (hit.position as Vector3).distance_to(clear_point) < 0.002, "picker miss falls back to an actual terrain physics raycast")
	var inspector_ray: Dictionary = game.terrain_raycast(game.camera.unproject_position(vehicle.position + Vector3.UP))
	check(not inspector_ray.is_empty() and inspector_ray.collider == game.terrain_body, "terrain query ignores units and only uses the dedicated terrain collision layer")
	game.select_actor(engineer)
	await game.contextual_order(game.camera.unproject_position(vehicle.position + Vector3(0, 1.1, -1)))
	check(engineer.order == "board" and engineer.target == vehicle, "right-clicking the jeep model issues boarding before considering terrain")
	game.update_focus_lines()
	check(game.focus_overlay.segments.size() == 1 and game.focus_overlay.segments[0].target == vehicle, "selected boarding engineer has a focus line to the jeep")
	vehicle.position.x += 1.5; game.update_focus_lines()
	check((game.focus_overlay.segments[0].point as Vector3).distance_to(vehicle.position) < 0.001, "focus line follows a moving target")
	var destination := Vector3(25.37, 0, -7.81)
	await game.contextual_order(game.camera.unproject_position(destination))
	check(engineer.order == "move" and engineer.goal.distance_to(destination) < 0.002, "empty-ground right click preserves its exact raycast destination")
	game.update_focus_lines()
	check(game.focus_overlay.segments.size() == 1 and (game.focus_overlay.segments[0].point as Vector3).distance_to(destination) < 0.002, "selected moving engineer has a focus line to the destination")
	game.stop_selected(); game.update_focus_lines()
	check(game.focus_overlay.segments.is_empty(), "stop clears active focus lines")
	var blocker_point: Vector3 = engineer.position + Vector3.UP * 1.5 + game.camera.global_basis.z * 3
	var blocker: MeshInstance3D = game.Visual.box(game, Vector3(5, 5, 3), blocker_point, Color("405259"))
	game.picker.register_occluder(blocker)
	check(await click_point(game, engineer, Vector3(0, 1.9, 0)) == null, "foreground geometry prevents selecting an actor through an occluder")
	game.picker.remove_owner(blocker); blocker.queue_free()
	var helmet_screen: Vector2 = game.camera.unproject_position(engineer.position + Vector3.UP * 1.9)
	check(vehicle.board(engineer), "test infantry boards an empty driver seat")
	check(await game.pick(helmet_screen) == null, "hidden boarded infantry is absent from the picker")
	vehicle.disembark(engineer, Vector3(21, 0, -15))
	check(await click_point(game, engineer, Vector3(0, 1.9, 0)) == engineer, "disembarked infantry becomes selectable again")
	# Exercise real engine input dispatch, including mouse-down GPU capture.
	game.select_actor(null)
	var hood_screen: Vector2 = game.camera.unproject_position(vehicle.position + Vector3(0, 1.1, -1))
	var pointer := InputEventMouseMotion.new(); pointer.position = hood_screen; pointer.global_position = hood_screen
	Input.parse_input_event(pointer); await process_frame
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true
	down.position = hood_screen; down.global_position = hood_screen; down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	await process_frame
	check(game.selecting and game.pressed_pick != null, "mouse-down starts a real geometry pick through the scene input pipeline")
	if game.pressed_pick != null: await game.picker.resolve_pick(game.pressed_pick)
	vehicle.position.x += 3
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.position = hood_screen; up.global_position = hood_screen
	Input.parse_input_event(up)
	await process_frame
	await process_frame
	check(game.selected.size() == 1 and game.selected[0] == vehicle, "jeep selection uses mouse-down geometry even if the vehicle moves before release")
	game.focus = vehicle.position; game.update_camera()
	var peer: ExpeditionUnit = game.add_unit("jeep", vehicle.position + Vector3(-3, 0, 3))
	var offscreen: ExpeditionUnit = game.add_unit("jeep", Vector3(-70, 0, -15))
	var hidden: ExpeditionUnit = game.add_unit("jeep", vehicle.position + Vector3(3, 0, 3)); hidden.visible = false
	var dead: ExpeditionUnit = game.add_unit("jeep", vehicle.position + Vector3(5, 0, 0)); dead.hp = 0
	game.select_actor(engineer, true)
	hood_screen = game.camera.unproject_position(vehicle.position + Vector3(0, 1.1, -1))
	down.position = hood_screen; down.global_position = hood_screen; down.double_click = true
	Input.parse_input_event(down)
	await process_frame; await process_frame; await process_frame
	check(game.selected == [vehicle, peer] and not game.selecting and not game.selection_box.active, "double-click immediately selects on-screen units of the clicked type and excludes hidden, dead, and off-screen units")
	up.position = hood_screen; up.global_position = hood_screen; Input.parse_input_event(up)
	await process_frame; await process_frame
	check(game.selected == [vehicle, peer], "double-click release preserves the type selection without starting drag selection")
	game.select_actor(engineer); game.choose_expedition()
	Input.parse_input_event(down)
	await process_frame; await process_frame; await process_frame
	check(game.selected == [vehicle, peer] and not game.expedition_mode, "double-clicking a unit selects its visible type while expedition targeting is active")
	Input.parse_input_event(up); await process_frame
	game.select_actor(engineer); down.shift_pressed = true
	Input.parse_input_event(down)
	await process_frame; await process_frame; await process_frame
	check(game.selected.size() == 3 and game.selected.has(engineer) and game.selected.has(vehicle) and game.selected.has(peer), "Shift-double-click adds all visible units of the clicked type to the existing selection")
	Input.parse_input_event(up); await process_frame
	peer.position = Vector3(-65, 0, 40); dead.position = Vector3(-65, 0, 45)
	var colleague: ExpeditionUnit = game.add_unit("engineer", engineer.position + Vector3(3, 0, -2))
	var boarded: ExpeditionUnit = game.add_unit("engineer", vehicle.position); vehicle.board(boarded)
	game.focus = engineer.position; game.update_camera()
	down.position = game.camera.unproject_position(engineer.position + Vector3.UP * 1.9); down.global_position = down.position; down.shift_pressed = false
	Input.parse_input_event(down)
	await process_frame; await process_frame; await process_frame
	check(game.selected.has(engineer) and game.selected.has(colleague) and not game.selected.has(boarded) and game.selected.all(func(unit): return unit is ExpeditionUnit and unit.kind == "engineer" and unit.aboard == null), "double-click selects matching infantry while excluding boarded personnel and other unit types")
	up.position = down.position; up.global_position = up.position; Input.parse_input_event(up); await process_frame
	vehicle.disembark(boarded, Vector3(-60, 0, 45)); colleague.position = Vector3(-60, 0, 40)
	game.focus = Vector3(25, 0, -15); game.update_camera()
	down.shift_pressed = false; down.double_click = false
	game.select_actor(engineer); game.choose_build("floodlight")
	vehicle.position.x -= 3
	hood_screen = game.camera.unproject_position(vehicle.position + Vector3(0, 1.1, -1))
	down.position = hood_screen; down.global_position = hood_screen
	Input.parse_input_event(down)
	await process_frame
	await process_frame
	up.position = hood_screen; up.global_position = hood_screen; Input.parse_input_event(up)
	await process_frame
	await process_frame
	check(game.selected.size() == 1 and game.selected[0] == vehicle and game.build_kind.is_empty(), "clicking a jeep exits construction placement and selects its model")
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	game.camera_yaw = 0.85; game.camera_pitch = deg_to_rad(42); game.update_camera()
	check(await click_point(game, vehicle, Vector3(0, 1.1, -1)) == vehicle, "picker stays aligned after camera orbit, tilt, and native window resize")
	check(game.picker.view.size == Vector2i(1600, 900), "ID viewport matches the current game viewport resolution")
	var marine: ExpeditionUnit = game.add_unit("marine", Vector3(25, 0, -10))
	var enemy: ExpeditionPredator = game.add_creature(Vector3(30, 0, -10), 8)
	marine.focus_target = enemy
	game.light.sources.clear(); game.light.add_source(enemy.position, 5)
	game.select_actor(marine); game.update_focus_lines()
	check(game.focus_overlay.segments.size() == 1 and game.focus_overlay.segments[0].target == enemy, "selected combat unit shows its visible enemy focus")
	game.light.sources.clear(); game.update_focus_lines()
	check(game.focus_overlay.segments.is_empty(), "focus line cannot reveal an enemy after visibility is lost")
	var reads: int = game.picker.gpu_reads
	for i in range(4): await process_frame
	check(game.picker.gpu_reads == reads, "idle frames perform no picker image readback")
	if game.picker.gpu_enabled:
		check(game.picker.gpu_reads > 0 and game.picker.cpu_queries == 0, "graphics mode uses real GPU ID reads with no CPU picking fallback")
		if game.picker.last_image != null: game.picker.last_image.save_png("res://art_source/.build/picking-id-buffer.png")
	else: check(game.picker.cpu_queries > 0, "headless validation uses exact mesh triangle queries")
	print("PICKING_TEST_RESULT: ", failures, " failures; GPU reads=", game.picker.gpu_reads, " CPU queries=", game.picker.cpu_queries)
	quit(1 if failures else 0)
