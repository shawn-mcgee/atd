extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.scenario_seed = 42
	root.add_child(game); current_scene = game
	await process_frame; await process_frame
	game.set_process(false); game.audio_enabled = false; game.begin_run()
	for enemy in game.creatures: enemy.hp = 0
	game.cleanup_dead(); game.director.groups.clear()
	check(game.economy.minerals == 100 and game.economy.gas == 100 and game.economy.mineral_capacity == 100 and game.economy.gas_capacity == 100, "HQ starts with exactly 100 materials / 100 methane and matching storage")
	check(game.hud.MATERIAL is Texture2D and game.hud.METHANE is Texture2D and game.hud.POWER is Texture2D, "materials, methane and power use imported icon assets")
	game.world_bars.refresh()
	check(game.world_bars.health_entries.is_empty() and game.world_bars.battery_entries.is_empty(), "healthy starting infantry and structures have no overhead health bars")
	game.select_actor(game.core); game.refresh_ui()
	check(game.hud.selection_grid.capacity == 4 and game.hud.selection_grid.used == 0 and not game.stats.text.contains("POWER"), "HQ selection reports its own grid while the global strip contains only resource counts")
	var engineer: ExpeditionUnit = game.units[0]
	game.select_actor(engineer); game.refresh_ui()
	check(game.hud.selection_grid.capacity == 4 and game.hud.build_tab.visible and not game.construction_panel.visible, "connected infantry receive grid details and an optional Build tab")
	var command_origin: Vector2 = game.command_panel.position
	game.hud.build_tab.pressed.emit()
	check(game.construction_panel.visible and not game.command_scroll.visible, "Build and Commands share the same command area rather than separate corners")
	game.hud.show_tab("orders")
	game.select_actor(game.core); game.refresh_ui()
	check(game.command_panel.position == command_origin and game.context_buttons.scout.get_meta("shortcut") == "2", "changing selections keeps the dock in place and preserves production hotkeys")
	# Two independent grids must never display or charge against a global sum.
	var generator: ExpeditionStructure = game.add_structure("generator", Vector3(-25, 0, -12))
	var laser: ExpeditionStructure = game.add_structure("laser_turret", generator.position + Vector3(0, 0, -3))
	var lamp: ExpeditionStructure = game.add_structure("floodlight", generator.position + Vector3(-3, 0, 0))
	game.power.tick(game.structures, game.economy, 0)
	check(game.power.capacity == 16 and laser.powered and lamp.powered, "fixture contains distinct four-power HQ and twelve-power generator grids")
	game.select_actor(laser); game.refresh_ui()
	check(game.hud.selection_grid.capacity == 12 and game.hud.selection_grid.used == 10 and game.hud.selection_grid.demand == 10, "a connected structure shows only its grid capacity, use and demand")
	engineer.position = generator.position + Vector3(1, 0, 0); game.select_actor(engineer); game.refresh_ui()
	check(game.hud.selection_grid.id == generator.network and game.hud.selection_grid.capacity == 12, "a unit moving into another network reports that network's power")
	var vehicle: ExpeditionUnit = game.add_unit("jeep", generator.position + Vector3(0, 0, 2))
	vehicle.battery = 30; game.select_actor(vehicle); game.vehicles.tick(game, 1); game.refresh_ui()
	check(vehicle.battery == 38 and vehicle.charging and game.hud.selection_grid.capacity == 12 and game.context_buttons.recharge.visible, "a supplied vehicle recharges and displays the same grid used by its charging logic")
	game.context_buttons.recharge.pressed.emit(); game.vehicles.tick(game, 1)
	check(not vehicle.auto_recharge and not vehicle.charging and vehicle.battery == 38, "the per-vehicle toggle stops automatic charging without disconnecting grid information")
	vehicle.motion_velocity = Vector3.FORWARD; game.vehicles.tick(game, 1)
	check(vehicle.battery == 37.75, "driving still drains batteries when automatic recharge is disabled inside a grid")
	vehicle.motion_velocity = Vector3.ZERO
	var shortcut := InputEventKey.new(); shortcut.keycode = KEY_N; shortcut.pressed = true; game._unhandled_input(shortcut)
	game.vehicles.tick(game, 1)
	check(vehicle.auto_recharge and vehicle.charging and vehicle.battery > 37.75, "N re-enables recharge for the selected vehicle")
	var scout: ExpeditionUnit = game.add_unit("scout", vehicle.position + Vector3(1, 0, 0))
	scout.auto_recharge = false; game.select_actor(scout, true); game.toggle_auto_recharge()
	check(scout.auto_recharge and vehicle.auto_recharge, "mixed vehicle selections can consistently enable automatic recharge")
	game.toggle_auto_recharge()
	check(not scout.auto_recharge and not vehicle.auto_recharge, "a subsequent toggle disables recharge for every selected vehicle")
	generator.enabled = false; game.power.tick(game.structures, game.economy, 0)
	game.select_actor(vehicle); game.refresh_ui()
	check(game.hud.selection_grid.is_empty() and not game.hud.grid_panel.visible, "disconnected vehicles do not show unrelated HQ or stale grid statistics")
	# Bars are geometry-relative, respond to healing, and obey enemy visibility.
	game.focus = generator.position; game.update_camera()
	engineer.hp -= 20; laser.hp -= 30; vehicle.hp -= 40
	game.world_bars.refresh()
	check([engineer, laser, vehicle].all(func(actor): return game.world_bars.health_entries.any(func(entry): return entry.actor == actor)), "damaged infantry, structures and vehicles all receive overhead health bars")
	check(game.world_bars.battery_entries.any(func(entry): return entry.actor == vehicle and entry.value < 1), "vehicle batteries appear even without a health selection")
	var battery: Dictionary = game.world_bars.battery_entries.filter(func(entry): return entry.actor == vehicle)[0]
	var health: Dictionary = game.world_bars.health_entries.filter(func(entry): return entry.actor == vehicle)[0]
	var vehicle_box: Rect2 = game.world_bars.screen_box(vehicle)
	check(health.rect.end.y < vehicle_box.position.y and battery.rect.position.y > vehicle_box.end.y, "health is above the model and battery is below it without overlapping geometry")
	engineer.hp = game.Rules.UNITS.engineer.hp; laser.hp = game.Rules.STRUCTURES.laser_turret.hp; vehicle.hp = game.Rules.UNITS.jeep.hp
	game.world_bars.refresh()
	check(not game.world_bars.health_entries.any(func(entry): return entry.actor in [engineer, laser, vehicle]), "restoring full health immediately removes all corresponding health bars")
	vehicle.battery = 100; game.world_bars.refresh()
	check(game.world_bars.battery_entries.any(func(entry): return entry.actor == vehicle and entry.value == 1), "full vehicle batteries remain visible as full bars")
	var enemy: ExpeditionPredator = game.add_creature(generator.position + Vector3(4, 0, -2), 99)
	game.light.add_source(enemy.position, 8); enemy.visible = true; enemy.hp -= 10
	game.world_bars.refresh()
	check(game.world_bars.health_entries.any(func(entry): return entry.actor == enemy and entry.enemy), "damaged visible Lightless receive enemy-colored health bars")
	game.light.sources.clear(); game.world_bars.refresh()
	check(not game.world_bars.health_entries.any(func(entry): return entry.actor == enemy), "health bars cannot expose a creature after its illumination is lost")
	game.light.add_source(enemy.position, 8); enemy.hp = enemy.max_hp; game.world_bars.refresh()
	check(not game.world_bars.health_entries.any(func(entry): return entry.actor == enemy), "fully recovered enemies have no health bar")
	game.select_actor(enemy); game.refresh_ui()
	check(game.command_title.text.begins_with("Lightless") and not game.context_buttons.destroy.visible and game.hud.selection_grid.is_empty(), "enemy inspection stays in the selection dock without owned-unit commands or grid data")
	game.select_actor(null); game.refresh_ui()
	check(not game.command_panel.visible and game.message.text.is_empty(), "clearing selection hides irrelevant details and leaves no permanent tutorial text")
	for dimensions in [Vector2i(1100, 720), Vector2i(1600, 1000)]:
		root.size = dimensions; game.select_actor(engineer); game.refresh_ui()
		await process_frame; await process_frame
		check(not game.command_panel.get_global_rect().intersects(game.minimap.get_global_rect()) and game.command_panel.get_global_rect().end.y <= dimensions.y - 17, "command dock and minimap fit without overlap at %dx%d" % [dimensions.x, dimensions.y])
	print("HUD_STATUS_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
