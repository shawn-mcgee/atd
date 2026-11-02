extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Chyme = preload("res://core/chyme.gd")
const Rollback = preload("res://net/rollback_session.gd")
const Canonical = preload("res://core/canonical.gd")
var failures: Array[String] = []
var checks := 0

func run() -> Dictionary:
	_validation()
	_collection()
	_delivery()
	_passive_and_ai()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission.enabled = false
	definitions.settings.erase("nest_loss")
	return definitions

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game():
	var game = Sim.new()
	var definitions := _definitions()
	definitions.units.nest.capabilities.erase("chyme_source")
	game.initialize(definitions, _players(), 42)
	game.entity(1).position = [-10 * Sim.SCALE, 0, 0]
	game.entity(4).position = [4 * Sim.SCALE, 0, 0]
	game.entity(5).position = [0, 0, 0]
	game.entity(3).position = [512, 0, 0]
	return game

func _validation() -> void:
	var content = Content.new()
	_check(content.load_text(Canonical.text(_definitions())), "chyme preset validates")
	for item in [["chyme_collector", "capacity", 0], ["chyme_collector", "yield_per_damage", 0.5], ["chyme_receiver", "radius", -1], ["chyme_source", "interval_ticks", 0], ["chyme_source", "amount", 1e30]]:
		var definitions := _definitions()
		var unit: String = "scavenger" if item[0] == "chyme_collector" else "nest"
		definitions.units[unit].capabilities[item[0]][item[1]] = item[2]
		_check(not content.load_text(Canonical.text(definitions)) and ("units.%s.capabilities.%s.%s" % [unit, item[0], item[1]]) in " ".join(content.errors), "invalid chyme fields identify their path")
	var invalid := _definitions()
	invalid.units.marine.capabilities.chyme_collector = invalid.units.scavenger.capabilities.chyme_collector.duplicate(true)
	_check(not content.load_text(Canonical.text(invalid)), "Human chyme collector rejected")
	invalid = _definitions()
	invalid.units.scavenger.capabilities.chyme_receiver = {"radius": 1}
	_check(not content.load_text(Canonical.text(invalid)), "mobile receiver rejected")
	invalid = _definitions()
	invalid.units.scavenger.capabilities.erase("weapon")
	_check(not content.load_text(Canonical.text(invalid)), "collector requires a weapon")
	invalid = _definitions()
	invalid.settings.chyme = {"initial_reserve": -1}
	_check(not content.load_text(Canonical.text(invalid)) and "settings.chyme.initial_reserve" in " ".join(content.errors), "starting chyme validates")
	invalid = _definitions()
	invalid.settings.erase("chyme")
	for definition in invalid.units.values():
		for cap in ["chyme_collector", "chyme_receiver", "chyme_source"]: definition.capabilities.erase(cap)
	_check(content.load_text(Canonical.text(invalid)), "older presets remain valid without economy capabilities")

func _collection() -> void:
	var game = _game()
	game.content.units.scavenger.capabilities.chyme_collector.yield_per_damage = 3
	game.step([{"player": 9, "kind": "attack", "actors": [5], "target": 3}])
	_check(int(game.entity(5).chyme) == 3 and int(game.entity(3).hp) == 29, "yield uses actual post-armor damage")
	_check(int(game.state.banks["9"]) == 100, "carried chyme is not spendable")
	game.entity(3).hp = 2
	game.entity(5).ready_tick = 0
	game.content.units.scavenger.capabilities.weapon.damage = 100
	game.step([])
	_check(int(game.entity(5).chyme) == 9 and game.entity(3) == null, "overkill yields only remaining health")
	game = _game()
	game.content.units.scavenger.capabilities.weapon.damage = 1
	game.step([{"player": 9, "kind": "attack", "actors": [5], "target": 3}])
	_check(int(game.entity(5).chyme) == 0, "fully absorbed damage yields nothing")
	game.content.settings.minimum_damage = 2
	game.entity(5).ready_tick = 0
	game.entity(5).chyme = 49
	game.step([])
	_check(int(game.entity(5).chyme) == 50, "minimum damage yields chyme but cargo is capped")
	game.entity(5).ready_tick = 0
	game.step([])
	_check(int(game.entity(5).chyme) == 50 and int(game.entity(3).hp) == 26, "full cargo does not prevent combat")
	game = _game()
	game.entity(1).position = [512, 0, 0]
	game.step([{"player": 9, "kind": "attack", "actors": [5], "target": 1}])
	_check(int(game.entity(5).chyme) == 2, "structure damage also yields chyme")
	game.entity(5).hp = 0
	game.step([])
	_check(game.entity(5) == null and int(game.state.banks["9"]) == 100, "dead collector does not deposit its cargo")

