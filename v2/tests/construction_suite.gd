extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Construction = preload("res://core/construction.gd")
const Hex = preload("res://core/hex_cells.gd")
const Rollback = preload("res://net/rollback_session.gd")
const Canonical = preload("res://core/canonical.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	_validation()
	_revelation()
	_build_and_cancel()
	_placement_and_loss()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission.enabled = false
	definitions.units.nest.capabilities.erase("chyme_source")
	definitions.units.scavenger_spawner.construction_ticks = 4
	definitions.units.chyme_pool.construction_ticks = 3
	return definitions

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game():
	var game = Sim.new()
	game.initialize(_definitions(), _players(), 42)
	game._spawn("mother", 9, Hex.point([8, 3]))
	game.step([])
	return game

func _build(point: Array = [8, 3], type: String = "scavenger_spawner") -> Dictionary:
	return {"kind": "build", "player": 9, "actors": [7], "definition": type, "point": Hex.point(point)}

func _validation() -> void:
	var content = Content.new()
	_check(content.load_text(Canonical.text(_definitions())), "builder and structure content validates")
	for entry in [["womb", "missing"], ["womb", "hq"], ["womb", "nest"], ["structures", []], ["structures", ["missing"]], ["structures", ["marine"]], ["structures", ["nest"]], ["structures", ["womb"]], ["structures", ["mother"]]]:
		var definitions := _definitions()
		definitions.units.mother.capabilities.metamorphosis[entry[0]] = entry[1]
		_check(not content.load_text(Canonical.text(definitions)) and "units.mother.capabilities.metamorphosis" in " ".join(content.errors), "invalid metamorphosis definitions have a useful field path")
	var definitions := _definitions()
	definitions.units.scavenger_spawner.erase("construction_ticks")
	_check(not content.load_text(Canonical.text(definitions)) and "units.scavenger_spawner.construction_ticks" in " ".join(content.errors), "structure construction duration is required")
	definitions = _definitions()
	definitions.units.mother.capabilities.erase("move")
	_check(not content.load_text(Canonical.text(definitions)), "stationary builder rejected")
	definitions = _definitions()
	definitions.units.womb.capabilities.chyme_receiver = {"radius": 1}
	_check(not content.load_text(Canonical.text(definitions)), "Womb cannot receive chyme or operate before completion")
	definitions = _definitions()
	definitions.units.nest.capabilities.factory.produces.append("nest")
	_check(not content.load_text(Canonical.text(definitions)), "Nest cannot be rebuilt through production")

func _revelation() -> void:
	var game = _game()
	_check(game.state.revealed["9"].has("8,3"), "starting senses reveal ground")
	_check(not game.state.revealed["1"].has("8,3"), "revealed ground is private to its owner")
	game.entity(4).position = Hex.point([12, -12])
	game.entity(5).position = Hex.point([12, -11])
	game.entity(6).position = Hex.point([11, -12])
	game.entity(7).position = Hex.point([10, -12])
	game.step([])
	_check(game.visibility_at(9, Hex.point([8, 3])) == 0 and game.state.revealed["9"].has("8,3"), "revelation survives after senses leave")
	_check(Construction.site_error(game, game.entity(7), "chyme_pool", Hex.point([8, 3])).is_empty(), "previously revealed darkness remains buildable")
	game.entity(3).position = Hex.point([8, 3])
	_check(Construction.site_error(game, game.entity(7), "chyme_pool", Hex.point([8, 3]), true).is_empty() and not Construction.site_error(game, game.entity(7), "chyme_pool", Hex.point([8, 3])).is_empty(), "placement preview does not leak unseen occupancy while core rejects it")
	var definitions := _definitions()
	for definition in definitions.units.values():
		definition.capabilities.erase("perception")
		definition.capabilities.erase("illumination")
	definitions.units.nest.capabilities.detection = {"radius": 24}
	game.initialize(definitions, _players(), 42)
	_check(game.state.revealed["9"].is_empty(), "detection alone does not reveal terrain")
	definitions.units.nest.capabilities.perception = {"radius": 4}
	game.initialize(definitions, _players(), 42)
	_check(game.state.revealed["9"].has("12,-2"), "sensor bounds include oblique axial range edges")
	var saved: Dictionary = game.checkpoint()
	game.restore(Canonical.normalize(JSON.parse_string(Canonical.text(saved))))
	game.step([])
	_check(game.state.revealed == saved.revealed, "derived discovery cache rebuild does not lose or invent revelation")

func _build_and_cancel() -> void:
	var game = _game()
	game.entity(7).hp = 39
	game.step([_build()])
	_check(game.entity(7).definition == "womb" and int(game.state.banks["9"]) == 60, "Mother becomes Womb and pays once on arrival")
	_check(game.entity(7).production.is_empty() and not game.state.veil.sources.has("7"), "Womb has no production or Veil source")
	game.step([{"kind": "move", "player": 9, "actors": [7], "point": Hex.point([6, 3])}, {"kind": "train", "player": 9, "actors": [7], "definition": "scavenger"}])
	_check(game.entity(7).position == Hex.point([8, 3]) and game.entity(7).production.is_empty(), "Womb cannot move or produce")
	game.step([{"kind": "cancel_build", "player": 1, "actors": [7]}])
	_check(game.entity(7).definition == "womb", "foreign player cannot cancel construction")
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(game.entity(7).definition == "mother" and int(game.entity(7).hp) == 39 and int(game.state.banks["9"]) == 100, "undamaged cancellation restores exact Mother health and full refund")
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(int(game.state.banks["9"]) == 100, "repeated cancellation cannot duplicate a refund")
	game.step([_build()])
	game.entity(7).hp = int(game.entity(7).hp) - 6
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(int(game.entity(7).hp) == 31, "damage to Womb persists proportionally on restored Mother")
	game.step([_build()])
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	for tick in 4: game.step([])
	_check(game.entity(7).definition == "scavenger_spawner" and game.entity(7).construction.is_empty(), "Womb matures after configured duration while preserving actor ID")
	_check(int(game.entity(7).hp) < 180 and game.state.veil.sources.has("7"), "completion preserves damage and activates structure capabilities")
	var expected: String = game.state_hash()
	game.restore(saved)
	for tick in 4: game.step([])
	_check(game.state_hash() == expected, "JSON restore reproduces in-progress construction and Veil activation")
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(game.entity(7).definition == "scavenger_spawner" and int(game.state.banks["9"]) == 60, "completed structure cannot refund or restore Mother")
	game.step([{"kind": "train", "player": 9, "actors": [7], "definition": "scavenger"}])
	_check(game.entity(7).production.size() == 1 and int(game.state.banks["9"]) == 50, "completed spawner uses shared chyme for production")
	game = _game()
	game.step([_build([8, 3], "chyme_pool")])
	for tick in 3: game.step([])
	_check(game.entity(7).definition == "chyme_pool", "Mother can build a different composed structure")
	for tick in 40: game.step([])
	_check(int(game.state.banks["9"]) == 72, "new passive structure waits a full generation interval")
	game = _game()
	game.content.units.mother.capabilities.weapon = {"damage": 10, "range": 2, "interval_ticks": 20}
	game.entity(3).position = Hex.point([8, 4])
	game.step([{"kind": "attack", "player": 9, "actors": [7], "target": 3}])
	var health := int(game.entity(3).hp)
	game.step([_build()])
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}, {"kind": "attack", "player": 9, "actors": [7], "target": 3}])
	_check(int(game.entity(3).hp) == health, "transformation and cancellation cannot reset an authored Mother's weapon cooldown")

