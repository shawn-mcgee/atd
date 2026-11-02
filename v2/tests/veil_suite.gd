extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Rules = preload("res://core/match_rules.gd")
const Hex = preload("res://core/hex_cells.gd")
const Veil = preload("res://core/veil.gd")
const Rollback = preload("res://net/rollback_session.gd")
const Canonical = preload("res://core/canonical.gd")
var failures: Array[String] = []
var checks := 0

func run() -> Dictionary:
	_validation()
	_growth_and_senses()
	_global_communication()
	_stances()
	_support_and_restore()
	var hash_value := _rollback()
	return {"ok": failures.is_empty(), "checks": checks, "failures": failures, "hash": hash_value}

func _game(interval: int = 1):
	var content = Content.new()
	content.load_text(FileAccess.get_file_as_string("res://content/default.json"))
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.veil = {"tile_hp": 10, "light_damage_per_tick": 2, "decay_per_tick": 1, "alert_cooldown_ticks": 2, "memory_ticks": 80}
	definitions.units.nest.capabilities.veil_source = {"radius": 3, "growth_interval_ticks": interval, "growth_tiles": 64}
	definitions.units.hq.capabilities.illumination.radius = 1
	definitions.units.relay = definitions.units.nest.duplicate(true)
	definitions.units.relay.name = "Test relay"
	definitions.units.relay.capabilities.erase("factory")
	var game = Sim.new()
	var players := Rules.participants([{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}])
	game.initialize(definitions, players, 42)
	for item in [[1, -12, 0], [2, -12, 1], [3, -11, 1], [4, 0, 0], [5, 0, 2], [6, 0, 3]]:
		game.entity(int(item[0])).position = Hex.point([item[1], item[2]])
	return game

func _step(game, count: int) -> void:
	for index in count: game.step([])

func _validation() -> void:
	var content = Content.new()
	var definitions: Dictionary = _game().content.duplicate(true)
	definitions.units.scavenger.capabilities.veil_source = {"radius": 3, "growth_interval_ticks": 1, "growth_tiles": 1}
	_check(not content.load_text(Canonical.text(definitions)) and "stationary Lightless" in " ".join(content.errors), "mobile Veil sources rejected")
	definitions.units.scavenger.capabilities.erase("veil_source")
	definitions.settings.veil.decay_per_tick = -1
	_check(not content.load_text(Canonical.text(definitions)) and "settings.veil.decay_per_tick" in " ".join(content.errors), "invalid Veil tuning has a field path")
	for cell in [[0, 0], [-5, 2], [2, -7]]:
		_check(Hex.from_point(Hex.point(cell)) == cell, "integer axial conversion round-trips")

func _growth_and_senses() -> void:
	var game = _game()
	_step(game, 5)
	_check(game.state.veil.cells.size() > 20, "Veil branches over time")
	_check(not game.state.veil.cells.has("0,2"), "growth skips occupied tiles")
	for cell in game.state.veil.cells.values():
		_check(Hex.distance([cell.q, cell.r], [0, 0]) <= 3, "growth stays within source radius")
		_check(int(cell.hp) == 10, "perception does not damage Veil")
	var lit = _game()
	lit.entity(1).position = Hex.point([4, 0])
	lit.content.units.hq.capabilities.illumination.radius = 2
	_step(lit, 5)
	_check(not lit.state.veil.cells.has("2,0") and lit.state.veil.cells.has("-2,0"), "illumination blocks growth without blocking perception-only ground")
	game.entity(1).position = Hex.point([2, 0])
	game.step([])
	_check(int(game.state.veil.cells["1,0"].hp) == 8, "illumination damages existing Veil")
	_check(game.state.events.any(func(event): return event.type == "veil_alert" and event.reason == "illumination"), "illumination damage alerts connected Lightless")
	game.entity(1).position = Hex.point([-12, 0])
	game.entity(3).position = Hex.point([-1, 0])
	var before := int(game.state.veil.cells["-1,0"].hp)
	game.step([])
	_check(int(game.state.veil.cells["-1,0"].hp) == before, "stepping on Veil does not damage it")
	_check(game.state.events.any(func(event): return event.type == "veil_alert" and event.reason == "contact" and event.hostile), "enemy entry alerts the membrane")
	game.step([])
	_check(not game.state.events.any(func(event): return event.type == "veil_alert" and event.reason == "contact"), "stationary contacts do not repeatedly enter")
	game.entity(5).position = Hex.point([-1, -1])
	game.step([])
	_check(game.state.events.any(func(event): return event.type == "veil_alert" and event.reason == "contact" and not event.hostile), "friendly entry is detected too")

