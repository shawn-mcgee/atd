extends SceneTree

var failures := 0

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures += 1; printerr("FAIL: ", message); quit(1)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted = true
	game._start_game(472, 1)
	var anchor: Dictionary = game.state.structures[int(game.state.players[0].anchor)]
	wall_paint_checks(game, anchor)
	model_selection_checks(game, anchor)
	facility_visual_checks(game, anchor)
	relay_control_checks(game, anchor)
	fog_visual_checks(game)
	var id: int = game.state.add_unit("operator", HexGrid.world(anchor.cell + Vector2i(2, 0)), 0)
	game.selection = [id]; game._update_hud()
	var before := false
	for button in game.actions.get_children():
		if button.text == "Build [B]": before = true
	game.state.units[id].kind = "engineer"
	game._update_hud()
	var after := false
	for button in game.actions.get_children():
		if button.text == "Build [B]": after = true
	verify(not before and after, "Specializing an Operator refreshes its command card")
	game.selection = [anchor.id]; game._update_hud()
	var control_id: int = game.personnel_controls.get_child(0).get_instance_id()
	game.state.resources(0).ore -= 1
	game._update_hud()
	verify(game.personnel_controls.get_child(0).get_instance_id() == control_id, "Income must not rebuild open personnel controls")
	game.state.command(0, {"action": "operator", "target": anchor.id})
	game._update_hud()
	var factory_id: int = game.state.add_structure("factory", anchor.cell + Vector2i(4, 0), 0)
	game.state.resources(0).alloy = 100
	game.selection = [factory_id]; game._update_hud()
	var vehicle_buttons := 0
	for button in game.actions.get_children():
		if button.text in ["Scout", "Ranger", "Excavator", "Reaper", "Cremator", "Javelin"]: vehicle_buttons += 1
	verify(vehicle_buttons == 6 and game.personnel_controls.get_child_count() == 2, "Factory exposes six vehicles and personnel source controls")
	game.state.command(0, {"action": "vehicle", "target": factory_id, "kind": "scout", "personnel": false})
	game._update_hud()
	verify(game.queue_view.cards.size() == 1 and game.queue_view.cards[0].key == "vehicles", "Vehicle production appears in a cancellable queue")
	var vehicle_id: int = game.state.add_unit("scout", HexGrid.world(anchor.cell + Vector2i(3, 0)), 0)
	game.selection = [vehicle_id]; game._update_hud()
	var unload: Button
	for button in game.actions.get_children():
		if button.text == "Unload [U]": unload = button
	verify(unload != null and unload.disabled, "An empty vehicle exposes a disabled unload control")
	game.state.units[vehicle_id].driver = id; game.state.units[id].vehicle = vehicle_id
	game._update_hud()
	for button in game.actions.get_children():
		if button.text == "Unload [U]": unload = button
	verify(not unload.disabled, "Boarding updates crew actions immediately")
	verify(CommandSkin.description(game.state, game.state.units[vehicle_id]).contains("ENGINEER"), "Vehicle inspector identifies its driver")
	for kind in ["radar", "rampart"]:
		verify(not game.build_buttons[kind].disabled, "Radar and Rampart are available in construction")
	var gate_id: int = game.state.add_structure("gate", anchor.cell + Vector2i(2, 2), 0)
	game.selection = [gate_id]; game._update_hud()
	var lock_present := false
	for button in game.actions.get_children():
		if button.text == "Lock": lock_present = true
	verify(lock_present, "Gate locking has a separate explicit control")
	game.state.command(0, {"action": "gate_lock", "target": gate_id})
	game._update_hud()
	var unlock_present := false
	for button in game.actions.get_children():
		if button.text == "Unlock": unlock_present = true
	verify(unlock_present, "Gate lock state refreshes its command label")
	var shield_id: int = game.state.add_structure("rampart", anchor.cell + Vector2i(1, 2), 0)
	game.state.structures[shield_id].powered = true
	verify(CommandSkin.description(game.state, game.state.structures[gate_id]).contains("RAMPART"), "Inspector explains applied shield armor")
	game.selection = [id]; game._update_hud()
	verify(game.selection == [vehicle_id], "Boarding carries selection onto the occupied vehicle")
	var radar_id: int = game.state.add_structure("radar", anchor.cell + Vector2i(2, -2), 0)
	game.selection = [radar_id]; game._update_hud()
	verify(game.status_label.text.contains("Amber markers"), "Radar selection provides relevant control guidance")
	game.status_label.text = "Player order feedback"
	game.state.resources(0).gas -= 1; game._update_hud()
	verify(game.status_label.text == "Player order feedback", "Income does not overwrite order feedback with a selection hint")
	game.state.paused = true
	var shooter_id: int = game.state.add_unit("marine", HexGrid.world(anchor.cell + Vector2i(3, 0)), 0)
	var victim_id: int = game.state.add_unit("ravager", game.state.units[shooter_id].pos + Vector2(2, 0), 1)
	for cell in HexGrid.line(HexGrid.cell(game.state.units[shooter_id].pos), HexGrid.cell(game.state.units[victim_id].pos)):
		game.state.tiles[cell].cliff = false
	game.state.visible[0][HexGrid.cell(game.state.units[victim_id].pos)] = true
	game.renderer.refresh_entities(); game.tactical._process(0.001)
	game.state.units[shooter_id].target = victim_id; game.state.units[shooter_id].job = {"kind": "attack"}
	game.state._fire(game.state.units[shooter_id], "marine_rifle", 0.05)
	game.renderer.refresh_entities(); game.tactical._process(0.001); game.audio.update(game.state, 0, 0.001)
	verify(not game.renderer.visual_shots.is_empty(), "Real fire feedback reaches the tracer renderer")
	verify(float(game.renderer.bodies[victim_id].get_meta("hit_flash")) > 0, "Damage activates a model hit flash")
	verify(game.tactical.health_trails[victim_id].trail > game.state.units[victim_id].hp, "Health bars retain a readable damage trail")
	game.state.tick += int(game.state.cfg.match.simulationTicksPerSecond)
	game.state._weapon_damage(game.state.units[victim_id], game.state.cfg.weapons.marine_rifle)
	game.tactical._process(0.001)
	verify(game.tactical.damage_numbers.filter(func(entry): return entry.kind == "hit" and int(entry.target) == victim_id).size() == 2, "Separated hits do not accumulate into one endless damage number")
	game.renderer.refresh_entities()
	var feedback_cursor: int = game.renderer.feedback_cursor
	game.renderer.refresh_entities()
	verify(game.renderer.feedback_cursor == feedback_cursor, "Rendering another frame does not replay the same event")
	game.state.units.erase(victim_id); game.renderer.refresh_entities()
	verify(game.renderer.death_effects.is_empty(), "An entity removed without a destruction event does not fake a death")
	var near_a: int = game.state.add_unit("marine", HexGrid.world(anchor.cell + Vector2i(2, 1)), 0)
	var near_b: int = game.state.add_unit("marine", HexGrid.world(anchor.cell + Vector2i(1, 2)), 0)
	var remote: int = game.state.add_unit("marine", Vector2.ZERO, 0)
	var foreign: int = game.state.add_unit("marine", game.state.units[near_a].pos + Vector2(1, 0), 1)
	game.renderer.refresh_entities()
	var double_click := InputEventMouseButton.new(); double_click.button_index = MOUSE_BUTTON_LEFT; double_click.pressed = true; double_click.double_click = true
	double_click.position = game.camera.unproject_position(Vector3(game.state.units[near_a].pos.x, 0.4, game.state.units[near_a].pos.y))
	game._unhandled_input(double_click)
	verify(near_a in game.selection and near_b in game.selection and not remote in game.selection and not foreign in game.selection, "Same-type selection includes only owned on-screen assets")
	game.selection = [near_a, near_b]; game._assign_group(1)
	game.selection.clear(); game._recall_group(1)
	verify(game.selection == [near_a, near_b], "Control groups recall their assigned units")
	verify(game.portrait.group_size == 2 and game.actions.get_child_count() > 0, "Homogeneous groups retain their portrait and usable commands")
	game.state.units.erase(near_b); game._recall_group(1)
	verify(game.selection == [near_a] and game.control_groups[1] == [near_a], "Group recall prunes destroyed members")
	game._focus_selection()
	verify(Vector2(game.camera.focus.x, game.camera.focus.z).distance_to(game.state.units[near_a].pos) < 0.01, "Selection focus centers the selected group")
	var builder_id: int = game.state.add_unit("engineer", HexGrid.world(anchor.cell + Vector2i(2, -1)), 0)
	game.selection = [builder_id]; game._update_hud(); game._toggle_build()
	verify(game.build_panel.visible, "Build command opens its modal catalogue")
	var depot_key := InputEventKey.new(); depot_key.keycode = KEY_D; depot_key.physical_keycode = KEY_D
	game._handle_key(depot_key)
	verify(game.build_kind == "depot" and game.depot_resource == "ore" and game.depot_panel.visible and not game.build_panel.visible, "B then D immediately arms an Ore Depot and offers optional resource buttons")
	var gas_key := InputEventKey.new(); gas_key.keycode = KEY_G; gas_key.physical_keycode = KEY_G
	game._handle_key(gas_key)
	verify(game.build_kind == "depot" and game.depot_resource == "gas" and not game.depot_panel.visible, "Depot resource hotkey chooses capacity and closes its optional menu")
	var alloy_key := InputEventKey.new(); alloy_key.keycode = KEY_A; alloy_key.physical_keycode = KEY_A
	game._handle_key(alloy_key)
	verify(game.build_kind == "depot" and game.depot_resource == "alloy", "Resource shortcuts remain available while holding a Depot after its menu closes")
	game._handle_key(gas_key)
	game._cancel_modes(); game._choose_build("depot")
	verify(game.build_kind == "depot" and game.depot_resource == "gas", "Subsequent Depot placements remember the last capacity type")
	game.renderer.show_preview(anchor.cell + Vector2i(2, 0), true, "depot", true)
	verify(game.renderer.ghost_model != null and game.renderer.ghost_model.visible, "Placement displays a real structure ghost")
	game._cancel_modes()
	game.selection = [near_a]
	var attack_key := InputEventKey.new(); attack_key.keycode = KEY_Q; attack_key.physical_keycode = KEY_Q
	game._handle_key(attack_key)
	verify(game.attack_mode, "Q enters explicit attack targeting")
	game._cancel_modes()
	game.selection = [anchor.id]; game._update_hud()
	rts_input_checks(game, int(builder_id), int(near_a), anchor)
	game.selection = [anchor.id]; game._update_hud()
	memory_interface_checks(game, int(builder_id), anchor.cell)
	game.selection = [anchor.id]; game._update_hud()
	game.state.players[0].alive = false
	game._update_hud()
	verify(game.actions.get_child_count() == 0, "Eliminated players inspect assets without command controls")
	verify(game.queue_view.cards[0].button.disabled, "Eliminated players cannot cancel queued production")
	game.audio.stop()
	await create_timer(0.05).timeout
	game.queue_free()
	await process_frame
	print("Interface checks complete; failures: ", failures)
	quit(0 if failures == 0 else 1)

