extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.scenario_seed = 42; root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.audio_enabled = false; game.begin_run()
	var starter: Array = game.resource_nodes.filter(func(p): return p.field >= 6)
	var materials: Array = starter.filter(func(p): return p.kind == "minerals")
	var methane: Array = starter.filter(func(p): return p.kind == "gas")
	check(materials.size() == 3 and materials.reduce(func(total, p): return total + p.remaining, 0) == 516 and methane.size() == 1 and methane[0].remaining == 129, "landing deposits contain three material cells totaling 516 and one methane cell containing 129, matching normal per-cell richness")
	check(starter.all(func(p): return p.discovered and game.light.sample(p.position) > 0.05), "HQ illumination reveals every starter patch immediately")
	var occupied: Array = game.Footprints.cells("core", game.core.position)
	check(starter.all(func(p): return not occupied.has(game.Hex.to_axial(p.position, game.Terrain.CELL)) and not game.navigation.blocked(p.position)), "starter deposits are outside HQ's footprint and reachable on foot")
	var distant: Array = game.resource_nodes.filter(func(p): return p.field < 6)
	check(distant.all(func(p): return not p.discovered), "all remote resource patches remain unknown at landing")
	game.select_actor(game.core); game.refresh_ui()
	var key := InputEventKey.new(); key.keycode = KEY_Q; key.pressed = true
	game._unhandled_input(key)
	check(not game.context_buttons.has("scan") and not game.has_method("scan") and distant.all(func(p): return not p.discovered), "HQ has no resource scan button or Q discovery shortcut")
	# A tiny illuminated area reveals only the visited cell, not its entire field.
	game.light.sources.clear(); game.light.add_source(distant[0].position, 0.6)
	game.resource_fields.discover(game); game.minimap.refresh()
	check(distant[0].discovered and distant.slice(1).all(func(p): return not p.discovered), "scouting surveys only the illuminated resource cell")
	check(game.resource_meshes[0].visible and game.minimap.markers.any(func(m): return m.kind == "minerals" and m.point == distant[0].position), "scouted deposit becomes visible and receives a minimap marker")
	distant[0].remaining = 0
	check(game.resource_fields.next_patch(game, distant[0]).is_empty(), "mining cannot automatically target an undiscovered neighboring patch")
	distant[0].remaining = 1; game.light.sources.clear(); game.resource_fields.discover(game)
	check(distant[0].discovered and not game.resource_meshes[0].visible and game.resource_markers[0].visible, "discovery persists in darkness while its world geometry hides")
	var engineer: ExpeditionUnit = game.units[0]
	for resource in [materials[0], methane[0]]:
		engineer.cargo = 0; engineer.gas_cargo = 0
		game.economy.minerals = 50; game.economy.gas = 50
		game.issue_order(engineer, "harvest", resource.position)
		var depleted := int(resource.remaining)
		for i in range(160):
			game.advance_movement(0.1); game.process_order(engineer, 0.1)
			if int(resource.remaining) < depleted: break
		check(int(resource.remaining) < depleted and engineer.cargo_total() > 0, "starting engineer can reach and harvest " + resource.kind)
		game.set_order(engineer, "deposit", game.core.position, game.core)
		for i in range(100):
			game.advance_movement(0.1); game.process_order(engineer, 0.1)
			if engineer.cargo_total() == 0: break
		check(engineer.cargo_total() == 0 and (game.economy.minerals > 50 if resource.kind == "minerals" else game.economy.gas > 50), "starter " + resource.kind + " can be physically delivered to HQ")
	print("RESOURCE_DISCOVERY_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
