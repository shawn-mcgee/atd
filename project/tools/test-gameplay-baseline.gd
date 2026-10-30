extends SceneTree
# Keep the frozen 3D comparison on its historical work radius. Current one-tile
# construction, repair and delivery behavior is covered by test-todo-logistics.
class OriginalWorkSimulation extends "res://engine/simulation.gd":
	func _init() -> void:
		director = preload("res://tools/fixtures/original_predator_director.gd").new()
	func within_work_reach(unit: SimUnit, target: SimEntity) -> bool:
		return Footprints.reach(target, unit.position) < 4

var failures := 0
func _initialize(): call_deferred("run")
func capture(game):
	var result = {"tick": game.tick_number, "bank": [game.economy.minerals, snappedf(game.economy.gas, 0.00001)], "power": [game.power.capacity, game.power.used], "resources": [], "units": [], "structures": [], "enemies": []}
	for patch in game.resource_nodes: result.resources.append([patch.kind, patch.position, patch.remaining, patch.discovered])
	for unit in game.units: result.units.append([unit.kind, unit.position, unit.hp, unit.order, unit.cargo, unit.gas_cargo, unit.path.duplicate(), unit.path_index, unit.facing, unit.cooldown])
	for building in game.structures: result.structures.append([building.kind, building.position, building.hp, building.complete, building.progress, building.powered, building.queue.duplicate(), building.production_progress])
	for enemy in game.creatures: result.enemies.append([enemy.kind, enemy.position, enemy.hp, enemy.state, enemy.path.duplicate(), enemy.path_index, enemy.cooldown])
	return result

func equivalent(a, b) -> bool:
	if a is float or a is Vector3:
		var okay = absf(a - b) < 0.0001 if a is float else a.distance_to(b) < 0.0001
		if not okay: print("NUMERIC DIFF ", a, " / ", b, " difference ", a - b)
		return okay
	if a is Array or a is PackedVector3Array:
		if a.size() != b.size(): print("SIZE DIFF ", a.size(), " / ", b.size(), " ", a, " / ", b); return false
		for i in range(a.size()):
			if not equivalent(a[i], b[i]): return false
		return true
	if a is Dictionary:
		if a.keys() != b.keys(): return false
		for key in a:
			if not equivalent(a[key], b[key]): return false
		return true
	if a != b: print("VALUE DIFF ", a, " / ", b)
	return a == b
func run():
	var game = OriginalWorkSimulation.new()
	game.layout = preload("res://tools/fixtures/original_seeded_layout.gd").new()
	game.initialize(42)
	game.selected.assign([game.core]); game.train_unit("engineer")
	game.selected.assign([game.units[0]])
	game.issue_order(game.units[0], "move", Vector3(-6, 0, -5))
	game.issue_order(game.units[1], "patrol", Vector3(8, 0, -5))
	var wall = game.add_structure("wall", Vector3(-6, 0, -7), false); wall.funded = true
	game.issue_order(game.units[0], "build", wall.position, wall, true)
	game.rebuild_navigation()
	var file = FileAccess.open("res://tools/fixtures/3d-gameplay-baseline.var", FileAccess.READ)
	var baseline = file.get_var(); file.close()
	# Later enemy paths legitimately change with the expanded world boundary.
	# Preserve the original movement/build/production checks before that divergence.
	for tick in range(200):
		for sub in range(6): game.advance_movement(0.1 / 6.0)
		game.simulation_tick(0.1, false)
		if tick % 20 == 0:
			if not equivalent(baseline[tick / 20], capture(game)): failures += 1; push_error("3D gameplay baseline diverged at tick %d" % tick)
	game.dispose()
	print("GAMEPLAY_BASELINE_TEST_RESULT: ", failures, " failures / 10 pre-expansion mechanics checkpoints")
	quit(1 if failures else 0)
