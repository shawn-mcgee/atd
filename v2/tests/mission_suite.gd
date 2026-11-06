extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Mission = preload("res://core/mission.gd")
const Canonical = preload("res://core/canonical.gd")
const Hex = preload("res://core/hex_cells.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	_validation()
	_logistics()
	_outcomes()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission = {"enabled": true, "extraction_definition": "extraction_point", "nacre_amount": 20, "threshold": 4, "repair_ticks": 2, "countdown_ticks": 3}
	definitions.units.engineer.capabilities.mission_worker = {"capacity": 4, "mining_amount": 2, "mining_interval_ticks": 2, "work_range": 1.5}
	return definitions

func _players(multiple: bool = false) -> Array:
	var players := [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]
	if multiple: players.append({"id": 10, "faction": "human", "controller": "human"})
	return players

func _game(multiple: bool = false):
	var game = Sim.new()
	game.initialize(_definitions(), _players(multiple), 42)
	return game

func _command(kind: String, actors: Array, target: int = 0, player: int = 1) -> Dictionary:
	return {"player": player, "kind": kind, "actors": actors, "target": target}

func _validation() -> void:
	var content = Content.new()
	_check(content.load_text(Canonical.text(_definitions())), "mission content validates")
	for entry in [["threshold", 0], ["countdown_ticks", 1.5], ["repair_ticks", -1], ["nacre_amount", 100001], ["enabled", 1], ["extraction_definition", "hq"]]:
		var definitions := _definitions()
		definitions.settings.mission[entry[0]] = entry[1]
		_check(not content.load_text(Canonical.text(definitions)) and ("settings.mission." + str(entry[0])) in " ".join(content.errors), "invalid mission configuration has useful field path")
	var definitions := _definitions()
	definitions.settings.mission.threshold = 21
	_check(not content.load_text(Canonical.text(definitions)), "threshold cannot exceed finite deposit")
	definitions = _definitions()
	definitions.units.engineer.capabilities.mission_worker.capacity = 0
	_check(not content.load_text(Canonical.text(definitions)), "invalid cargo capacity rejected")
	definitions = _definitions()
	definitions.units.scavenger.capabilities.mission_worker = definitions.units.engineer.capabilities.mission_worker.duplicate(true)
	_check(not content.load_text(Canonical.text(definitions)), "Lightless cannot be Human mission workers")
	definitions = _definitions()
	definitions.units.hq.capabilities.factory.produces.append("extraction_point")
	_check(not content.load_text(Canonical.text(definitions)), "extraction points cannot be rebuilt")
	definitions = _definitions()
	definitions.settings.erase("mission")
	_check(content.load_text(Canonical.text(definitions)), "older presets may omit mission settings")
	var game = Sim.new()
	game.initialize(content.data, _players(), 42)
	_check(game.state.actors.size() == 6 and game.state.mission.humans.is_empty(), "omitted mission retains sandbox roster")
	game = _game()
	_check(game.state.actors.size() == 7 and int(game.state.mission.humans["1"].extraction) == 7, "mission appends one extraction point without shifting starting actor IDs")
	_check(int(game.entity(7).hp) == 60, "extraction starts damaged and inactive")

func _logistics() -> void:
	var game = _game()
	game.entity(2).position = game.entity(7).position.duplicate()
	game.step([_command("repair_point", [2], 7, 9)])
	_check(int(game.state.mission.humans["1"].repair_remaining) == 2, "foreign actor cannot repair point")
	game.step([_command("repair_point", [3], 7)])
	_check(int(game.state.mission.humans["1"].repair_remaining) == 2, "non-worker cannot repair")
	game.step([_command("repair_point", [2], 7)])
	game.step([])
	_check(int(game.state.mission.humans["1"].repair_remaining) == 0 and int(game.entity(7).hp) == 240, "engineer repairs and activates own extraction point")
	var reserve := int(game.state.banks["1"])
	game.entity(4).position = game.entity(7).position.duplicate()
	game.entity(4).hp = 0
	game.step([])
	_check(game.state.mission.fields.has("4") and int(game.state.mission.fields["4"].remaining) == 20, "destroyed Nest becomes finite nacre without winning")
	_check(not Mission.finished(game) and 1 in game.state.mission.fields["4"].known_by, "nearby Human discovers wreck with ordinary vision")
	game.step([_command("mine_nacre", [2], 4)])
	_check(int(game.entity(2).nacre) == 2 and int(game.state.mission.fields["4"].remaining) == 18, "mining transfers finite nacre into cargo")
	game.step([_command("mine_nacre", [2], 4)])
	_check(int(game.entity(2).nacre) == 2, "reissuing mining cannot bypass cooldown")
	game.step([])
	_check(int(game.entity(2).nacre) == 4, "mining fills but never exceeds cargo capacity")
	game.step([])
	_check(int(game.entity(2).nacre) == 0 and int(game.state.mission.humans["1"].deposited) == 4 and int(game.state.banks["1"]) == reserve, "automatic return deposits only at extraction and never into currency")
	_check(int(game.state.mission.humans["1"].countdown) == -1, "threshold enables extraction without automatically starting it")
	game.step([_command("stop", [2])])
	game.step([_command("start_extraction", [1])])
	_check(int(game.state.mission.humans["1"].countdown) == -1, "HQ cannot trigger extraction")
	game.step([_command("start_extraction", [7])])
	_check(int(game.state.mission.humans["1"].countdown) == 3, "player explicitly starts a full countdown")
	game.entity(2).nacre = 2
	game.step([_command("deliver_nacre", [2], 7)])
	_check(int(game.state.mission.humans["1"].deposited) == 6, "deliveries continue during countdown")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	game.step([])
	game.step([])
	_check(Mission.finished(game) and int(game.state.mission.outcome.winner) == 1 and int(game.state.mission.outcome.nacre) == 6, "first successful extraction wins with extra deposited nacre")
	var expected: String = game.state_hash()
	game.restore(saved)
	game.step([])
	game.step([])
	_check(game.state_hash() == expected, "JSON restore includes deposits, discovery, countdown and outcome")
	game.step([{"player": 1, "kind": "move", "actors": [2], "point": [0, 0, 0]}])
	_check(game.state.events.is_empty() and game.entity(2).order.is_empty(), "finished match freezes gameplay and does not repeat victory events")
	game = _game(true)
	game.entity(2).nacre = 3
	game.step([_command("deliver_nacre", [2], 11)])
	_check(game.entity(2).order.is_empty(), "cargo cannot be donated to another Human extraction point")
	game.step([_command("deliver_nacre", [2], 1)])
	_check(game.entity(2).order.is_empty(), "HQ is not a nacre receiver")
	game.entity(2).hp = 0
	game.step([])
	_check(game.entity(2) == null and int(game.state.mission.humans["1"].deposited) == 0, "dead carrier loses undelivered cargo")
	game = _game()
	game.entity(4).hp = 0
	game.step([])
	game.step([_command("mine_nacre", [2], 4)])
	_check(game.entity(2).order.is_empty(), "undiscovered wreck cannot be targeted through hidden global state")

func _outcomes() -> void:
	var game = _game(true)
	game.entity(1).hp = 0
	game.step([])
	_check(Mission.defeated(game, 1) and not Mission.finished(game), "one HQ loss defeats only its owner while another Human remains")
	var point: Array = game.entity(2).position.duplicate()
	game.step([{"player": 1, "kind": "move", "actors": [2], "point": [0, 0, 0]}])
	_check(game.entity(2).position == point and game.entity(2).order.is_empty(), "defeated player's remaining actors cannot receive commands or work")
	var extraction := int(game.state.mission.humans["10"].extraction)
	game.entity(extraction).hp = 0
	game.step([])
	_check(Mission.finished(game) and int(game.state.mission.outcome.winner) == 9, "Lightless wins only after defeating every Human including other players")
	game = _game()
	game.state.mission.humans["1"].countdown = 1
	game.state.mission.humans["1"].started_tick = -1
	game.entity(7).hp = 0
	game.step([])
	_check(game.state.mission.outcome.faction == "lightless", "destruction on final countdown tick defeats extraction")
	game = _game(true)
	for progress in game.state.mission.humans.values():
		progress.countdown = 1
		progress.started_tick = -1
	game.step([])
	_check(int(game.state.mission.outcome.winner) == 1, "simultaneous extraction uses roster order deterministically")
	game = _game()
	game.entity(2).position = game.entity(7).position.duplicate()
	for tick in 3: game.step([])
	_check(int(game.state.mission.humans["1"].repair_remaining) == 2 and game.entity(2).order.is_empty(), "idle workers do not repair without a player order")

func _rollback() -> String:
	var definitions := _definitions()
	definitions.settings.input_delay = 0
	definitions.units.scavenger.capabilities.weapon = {"damage": 1000, "range": 24, "interval_ticks": 1}
	definitions.units.scavenger.capabilities.perception.radius = 24
	var a = Rollback.new()
	var b = Rollback.new()
	a.initialize(definitions, _players(), 42, 0)
	b.initialize(definitions, _players(), 42, 0)
	for session in [a, b]:
		var progress: Dictionary = session.simulation.state.mission.humans["1"]
		progress.repair_remaining = 0
		progress.deposited = 4
		progress.countdown = 3
		progress.started_tick = 0
		session._save()
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events:
			if event.type == "match_won": seen.append(event))
	var delayed := [{"kind": "attack", "actors": [5], "target": 1}]
	for tick in 16:
		for player in [1, 9]:
			var commands: Array = delayed if tick == 2 and player == 9 else []
			a.receive(player, tick, commands)
			if not (tick == 2 and player == 9): b.receive(player, tick, commands)
	for tick in 10: a.advance(); b.advance()
	_check(b.simulation.state.mission.outcome.get("faction") == "human" and seen.is_empty(), "predicted Human extraction is withheld while a rival input frame is missing")
	_check(b.receive(9, 2, delayed) and b.rollbacks == 1, "late lethal input rolls back mission defeat")
	for tick in 6: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash() and int(b.simulation.state.mission.outcome.winner) == 9, "peers reproduce terminal mission state after replay")
	_check(seen.size() == 1 and b.confirmed_tick == 15, "terminal result is confirmed once while input confirmation continues")
	var unsafe = Rollback.new()
	unsafe.initialize(definitions, _players(), 42, 1)
	_check(not unsafe.queue({"kind": "mine_nacre", "actors": [2], "target": {}}), "malformed mission target rejected by network sanitizer")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
