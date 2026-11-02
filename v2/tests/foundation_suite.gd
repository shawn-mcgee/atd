extends RefCounted
const Content = preload("res://core/content.gd")
const Rules = preload("res://core/match_rules.gd")
const Sim = preload("res://core/simulation.gd")
const Rollback = preload("res://net/rollback_session.gd")
const Canonical = preload("res://core/canonical.gd")
const VeilSuite = preload("res://tests/veil_suite.gd")
var failures: Array[String] = []
var checks := 0

func run() -> Dictionary:
	var content = Content.new()
	_check(content.load_text(FileAccess.get_file_as_string("res://content/default.json")), "default content validates")
	var invalid: Dictionary = content.data.duplicate(true)
	invalid.units.marine.capabilities.weapon.range = -1
	var bad = Content.new()
	_check(not bad.load_text(Canonical.text(invalid)) and "units.marine.capabilities.weapon.range" in " ".join(bad.errors), "invalid fields produce useful paths")
	invalid = content.data.duplicate(true)
	invalid.units.marine.capabilities.script = {}
	_check(not bad.load_text(Canonical.text(invalid)), "unknown capabilities rejected")
	var fallback := Rules.participants([{"id": 1, "faction": "lightless", "controller": "human"}])
	_check(fallback.size() == 2 and fallback[1].faction == "human" and fallback[1].controller == "ai", "AI supplies missing Human faction")
	_check(Rules.participants([{"id": 1, "faction": "lightless", "controller": "human"}, {"id": 2, "faction": "lightless", "controller": "ai"}]).is_empty(), "only one Lightless participant")
	var players := Rules.participants([{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}])
	var sim = Sim.new()
	sim.initialize(content.data, players, 42)
	var initial := sim.state_hash()
	sim.step([{"player": 9, "kind": "train", "actors": [1], "definition": "marine"}])
	_check(int(sim.state.banks["1"]) == 100 and sim.entity(1).production.is_empty(), "foreign ownership cannot train")
	sim.step([{"player": 1, "kind": "train", "actors": [1], "definition": "marine"}])
	_check(int(sim.state.banks["1"]) == 80, "production costs paid exactly once")
	var checkpoint := sim.checkpoint()
	var roundtrip: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(checkpoint)))
	for tick in 120: sim.step([])
	var expected := sim.state_hash()
	_check(sim.state.actors.size() == 7, "production creates a new actor")
	sim.restore(roundtrip)
	for tick in 120: sim.step([])
	_check(sim.state_hash() == expected, "JSON checkpoint restore reproduces production and RNG")
	checkpoint.actors[0].hp = 1
	_check(int(sim.entity(1).hp) == 300, "checkpoint is isolated from live state")
	var twin = Sim.new()
	twin.initialize(content.data, players, 42)
	_check(twin.state_hash() == initial, "seeded initial states match")
	var small: Dictionary = content.data.duplicate(true)
	small.settings.map_radius = 8
	twin.initialize(small, players, 42)
	for actor in twin.state.actors:
		_check(twin.valid_point(actor.position), "starting actors fit the smallest configured map")
	var authored: Dictionary = content.data.duplicate(true)
	authored.units.sentry = authored.units.marine.duplicate(true)
	authored.units.sentry.name = "Sentry"
	authored.units.sentry.capabilities.erase("move")
	authored.units.sentry.capabilities.weapon.turret = true
	authored.units.hq.capabilities.factory.produces.append("sentry")
	_check(bad.load_text(Canonical.text(authored)), "new unit composes existing capabilities without code")
	twin.initialize(bad.data, players, 42)
	twin.step([{"player": 1, "kind": "train", "actors": [1], "definition": "sentry"}])
	for tick in int(authored.units.sentry.production_ticks): twin.step([])
	_check(twin.state.actors.any(func(actor): return actor.definition == "sentry"), "authored unit can be produced")
	var detector: Dictionary = content.data.duplicate(true)
	detector.units.marine.capabilities.weapon.range = 24
	detector.units.marine.capabilities.perception.radius = 0
	detector.units.marine.capabilities.detection = {"radius": 24}
	twin.initialize(detector, players, 42)
	twin.step([{"player": 1, "kind": "attack", "actors": [3], "target": 4}])
	_check(int(twin.entity(4).hp) == 500, "ordinary weapon cannot attack detection-only contact")
	detector.units.marine.capabilities.weapon.turret = true
	twin.initialize(detector, players, 42)
	twin.step([{"player": 1, "kind": "attack", "actors": [3], "target": 4}])
	_check(int(twin.entity(4).hp) == 495, "turret can attack detection-only contact")
	# Two independently advancing peers; one receives a nonempty frame eight ticks late.
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.units.marine.capabilities.weapon.range = 24
	definitions.units.marine.capabilities.weapon.interval_ticks = 2
	definitions.units.marine.capabilities.perception.radius = 24
	var a = Rollback.new()
	var b = Rollback.new()
	a.initialize(definitions, players, 42, 0)
	b.initialize(definitions, players, 42, 0)
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events: seen.append(event.id))
	var delayed := [{"kind": "move", "actors": [5], "point": [6 * Sim.SCALE, 0, 2 * Sim.SCALE]}]
	for tick in 50:
		for player in [1, 9]:
			var commands: Array = []
			if tick == 2 and player == 9: commands = delayed
			if tick == 3 and player == 1: commands = [{"kind": "attack", "actors": [3], "target": 4}]
			_check(a.receive(player, tick, commands), "reference frame accepted")
			if not (tick == 2 and player == 9): _check(b.receive(player, tick, commands), "delayed peer frame accepted")
	for tick in 10:
		_check(a.advance() and b.advance(), "peers advance before correction")
	_check(b.receive(9, 2, delayed), "late input accepted")
	_check(b.rollbacks == 1 and b.replayed_ticks == 8, "late command restores and replays only affected history")
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "rollback corrects divergent speculative state")
	for tick in 40: _check(a.advance() and b.advance(), "peers advance after correction")
	_check(a.simulation.state_hash() == b.simulation.state_hash(), "corrected peers remain identical")
	var unique: Dictionary = {}
	for id in seen: unique[id] = true
	_check(not seen.is_empty() and unique.size() == seen.size(), "confirmed effects are not duplicated during rollback")
	_check(b.confirmed_tick == 49, "all received frames become confirmed")
	_check(not b.receive(9, 3, [{"kind": "stop", "actors": [5]}]), "conflicting sealed input rejected")
	var stalled = Rollback.new()
	stalled.initialize(content.data, players, 42, 1)
	for tick in 150: stalled.advance()
	_check(int(stalled.simulation.state.tick) <= stalled.window + 2, "missing peer stalls before rollback history is lost")
	var unsafe = Rollback.new()
	unsafe.initialize(content.data, players, 42, 1)
	_check(not unsafe.queue({"kind": "move", "actors": [2], "point": [999999999999, 0, 0]}), "out-of-world movement rejected")
	var veil: Dictionary = VeilSuite.new().run()
	checks += int(veil.checks)
	for failure in veil.failures: failures.append("Veil: " + str(failure))
	return {"ok": failures.is_empty(), "checks": checks, "failures": failures, "deterministic_hash": Canonical.hash_of([a.simulation.state_hash(), veil.hash])}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