func _placement_and_loss() -> void:
	var game = _game()
	game.step([_build([-12, 0])])
	_check(game.entity(7).order.is_empty(), "unrevealed ground cannot receive a build order")
	game.step([_build([8, 0])])
	_check(game.entity(7).order.is_empty(), "occupied footprint cannot receive a build order")
	game.step([_build([8, 3], "nest")])
	_check(game.entity(7).definition == "mother", "Nest is not a construction product")
	game._spawn("mother", 9, Hex.point([8, 4]))
	var command := _build([5, 3])
	command.actors = [7, 8]
	game.step([command])
	_check(game.entity(7).order.get("kind") == "build" and game.entity(8).order.is_empty() and int(game.state.banks["9"]) == 100, "first Mother reserves tile without charging while travelling")
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(game.entity(7).order.is_empty() and int(game.state.banks["9"]) == 100, "cancelling travel releases reservation without refunding unpaid cost")
	game = _game()
	game.step([_build([6, 3])])
	game.state.banks["9"] = 0
	for tick in 50: game.step([])
	_check(game.entity(7).definition == "mother" and game.entity(7).order.is_empty(), "insufficient funds on arrival safely cancel unpaid order")
	game = _game()
	game.step([_build()])
	game.entity(3).position = Hex.point([8, 3])
	game.step([{"kind": "attack", "player": 1, "actors": [3], "target": 7}])
	_check(int(game.entity(7).hp) == 20, "Womb is vulnerable to normal enemy combat")
	game.entity(7).hp = 0
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(game.entity(7) == null and int(game.state.banks["9"]) == 60, "destroyed Womb loses Mother and investment without refund")
	game = _game()
	game.step([_build()])
	game.entity(5).position = Hex.point([8, 3])
	for tick in 4: game.step([])
	_check(game.entity(7).definition == "womb" and game.entity(7).construction.get("blocked", false), "completion waits for footprint occupants to clear")
	game.entity(5).position = Hex.point([6, 3])
	game.step([])
	_check(game.entity(7).definition == "scavenger_spawner", "completion resumes after footprint clears")