func wall_paint_checks(game, anchor: Dictionary) -> void:
	var worker: Dictionary = {}
	for u in game.state.units.values():
		if u.owner == 0 and u.kind == "engineer": worker = u; break
	var saved: Dictionary = worker.duplicate(true)
	var ore: int = game.state.resources(0).ore
	var start: Vector2i = anchor.cell - anchor.cell.sign() * 4
	var finish := start + Vector2i(0, 2)
	for cell in HexGrid.line(start, finish): game.state.tiles[cell].cliff = false; game.state.known[0][cell] = true
	game.state.paused = true; game.selection = [worker.id]; game._choose_build("wall")
	var position := HexGrid.world(start)
	var screen: Vector2 = game.camera.unproject_position(Vector3(position.x, 0, position.y))
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = screen
	game._unhandled_input(press)
	verify(game.wall_dragging and game.pending_orders.is_empty(), "Starting a wall stroke captures the pointer without committing resources")
	position = HexGrid.world(finish); screen = game.camera.unproject_position(Vector3(position.x, 0, position.y))
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.position = screen
	game._input(release)
	verify(not game.wall_dragging and game.build_kind == "" and game.pending_orders.size() == 1 and game.pending_orders[0].order.action == "build_line", "Releasing a wall stroke issues one authoritative line command")
	game._physics_process(0.05)
	var sites: Array = []
	for s in game.state.structures.values():
		if s.kind == "wall" and not s.built: sites.append(s.id)
	verify(sites.size() == 3 and worker.orders.size() == 2, "Wall dragging queues a contiguous line while paused")
	game._choose_build("wall"); game._unhandled_input(press)
	game._cancel_modes()
	verify(not game.wall_dragging and game.pending_orders.is_empty(), "Canceling a wall stroke places nothing")
	var wall: Node3D = game.renderer.art.create({"kind": "wall", "cell": Vector2i.ZERO, "owner": 0}, Color.WHITE)
	var prism: MeshInstance3D = wall.get_node("Model/WallPrism")
	var vertices: PackedVector3Array = prism.mesh.get_faces()
	var covers_hex := true
	for direction in range(6):
		var corner := Vector2.from_angle(PI / 6 + direction * TAU / 6) * HexGrid.RADIUS
		var found := false
		for vertex in vertices:
			if Vector2(vertex.x, vertex.z).distance_to(corner) < 0.001 and absf(vertex.y - 0.5) < 0.001: found = true
		covers_hex = covers_hex and found
	verify(covers_hex and wall.get_node("Model").get_child_count() == 1 and prism.mesh.get_aabb().size.y == 1, "Walls use one full-footprint hexagonal prism with height")
	wall.free()
	for id in sites: game.state.structures.erase(id)
	game.state.units[int(worker.id)] = saved; game.state.resources(0).ore = ore
	game.state._rebuild_navigation(); game.state.update_visibility(); game.state.paused = false
	game.selection = []; game._update_hud()

