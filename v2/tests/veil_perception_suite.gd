extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Hex = preload("res://core/hex_cells.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	_coverage()
	_growth_and_discovery()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission.enabled = false
	definitions.settings.input_delay = 0
	definitions.settings.veil.decay_per_tick = 1
	for definition in definitions.units.values():
		for cap in ["perception", "illumination", "veil_source", "passive_spawner", "chyme_source"]: definition.capabilities.erase(cap)
	definitions.units.nest.capabilities.detection = {"radius": 24}
	definitions.units.scavenger.capabilities.weapon.range = 24
	return definitions

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game():
	var game = Sim.new()
	game.initialize(_definitions(), _players(), 42)
	for item in [[1, -12, 0], [2, -12, 1], [3, 6, 0], [4, 0, 0], [5, 0, 2], [6, 0, 3]]:
		game.entity(int(item[0])).position = Hex.point([item[1], item[2]])
	for cell in [[6, 0], [9, 0]]:
		game.state.veil.cells[Hex.key(cell)] = {"q": cell[0], "r": cell[1], "owner": 9, "hp": 10, "sources": [], "network": 0}
	game.state.veil.network_dirty = true
	return game

func _step(game, count: int) -> void:
	for tick in count: game.step([])

func _coverage() -> void:
	var game = _game()
	game.step([])
	_check(game.visibility_at(9, Hex.point([6, 0])) == 2 and game.visibility_at(9, Hex.point([9, 0])) == 2, "disconnected unsupported Veil patches provide global full perception without nearby units")
	_check(game.visibility_at(9, [6 * Sim.SCALE + 256, 0, 0]) == 2, "perception covers positions inside the hex rather than only its center")
	_check(game.visibility_at(9, Hex.point([7, 0])) == 1, "adjacent uncovered tile retains detection-only status")
	_check(game.visibility_at(1, Hex.point([9, 0])) == 0, "Veil perception is private to its owner")
	_check(game.visible_to(9, game.entity(3)) == 2, "hostile actor standing on Veil becomes fully visible")
	_check(game.state.revealed["9"].has("6,0") and game.state.revealed["9"].has("9,0") and game.state.revealed["1"].is_empty(), "Veil reveals its owner's covered ground without sharing it")
	_check(int(game.state.veil.cells["6,0"].hp) == 9, "Veil perception does not add illumination damage to unsupported decay")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	_step(game, 12)
	_check(game.visibility_at(9, Hex.point([6, 0])) == 1 and game.state.veil.cells.is_empty(), "perception ends when tissue decays away and falls back to remaining senses")
	_check(game.state.revealed["9"].has("6,0"), "revealed ground remains remembered after Veil vision ends")
	var expected: String = game.state_hash()
	game.restore(saved)
	_step(game, 12)
	_check(game.state_hash() == expected, "JSON restore reproduces perception loss and permanent revelation")
	game.restore(saved)
	game.step([{"player": 9, "kind": "attack", "actors": [5], "target": 3}])
	_check(int(game.entity(3).hp) == int(game.content.units.marine.hp) - 1, "ordinary weapons can target enemies perceived solely through Veil")
	game.entity(3).position = Hex.point([7, 0])
	game.entity(5).ready_tick = 0
	game.step([])
	_check(int(game.entity(3).hp) == int(game.content.units.marine.hp) - 1, "ordinary weapons cannot keep firing after target leaves Veil into detection-only space")
	var definitions := _definitions()
	definitions.units.nest.capabilities.perception = {"radius": 1}
	definitions.units.scavenger.capabilities.perception = {"radius": 1}
	game.initialize(definitions, _players(), 42)
	_check(game.visibility_at(9, Hex.point([9, 0])) == 2, "ordinary structure perception still works independently of Veil")
	_check(game.visibility_at(9, game.entity(5).position) == 2, "ordinary unit perception still works independently of Veil")

func _growth_and_discovery() -> void:
	var definitions := _definitions()
	definitions.settings.mission.enabled = true
	definitions.units.nest.capabilities.veil_source = {"radius": 1, "growth_interval_ticks": 1, "growth_tiles": 1}
	var game = Sim.new()
	game.initialize(definitions, _players(), 42)
	game.state.mission.fields["99"] = {"position": game.entity(4).position.duplicate(), "remaining": 10, "known_by": []}
	_check(game.visibility_at(9, game.entity(4).position) == 1, "detection alone does not provide full pre-growth visibility")
	game.step([])
	var key := Hex.key(Hex.from_point(game.entity(4).position))
	_check(game.state.veil.cells.has(key) and game.state.revealed["9"].has(key), "fresh membrane reveals its ground in the same tick it grows")
	_check(9 in game.state.mission.fields["99"].known_by and not 1 in game.state.mission.fields["99"].known_by, "new Veil discovers resources in the growth tick without sharing Human vision")

func _rollback() -> String:
	var fixture = _game()
	fixture.entity(5).position = Hex.point([6, 1])
	var a = Rollback.new()
	var b = Rollback.new()
	for session in [a, b]:
		session.initialize(fixture.content, _players(), 42, 0)
		session.simulation.restore(fixture.checkpoint())
		session._save()
	var delayed := [{"kind": "move", "actors": [3], "point": Hex.point([7, 0])}]
	for tick in 16:
		for player in [1, 9]:
			var commands: Array = []
			if tick == 1 and player == 9: commands = [{"kind": "attack", "actors": [5], "target": 3}]
			if tick == 2 and player == 1: commands = delayed
			a.receive(player, tick, commands)
			if not (tick == 2 and player == 1): b.receive(player, tick, commands)
	for tick in 8: a.advance(); b.advance()
	_check(b.receive(1, 2, delayed) and b.rollbacks == 1, "late departure from perceived Veil triggers rollback")
	for tick in 8: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash() and b.confirmed_tick == 15, "rollback reproduces Veil perception, targeting, movement and decay")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
