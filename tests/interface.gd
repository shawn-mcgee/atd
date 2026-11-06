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
	verify(game.build_kind == "depot" and not game.build_panel.visible, "B then D chooses Depot and restores normal camera key use")
	game.renderer.show_preview(anchor.cell + Vector2i(2, 0), true, "depot", true)
	verify(game.renderer.ghost_model != null and game.renderer.ghost_model.visible, "Placement displays a real structure ghost")
	game._cancel_modes()
	game.selection = [near_a]
	var attack_key := InputEventKey.new(); attack_key.keycode = KEY_Q; attack_key.physical_keycode = KEY_Q
	game._handle_key(attack_key)
	verify(game.attack_mode, "Q enters explicit attack targeting")
	game._cancel_modes()
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