func relay_control_checks(game, anchor: Dictionary) -> void:
	var inward := Vector2i.ZERO
	for direction in HexGrid.DIRECTIONS:
		if inward == Vector2i.ZERO or HexGrid.distance(anchor.cell + direction) < HexGrid.distance(anchor.cell + inward): inward = direction
	var relay: int = game.state.add_structure("relay", anchor.cell + inward * 7, 0)
	var flood: int = game.state.add_structure("floodlight", anchor.cell + inward * 15, 0)
	game.state._update_power(0)
	var links: Array = game.tactical.electrical_links("relay", game.state.structures[relay].cell, relay)
	verify(links.any(func(s): return s.id == anchor.id) and links.any(func(s): return s.id == flood), "Zero-demand Relay preview includes both source and downstream consumer")
	links = game.tactical.electrical_links("floodlight", game.state.structures[flood].cell, flood)
	verify(links.any(func(s): return s.id == relay), "Consumer placement recognizes an existing zero-demand Relay")
	game.selection = [relay]; game._update_hud()
	var button: Button
	for child in game.actions.get_children():
		if child.text == "Switch off": button = child
	verify(button != null, "Selected Relays expose an explicit Switch off action")
	game.state.paused = true
	button.pressed.emit()
	var pending: Dictionary = game.pending_orders.pop_back()
	game.state.command(int(pending.owner), pending.order); game._update_hud()
	verify(not game.state.structures[relay].enabled and not game.state.structures[flood].powered, "Relay UI toggle immediately disconnects downstream supply while paused")
	var on := false
	for child in game.actions.get_children():
		if child.text == "Switch on": on = true
	verify(on, "Disabled Relay exposes Switch on without reselecting")
	verify(not game.tactical.electrical_links("floodlight", game.state.structures[flood].cell, flood).any(func(s): return s.id == relay), "Inactive Relays are excluded from active connection candidates")
	game.state.command(0, {"action": "toggle", "target": relay})
	verify(game.state.structures[flood].powered, "Switching the Relay back on restores its downstream grid immediately")
	game.state.structures.erase(relay); game.state.structures.erase(flood); game.state._index_structures()
	game.state.paused = false; game.state._update_power(0); game.state.update_visibility()
	game.selection = []; game._update_hud()