func _delivery() -> void:
	var game = _game()
	game.entity(5).chyme = 12
	game.step([{"player": 1, "kind": "deliver_chyme", "actors": [5], "target": 4}])
	_check(game.entity(5).order.is_empty(), "foreign owner cannot order delivery")
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5], "target": 1}])
	_check(game.entity(5).order.is_empty() and int(game.state.banks["1"]) == 100, "enemy structures cannot receive cargo")
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5], "target": 6}])
	_check(game.entity(5).order.is_empty(), "friendly units are not receivers")
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5]}])
	_check(game.entity(5).order.get("kind") == "deliver_chyme" and int(game.state.banks["9"]) == 100, "nearest receiver order moves before crediting cargo")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	for tick in 30: game.step([])
	var expected: String = game.state_hash()
	_check(int(game.entity(5).chyme) == 0 and int(game.state.banks["9"]) == 112, "delivery credits exactly once within receiver radius")
	game.restore(saved)
	for tick in 30: game.step([])
	_check(game.state_hash() == expected, "JSON checkpoint restores cargo and in-flight delivery")
	game.state.banks["9"] = 0
	game.entity(5).chyme = 12
	game.step([{"player": 9, "kind": "train", "actors": [4], "definition": "scavenger"}])
	_check(game.entity(4).production.is_empty(), "production cannot spend undelivered cargo")
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5], "target": 4}])
	game.step([{"player": 9, "kind": "train", "actors": [4], "definition": "scavenger"}])
	_check(int(game.state.banks["9"]) == 2 and game.entity(4).production.size() == 1, "delivered chyme funds production at existing cost")
	game = _game()
	game.entity(5).chyme = 8
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5], "target": 4}])
	game.entity(4).hp = 0
	game.step([])
	_check(game.entity(5).order.is_empty() and int(game.entity(5).chyme) == 8 and int(game.state.banks["9"]) == 100, "destroyed receiver cancels delivery without losing cargo or crediting bank")
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5]}])
	_check(game.entity(5).order.is_empty(), "no receiver is a safe no-op")

func _passive_and_ai() -> void:
	var game = Sim.new()
	var definitions := _definitions()
	definitions.settings.chyme.initial_reserve = 0
	definitions.units.nest.capabilities.chyme_source = {"amount": 3, "interval_ticks": 2}
	game.initialize(definitions, _players(), 42)
	game.step([])
	game.step([])
	_check(int(game.state.banks["9"]) == 0, "passive source waits a full interval")
	var saved: Dictionary = game.checkpoint()
	game.step([])
	_check(int(game.state.banks["9"]) == 3, "passive generation credits shared reserve on schedule")
	var expected: String = game.state_hash()
	game.restore(Canonical.normalize(JSON.parse_string(Canonical.text(saved))))
	game.step([])
	_check(game.state_hash() == expected, "passive schedule survives JSON restore")
	game.entity(4).hp = 0
	for tick in 5: game.step([])
	_check(int(game.state.banks["9"]) == 3, "destroyed sources stop generating")
	game._spawn("nest", 9, [8 * Sim.SCALE, 0, 0])
	game.step([])
	game.step([])
	_check(int(game.state.banks["9"]) == 3, "new sources schedule relative to their spawn tick")
	game.step([])
	_check(int(game.state.banks["9"]) == 6, "new sources generate after their full interval")
	game = _game()
	game.state.players[1].controller = "ai"
	game.entity(5).chyme = 50
	game.step([])
	_check(game.entity(5).order.get("kind") == "deliver_chyme", "AI returns full cargo to a friendly receiver")
	for tick in 30: game.step([])
	_check(int(game.state.banks["9"]) == 150, "AI completes delivery")
	game = _game()
	game.state.players[1].controller = "ai"
	game.entity(5).chyme = 50
	game.step([{"player": 9, "kind": "move", "actors": [5], "point": [-4 * Sim.SCALE, 0, 0]}])
	_check(game.entity(5).order.get("kind") == "move", "explicit orders override automatic cargo return")

func _rollback() -> String:
	var definitions := _definitions()
	definitions.units.scavenger.capabilities.weapon = {"damage": 5, "range": 24, "interval_ticks": 1}
	definitions.units.scavenger.capabilities.perception.radius = 24
	definitions.units.scavenger.capabilities.chyme_collector.capacity = 6
	definitions.units.marine.hp = 100
	definitions.units.marine.armor = 0
	definitions.units.nest.capabilities.chyme_source.interval_ticks = 2
	definitions.settings.input_delay = 0
	var a = Rollback.new()
	var b = Rollback.new()
	a.initialize(definitions, _players(), 42, 0)
	b.initialize(definitions, _players(), 42, 0)
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events:
			if event.type.begins_with("chyme_"): seen.append(event))
	var delayed := [{"kind": "attack", "actors": [5], "target": 3}]
	for tick in 20:
		for player in [1, 9]:
			var commands: Array = []
			if tick == 2 and player == 9: commands = delayed
			if tick == 6 and player == 9: commands = [{"kind": "deliver_chyme", "actors": [5], "target": 4}]
			if tick == 7 and player == 9: commands = [{"kind": "train", "actors": [4], "definition": "scavenger"}]
			_check(a.receive(player, tick, commands), "reference frame accepted")
			if not (tick == 2 and player == 9): _check(b.receive(player, tick, commands), "delayed frame accepted")
	for tick in 10:
		a.advance()
		b.advance()
	_check(b.receive(9, 2, delayed) and b.rollbacks == 1, "late collection command triggers rollback")
	for tick in 10:
		a.advance()
		b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "rollback reproduces collection, delivery, passive income and spending")
	_check(int(b.simulation.state.banks["9"]) == 105, "corrected reserve includes delivery and production cost exactly once")
	var ids: Dictionary = {}
	var delivered := 0
	for event in seen:
		ids[event.id] = true
		if event.type == "chyme_delivered": delivered += int(event.amount)
	_check(ids.size() == seen.size() and delivered == 6, "confirmed chyme events never duplicate after rollback")
	var unsafe = Rollback.new()
	unsafe.initialize(definitions, _players(), 42, 9)
	_check(not unsafe.queue({"kind": "deliver_chyme", "actors": [5], "target": {}}), "malformed delivery target rejected")
	_check(unsafe.queue({"kind": "deliver_chyme", "actors": [5]}), "nearest delivery is a valid network command")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
