extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Escalation = preload("res://core/nest_escalation.gd")
const Hex = preload("res://core/hex_cells.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	_validation()
	_grant_and_rates()
	_new_structures()
	_queue_budget()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission.enabled = false
	definitions.units.nest.capabilities.erase("chyme_source")
	definitions.units.scavenger.production_ticks = 12
	definitions.units.maw.construction_ticks = 12
	return definitions

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game(new_structures: bool = true):
	var definitions := _definitions()
	definitions.settings.nest_loss.affect_new_structures = new_structures
	var game = Sim.new()
	game.initialize(definitions, _players(), 42)
	game._spawn("scavenger_spawner", 9, Hex.point([5, 3]))
	game._spawn("mother", 9, Hex.point([8, 3]))
	game._spawn("mother", 9, Hex.point([9, 3]))
	game.step([{"player": 9, "kind": "build", "actors": [8], "definition": "maw", "point": Hex.point([8, 3])}])
	return game

func _validation() -> void:
	var content = Content.new()
	for entry in [["chyme_grant", -1], ["chyme_grant", 1e20], ["production_rate", 0], ["production_rate", 2.5], ["construction_rate", 9], ["construction_rate", "fast"], ["affect_new_structures", 1]]:
		var definitions := _definitions()
		definitions.settings.nest_loss[entry[0]] = entry[1]
		_check(not content.load_text(Canonical.text(definitions)) and ("settings.nest_loss." + str(entry[0])) in " ".join(content.errors), "invalid escalation parameters identify their field")
	var definitions := _definitions()
	definitions.settings.nest_loss = []
	_check(not content.load_text(Canonical.text(definitions)), "non-object Nest loss settings rejected")
	definitions = _definitions()
	definitions.settings.erase("nest_loss")
	_check(content.load_text(Canonical.text(definitions)), "older presets can omit Nest loss escalation")
	var game = Sim.new()
	game.initialize(content.data, _players(), 42)
	game.entity(4).hp = 0
	game.step([])
	_check(game.state.escalations.is_empty() and int(game.state.banks["9"]) == 100, "omitted escalation settings preserve previous gameplay")

func _grant_and_rates() -> void:
	var unrelated = _game()
	unrelated.entity(1).hp = 0
	unrelated.entity(7).hp = 0
	unrelated.step([])
	_check(unrelated.state.escalations.is_empty() and int(unrelated.state.banks["9"]) == 70, "ordinary structure and Human HQ losses do not trigger Nest escalation")
	var game = _game()
	game.step([{"player": 9, "kind": "train", "actors": [7], "definition": "scavenger"}])
	var remaining := int(game.entity(7).production[0].remaining)
	var growing := int(game.entity(8).construction.remaining)
	var reserve := int(game.state.banks["9"])
	_check(Escalation.rate(game, game.entity(7), "production") == 1, "living Nest gives no development bonus")
	game.entity(3).position = Hex.point([8, 0])
	game.entity(4).hp = 1
	game.step([{"player": 1, "kind": "attack", "actors": [3], "target": 4}])
	_check(game.entity(4) == null and int(game.state.banks["9"]) == reserve + 500, "enemy combat destroys Nest and grants chyme to its owner")
	_check(int(game.state.banks["1"]) == 100, "Nest grant is not shared with attacker or Human participants")
	_check(int(game.entity(7).production[0].remaining) == remaining - 1 and int(game.entity(8).construction.remaining) == growing - 1, "death tick keeps its original work rate regardless of actor order")
	var events: Array = game.state.events.filter(func(event): return event.type == "nest_destroyed")
	_check(events.size() == 1 and int(events[0].amount) == 500 and int(events[0].owner) == 9, "one owned escalation notice is emitted")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	remaining = int(game.entity(7).production[0].remaining)
	growing = int(game.entity(8).construction.remaining)
	game.step([])
	_check(int(game.entity(7).production[0].remaining) == remaining - 2 and int(game.entity(8).construction.remaining) == growing - 2, "existing queue and Womb accelerate from following tick")
	_check(Escalation.rate(game, game.entity(1), "production") == 1 and Escalation.rate(game, game.entity(9), "construction") == 1, "Human actors and mobile Mothers do not receive structure bonuses")
	_check(int(game.state.banks["9"]) == reserve + 500, "speed bonus does not spend resources again")
	var expected: String = game.state_hash()
	game.restore(saved)
	game.step([])
	_check(game.state_hash() == expected, "JSON checkpoints preserve grant guard and accelerated work")
	game._spawn("nest", 9, Hex.point([8, -3]))
	game.entity(int(game.state.next_id) - 1).hp = 0
	game.step([])
	_check(int(game.state.banks["9"]) == reserve + 500 and not game.state.events.any(func(event): return event.type == "nest_destroyed"), "even an injected second Nest cannot repeat the grant")
	for tick in 4: game.step([])
	_check(game.entity(8).definition == "maw" and game.entity(7).production.is_empty(), "ongoing production and construction finish at accelerated rates")
	_check(game.state.actors.any(func(actor): return int(actor.id) > 9 and actor.definition == "scavenger"), "accelerated production creates the queued unit")

func _new_structures() -> void:
	for inherit in [true, false]:
		var game = _game(inherit)
		game.entity(4).hp = 0
		game.step([])
		game.step([{"player": 9, "kind": "build", "actors": [9], "definition": "maw", "point": Hex.point([9, 3])}])
		_check(Escalation.rate(game, game.entity(8), "construction") == 2, "existing Womb remains eligible under either inheritance policy")
		_check(Escalation.rate(game, game.entity(9), "construction") == (2 if inherit else 1), "future Womb obeys configured inheritance policy")
		game._spawn("scavenger_spawner", 9, Hex.point([6, -3]))
		var future = game.entity(int(game.state.next_id) - 1)
		_check(Escalation.rate(game, future, "production") == (2 if inherit else 1), "future factory obeys configured inheritance policy")
		for tick in 12: game.step([])
		_check(game.entity(8).definition == "maw" and Escalation.rate(game, game.entity(8), "production") == 2, "existing Womb keeps eligibility when its actor definition changes")
		var before := int(game.state.banks["9"])
		for tick in 40: game.step([])
		_check(int(game.state.banks["9"]) == before + 4, "development bonus does not multiply passive resource income")
	var game = _game(false)
	game.entity(4).hp = 0
	game.step([])
	game.step([{"player": 9, "kind": "cancel_build", "actors": [8]}])
	game.step([{"player": 9, "kind": "build", "actors": [8], "definition": "maw", "point": Hex.point([8, 3])}])
	_check(Escalation.rate(game, game.entity(8), "construction") == 1, "cancelled Womb cannot transfer old eligibility into a new build")

func _queue_budget() -> void:
	var definitions := _definitions()
	definitions.settings.nest_loss.production_rate = 8
	definitions.units.scavenger.production_ticks = 3
	var game = Sim.new()
	game.initialize(definitions, _players(), 42)
	game._spawn("scavenger_spawner", 9, Hex.point([6, 3]))
	game.entity(4).hp = 0
	game.step([])
	game.step([{"player": 9, "kind": "train", "actors": [7], "definition": "scavenger"}, {"player": 9, "kind": "train", "actors": [7], "definition": "scavenger"}, {"player": 9, "kind": "train", "actors": [7], "definition": "scavenger"}])
	_check(game.state.actors.size() == 8 and game.entity(7).production.size() == 1 and int(game.entity(7).production[0].remaining) == 1, "work budget crosses queue entries without wasting progress or overproducing")
	_check(int(game.state.banks["9"]) == 570, "each boosted product is charged only when queued")
	game.step([])
	_check(game.entity(7).production.is_empty() and game.state.actors.size() == 9, "partially worked next entry completes on following tick")

func _rollback() -> String:
	var definitions := _definitions()
	definitions.units.marine.capabilities.weapon = {"damage": 1000, "range": 24, "interval_ticks": 1}
	definitions.units.marine.capabilities.perception.radius = 24
	definitions.units.scavenger.production_ticks = 2
	definitions.units.nest.capabilities.factory.produces.append("scavenger_spawner")
	definitions.units.scavenger_spawner.production_ticks = 1
	definitions.settings.input_delay = 0
	var a = Rollback.new()
	var b = Rollback.new()
	a.initialize(definitions, _players(), 42, 0)
	b.initialize(definitions, _players(), 42, 0)
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events:
			if event.type == "nest_destroyed": seen.append(event))
	var delayed := [{"kind": "attack", "actors": [3], "target": 4}]
	for tick in 24:
		for player in [1, 9]:
			var commands: Array = []
			if tick == 0 and player == 9: commands = [{"kind": "train", "actors": [4], "definition": "scavenger_spawner"}]
			if tick == 2 and player == 1: commands = delayed
			if tick == 4 and player == 9: commands = [{"kind": "train", "actors": [7], "definition": "scavenger"}]
			_check(a.receive(player, tick, commands), "reference frame accepted")
			if not (tick == 2 and player == 1): _check(b.receive(player, tick, commands), "delayed frame accepted")
	for tick in 10:
		a.advance()
		b.advance()
	_check(b.receive(1, 2, delayed) and b.rollbacks == 1, "late killing attack triggers rollback")
	for tick in 14:
		a.advance()
		b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "rollback reproduces Nest grant and accelerated production")
	_check(int(b.simulation.state.banks["9"]) == 550 and b.simulation.entity(7).production.is_empty(), "corrected reserve pays post-death production exactly once")
	_check(seen.size() == 1 and int(seen[0].amount) == 500 and b.confirmed_tick == 23, "Nest escalation is confirmed exactly once after replay")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