func _global_communication() -> void:
	var game = _game(100)
	_seed(game, [[0, 0], [2, 0], [8, 0]])
	game.entity(5).position = Hex.point([0, 1])
	game.entity(6).position = Hex.point([9, 0])
	Veil.signal_at(game, 9, Hex.point([0, 0]), "nest_attacked", 4)
	_check(game.state.veil.networks.size() == 1, "disconnected patches communicate globally")
	_check(game.state.events.back().recipients.has(5) and game.state.events.back().recipients.has(6), "alerts reach distant connected units")
	_check(Veil.networks_at(game.state.veil, 9, Hex.point([9, 0])).size() == 1, "units connect one tile away")
	_check(Veil.networks_at(game.state.veil, 9, Hex.point([10, 0])).is_empty(), "units do not connect two tiles away")
	game.entity(3).position = Hex.point([1, 0])
	game.entity(3).order = {"kind": "attack_veil", "point": Hex.point([2, 0])}
	Veil.attack(game, game.entity(3), Hex.point([2, 0]))
	_check(not game.state.veil.cells.has("2,0"), "weapons can destroy membrane tiles")
	_check(game.state.events.back().destroyed and game.state.events.back().recipients.has(6), "destruction alert reaches distant Veil before tile removal")
	Veil.signal_at(game, 9, Hex.point([0, 0]), "follow_up", 4)
	_check(game.state.veil.networks.size() == 1 and game.state.events.back().recipients.has(6), "wider gaps do not split communication")
	game.entity(6).position = Hex.point([12, 0])
	Veil.signal_at(game, 9, Hex.point([0, 0]), "unlinked", 4)
	_check(not game.state.events.back().recipients.has(6), "unconnected units do not receive global alerts")
	var snapshot := game.state_hash()
	Veil.networks_at(game.state.veil, 9, Hex.point([1, 0]))
	_check(snapshot == game.state_hash(), "network inspection is read-only")

func _stances() -> void:
	var game = _game()
	_step(game, 5)
	game.step([{"player": 9, "kind": "veil_stance", "actors": [4], "stance": "defensive"}])
	_check(game.entity(5).veil_stance.mode == "defensive", "connected units adopt Defensive")
	game.entity(3).position = Hex.point([1, -1])
	_step(game, 6)
	_check(game.entity(5).order.get("veil_order", false), "Defensive reacts to intrusions for a playable Lightless owner")
	game.step([{"player": 9, "kind": "move", "actors": [5], "point": Hex.point([0, 6])}])
	_check(game.entity(5).order.get("manual", false), "direct unit orders take priority over automatic stance response")
	game.step([{"player": 9, "kind": "veil_stance", "actors": [4], "stance": "neutral"}])
	_check(game.entity(5).veil_stance.mode == "neutral" and game.entity(5).order.get("manual", false), "Neutral preserves explicit unit work")
	_step(game, 85)
	game.step([{"player": 9, "kind": "veil_stance", "actors": [4], "stance": "defensive"}])
	_check(not game.entity(6).veil_stance.target.is_empty() and int(game.entity(6).veil_stance.expires) > int(game.state.tick), "Defensive detects a stationary intruder already inside the Veil")
	var assault = _game()
	_step(assault, 5)
	assault.step([{"player": 9, "kind": "veil_stance", "actors": [4], "stance": "offensive", "point": Hex.point([6, 0])}])
	var before: Array = assault.entity(5).position.duplicate()
	_step(assault, 10)
	_check(assault.entity(5).veil_stance.mode == "offensive" and assault.entity(5).position != before, "Offensive sends units toward an outside target")
	var mode: String = assault.state.veil.networks["1"].stance
	assault.step([{"player": 1, "kind": "veil_stance", "actors": [4], "stance": "neutral"}])
	_check(assault.state.veil.networks["1"].stance == mode, "opponents cannot change Veil stance")
	assault.step([{"player": 9, "kind": "veil_stance", "actors": [4], "stance": "offensive", "point": Hex.point([0, 0])}])
	_check(assault.state.veil.networks["1"].target == Hex.point([6, 0]), "offensive targets must be outside Veil")

