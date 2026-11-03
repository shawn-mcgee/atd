extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Spawning = preload("res://core/spawning.gd")
const Hex = preload("res://core/hex_cells.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	_validation()
	_timing_and_caps()
	_blocking()
	_paid_and_escalation()
	_construction()
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _definitions(interval: int = 3, limit: int = 2, radius: int = 1) -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission.enabled = false
	definitions.units.nest.collision_radius = 0.4
	definitions.units.nest.footprint = [[0, 0]] # Isolate single-tile source timing fixtures.
	definitions.settings.nest_loss.chyme_grant = 0
	# Isolate birth RNG assertions from seeded Veil growth.
	for definition in definitions.units.values():
		for cap in ["passive_spawner", "veil_source"]: definition.capabilities.erase(cap)
	definitions.units.nest.capabilities.erase("chyme_source")
	definitions.units.nest.capabilities.passive_spawner = {"definition": "scavenger", "interval_ticks": interval, "max_alive": limit, "spawn_radius": radius}
	return definitions

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game(interval: int = 3, limit: int = 2, radius: int = 1):
	var game = Sim.new()
	game.initialize(_definitions(interval, limit, radius), _players(), 42)
	return game

func _step(game, count: int) -> void:
	for tick in count: game.step([])

func _validation() -> void:
	var content = Content.new()
	for entry in [["interval_ticks", 0], ["interval_ticks", 1.5], ["max_alive", 0], ["max_alive", 65], ["spawn_radius", 0], ["spawn_radius", 5], ["definition", "missing"], ["definition", "marine"], ["definition", "nest"]]:
		var definitions := _definitions()
		definitions.units.nest.capabilities.passive_spawner[entry[0]] = entry[1]
		_check(not content.load_text(Canonical.text(definitions)) and ("units.nest.capabilities.passive_spawner." + str(entry[0])) in " ".join(content.errors), "invalid passive parameters identify their field")
	var definitions := _definitions()
	definitions.units.scavenger.capabilities.passive_spawner = definitions.units.nest.capabilities.passive_spawner.duplicate(true)
	_check(not content.load_text(Canonical.text(definitions)), "mobile passive sources are rejected")
	definitions = _definitions()
	definitions.units.hq.capabilities.passive_spawner = definitions.units.nest.capabilities.passive_spawner.duplicate(true)
	_check(not content.load_text(Canonical.text(definitions)), "Human passive sources are rejected")
	definitions = _definitions()
	definitions.units.nest.capabilities.erase("passive_spawner")
	_check(content.load_text(Canonical.text(definitions)), "presets can omit passive spawning")

func _timing_and_caps() -> void:
	var game = _game()
	_step(game, 3)
	_check(Spawning.alive_count(game, 4) == 0, "first birth waits a full interval")
	game.step([])
	_check(Spawning.alive_count(game, 4) == 1 and int(game.entity(7).spawn_source) == 4 and int(game.entity(7).owner) == 9, "birth records source, faction ownership and unique actor ID")
	_check(game.entity(7).facing != Vector3i.ZERO and game.entity(7).definition == "scavenger", "offspring use their configured definition with a valid outward facing")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	_step(game, 10)
	var expected: String = game.state_hash()
	_check(Spawning.alive_count(game, 4) == 2 and int(game.entity(4).passive_remaining) == 3, "source cap pauses the next birth timer")
	game.restore(saved)
	_step(game, 10)
	_check(game.state_hash() == expected, "JSON restore reproduces births, origin tags, timers and RNG")
	game.entity(7).position = Hex.point([-4, 6])
	var rng := int(game.state.rng)
	_step(game, 10)
	_check(Spawning.alive_count(game, 4) == 2 and int(game.state.rng) == rng, "moving offspring away does not free cap or spend RNG")
	game.entity(7).hp = 0
	game.step([])
	_check(Spawning.alive_count(game, 4) == 1 and int(game.entity(4).passive_remaining) == 2, "casualties resume the paused timer instead of causing an instant replacement")
	_step(game, 2)
	_check(Spawning.alive_count(game, 4) == 2 and int(game.state.banks["9"]) == 100, "replacement birth spends no chyme")
	game.entity(4).hp = 0
	_step(game, 10)
	_check(game.entity(4) == null and Spawning.alive_count(game, 4) == 2, "source death stops spawning without despawning offspring")

func _blocking() -> void:
	var game = _game(1, 1)
	var last: Array = []
	for offset in Hex.NEIGHBORS:
		last = Hex.point([8 + int(offset[0]), int(offset[1])])
		game._spawn("engineer", 1, last)
	var rng := int(game.state.rng)
	_step(game, 5)
	_check(Spawning.alive_count(game, 4) == 0 and int(game.entity(4).passive_remaining) == 0 and int(game.state.rng) == rng, "occupied sites leave source ready without spending RNG")
	game.entity(12).position = Hex.point([-12, 3])
	game._spawn("mother", 9, Hex.point([0, 0]))
	game.entity(13).order = {"kind": "build", "definition": "maw", "point": last, "manual": true}
	game.step([])
	_check(Spawning.alive_count(game, 4) == 0, "reserved construction sites block passive birth")
	game.entity(13).order = {}
	game.step([])
	_check(Spawning.alive_count(game, 4) == 1 and game.entity(14).position == last, "ready source uses a newly freed unreserved tile")
	game = _game(1, 1, 2)
	game.entity(4).position = Hex.point([int(game.content.settings.map_radius), 0])
	_step(game, 2)
	_check(game.valid_point(game.entity(7).position) and Hex.distance(Hex.from_point(game.entity(7).position), Hex.from_point(game.entity(4).position)) == 1, "adjacent spawning remains inside map edges")

func _paid_and_escalation() -> void:
	var definitions := _definitions(1, 5)
	definitions.units.scavenger.production_ticks = 1
	definitions.settings.nest_loss.production_rate = 8
	definitions.units.scavenger_spawner.capabilities.passive_spawner = definitions.units.nest.capabilities.passive_spawner.duplicate(true)
	var game = Sim.new()
	game.initialize(definitions, _players(), 42)
	game._spawn("scavenger_spawner", 9, Hex.point([5, 3]))
	game.entity(4).hp = 0
	game.step([])
	game.step([{"player": 9, "kind": "train", "actors": [7], "definition": "scavenger"}])
	_check(Spawning.alive_count(game, 7) == 5 and game.entity(7).production.is_empty(), "accelerated passive births share a tick with independent paid production")
	_check(int(game.state.banks["9"]) == 90 and int(game.entity(8).spawn_source) == 0, "paid units cost once and do not occupy passive slots")
	definitions = _definitions()
	definitions.units.nest.capabilities.erase("passive_spawner")
	definitions.units.scavenger_spawner.capabilities.passive_spawner = {"definition": "scavenger", "interval_ticks": 8, "max_alive": 1, "spawn_radius": 1}
	game.initialize(definitions, _players(), 42)
	game._spawn("scavenger_spawner", 9, Hex.point([5, 3]))
	game.entity(4).hp = 0
	game.step([])
	_check(int(game.entity(7).passive_remaining) == 8, "death boundary and source creation do not consume work early")
	_step(game, 4)
	_check(Spawning.alive_count(game, 7) == 1, "Nest loss accelerates passive spawn work from the following tick")

func _construction() -> void:
	var definitions := _definitions()
	definitions.units.nest.capabilities.erase("passive_spawner")
	definitions.units.scavenger_spawner.construction_ticks = 1
	definitions.units.scavenger_spawner.capabilities.passive_spawner = {"definition": "scavenger", "interval_ticks": 2, "max_alive": 1, "spawn_radius": 1}
	var game = Sim.new()
	game.initialize(definitions, _players(), 42)
	game._spawn("mother", 9, Hex.point([8, 3]))
	game.step([{"player": 9, "kind": "build", "actors": [7], "definition": "scavenger_spawner", "point": Hex.point([8, 3])}])
	game.step([])
	_check(game.entity(7).definition == "scavenger_spawner" and int(game.entity(7).passive_remaining) == 2, "Womb completion starts a fresh passive interval")
	game.step([])
	_check(Spawning.alive_count(game, 7) == 0, "new structure cannot spawn before its interval")
	game.step([])
	_check(Spawning.alive_count(game, 7) == 1, "new structure starts producing after its full interval")

func _rollback() -> String:
	var definitions := _definitions(1, 1)
	definitions.settings.input_delay = 0
	definitions.units.marine.capabilities.weapon = {"damage": 1000, "range": 24, "interval_ticks": 1}
	definitions.units.marine.capabilities.perception.radius = 24
	var a = Rollback.new()
	var b = Rollback.new()
	a.initialize(definitions, _players(), 42, 0)
	b.initialize(definitions, _players(), 42, 0)
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events:
			if event.type == "passive_spawn": seen.append(event))
	var delayed := [{"kind": "attack", "actors": [3], "target": 7}]
	for tick in 24:
		for player in [1, 9]:
			var commands: Array = delayed if tick == 3 and player == 1 else []
			a.receive(player, tick, commands)
			if not (tick == 3 and player == 1): b.receive(player, tick, commands)
	for tick in 10: a.advance(); b.advance()
	_check(b.receive(1, 3, delayed) and b.rollbacks == 1, "late casualty rolls back passive cap and RNG history")
	for tick in 14: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash() and Spawning.alive_count(b.simulation, 4) == 1, "peers reproduce the replacement offspring and cap after replay")
	_check(seen.size() == 2 and int(seen[0].target) != int(seen[1].target) and b.confirmed_tick == 23, "passive births are confirmed exactly once across rollback")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