func rts_input_checks(game, builder: int, marine: int, anchor: Dictionary) -> void:
	game.selection = [marine]; game._update_hud()
	game.state.command(0, {"action": "stance", "ids": [marine], "stance": "aggressive"})
	game._update_hud()
	var active_stance := false
	for button in game.actions.get_children():
		if button.get_meta("stance", "") == "aggressive": active_stance = button.button_pressed
	verify(active_stance, "Accepted stance changes update the selected command without reselecting the unit")
	var stance := InputEventKey.new(); stance.keycode = KEY_N; stance.physical_keycode = KEY_N
	game._handle_key(stance)
	verify(game.pending_orders.back().order.action == "stance" and game.pending_orders.back().order.stance == "neutral", "Neutral stance shortcut issues the same gameplay command")
	game.pending_orders.clear()
	game.selection = [builder]; game._update_hud()
	var map_center: Vector2 = game.tactical.minimap_rect().get_center()
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = map_center
	game._input(click)
	var motion := InputEventMouseMotion.new(); motion.position = map_center + Vector2(12, -8)
	game._input(motion)
	verify(game.minimap_dragging and Vector2(game.camera.focus.x, game.camera.focus.z).distance_to(game.tactical.minimap_world(motion.position)) < 0.01, "Holding and dragging the minimap continuously moves the camera")
	click.pressed = false; click.position = Vector2(500, 300); game._input(click)
	verify(not game.minimap_dragging and game.selection == [builder], "Releasing outside the minimap ends capture without changing selection")
	click.button_index = MOUSE_BUTTON_RIGHT; click.pressed = true; click.shift_pressed = true
	click.position = game.tactical.map_point(Vector2(12, 9)); game._input(click)
	verify(not game.pending_orders.is_empty() and game.pending_orders.back().order.action == "move" and game.pending_orders.back().order.queued, "Shift right-click on the minimap issues a queued world-space move")
	game.pending_orders.clear()
	game._target_interaction("repair"); verify(game._cursor_mode() == "repair", "Repair targeting selects its own action cursor")
	game._cancel_modes(); game.mining_mode = true; verify(game._cursor_mode() == "mine", "Mining selects its own action cursor")
	game._cancel_modes(); game.attack_mode = true; verify(game._cursor_mode() == "attack", "Attack targeting selects its own action cursor")
	game._cancel_modes()
	game.selection = [anchor.id]; game._update_hud()
	var toggle := InputEventKey.new(); toggle.keycode = KEY_T; toggle.physical_keycode = KEY_T
	game._handle_key(toggle)
	verify(game.pending_orders.back().order.action == "global_personnel", "Structure T shortcut controls the global Operator setting")
	game.pending_orders.clear()
	game.state.resources(0).ore = 100; game.state.resources(0).gas = 100; game._update_hud()
	var operator_key := InputEventKey.new(); operator_key.keycode = KEY_O; operator_key.physical_keycode = KEY_O
	game._handle_key(operator_key)
	verify(game.pending_orders.back().order.action == "operator", "Personnel hotkey uses the structure's production action")
	game.pending_orders.clear(); game._focus_anchor()
	var p := HexGrid.world(anchor.cell)
	var obscured: int = game.state.add_unit("marine", p + Vector2(0, -0.45), 0)
	game.renderer.refresh_entities()
	verify(game.renderer.bodies[obscured].get_meta("occluded", false), "A visible unit behind structure geometry receives an occlusion silhouette")
	game.renderer.bodies[obscured].hide(); game.renderer._highlight_occluded_units()
	verify(not game.renderer.bodies[obscured].get_meta("occluded", false), "Hidden bodies do not receive occlusion silhouettes")
	game.state.units.erase(obscured); game.renderer.refresh_entities()

