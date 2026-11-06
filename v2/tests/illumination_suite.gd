extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Hex = preload("res://core/hex_cells.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var data: Dictionary = content.data.duplicate(true)
	data.settings.mission.enabled = false
	data.units.hq.footprint = [[0, 0]] # Compact corner/blocker fixture.
	data.settings.input_delay = 0
	for definition in data.units.values():
		for cap in ["perception", "illumination", "detection", "veil_source", "passive_spawner", "chyme_source"]: definition.capabilities.erase(cap)
	data.units.hq.capabilities.illumination = {"radius": 2}
	data.units.wall.construction_ticks = 1
	return data

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game():
	var game = Sim.new()
	game.initialize(_definitions(), _players(), 42)
	game.entity(1).position = Hex.point([0, 0])
	game.state.revealed["1"] = {}
	return game

func run() -> Dictionary:
	var content = Content.new()
	_check(content.load_text(Canonical.text(_definitions())), "light blocker content validates")
	var invalid := _definitions()
	invalid.units.wall.capabilities.move = {"speed": 1}
	_check(not content.load_text(Canonical.text(invalid)) and "capabilities.light_blocker" in " ".join(content.errors), "mobile blocker rejected with field path")
	invalid = _definitions()
	invalid.units.wall.capabilities.light_blocker = {"radius": 1}
	_check(not content.load_text(Canonical.text(invalid)), "unsupported blocker parameters rejected")
	var game = _game()
	_check(not game.content.units.hq.capabilities.has("light_blocker"), "HQ never blocks light")
	_check(game.illumination_cells(1).size() == 19, "radius two covers nineteen hexes")
	_check(game.illumination_cells(9).is_empty(), "illumination visibility stays owner-specific")
	game._spawn("wall", 9, Hex.point([1, 0]))
	_check(game.illumination_cells(1).has("1,0") and not game.illumination_cells(1).has("2,0"), "hostile wall receives light and stops propagation")
	_check(game.visibility_at(1, [1024 + 200, 0, 100]) == 2 and game.visibility_at(1, Hex.point([2, 0])) == 0, "illumination visibility follows whole reached tiles")
	var before: String = game.state_hash()
	for query in 3: game.illumination_cells(); game.visibility_at(1, Hex.point([2, 0]))
	_check(game.state_hash() == before, "derived queries never change checkpoint state")
	game.step([])
	_check(game.state.revealed["1"].has("1,0") and not game.state.revealed["1"].has("2,0"), "discovery uses propagated light, including blocking tile")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	game.entity(7).hp = 0
	_check(game.illumination_cells(1).has("2,0"), "destroyed blocker immediately opens light path")
	game.step([])
	_check(game.state.revealed["1"].has("2,0"), "stationary source reveals newly opened paths")
	game.restore(saved)
	_check(not game.illumination_cells(1).has("2,0"), "JSON restore discards stale derived field")
	game.content.units.hq.capabilities.illumination.radius = 3
	_check(game.illumination_cells(1).has("2,0"), "light travels around wall when detour fits budget")
	game.content.units.hq.capabilities.illumination.radius = 2
	game._spawn("hq", 9, Hex.point([2, 0]))
	_check(game.illumination_cells(9).has("0,0") == false, "second light source still respects wall")
	game.entity(8).position = Hex.point([1, 1])
	_check(game.illumination_cells(9).has("2,0") and not game.illumination_cells(1).has("2,0"), "overlapping sources retain separate ownership")
	game.content.units.marine.capabilities.detection = {"radius": 24}
	_check(game.visibility_at(1, Hex.point([2, 0])) == 1, "detection stays radial through light blockers")
	game.content.units.marine.capabilities.perception = {"radius": 24}
	_check(game.visibility_at(1, Hex.point([2, 0])) == 2, "perception independently reveals unlit tiles")
	game = _game()
	game.content.units.hq.capabilities.illumination.radius = 0
	_check(game.illumination_cells(1).size() == 1, "zero radius illuminates only emitter tile")
	game.content.units.hq.capabilities.illumination.radius = 1.9
	_check(game.illumination_cells(1).size() == 7, "fractional radius uses complete propagation steps")
	game.entity(1).position = Hex.point([int(game.content.settings.map_radius), 0])
	for cell in game.illumination_cells().values():
		_check(Hex.inside(cell, int(game.content.settings.map_radius)), "flood fill stays inside arena")
	_effects()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _effects() -> void:
	var game = _game()
	game._spawn("wall", 1, Hex.point([1, 0]))
	game.entity(4).position = Hex.point([2, 0])
	game.content.units.nest.capabilities.veil_source = {"radius": 1, "growth_interval_ticks": 1, "growth_tiles": 64}
	game.step([])
	_check(game.state.veil.cells.has("2,0"), "Veil can grow in wall's shadow")
	game.step([])
	_check(int(game.state.veil.cells["2,0"].hp) == int(game.content.settings.veil.tile_hp), "shadow protects existing Veil from light damage")
	game.content.units.hq.capabilities.illumination.radius = 3
	game.step([])
	_check(int(game.state.veil.cells["2,0"].hp) == int(game.content.settings.veil.tile_hp) - int(game.content.settings.veil.light_damage_per_tick), "light reaching around corner damages Veil")
	game = _game()
	game.content.units.turret.capabilities.light_blocker = {}
	game.entity(2).position = Hex.point([1, 1])
	game.state.revealed["1"]["1,0"] = true
	game.content.units.turret.construction_ticks = 1
	game.step([{"kind": "build", "player": 1, "actors": [2], "definition": "turret", "point": Hex.point([1, 0])}])
	_check(not game.illumination_cells(1).has("2,0"), "completed structure activates authored light blocker")
	game.entity(1).hp = 0
	_check(game.illumination_cells(1).is_empty(), "destroyed source removes its illumination")

func _rollback() -> String:
	var data := _definitions()
	data.units.hq.capabilities.illumination.radius = 3
	data.units.engineer.capabilities.move.speed = 15
	var a = Rollback.new(); var b = Rollback.new()
	a.initialize(data, _players(), 42, 0)
	b.initialize(data, _players(), 42, 0)
	var build := {"kind": "build", "actors": [2], "definition": "wall", "point": Hex.point([-6, 0])}
	for tick in 90:
		for player in [1, 9]:
			var commands: Array = [build] if tick == 0 and player == 1 else []
			a.receive(player, tick, commands)
			if tick != 0 or player != 1: b.receive(player, tick, commands)
	for tick in 40: a.advance(); b.advance()
	_check(a.simulation.entity(7).definition == "wall" and not a.simulation.illumination_cells(1).has("-5,0"), "constructed wall blocks reference illumination")
	_check(b.simulation.illumination_cells(1).has("-5,0"), "predicted peer has unblocked field before correction")
	_check(b.receive(1, 0, [build]) and b.rollbacks == 1, "late wall construction triggers rollback")
	for tick in 50: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash() and a.simulation.illumination_cells() == b.simulation.illumination_cells(), "rollback reproduces discovery and blocked light field")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
