extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run(); game.rocks.clear(); game.rebuild_navigation()
	game.select_actor(game.core); game.refresh_ui()
	check(game.context_buttons.engineer.visible and game.context_buttons.scan.visible and not game.context_buttons.marine.visible, "Command Center exposes engineer production alongside scanning")
	var bank: int = game.economy.minerals
	game.numbered_command(0)
	check(game.core.queue == ["engineer"] and game.economy.minerals == bank - 35, "Command Center engineer hotkey reserves the normal cost")
	game.cancel_training()
	check(game.core.queue.is_empty() and game.economy.minerals == bank and not game.train_unit("marine"), "Command Center refunds cancelled engineers and rejects combat-unit production")
	game.train_unit("engineer")
	var count: int = game.units.size()
	for i in range(75): game.simulation_tick(0.1)
	check(game.core.queue.is_empty() and game.units.size() == count + 1 and game.units[-1].kind == "engineer", "queued engineer completes and spawns at the Command Center")
	bank = game.economy.minerals
	for i in range(5): game.train_unit("engineer")
	check(game.core.queue.size() == 5 and not game.train_unit("engineer"), "Command Center enforces the five-unit production queue limit")
	for i in range(5): game.cancel_training()
	check(game.economy.minerals == bank and game.core.queue.is_empty(), "cancelling the Command Center queue refunds every reservation")
	var gate: ExpeditionStructure = game.add_structure("gate", Vector3(30, 0, 30))
	var generator: ExpeditionStructure = game.add_structure("generator", gate.position - Vector3(3, 0, 0))
	game.power.tick(game.structures, game.economy, 0); game.gate_passage.update(game, 0)
	var marine: ExpeditionUnit = game.add_unit("marine", gate.position - Vector3(0, 0, 8))
	var engineer: ExpeditionUnit = game.add_unit("engineer", gate.position - Vector3(1, 0, 11))
	game.set_order(marine, "move", gate.position + Vector3(0, 0, 8))
	game.set_order(engineer, "move", gate.position + Vector3(1, 0, 9))
	var opened := false; var closed_on_unit := false
	for i in range(300):
		game.advance_movement(0.05); game.process_order(marine, 0.05); game.process_order(engineer, 0.05)
		opened = opened or gate.gate_open
		if not gate.gate_open and engineer.position.distance_to(gate.position) < 2.5: closed_on_unit = true
	check(opened and not gate.gate_open and not closed_on_unit and engineer.position.z > gate.position.z + 5, "friendly group opens a powered gate, passes, and closes it safely behind the last unit")
	game.set_gate(gate, true, false, true)
	game.set_gate(gate, true) # An explicit open order takes over an auto-open gate.
	game.set_order(marine, "move", gate.position - Vector3(0, 0, 8))
	for i in range(180): game.advance_movement(0.05); game.process_order(marine, 0.05)
	check(gate.gate_open and not gate.gate_auto_opened, "a manually open gate remains open after friendly passage")
	game.select_actor(gate); game.toggle_gate_lock()
	check(gate.gate_locked and not gate.gate_open and not game.set_gate(gate, true), "locking closes a clear gate and prevents opening")
	var route: PackedVector3Array = game.navigation.path(gate.position - Vector3(0, 0, 8), gate.position + Vector3(0, 0, 8))
	check(route.size() > 2, "friendly pathfinding routes around a locked gate")
	game.toggle_gate_lock(); generator.enabled = false; game.power.tick(game.structures, game.economy, 0); game.gate_passage.update(game, 0)
	check(not gate.powered and not game.set_gate(gate, true), "unpowered gates cannot be opened by automatic or direct orders")
	generator.enabled = true; game.power.tick(game.structures, game.economy, 0); game.gate_passage.update(game, 0)
	route = game.navigation.path(gate.position - Vector3(0, 0, 8), gate.position + Vector3(0, 0, 8), null, false)
	check(route.size() > 2 and game.navigation.blocked(gate.position), "creatures retain blocked navigation through closed automatic gates")
	# Compare incremental graph state with a clean full rebuild after edits.
	for i in range(6):
		game.add_structure("wall", Vector3(-50 + i * game.Terrain.SPACING, 0, 24)); game.rebuild_navigation()
	check(game.navigation.last_dirty.size() < game.navigation.cells.size() / 5, "wall completion updates a local navigation region instead of the whole map")
	var fresh = game.Navigation.new(); fresh.terrain.natural_enabled = game.navigation.terrain.natural_enabled; fresh.terrain.structures.assign(game.navigation.terrain.structures); fresh.rebuild(game.navigation.obstacles)
	var matching := true
	for pair in [[fresh.graph, game.navigation.graph], [fresh.friendly_graph, game.navigation.friendly_graph]]:
		for id in pair[0].get_point_ids():
			if pair[0].is_point_disabled(id) != pair[1].is_point_disabled(id): matching = false
			var expected := Array(pair[0].get_point_connections(id)); expected.sort()
			var actual := Array(pair[1].get_point_connections(id)); actual.sort()
			if expected != actual: matching = false
	check(matching, "incremental navigation produces the same blocked nodes and edges as a full rebuild")
	print("TODO_FEATURE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
