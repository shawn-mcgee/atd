extends SceneTree
const Actor = preload("res://core/actor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	call_deferred("_run")

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	var view = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(view)
	await process_frame
	await process_frame
	_check(view.menu_tabs.current_tab == 0 and not view.editor_panel.is_visible_in_tree(), "menu opens on Play with content editor tucked away")
	_check(not view.menu_tabs.tabs_visible and view.menu_buttons.size() == 5, "main menu uses vertical navigation")
	_check(not view.faction.is_visible_in_tree() and not view.seed_value.is_visible_in_tree() and not view.room.is_visible_in_tree() and view.status.text.is_empty(), "landing screen hides configuration and connection details")
	for index in view.menu_buttons.size():
		view.menu_buttons[index].pressed.emit()
		_check(view.menu_tabs.current_tab == index and view.menu_buttons[index].button_pressed, "sidebar opens and highlights its matching page")
	view.menu_buttons[view.MENU_SETUP].pressed.emit()
	_check(view.faction.is_visible_in_tree() and view.seed_value.is_visible_in_tree() and not view.room.is_visible_in_tree(), "match setup groups faction and world settings")
	view.menu_buttons[view.MENU_MULTIPLAYER].pressed.emit()
	_check(view.room.is_visible_in_tree() and not view.network_lobby.is_visible_in_tree() and not view.ice.is_visible_in_tree(), "multiplayer groups room controls and folds advanced settings")
	view.menu_tabs.current_tab = view.MENU_CONTENT
	for frame in 12: await process_frame
	_check(view.editor_panel.is_visible_in_tree(), "Content tab opens source editing")
	_check(view.editor_panel.get_global_rect().end.x <= 1280, "content editor fits the viewport")
	_check(view.editor_panel.get_global_rect().end.y <= 800, "content editor fits vertically: " + str(view.editor_panel.get_global_rect()))
	root.content_scale_size = Vector2i(960, 640)
	root.size = Vector2i(960, 640)
	for frame in 12: await process_frame
	_check(view.menu_navigation.get_global_rect().end.x < view.editor.get_global_rect().position.x, "sidebar and editor remain separate in smaller windows")
	_check(view.lobby.get_global_rect().end.x <= 960 and view.lobby.get_global_rect().end.y <= 640 and view.editor.get_global_rect().end.x <= 960 and view.editor.get_global_rect().end.y <= 640, "menu and editor adapt to smaller windows")
	root.content_scale_size = Vector2i(1280, 800)
	root.size = Vector2i(1280, 800)
	view.menu_tabs.current_tab = view.MENU_PLAY
	_check(view.menu_buttons[view.MENU_PLAY].button_pressed and not view.menu_buttons[view.MENU_CONTENT].button_pressed, "programmatic navigation keeps the sidebar highlight in sync")
	_check(view.faction.get_item_text(0) == "Human", "faction selector uses Human")
	_check(view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera is orthographic")
	_check(view.camera.rotation_degrees == Vector3(-90, 0, 0), "camera is locked top-down")
	var config = view.config_editor
	_check(config.workspace.files.size() > 2 and config.file_tree.get_root() != null, "configurator lists all imported files")
	var main: String = config.workspace.root_path
	var engineer := main.get_base_dir().path_join("human/units/engineer.json")
	var marine := main.get_base_dir().path_join("human/units/marine.json")
	var original_source: String = config.workspace.files[engineer]
	config._show_file(engineer)
	view.editor.text = "{"
	config._show_file(main)
	config._show_file(engineer)
	_check(view.editor.text == "{" and config.workspace.dirty(engineer), "switching files preserves invalid unsaved edits")
	_check(view._content() == null and "engineer.json: JSON line" in view.status.text, "validation points to the broken imported file")
	var edited_definition: Dictionary = JSON.parse_string(original_source)
	edited_definition.units.engineer.hp = 19
	view.editor.text = JSON.stringify(edited_definition)
	config._show_file(main)
	var compiled = view._content()
	_check(compiled != null and int(compiled.data.units.engineer.hp) == 19, "starting/validation merges edits from inactive files")
	config.filter.text = "engineer"
	config.filter.text_changed.emit(config.filter.text)
	_check(config._items.has(engineer) and not config._items.has(marine), "file search narrows definitions by name")
	var project_text := JSON.stringify(config.workspace.project())
	config.load_text(project_text)
	compiled = view._content()
	_check(compiled != null and int(compiled.data.units.engineer.hp) == 19 and config.workspace.files.size() > 2, "project import retains individual editable source files")
	config.reset_defaults()
	_check(config.new_file("custom/test.json") and JSON.parse_string(config.workspace.files[config.workspace.root_path]).imports.has("custom/test.json"), "new file created from the main editor keeps its automatically added import")
	_check(view._content() != null, "empty imported draft does not invalidate an otherwise complete project")
	config.reset_defaults()
	view._local()
	view.set_process(false)
	var simulation = view.session.rollback.simulation
	view._refresh_hud()
	_check(not view.selection_panel.visible and view.selection_hint.visible and not view.extract_button.visible, "empty selection hides actor details, commands and unavailable extraction")
	view.selected.assign([1])
	view._refresh_hud()
	_check(view.production_panel.visible and not view.construction_panel.visible and not view.context_controls.repair.visible and not view.stance_panel.visible, "Human factory shows production without unrelated commands")
	_check(view.context_controls.rally.visible, "selected factory exposes rally control")
	var rally_before: String = simulation.state_hash()
	view._sync_orders(simulation)
	_check(view.get_node_or_null("RallyMarkers") != null and view.get_node_or_null("Orders") != null and simulation.state_hash() == rally_before, "selection shows rally flag and connection without mutating simulation")
	view._context_order(0, [0, 0, 0])
	_check(simulation.state_hash() == rally_before, "right-click rally is queued through session")
	for tick in 3: view.session.advance()
	_check(simulation.entity(1).rally_point == [0, 0, 0], "factory right-click sets rally through command queue")
	view.selected.assign([2])
	view._refresh_hud()
	view._sync_orders(simulation)
	_check(not view.context_controls.rally.visible and view.get_node_or_null("RallyMarkers") == null, "unit selection removes rally marker and unrelated command")
	_check(view.context_controls.repair.visible and not view.production_panel.visible and not view.context_controls.nacre.visible, "engineer shows repair and hides empty cargo delivery")
	view.selected.assign([1, 2])
	view._refresh_hud()
	_check(view.production_panel.visible and view.context_controls.repair.visible, "mixed selection keeps applicable group commands")
	view.selected.assign([4])
	view._refresh_hud()
	_check(not view.production_panel.visible and not view.stance_panel.visible and not view.context_controls.stop.visible, "enemy inspection exposes no owned actor commands")
	view.selected.clear()
	view._refresh_hud()
	_check(not view.selection_panel.visible and not view.context_controls.repair.visible and not view.production_panel.visible, "clearing selection removes stale commands")
	var details: Control = view.diagnostics.get_parent()
	var details_toggle: Button = details.get_parent().get_child(0)
	_check(not details.visible, "session diagnostics start collapsed")
	details_toggle.button_pressed = true
	_check(details.visible, "session details can be expanded")
	details_toggle.button_pressed = false
	var state_hash: String = simulation.state_hash()
	view.selected.assign([1, 3])
	view._sync_meshes()
	view._refresh_hud()
	view._focus_base()
	_check(simulation.state_hash() == state_hash, "drawing, selection and camera do not mutate gameplay")
	_check(view.actor_nodes.size() == simulation.state.actors.size(), "actors have primitive mesh views")
	_check(view.actor_nodes[3].get_node("WeaponRange").visible, "selected weapon range is inspectable")
	for actor: Actor in simulation.state.actors:
		var body = view.actor_nodes[int(actor.id)].get_node("Body")
		_check(body.mesh is CapsuleMesh or body.mesh is CylinderMesh, "every actor uses an allowed round mesh")
		_check(body.has_node("Facing") and body.get_node("Facing").visible, "every actor has an orientation indicator")
		var radius := float(simulation.content.units[actor.definition].visual.radius) * sqrt(3.0)
		_check(is_equal_approx(float(body.mesh.radius if body.mesh is CapsuleMesh else body.mesh.top_radius), radius), "configured radius reaches the actor mesh")
	# The grid has unit-length center-to-vertex vectors. Its edge midpoint is the apothem.
	var edge_midpoint := (Vector3(cos(PI / 6.0), 0, sin(PI / 6.0)) + Vector3(0, 0, 1)) * 0.5
	for shape in ["capsule", "cylinder"]:
		for radius_in_tiles in [0.5, 1.0]:
			var definition: Dictionary = simulation.content.units.hq.duplicate(true)
			definition.visual.shape = shape
			definition.visual.radius = radius_in_tiles
			var unit_radius_node: Node3D = view._actor_node(simulation.entity(1), definition)
			var mesh = unit_radius_node.get_node("Body").mesh
			var mesh_radius := float(mesh.radius if mesh is CapsuleMesh else mesh.top_radius)
			var expected_radius: float = edge_midpoint.length() if radius_in_tiles == 0.5 else view._world([1024, 0, 0]).length()
			_check(is_equal_approx(mesh_radius, expected_radius), "radius half fits the hex; radius one equals adjacent tile-center spacing")
			_check(is_equal_approx(float(unit_radius_node.get_meta("radius")), mesh_radius), "picking uses the same inner-diameter scale as the mesh")
			unit_radius_node.queue_free()
	simulation.entity(2).facing = [1024, 0, 0]
	state_hash = simulation.state_hash()
	view._sync_meshes()
	var body: MeshInstance3D = view.actor_nodes[2].get_node("Body")
	var facing_line: MeshInstance3D = body.get_node("Facing")
	var vertices: PackedVector3Array = facing_line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(vertices[0] == Vector3.ZERO and vertices[1].length() > float(body.mesh.radius), "facing line starts at mesh origin and extends beyond the body")
	_check((-body.basis.z).is_equal_approx(Vector3.RIGHT) and simulation.state_hash() == state_hash, "mesh orientation follows state without drawing mutating it")
	var center: Vector2 = view.camera.unproject_position(view.actor_nodes[1].position)
	_check(view._pick(center) == 1, "round actors remain pickable at their center")
	view.selected.assign([1])
	view._order({"kind": "train", "definition": "marine"})
	_check(simulation.state_hash() == state_hash, "view queues commands without applying them")
	for tick in 3: view.session.advance()
	_check(int(simulation.state.banks["1"]) == 80, "queued command applies through the session")
	var progress: Dictionary = simulation.state.mission.humans["1"]
	simulation.entity(2).position = simulation.entity(int(progress.extraction)).position.duplicate()
	view.selected.assign([2])
	state_hash = simulation.state_hash()
	view._context_order(int(progress.extraction), [])
	_check(simulation.state_hash() == state_hash, "extraction repair UI queues without mutating state")
	for tick in 63: view.session.advance()
	_check(int(progress.repair_remaining) == 0, "context repair operates through rollback commands")
	simulation.entity(2).nacre = 10
	view._context_order(int(progress.extraction), [])
	for tick in 3: view.session.advance()
	simulation.entity(2).nacre = 10
	view._context_order(int(progress.extraction), [])
	for tick in 3: view.session.advance()
	view._refresh_hud()
	_check(int(progress.deposited) == 20 and not view.extract_button.disabled and "Nacre cargo 0/10" in view.inspector.text, "mission HUD separates delivered nacre from cargo and enables explicit extraction")
	state_hash = simulation.state_hash()
	view._start_extraction()
	_check(simulation.state_hash() == state_hash, "extraction button queues its start command")
	for tick in 3: view.session.advance()
	_check(int(progress.countdown) == 200, "extraction starts with a full countdown after input delay")
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
	view._refresh_hud()
	_check("Passive Scavenger: 0/6 alive" in view.inspector.text and "Next birth:" in view.inspector.text, "source inspector exposes passive count and timer")
	view.stance_choices.select(1)
	view._set_veil_stance()
	_check(simulation.state_hash() == state_hash, "stance controls enqueue rather than mutate")
	for tick in 3: view.session.advance()
	_check(simulation.state.veil.networks["1"].stance == "defensive", "stance UI applies through rollback commands")
	simulation.entity(2).chyme = 7
	view.selected.assign([2])
	view._refresh_hud()
	_check("Chyme cargo 7/50" in view.inspector.text and "Chyme reserve" in view.stats.text, "HUD separates cargo from reserve")
	state_hash = simulation.state_hash()
	var reserve := int(simulation.state.banks["1"])
	view._context_order(1, [])
	_check(simulation.state_hash() == state_hash, "right-click delivery enqueues without mutating simulation")
	for tick in 3: view.session.advance()
	_check(int(simulation.entity(2).chyme) == 0 and int(simulation.state.banks["1"]) == reserve + 7, "context delivery applies through rollback commands")
	simulation._spawn("mother", 1, [simulation.entity(1).position[0], 0, -2 * 1024])
	var mother_id := int(simulation.state.next_id) - 1
	view.selected.assign([mother_id])
	view._sync_meshes()
	view._refresh_hud()
	_check(view.construction_panel.visible and not view.production_panel.visible and not view.context_controls.cancel.visible, "Mother shows construction choices without Womb cancellation")
	_check(not view.structures.disabled and not view.build_button.disabled, "Mother exposes build choices")
	var site: Array = simulation.entity(mother_id).position.duplicate()
	state_hash = simulation.state_hash()
	view._begin_build()
	view._preview_build(site)
	_check(view.placement_preview.visible and simulation.state_hash() == state_hash, "placement preview is read-only")
	view._place_build(site)
	_check(simulation.state_hash() == state_hash, "placement queues construction without applying it")
	for tick in 3: view.session.advance()
	view._sync_meshes()
	view._refresh_hud()
	_check(simulation.entity(mother_id).definition == "womb" and view.actor_nodes[mother_id].get_meta("definition") == "womb", "Mother view changes to Womb after command applies")
	_check(view.context_controls.cancel.visible and not view.construction_panel.visible, "growing Womb replaces placement controls with cancellation")
	_check("Cancel refunds 40 chyme" in view.inspector.text, "Womb inspector exposes progress and refund")
	view._order({"kind": "cancel_build"})
	for tick in 3: view.session.advance()
	view._sync_meshes()
	_check(simulation.entity(mother_id).definition == "mother" and view.actor_nodes[mother_id].get_meta("definition") == "mother", "cancellation restores Mother view at the same actor ID")
	var bank_before := int(simulation.state.banks["1"])
	simulation.entity(1).hp = 0
	view.session.advance()
	state_hash = simulation.state_hash()
	view._refresh_hud()
	_check(simulation.state_hash() == state_hash and "Nest lost" in view.stats.text, "escalation HUD reads permanent state without mutating gameplay")
	_check(int(simulation.state.banks["1"]) == bank_before + 500 and "Nest lost: +500 chyme" in view.event_log.text, "confirmed Nest loss reports the one-time owned grant")
	view._confirmed_events([{"type": "nest_destroyed", "owner": 2, "amount": 999, "production_rate": 8, "construction_rate": 8}])
	_check(not "999" in view.event_log.text, "economic notices from other participants remain private")
	view._reset()
	var veil_only: Dictionary = view._content().data.duplicate(true)
	for definition in veil_only.units.values():
		if definition.faction == "lightless": definition.capabilities.erase("perception")
	view.session.start_local(veil_only, 42, "lightless")
	view.set_process(false)
	view.session.advance()
	simulation = view.session.rollback.simulation
	simulation.entity(6).position = simulation.entity(1).position.duplicate()
	state_hash = simulation.state_hash()
	view.veil_overlay.show_veil = false
	view.veil_overlay.show_perception = true
	view._sync_meshes()
	_check(view.actor_nodes[6].visible, "enemy mesh is shown through Veil perception without actor sensors")
	_check(view.veil_overlay.get_node("Perception").visible and not view.veil_overlay.get_node("Membrane").visible, "perception overlay shows membrane coverage independently of membrane fill")
	_check(simulation.state_hash() == state_hash, "Veil perception drawing remains read-only")
	view._reset()
	view.faction.select(0)
	view._local()
	view.set_process(false)
	simulation = view.session.rollback.simulation
	state_hash = simulation.state_hash()
	view._switch_control(1)
	_check(simulation.state_hash() == state_hash and view.session.controls(2) and not view.session.controls(1), "sandbox switches faction without changing simulation state")
	view.selected.assign([1, 4])
	view._order({"kind": "train", "definition": "scavenger"})
	for tick in 3: view.session.advance()
	_check(int(simulation.state.banks["1"]) == 100 and int(simulation.state.banks["2"]) < 100, "switched faction spends only its own bank through queued input")
	state_hash = simulation.state_hash()
	view._switch_control(2)
	_check(simulation.state_hash() == state_hash and view.session.controls(1) and view.session.controls(2), "sandbox both mode grants both participants without state mutation")
	view.selected.assign([2, 5])
	view._order({"kind": "move", "point": [0, 0, 0]})
	for tick in 3: view.session.advance()
	_check(simulation.entity(2).order.get("kind") == "move" and simulation.entity(5).order.get("kind") == "move", "mixed selection routes commands to each actor owner")
	view.veil_overlay.show_veil = true
	view._sync_meshes()
	_check(view.actor_nodes[1].visible and view.actor_nodes[4].visible, "both mode combines faction vision")
	state_hash = simulation.state_hash()
	var membrane: MeshInstance3D = view.veil_overlay.get_node("Membrane")
	var combined_vertices: int = membrane.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	_check(membrane.visible and combined_vertices == simulation.state.veil.cells.size() * 18, "both mode reveals every controlled faction's Veil tiles")
	view.selected.assign([1])
	view._sync_meshes()
	_check(membrane.visible and membrane.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == combined_vertices, "Human selection keeps Lightless tiles revealed in both mode")
	view.selected.assign([4])
	view._sync_meshes()
	_check(membrane.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == combined_vertices, "Lightless selection retains the same combined tile view")
	view.selected.assign([1, 4])
	view._sync_meshes()
	_check(view.veil_overlay.get_node("Links").visible, "mixed selection includes Lightless connections even with Human first")
	for surface_name in ["Perception", "Illumination"]:
		var surface: MeshInstance3D = view.veil_overlay.get_node(surface_name)
		var combined_count: int = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		view.veil_overlay.refresh(simulation, 1, view.selected)
		var human_count: int = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() if surface.visible else 0
		view.veil_overlay.refresh(simulation, 2, view.selected)
		var lightless_count: int = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() if surface.visible else 0
		_check(combined_count == human_count + lightless_count, "both mode combines " + surface_name + " overlays")
		view._sync_meshes()
	_check(simulation.state_hash() == state_hash, "combined tile and sense overlays never mutate exploration or gameplay")
	view._switch_control(0)
	_check(not membrane.visible, "switching back to Humans hides unseen Lightless tiles without advancing a tick")
	view.selected.assign([5])
	view._order({"kind": "stop"})
	for tick in 3: view.session.advance()
	_check(simulation.entity(5).order.get("kind") == "move", "single-faction mode rejects orders to the other faction")
	for tick in 130: view.session.advance()
	_check(view.session.rollback.confirmed_tick == int(simulation.state.tick) - 1 and view.session.error.is_empty(), "sandbox supplies idle frames for both factions beyond rollback window")
	await process_frame
	_check(view.hud.get_global_rect().end.y <= 800, "scrollable HUD stays inside the viewport")
	_geometry_view(view)
	_visibility_ground(view)
	_illumination_overlay(view)
	await _hud_interaction_stability(view)
	_engineering(view)
	view.queue_free()
	await process_frame
	print("ATD_VIEW " + JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _engineering(view) -> void:
	view._reset()
	view.faction.select(0)
	view._local()
	view.set_process(false)
	var simulation = view.session.rollback.simulation
	view.selected.assign([2])
	view._refresh_hud()
	_check(view.construction_panel.visible and view.structures.item_count == 2 and "Defense Turret" in view.structures.get_item_text(0), "engineer offers turret construction")
	var before: String = simulation.state_hash()
	view._begin_build()
	view._preview_build([-6144, 0, 2048])
	_check(view._build_error([-6144, 0, 2048]).is_empty() and simulation.state_hash() == before, "Human placement preview is read-only")
	view._place_build([-6144, 0, 2048])
	_check(simulation.state_hash() == before, "Human placement queues command")
	for tick in 3: view.session.advance()
	var site = simulation.entity(int(simulation.state.next_id) - 1)
	_check(site.construction.get("kind") == "blueprint" and int(simulation.state.banks["1"]) == 65, "queued placement creates paid blueprint")
	view.selected.assign([int(site.id)])
	view._refresh_hud()
	view._sync_meshes()
	_check(view.context_controls.cancel.visible and "Cancel refunds 35 credits" in view.inspector.text, "blueprint inspection exposes progress and full refund")
	view.selected.assign([2])
	view._order({"kind": "stop"})
	for tick in 3: view.session.advance()
	view._context_order(int(site.id), [])
	for tick in 3: view.session.advance()
	_check(simulation.entity(2).order.get("kind") == "construct", "right click resumes blueprint through commands")
	view._order({"kind": "cancel_build"})
	for tick in 3: view.session.advance()
	_check(simulation.entity(int(site.id)) == null and int(simulation.state.banks["1"]) == 100, "engineer cancellation refunds via session")

func _hud_interaction_stability(view) -> void:
	view._reset()
	view.faction.select(0)
	view._local()
	view.set_process(false)
	view.selected.assign([1])
	view._refresh_hud()
	await process_frame
	await process_frame
	var legend: Control = view.hud.find_child("VisibilityLegend", true, false)
	_check(legend.get_combined_minimum_size().y < 60 and legend.size.x <= view.hud.size.x, "visibility legend stays compact without character-by-character wrapping")
	var churn: Array = []
	var production_changed := func(): churn.append("production")
	view.production_panel.visibility_changed.connect(production_changed)
	view.products.grab_focus()
	view.products.show_popup()
	for refresh in 8: view._refresh_hud()
	await process_frame
	_check(churn.is_empty() and view.products.get_popup().visible, "HUD refresh keeps production panel and open dropdown stable")
	view.products.get_popup().hide()
	view.products.select(1)
	view._refresh_hud()
	_check(view.products.selected == 1 and view.products.has_focus(), "HUD refresh preserves dropdown selection and focus")
	view.production_panel.visibility_changed.disconnect(production_changed)
	view.selected.assign([2])
	view._refresh_hud()
	await process_frame
	await process_frame
	churn.clear()
	var construction_changed := func(): churn.append("construction")
	var command_changed := func(): churn.append("command")
	view.construction_panel.visibility_changed.connect(construction_changed)
	view.context_controls.attack.visibility_changed.connect(command_changed)
	view.context_controls.attack.grab_focus()
	for refresh in 8: view._refresh_hud()
	_check(churn.is_empty() and view.context_controls.attack.has_focus(), "refresh does not hide active commands or release focus")
	view.structures.show_popup()
	for refresh in 8: view._refresh_hud()
	await process_frame
	_check(view.structures.get_popup().visible, "construction dropdown stays open across refreshes")
	view.structures.get_popup().hide()
	await process_frame
	var point: Vector2 = view.build_button.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.global_position = point
	down.pressed = true
	root.push_input(down)
	for refresh in 8: view._refresh_hud()
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	root.push_input(up)
	_check(view._target_mode == "build", "button click completes when refresh occurs between press and release")
	view.construction_panel.visibility_changed.disconnect(construction_changed)
	view.context_controls.attack.visibility_changed.disconnect(command_changed)
	var simulation = view.session.rollback.simulation
	var progress: Dictionary = simulation.state.mission.humans["1"]
	progress.repair_remaining = 0
	progress.deposited = int(simulation.content.settings.mission.threshold)
	view._refresh_hud()
	churn.clear()
	var extraction_changed := func(): churn.append("extraction")
	view.extract_button.visibility_changed.connect(extraction_changed)
	view.extract_button.grab_focus()
	for refresh in 8: view._refresh_hud()
	_check(churn.is_empty() and view.extract_button.has_focus() and not view.extract_button.disabled, "ready extraction button stays visible and focused during refresh")
	view.extract_button.visibility_changed.disconnect(extraction_changed)
	view._reset()
	view.faction.select(1)
	view._local()
	view.set_process(false)
	for tick in 20: view.session.advance()
	view.selected.assign([1])
	view._refresh_hud()
	await process_frame
	churn.clear()
	var stance_changed := func(): churn.append("stance")
	view.stance_panel.visibility_changed.connect(stance_changed)
	view.stance_choices.show_popup()
	for refresh in 8: view._refresh_hud()
	await process_frame
	_check(churn.is_empty() and view.stance_choices.get_popup().visible, "Veil stance panel and dropdown remain stable during refresh")
	view.stance_choices.get_popup().hide()
	view.stance_panel.visibility_changed.disconnect(stance_changed)

func _illumination_overlay(view) -> void:
	view._reset()
	var content = view._content()
	var data: Dictionary = content.data.duplicate(true)
	data.settings.mission.enabled = false
	for definition in data.units.values():
		for cap in ["illumination", "perception", "veil_source", "passive_spawner"]: definition.capabilities.erase(cap)
	data.units.hq.capabilities.illumination = {"radius": 2}
	view.session.start_local(data, 42, "human")
	view.set_process(false)
	var game = view.session.rollback.simulation
	game.entity(1).position = [0, 0, 0]
	game._spawn("wall", 1, [1024, 0, 0])
	game.step([])
	view.veil_overlay.show_illumination = true
	view.veil_overlay.show_perception = false
	view.veil_overlay.clear()
	var before: String = game.state_hash()
	view.veil_overlay.refresh(game, 1, [])
	var surface = view.veil_overlay.get_node("Illumination")
	var blocked_count: int = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	_check(blocked_count == game.illumination_cells(1).size() * 12 and not game.illumination_cells(1).has("2,0"), "illumination overlay draws reached hexes with wall shadow")
	_check(game.state_hash() == before, "light overlay never mutates gameplay state")
	game.entity(7).hp = 0
	game.step([])
	view.veil_overlay.refresh(game, 1, [])
	_check(surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > blocked_count, "light overlay expands after blocker destruction")

func _visibility_ground(view) -> void:
	view._reset()
	var content = view._content()
	var data: Dictionary = content.data.duplicate(true)
	data.settings.mission.enabled = false
	for definition in data.units.values():
		for cap in ["illumination", "perception", "detection", "veil_source", "passive_spawner"]: definition.capabilities.erase(cap)
	data.units.hq.capabilities.illumination = {"radius": 1}
	data.units.marine.capabilities.perception = {"radius": 1}
	data.units.engineer.capabilities.detection = {"radius": 24}
	view.session.start_local(data, 42, "human")
	view.set_process(false)
	var game = view.session.rollback.simulation
	game.entity(1).position = [0, 0, 0]
	game.entity(3).position = [4 * 1024, 0, 0]
	game.state.revealed["1"] = {}
	game.state.revealed["1"]["-4,0"] = true
	game.step([])
	var ground = view.visibility_ground
	var before: String = game.state_hash()
	view._sync_meshes()
	_check(ground.cells.get("0,0") == ground.State.ILLUMINATED and game.visibility_at(1, [0, 0, 0]) == 2, "illuminated tiles display as lit and always provide perception")
	_check(ground.cells.get("4,0") == ground.State.PERCEIVED, "perceived unlit tiles have a distinct ground state")
	_check(ground.cells.get("-4,0") == ground.State.FOG, "remembered unseen ground displays fog")
	_check(ground.tile_state(game, [1], [0, 6]) == ground.State.DARK and game.visibility_at(1, [0, 0, 6 * 1024]) == 1, "detection-only unexplored tiles remain dark")
	_check(game.state_hash() == before, "ground visibility rendering is read-only")
	var mesh = ground.surface.mesh
	view.selected.assign([2])
	view._sync_meshes()
	_check(ground.surface.mesh == mesh, "selection changes do not rebuild or flash ground visibility")
	game.step([])
	view._sync_meshes()
	_check(ground.surface.mesh == mesh, "advancing an unchanged tick retains ground mesh")
	for key in ground.cells:
		var parts: PackedStringArray = str(key).split(",")
		_check(ground.cells[key] == ground.tile_state(game, [1], [int(parts[0]), int(parts[1])]), "batched ground visibility matches simulation query")
	var saved: Dictionary = game.checkpoint()
	game.entity(3).position = [6 * 1024, 0, 0]
	game.step([])
	view._sync_meshes()
	_check(ground.cells.get("4,0") == ground.State.FOG, "lost perception leaves remembered fog")
	game.entity(1).position = [-2 * 1024, 0, 0]
	game.step([])
	view._sync_meshes()
	_check(ground.cells.get("0,0") == ground.State.FOG, "lost illumination leaves remembered fog")
	game.restore(saved)
	view._sync_meshes()
	_check(ground.cells.get("0,0") == ground.State.ILLUMINATED and ground.cells.get("4,0") == ground.State.PERCEIVED, "rollback restores tile visibility")
	# Equal-tick corrections must refresh the display as well.
	game.entity(1).position = [-2 * 1024, 0, 0]
	view._sync_meshes()
	_check(ground.cells.get("0,0") == ground.State.FOG, "same-tick corrected visibility invalidates ground cache")
	game.state.veil.cells["0,6"] = {"q": 0, "r": 6, "owner": 2, "hp": 10, "sources": [], "network": 0}
	game.state.veil.network_dirty = true
	game.step([])
	view._switch_control(2)
	view._sync_meshes()
	_check(ground.cells.get("0,6") == ground.State.PERCEIVED, "both-faction mode combines owned Veil perception")
	view._switch_control(0)
	view._sync_meshes()
	_check(not ground.cells.has("0,6"), "switching back to Humans hides Lightless-only ground")
	game.content.units.marine.capabilities.erase("perception")
	view.veil_overlay.show_perception = true
	view.veil_overlay.show_illumination = false
	view.veil_overlay.clear()
	view.veil_overlay.refresh(game, 1, [])
	var perceived = view.veil_overlay.get_node("Perception")
	_check(perceived.visible and perceived.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == game.illumination_cells(1).size() * 12, "perception inspection includes illuminated tiles without a perception capability")
	view._reset()
	_check(not ground.surface.visible and ground.cells.is_empty(), "returning to menu clears ground visibility")

func _geometry_view(view) -> void:
	view._reset()
	var content = view._content()
	var data: Dictionary = content.data.duplicate(true)
	data.settings.mission.enabled = false
	data.units.wall.footprint = [[0, 0], [1, 0], [2, 0]]
	data.units.test_cylinder = data.units.turret.duplicate(true)
	data.units.test_cylinder.footprint = [[0, 0], [1, 0], [2, 0]]
	data.settings.terrain = [[-5, -2], [-4, -2], [15, -10]]
	view.session.start_local(data, 42, "human")
	view.set_process(false)
	var game = view.session.rollback.simulation
	game._spawn("wall", 1, [-3 * 1024, 0, 0])
	game._spawn("test_cylinder", 1, [-3 * 1024, 0, 3 * 1024])
	view.selected.assign([7])
	var before: String = game.state_hash()
	view._sync_meshes()
	_check(view.actor_nodes[7].get_node("Body").mesh is ImmediateMesh, "footprint shape renders extruded occupied hexes")
	_check(view.actor_nodes[7].position.is_equal_approx(view._world([-2 * 1024, 0, 0])) and view.actor_nodes[8].position.is_equal_approx(view._world([-2 * 1024, 0, 3 * 1024])), "footprint and cylinder bodies share the geometric centroid")
	_check(view._pick(view.camera.unproject_position(view._world([-1 * 1024, 0, 3 * 1024]))) == 8, "full footprint remains pickable away from center")
	_check(view.get_node("Terrain").visible and view.get_node("Terrain").mesh.get_aabb().end.x < 0, "terrain renders known cells without exposing unexplored obstacles")
	_check(game.state_hash() == before, "footprint rendering and picking never mutate gameplay")
	game.entity(7).rotation = 1
	before = game.state_hash()
	view._sync_meshes()
	_check(view.actor_nodes[7].position.is_equal_approx(view._world([-3 * 1024, 0, 1 * 1024])) and game.state_hash() == before, "rotated footprints rebuild meshes around their new centroid")
	view.selected.assign([2])
	view._refresh_hud()
	view.structures.select(1)
	view._begin_build()
	var rotate := InputEventKey.new()
	rotate.pressed = true
	rotate.physical_keycode = KEY_R
	view._unhandled_input(rotate)
	for cell in [[0, 0], [0, 1], [0, 2]]: game.state.revealed["1"][view.Hex.key(cell)] = true
	before = game.state_hash()
	view._preview_build([0, 0, 0])
	_check(view._build_rotation == 1 and view.placement_preview.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 28 and game.state_hash() == before, "placement preview shows entire rotated footprint read-only")
	view._place_build([0, 0, 0])
	_check(game.state_hash() == before, "rotated placement is queued rather than applied by the view")
	for tick in 3: view.session.advance()
	var site = game.entity(9)
	_check(site != null and int(site.rotation) == 1 and view.Geometry.cells(game, site) == [[0, 0], [0, 1], [0, 2]], "session preserves footprint rotation on blueprint")
	_construction_footprint(view, game, site, "rotated multi-tile blueprint")
	game.content.units.scavenger_spawner.footprint = [[0, 0], [1, 0], [0, 1]]
	game.content.units.scavenger_spawner.construction_ticks = 100
	game._spawn("mother", 1, [-4 * 1024, 0, -4 * 1024])
	var mother_id := int(game.state.next_id) - 1
	for cell in [[-4, -4], [-4, -3], [-5, -3]]: game.state.revealed["1"][view.Hex.key(cell)] = true
	game.step([{"kind": "build", "player": 1, "actors": [mother_id], "definition": "scavenger_spawner", "point": [-4 * 1024, 0, -4 * 1024], "rotation": 1}])
	var womb = game.entity(mother_id)
	_check(womb.definition == "womb" and view.Geometry.cells(game, womb) == [[-4, -4], [-4, -3], [-5, -3]], "Womb inherits asymmetric rotated target footprint")
	_construction_footprint(view, game, womb, "rotated multi-tile Womb")
	view._reset()

func _construction_footprint(view, game, actor: Actor, description: String) -> void:
	view.selected.assign([int(actor.id)])
	var before: String = game.state_hash()
	view._sync_meshes()
	var node: Node3D = view.actor_nodes[int(actor.id)]
	_check(node.get_node("Body").mesh is ImmediateMesh and node.has_node("FootprintRim"), description + " renders filled footprint geometry")
	var body: AABB = node.get_node("Body").mesh.get_aabb()
	var outline: AABB = node.get_node("Selection").mesh.get_aabb()
	_check(Vector2(body.position.x, body.position.z).is_equal_approx(Vector2(outline.position.x, outline.position.z)) and Vector2(body.size.x, body.size.z).is_equal_approx(Vector2(outline.size.x, outline.size.z)), description + " body covers the entire footprint boundary")
	_check(node.position.is_equal_approx(view._world(view.Geometry.center(game, actor))) and is_zero_approx(node.get_node("Body").rotation.y) and game.state_hash() == before, description + " preserves centroid, axial rotation and view isolation")