func _support_and_restore() -> void:
	var game = _game()
	_step(game, 5)
	game._spawn("relay", 9, Hex.point([2, 0]))
	_step(game, 6)
	_check(game.state.veil.cells["1,0"].sources.size() == 2, "sources can support overlapping membrane")
	var overlap := int(game.state.veil.cells["1,0"].hp)
	var orphan := int(game.state.veil.cells["-2,0"].hp)
	game.entity(4).hp = 0
	game.step([])
	_check(int(game.state.veil.cells["1,0"].hp) == overlap, "a surviving source maintains shared Veil")
	_check(int(game.state.veil.cells["-2,0"].hp) == orphan - 1, "unsupported Veil decays after source death")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	_step(game, 15)
	var expected := game.state_hash()
	_check(not game.state.veil.cells.has("-2,0"), "unsupported Veil eventually disappears")
	game.restore(saved)
	_step(game, 15)
	_check(game.state_hash() == expected, "restoration includes support, growth timers, stance and alert cooldowns")

func _rollback() -> String:
	var fixture = _game()
	fixture.entity(3).position = Hex.point([-3, 0])
	var a = Rollback.new()
	var b = Rollback.new()
	var seen: Array = []
	for session in [a, b]:
		session.initialize(fixture.content, fixture.state.players, 42, 0)
		session.simulation.restore(fixture.checkpoint())
		session._save()
	b.events_confirmed.connect(func(events):
		for event in events: seen.append(int(event.id)))
	var delayed := [{"kind": "move", "actors": [3], "point": Hex.point([1, 0])}]
	for tick in 40:
		for player in [1, 9]:
			var commands: Array = []
			if tick == 2 and player == 9: commands = [{"kind": "veil_stance", "actors": [4], "stance": "defensive"}]
			if tick == 4 and player == 1: commands = delayed
			a.receive(player, tick, commands)
			if not (tick == 4 and player == 1): b.receive(player, tick, commands)
	for tick in 15: a.advance(); b.advance()
	_check(a.simulation.state_hash() != b.simulation.state_hash(), "late intrusion produces a genuinely divergent speculative state")
	_check(b.receive(1, 4, delayed), "late intrusion accepted within history")
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "rollback corrects membrane, contacts and stance response")
	for tick in 25: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "corrected Veil peers remain identical")
	var unique: Dictionary = {}
	for id in seen: unique[id] = true
	_check(not seen.is_empty() and unique.size() == seen.size(), "rollback does not duplicate confirmed Veil alerts")
	_check(a.error.is_empty() and b.error.is_empty(), "Veil rollback finishes without session errors")
	return a.simulation.state_hash()

func _seed(game, cells: Array) -> void:
	for cell in cells:
		game.state.veil.cells[Hex.key(cell)] = {"q": int(cell[0]), "r": int(cell[1]), "owner": 9, "hp": 10, "sources": [], "network": 0}
	game.state.veil.network_dirty = true

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
