extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	call_deferred("_run")

func _run() -> void:
	var view = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(view)
	await process_frame
	await process_frame
	_check(view.editor_panel.get_global_rect().end.x <= 1280, "content editor fits the viewport")
	_check(view.editor_panel.get_global_rect().end.y <= 800, "content editor fits vertically")
	_check(view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera is orthographic")
	_check(view.camera.rotation_degrees == Vector3(-90, 0, 0), "camera is locked top-down")
	view._local()
	view.set_process(false)
	var simulation = view.session.rollback.simulation
	var state_hash: String = simulation.state_hash()
	view.selected.assign([1, 3])
	view._sync_meshes()
	view._refresh_hud()
	view._focus_base()
	_check(simulation.state_hash() == state_hash, "drawing, selection and camera do not mutate gameplay")
	_check(view.actor_nodes.size() == simulation.state.actors.size(), "actors have primitive mesh views")
	_check(view.actor_nodes[3].get_node("WeaponRange").visible, "selected weapon range is inspectable")
	view.selected.assign([1])
	view._order({"kind": "train", "definition": "marine"})
	_check(simulation.state_hash() == state_hash, "view queues commands without applying them")
	for tick in 3: view.session.advance()
	_check(int(simulation.state.banks["1"]) == 80, "queued command applies through the session")
	view._reset()
	view.faction.select(1)
	view._local()
	view.set_process(false)
	for tick in 20: view.session.advance()
	simulation = view.session.rollback.simulation
	view.selected.assign([1, 2])
	state_hash = simulation.state_hash()
	view._sync_meshes()
	view.veil_overlay.show_perception = true
	view.veil_overlay.show_illumination = true
	view.veil_overlay.refresh(simulation, 1, view.selected)
	view._refresh_hud()
	_check(simulation.state_hash() == state_hash, "membrane, connections, senses and stance inspection are read-only")
	_check(view.veil_overlay.get_node("Membrane").visible, "Lightless can inspect their Veil")
	_check(view.veil_overlay.get_node("Perception").visible, "perception overlay is available")
	view.selected.assign([1])
	view.stance_choices.select(1)
	view._set_veil_stance()
	_check(simulation.state_hash() == state_hash, "stance controls enqueue rather than mutate")
	for tick in 3: view.session.advance()
	_check(simulation.state.veil.networks["1"].stance == "defensive", "stance UI applies through rollback commands")
	await process_frame
	_check(view.hud.get_global_rect().end.y <= 800, "scrollable HUD stays inside the viewport")
	view.queue_free()
	await process_frame
	print("ATD_VIEW " + JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
