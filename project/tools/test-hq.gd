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
	await process_frame
	game.set_process(false); game.audio_enabled = false; game.begin_run()
	for enemy in game.creatures: enemy.hp = 0
	game.cleanup_dead(); game.director.groups.clear(); game.director.outpost_group_created = true
	check(game.core.powered and game.power.capacity == 4 and game.power.used == 0 and game.power.demand == 0, "idle HQ supplies four power with no self-consumption")
	check(is_equal_approx(game.core.lamp.omni_range, 4.2 + game.Terrain.SPACING) and game.light.sample(Vector3(5.4, 0, 0)) > 0.05 and game.light.sample(Vector3(6.2, 0, 0)) == 0, "HQ graphical and gameplay light extend one additional tile step")
	var gates: Array[ExpeditionStructure] = []
	for point in [Vector3(3.5, 0, 0), Vector3(-3.5, 0, 0), Vector3(0, 0, 4.5), Vector3(0, 0, -4.5)]: gates.append(game.add_structure("gate", point))
	game.economy.gas = 0
	game.power.tick(game.structures, game.economy, 1)
	check(gates.all(func(gate): return gate.powered) and game.core.powered and game.power.used == 4 and game.power.demand == 4 and game.economy.gas == 0, "all four auxiliary power units can serve external consumers without methane")
	game.core.scan_charge = 0; game.power.tick(game.structures, game.economy, 5)
	check(game.core.scan_charge == 0 and gates.all(func(gate): return gate.powered), "scanner charging waits when external consumers use all available power")
	for gate in gates: gate.enabled = false
	game.power.tick(game.structures, game.economy, 5)
	check(game.core.scan_charge == 20 and game.power.used == 4 and game.economy.gas == 0, "scanner recharge still uses spare auxiliary power after HQ stops being a consumer")
	game.core.scan_charge = 120; game.power.tick(game.structures, game.economy, 1)
	check(game.power.used == 0 and game.power.demand == 0 and game.core.powered, "finishing a scan recharge returns HQ to zero idle draw")
	game.economy.gas = 80; game.select_actor(game.core); game.refresh_ui()
	check(game.context_buttons.scout.visible and game.context_buttons.scout.get_meta("shortcut") == "2" and game.context_buttons.engineer.visible, "HQ exposes engineer and scout production with matching hotkey labels")
	var bank: int = game.economy.minerals; var methane: float = game.economy.gas
	game.numbered_command(1)
	check(game.core.queue == ["scout"] and game.economy.minerals == bank - 60 and game.economy.gas == methane - 25, "HQ hotkey 2 reserves a scout at its normal materials and methane cost")
	game.cancel_training()
	check(game.core.queue.is_empty() and game.economy.minerals == bank and game.economy.gas == methane, "cancelling an HQ scout refunds both resources exactly once")
	check(game.train_unit("scout") and not game.train_unit("jeep") and not game.train_unit("marine"), "HQ authorizes scouts while preserving other factory restrictions")
	var count: int = game.units.size()
	for i in range(105): game.simulation_tick(0.1)
	check(game.units.size() == count + 1 and game.units[-1].kind == "scout" and not game.units[-1].has_driver() and game.core.queue.is_empty(), "HQ finishes an unpiloted scout after its normal production time")
	var garage: ExpeditionStructure = game.add_structure("garage", Vector3(-12, 0, -12))
	game.select_actor(garage); game.refresh_ui()
	check(game.context_buttons.scout.get_meta("shortcut") == "1" and game.context_buttons.jeep.visible, "Garage keeps scout hotkey 1 and its other vehicle production choices")
	print("HQ_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
