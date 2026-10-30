extends SceneTree
const Simulation = preload("res://engine/simulation.gd")
const Unit = preload("res://engine/expedition_unit.gd")
const Structure = preload("res://engine/expedition_structure.gd")
const Power = preload("res://engine/expedition_power.gd")
const Economy = preload("res://engine/expedition_economy.gd")
const Hex = preload("res://engine/hex_grid.gd")
const Navigation = preload("res://engine/expedition_navigation.gd")
const Light = preload("res://engine/illumination.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func building(kind: String, point: Vector3) -> SimStructure:
	var result := Structure.new(); result.setup(kind, point, true); return result
func run() -> void:
	var game := Simulation.new(); game.initialize(42)
	var engineer: SimUnit = game.units[0]; engineer.hp = 10
	game.heal_near_hq(1)
	check(engineer.hp == 13, "HQ passively heals nearby friendly units at the configured rate")
	engineer.position = Vector3(30, 0, 0); game.heal_near_hq(1)
	check(engineer.hp == 13, "HQ healing is limited to its configured radius")
	engineer.position = Vector3.ZERO; engineer.hp = 79; game.heal_near_hq(2)
	check(engineer.hp == 80, "healing caps at maximum HP")
	engineer.hp = 0; game.heal_near_hq(1); check(engineer.hp == 0, "HQ does not revive dead units")
	engineer.hp = 80
	var jeep := Unit.new(); jeep.setup("jeep", Vector3.ZERO); jeep.board(engineer); jeep.battery = 0
	jeep.path = PackedVector3Array([Vector3.ZERO, Vector3(3, 0, 0)]); jeep.tick_move(1)
	check(jeep.position.x > 0 and jeep.light_state, "vehicles need pilots but no battery or charging")
	jeep.disembark(engineer, Vector3.ZERO)
	var gen := building("generator", Vector3.ZERO)
	var relay := building("repeater", Vector3(13.8, 0, 0))
	var relay2 := building("repeater", Vector3(34.4, 0, 0))
	var extractor := building("extractor", Hex.to_world(Vector2i(26, 0), 1))
	var power := Power.new(); var economy := Economy.new()
	power.tick([gen, relay, relay2, extractor], economy, 0)
	check(relay.powered and relay2.powered, "relay connections use generator+relay and relay+relay ranges")
	check(extractor.powered and not Power.covers(relay2, extractor.position), "a consumer connects through any occupied tile")
	extractor.position.x += 1.7320508075688772; power.tick([gen, relay, relay2, extractor], economy, 0)
	check(not extractor.powered, "consumers outside every source footprint range remain offline")
	game.resource_nodes.clear(); var center := Vector3(40, 0, -20)
	var cells: Array = [Vector2i.ZERO] + Hex.NEIGHBORS
	for i in range(7):
		game.add_resource_patch("minerals" if i < 3 else "gas", center + Hex.to_world(cells[i], 1), 100)
		game.resource_nodes[-1].discovered = true
	extractor = game.add_structure("extractor", center); extractor.powered = true
	check(game.Footprints.cells("extractor", center).size() == 7 and game.resource_fields.extractor_site(game, center + Vector3(1.732, 0, 0)), "extractor covers seven hexes and can overlap a field off-center")
	engineer.position = center + Vector3(3.464, 0, 0); engineer.capacity = 1000; engineer.cargo = 0; engineer.gas_cargo = 0
	for i in range(70): game.resource_fields.harvest(game, engineer, game.resource_nodes[0])
	check(engineer.cargo == 90 and engineer.gas_cargo == 120, "extractor output follows covered mineral/gas proportions")
	check(game.resource_nodes.all(func(patch): return patch.remaining == 70), "all covered deposits deplete evenly")
	game.resource_nodes[0].remaining = 0
	var cargo_before := engineer.cargo_total()
	check(game.resource_fields.available(game, game.resource_nodes[0]) and game.resource_fields.harvest(game, engineer, game.resource_nodes[0]) == 3 and engineer.cargo_total() == cargo_before + 3, "an exhausted clicked patch can still service the rest of an extractor")
	engineer.capacity = engineer.cargo_total() + 1
	check(game.resource_fields.harvest(game, engineer, game.resource_nodes[0]) == 1, "mixed extraction respects the final cargo slot")
	game.dispose()
	var nav := Navigation.new(); var blockers: Array[Dictionary] = []
	for r in range(-10, 11):
		var cell := Vector2i(2, r); blockers.append({"position": Hex.to_world(cell, 1), "cell": cell, "radius": 0.95, "height": 3.0})
	nav.rebuild(blockers)
	var light := Light.new(); light.configure(nav); light.add_source(Vector3.ZERO, 8)
	check(light.sample(Hex.to_world(Vector2i(1, 0), 1)) > 0 and light.sample(Hex.to_world(Vector2i(4, 0), 1)) == 0, "ground light flood-fill stops at a cliff barrier")
	var top := Hex.to_world(Vector2i(2, 0), 1) + Vector3.UP * 3
	check(light.sample(top) == 0, "ground light cannot reveal the top of a tall cliff")
	light.clear(); light.add_source(Vector3(0, 3, 0), 8)
	check(light.sample(top) > 0 and light.sample(Hex.to_world(Vector2i(4, 0), 1)) > 0, "upper-level sources illuminate equal and lower levels")
	check(Simulation.Config.error_message.is_empty() and Simulation.Rules.UNITS.engineer.speed == 3.1, "gameplay balance loads from JSON")
	print("TODO_UPGRADES_TEST_RESULT: ", failures, " failures"); quit(1 if failures else 0)