func fog_visual_checks(game) -> void:
	var explored := {Vector2i.ZERO: true, Vector2i(1, 0): true}
	var image: Image = game.renderer._update_visibility_texture(explored, {Vector2i.ZERO: true}, {})
	var center := Vector2i(image.get_width() / 2, image.get_height() / 2)
	verify(image.get_pixelv(center).g > 0.9, "A remembered neighbor cannot erase a currently visible tile from the fog mask")
	var memory_image: Image = game.renderer._update_visibility_texture(explored, {}, {})
	var memory: Color = memory_image.get_pixelv(center)
	verify(memory.r > 0.9 and memory.g == 0, "Fog distinguishes remembered ground from current visibility")
	var light: Dictionary = {}
	for area in game.state.illuminated.values(): light.merge(area, true)
	game.renderer._update_visibility_texture(game.state.known.get(0, {}), game.state.visible.get(0, {}), light)

func facility_visual_checks(game, anchor: Dictionary) -> void:
	var id: int = game.state.add_structure("armory", anchor.cell + Vector2i(5, -5), 0)
	var facility: Dictionary = game.state.structures[id]
	facility.powered = true
	facility.kits = [{"kind": "marine", "progress": 2.0, "done": false}, {"kind": "engineer", "progress": 10.0, "done": true}]
	game.renderer.refresh_entities()
	var model: Node3D = game.renderer.bodies[id].get_node("Model")
	verify(game.renderer._facility_state(facility).working, "A powered facility with a progressing kit shows production")
	verify(model.get_node("KitRack/Slot0").visible and model.get_node("KitRack/Slot1").visible and not model.get_node("KitRack/Slot2").visible, "Physical kit rack shows the actual queue count")
	facility.powered = false
	game.renderer._animate_facility(model, facility)
	verify(not game.renderer._facility_state(facility).working and model.get_node("ServiceRail").material_override is ShaderMaterial, "Power loss stops work indications and extinguishes service lighting")
	facility.powered = true; facility.kits = [{"kind": "marine", "progress": 10.0, "done": true}]
	verify(not game.renderer._facility_state(facility).working, "Finished kits waiting for pickup do not imply active production")
	game.renderer.viewer_owner = 1; game.renderer._animate_facility(model, facility)
	verify(not model.get_node("KitRack").visible, "Enemy queues are not exposed by physical props")
	game.renderer.viewer_owner = 0
	game.state.structures.erase(id); game.renderer.refresh_entities()

