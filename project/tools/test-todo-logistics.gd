extends SceneTree
const Hex = preload("res://engine/hex_grid.gd")
var failures := 0

func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error(text)

func _initialize() -> void: call_deferred("run")

func fixture():
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	game.rocks.clear(); game.structures.clear(); game.resource_nodes.clear()
	game.navigation.terrain.natural_enabled = false; game.rebuild_navigation()
	return game

func patch(game, cell: Vector2i, amount: int, field: int, kind: String = "minerals") -> Dictionary:
	game.add_resource_patch(kind, Hex.to_world(cell, 1), amount)
	var result: Dictionary = game.resource_nodes[-1]
	result.discovered = true; result.field = field
	return result

func work_distance() -> void:
	var game = fixture()
	var center := Hex.to_world(Vector2i(15, -15), 1)
	var wall: SimStructure = game.add_structure("wall", center, false)
	var worker: SimUnit = game.add_unit("engineer", center + Hex.to_world(Vector2i(2, 0), 1))
	game.set_order(worker, "build", center, wall); game.process_order(worker, 1)
	check(wall.progress == 0, "construction cannot progress two tiles away")
	worker.position = center + Hex.to_world(Vector2i(1, 0), 1); game.process_order(worker, 1)
	check(wall.progress > 0, "construction progresses from an adjacent tile")
	wall.complete = true; wall.hp -= 16; game.rebuild_navigation()
	worker.position = center + Hex.to_world(Vector2i(2, 0), 1)
	check(game.set_order(worker, "repair", center, wall), "repair has a clear route to the completed structure")
	var hp := wall.hp; game.process_order(worker, 1)
	check(wall.hp == hp, "repair cannot progress two tiles away")
	worker.position = center + Hex.to_world(Vector2i(1, 0), 1); game.process_order(worker, 1)
	check(wall.hp > hp, "repair progresses from an adjacent tile")
	var depot: SimStructure = game.add_structure("depot", center + Hex.to_world(Vector2i(-4, 0), 1))
	worker.position = depot.position + Hex.to_world(Vector2i(2, 0), 1); worker.cargo = 2
	game.set_order(worker, "stock", depot.position, depot); game.process_order(worker, 1)
	check(worker.cargo == 2, "engineers cannot deposit from two tiles away")
	worker.position = depot.position + Hex.to_world(Vector2i(1, 0), 1); game.process_order(worker, 1)
	check(worker.cargo == 0, "engineers can deposit from an adjacent tile")
	worker.position.y += 3
	check(not game.within_work_reach(worker, depot), "work reach respects elevation")
	var gate: SimStructure = game.add_structure("gate", center + Hex.to_world(Vector2i(-8, 0), 1))
	gate.gate_open = true; game.rebuild_navigation()
	worker.position = gate.position + Hex.to_world(Vector2i(1, 0), 1)
	game.set_order(worker, "close_gate", gate.position, gate)
	for i in range(100):
		game.advance_movement(0.1); game.process_order(worker, 0.1)
	check(not gate.gate_open and game.within_work_reach(worker, gate), "manual gate workers step clear and close the gate from an adjacent tile")
	game.dispose()

func field_loops(on_foot: bool) -> void:
	var game = fixture()
	var first := patch(game, Vector2i(15, -15), 1, 100)
	var second := patch(game, Vector2i(16, -15), 4, 100)
	var other := patch(game, Vector2i(17, -15), 50, 101)
	game.add_structure("depot", Hex.to_world(Vector2i(11, -15), 1)); game.rebuild_navigation()
	game.economy.minerals = 0
	var worker: SimUnit = game.add_unit("engineer", first.position); worker.capacity = 2
	if on_foot: game.complex_commands.start_expedition(game, [worker], first)
	else: game.issue_order(worker, "harvest", first.position)
	for i in range(700):
		game.advance_movement(0.1)
		if on_foot: game.complex_commands.tick(game, 0.1)
		else: game.process_order(worker, 0.1)
	check(first.remaining == 0 and second.remaining == 0 and game.economy.minerals == 5, "%s workers finish their field across repeated delivery trips" % ("on-foot expedition" if on_foot else "direct-order"))
	check(other.remaining == 50, "field assignment never spills into a neighboring field")
	game.dispose()

func convoy_and_extractor() -> void:
	var game = fixture()
	var first := patch(game, Vector2i(15, -15), 0, 100)
	var second := patch(game, Vector2i(16, -15), 5, 100)
	var worker: SimUnit = game.add_unit("engineer", second.position)
	var truck: SimUnit = game.add_unit("jeep", first.position + Vector3(0, 0, 6))
	var driver: SimUnit = game.add_unit("marine", truck.position)
	game.complex_commands.start(game, [truck, driver, worker], first)
	var group: Dictionary = game.complex_commands.groups[-1]
	truck.board(group.driver); group.phase = "work"
	game.complex_commands.tick(game, 0.7)
	check(group.resource == second and second.remaining < 5 and group.phase == "work", "working convoys switch to another patch in their assigned field")
	game.complex_commands.finish(group)
	var gas := patch(game, Vector2i(15, -14), 7, 101, "gas")
	var extractor: SimStructure = game.add_structure("extractor", first.position)
	extractor.powered = true; game.rebuild_navigation()
	var remaining: Dictionary = game.resource_fields.extractor_remaining(game, extractor)
	check(remaining.minerals == second.remaining and remaining.gas == gas.remaining, "extractors report both covered resource totals")
	var outside := patch(game, Vector2i(20, -15), 10, 100)
	check(not game.resource_fields.same_field(game, outside, second) and not game.resource_fields.same_field(game, second, outside), "extractor mining assignments remain distinct from uncovered parts of their original field")
	check(game.resource_fields.resolve_patch(game, first) == second, "an exhausted extractor patch retargets a remaining covered resource")
	game.selected.assign([worker]); game.contextual_order(extractor.position, extractor)
	check(worker.order == "harvest", "right-clicking an extractor assigns harvesting even with an empty center tile")
	second.discovered = false; gas.discovered = false
	game.contextual_order(extractor.position, extractor)
	check(worker.order == "harvest", "extractors remain usable when only unsurveyed covered patches remain")
	game.apply_command({"kind": "expedition", "actors": [worker.simulation_id], "point": first.position, "mining": true})
	check(worker.complex_id < 0, "queued mining commands resolve an exhausted extractor patch to its remaining deposits")
	game.complex_commands.interrupt(worker)
	worker.position = extractor.position + Hex.to_world(Vector2i(2, 0), 1)
	check(game.resource_fields.harvest(game, worker, second) > 0, "extractors can be operated from an adjacent perimeter tile")
	extractor.powered = false
	check(game.resource_fields.harvest(game, worker, second) == 0, "an unpowered extractor cannot be bypassed by hand mining its hidden patches")
	game.dispose()

func run() -> void:
	work_distance(); field_loops(false); field_loops(true); convoy_and_extractor()
	print("TODO_LOGISTICS_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