func _rollback() -> String:
	var definitions := _definitions()
	definitions.settings.input_delay = 0
	definitions.units.mother.production_ticks = 1
	var a = Rollback.new()
	var b = Rollback.new()
	a.initialize(definitions, _players(), 42, 0)
	b.initialize(definitions, _players(), 42, 0)
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events:
			if event.type.begins_with("construction_"): seen.append(event))
	var delayed := [{"kind": "build", "actors": [7], "definition": "chyme_pool", "point": Hex.point([6, 2])}]
	for tick in 90:
		for player in [1, 9]:
			var commands: Array = []
			if player == 9 and tick == 0: commands = [{"kind": "train", "actors": [4], "definition": "mother"}]
			if player == 9 and tick == 2: commands = delayed
			if player == 9 and tick == 4: commands = [{"kind": "cancel_build", "actors": [7]}]
			if player == 9 and tick == 6: commands = delayed
			_check(a.receive(player, tick, commands), "reference frame accepted")
			if not (player == 9 and tick == 2): _check(b.receive(player, tick, commands), "delayed frame accepted")
	for tick in 10:
		a.advance()
		b.advance()
	_check(b.receive(9, 2, delayed) and b.rollbacks == 1, "late build order triggers rollback")
	for tick in 80:
		a.advance()
		b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash() and b.simulation.entity(7).definition == "chyme_pool", "rollback reproduces movement, discovery, construction and passive schedules")
	var ids: Dictionary = {}
	var completed := 0
	for event in seen:
		ids[event.id] = true
		if event.type == "construction_completed": completed += 1
	_check(ids.size() == seen.size() and completed == 1, "construction confirmations appear exactly once after rollback")
	var unsafe = Rollback.new()
	unsafe.initialize(definitions, _players(), 42, 9)
	_check(not unsafe.queue({"kind": "build", "actors": [7], "definition": "chyme_pool", "point": [0, 0]}), "malformed build point rejected")
	_check(not unsafe.queue({"kind": "build", "actors": [7], "definition": "missing", "point": [0, 0, 0]}), "unknown network build definition rejected")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