func model_selection_checks(game, anchor: Dictionary) -> void:
	var saved: Dictionary = game.renderer.bodies
	game.renderer.bodies = {}
	var position := HexGrid.world(anchor.cell)
	var front := Node3D.new()
	game.renderer.add_child(front)
	front.position = Vector3(position.x, 4, position.y)
	front.rotation.y = 0.4; front.scale = Vector3(1.5, 1, 0.8)
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new()
	front.add_child(mesh); front.set_meta("surfaces", [mesh])
	game.renderer.bodies[900001] = front
	var back := Node3D.new()
	game.renderer.add_child(back)
	back.position = front.position - Vector3(0, 0, 3)
	var back_mesh := MeshInstance3D.new(); back_mesh.mesh = BoxMesh.new()
	back.add_child(back_mesh); back.set_meta("surfaces", [back_mesh])
	game.renderer.bodies[900002] = back
	var origin := front.position + Vector3(0, 0, 10)
	verify(game.renderer.pick_model(origin, Vector3.FORWARD) == 900001, "Model picking selects the nearest rotated/scaled mesh")
	front.hide()
	verify(game.renderer.pick_model(origin, Vector3.FORWARD) == 900002, "Hidden bodies cannot occlude model selection")
	back_mesh.hide()
	verify(game.renderer.pick_model(origin, Vector3.FORWARD) == 0, "Hidden model parts cannot be selected")
	front.show()
	var screen: Vector2 = game.camera.unproject_position(front.position)
	var center: Vector2 = game.camera.unproject_position(Vector3(position.x, 0.4, position.y))
	verify(screen.distance_to(center) > 28, "Selection regression exercises geometry beyond the old center tolerance")
	verify(game._pick(screen) == 900001, "Clicking elevated model geometry selects beyond the center tile")
	front.free(); back.free()
	game.renderer.bodies = saved

func memory_interface_checks(game, builder_id: int, anchor_cell: Vector2i) -> void:
	var state: WorldState = game.state
	var cell := anchor_cell + Vector2i(0, -6)
	state.tiles[cell].cliff = false
	var enemy := state.add_structure("stoma", cell, -1)
	state.visible[0] = {cell: true}; state.known[0][cell] = true
	state._remember_structures()
	state.visible[0].clear(); state._remember_structures()
	state.structures[enemy].hp = 7
	game.renderer.refresh_entities()
	game.selection = [enemy]; game._update_hud()
	verify(game.selection_label.text.contains("LAST SEEN") and game.detail_label.text.contains("Current condition unknown"), "Remembered structure inspection identifies stale information")
	verify(float(game._observed_entity(enemy).hp) != 7, "The single-player inspector uses the frozen record rather than hidden live health")
	verify(game.renderer.bodies.has(enemy) and game.renderer.bodies[enemy].visible, "Previously scouted structures keep a model in fog")
	var position := HexGrid.world(cell)
	var screen: Vector2 = game.camera.unproject_position(Vector3(position.x, 0.4, position.y))
	game.selection = [builder_id]
	game._context_order(screen, cell, Vector3(position.x, 0, position.y))
	verify(not game.pending_orders.is_empty() and game.pending_orders.back().order.action == "move", "Right-clicking a scouting record moves toward its last-known site")
	game.attack_mode = true
	game._context_order(screen, cell, Vector3(position.x, 0, position.y))
	verify(game.status_label.text.contains("Rediscover"), "Explicit targeting requires rediscovery of a remembered structure")
	game._cancel_modes()
	state._destroy(state.structures[enemy]); game.renderer.refresh_entities()
	verify(game.renderer.bodies.has(enemy), "Hidden destruction does not remove the remembered model")
	state.visible[0][cell] = true; state._remember_structures(); game.renderer.refresh_entities()
	verify(not game.renderer.bodies.has(enemy), "Rediscovering an empty footprint removes its remembered model")
