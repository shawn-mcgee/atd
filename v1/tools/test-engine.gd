extends SceneTree
const Simulation = preload("res://engine/simulation.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a = Simulation.new(); a.initialize(42)
	var b = Simulation.new(); b.initialize(42)
	check(a.state_hash() == b.state_hash(), "same seed produces identical state with independent object identities")
	var engineer: SimUnit = a.units[0]
	var marine: SimUnit = a.units[1]
	a.enqueue({"kind": "train", "actors": [a.core.simulation_id], "unit": "engineer", "tick": 0})
	a.enqueue({"kind": "context", "actors": [engineer.simulation_id], "point": Vector3(-8, 0, -5), "tick": 1})
	a.enqueue({"kind": "tactical", "actors": [marine.simulation_id], "mode": "patrol", "point": Vector3(8, 0, -6), "tick": 4})
	a.enqueue({"kind": "stop_selected", "actors": [marine.simulation_id], "tick": 180})
	a.enqueue({"kind": "context", "actors": [engineer.simulation_id], "point": Vector3(-10, 0, -8), "append": true, "tick": 5})
	var replay: Dictionary = JSON.parse_string(JSON.stringify(a.replay_data(), "", true, true))
	b.dispose(); b = Simulation.new(); b.load_replay(replay)
	var all_equal := true
	for tick in range(400):
		a.step(); b.step()
		if tick % 20 == 0 and a.state_hash() != b.state_hash():
			all_equal = false; print("Diverged at ", tick)
			if tick == 0:
				var left = a.snapshot(); var right = b.snapshot()
				for key in left:
					if JSON.stringify(left[key], "", true, true) != JSON.stringify(right[key], "", true, true): print("DIFF ", key, " ", left[key], " / ", right[key])
	check(all_equal, "serialized tick-stamped replay reproduces movement, commands, production and AI")
	a.elapsed = 600; b.elapsed = 600
	var late_equal := true
	for tick in range(40):
		a.step(); b.step()
		if a.state_hash() != b.state_hash(): late_equal = false
	check(late_equal, "late pressure, species roles and reinforcements remain deterministic")
	check(a.units.size() == 3 and a.core.queue.is_empty(), "HQ engineer production is preserved")
	check(engineer.position.distance_to(Vector3(-10, 0, -8)) < 1, "queued movement reaches its destination")
	var saved_tick: int = a.tick_number
	a.paused = true; a.step(); check(a.tick_number == saved_tick, "pause does not advance gameplay")
	a.paused = false
	var vehicle: SimUnit = a.add_unit("jeep", Vector3(5, 0, 0))
	var driver: SimUnit = a.add_unit("marine", vehicle.position)
	var worker: SimUnit = a.add_unit("engineer", vehicle.position)
	vehicle.board(driver); vehicle.board(worker)
	a.selected.assign([vehicle]); a.unload()
	check(vehicle.driver == driver and worker.aboard == null, "first unload leaves driver aboard")
	a.unload(); check(not vehicle.has_driver() and not vehicle.light_state, "second unload removes driver and turns headlights off")
	vehicle.cargo = 7; vehicle.gas_cargo = 9
	a.economy.minerals = a.economy.mineral_capacity
	a.economy.gas = 50
	a.deposit_cargo(vehicle, a.core)
	check(vehicle.cargo == 7 and vehicle.gas_cargo == 0 and a.economy.gas == 59, "full minerals never prevent methane delivery")
	var gate: SimStructure = a.add_structure("gate", Vector3(20, 0, 0))
	gate.powered = true; gate.gate_locked = true
	check(not a.set_gate(gate, true, false, true), "pathing cannot open a locked gate")
	gate.gate_locked = false
	check(a.set_gate(gate, true, false, true) and gate.gate_auto_opened, "powered unlocked gate records automatic passage")
	a.mission.beacon.complete = true
	check(a.mission.take(a, worker), "repaired beacon permits taking the Hive Core")
	a.mission.drop(worker); check(a.mission.dropped and a.mission.carrier == null, "carrier death drops the mission item")
	a.core.hp = 0; a.check_mission(); check(a.ended and not a.victorious, "HQ destruction still loses the mission")
	a.dispose(); b.dispose()
	print("ENGINE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
