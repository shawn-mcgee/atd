extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Hex = preload("res://core/hex_cells.gd")
const Construction = preload("res://core/construction.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
var checks := 0
var failures: Array[String] = []

func _definitions() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var data: Dictionary = content.data.duplicate(true)
	data.settings.mission.enabled = false
	data.settings.input_delay = 0
	data.units.turret.construction_ticks = 4
	return data

func _players() -> Array:
	return [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]

func _game():
	var game = Sim.new()
	game.initialize(_definitions(), _players(), 42)
	return game

func _build() -> Dictionary:
	return {"kind": "build", "player": 1, "actors": [2], "definition": "turret", "point": Hex.point([-6, 2])}

func run() -> Dictionary:
	var content = Content.new()
	_check(content.load_text(Canonical.text(_definitions())), "builder content validates")
	for structures in [[], ["missing"], ["hq"], ["engineer"], ["extraction_point"], ["human_blueprint"], ["nest"]]:
		var data := _definitions()
		data.units.engineer.capabilities.builder.structures = structures
		_check(not content.load_text(Canonical.text(data)) and "capabilities.builder" in " ".join(content.errors), "invalid build catalog rejected with field path")
	var invalid := _definitions()
	invalid.units.human_blueprint.capabilities.perception = {"radius": 2}
	_check(not content.load_text(Canonical.text(invalid)), "blueprint must have no active capabilities")
	invalid = _definitions()
	invalid.units.turret.erase("construction_ticks")
	_check(not content.load_text(Canonical.text(invalid)), "build time required")
	var game = _game()
	_check(not Construction.site_error(game, game.entity(2), "turret", Hex.point([0, 0])).is_empty(), "unrevealed placement rejected")
	var foreign := _build(); foreign.player = 9
	game.step([foreign])
	_check(int(game.state.banks["1"]) == 100 and game.entity(7) == null, "foreign builder cannot spend")
	game.step([_build()])
	_check(int(game.state.banks["1"]) == 65 and game.entity(7).definition == "human_blueprint" and game.entity(2).definition == "engineer", "placement pays immediately and preserves engineer")
	game.step([_build()])
	_check(int(game.state.banks["1"]) == 65 and game.entity(8) == null, "blueprint reserves tile without duplicate spending")
	game.step([{"kind": "stop", "player": 1, "actors": [2]}])
	var remaining := int(game.entity(7).construction.remaining)
	for tick in 10: game.step([])
	_check(int(game.entity(7).construction.remaining) == remaining and game.entity(7).order.is_empty(), "unassigned blueprint supplies neither work nor combat")
	game.step([{"kind": "construct", "player": 9, "actors": [5], "target": 7}])
	_check(int(game.entity(7).construction.worker) == 2, "foreign workers cannot resume blueprint")
	game.step([{"kind": "construct", "player": 1, "actors": [2], "target": 7}])
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	for tick in 80: game.step([])
	_check(game.entity(7).definition == "turret" and game.entity(7).construction.is_empty() and game.entity(2).order.is_empty(), "engineer travels, works and completes turret")
	var expected: String = game.state_hash()
	game.restore(saved)
	for tick in 80: game.step([])
	_check(game.state_hash() == expected, "JSON restore reproduces travel and completion")
	game = _game()
	game.step([_build()])
	game.entity(7).hp = 20
	game.step([{"kind": "cancel_build", "player": 9, "actors": [7]}])
	_check(game.entity(7) != null and int(game.state.banks["1"]) == 65, "foreign cancellation rejected")
	game.step([{"kind": "cancel_build", "player": 1, "actors": [2, 7]}])
	_check(game.entity(7) == null and int(game.state.banks["1"]) == 100 and game.entity(2).order.is_empty(), "worker plus blueprint cancellation refunds damaged site exactly once")
	game.step([_build()])
	game.entity(2).hp = 0
	game.step([])
	_check(game.entity(8) != null and int(game.state.banks["1"]) == 65, "builder loss preserves investment for reassignment")
	game._spawn("engineer", 1, Hex.point([-6, 3]))
	game.step([{"kind": "construct", "player": 1, "actors": [9], "target": 8}])
	for tick in 6: game.step([])
	_check(game.entity(8).definition == "turret", "replacement engineer resumes construction")
	game = _game()
	game.entity(2).position = Hex.point([-6, 3])
	game.step([_build()])
	game.entity(7).hp = 40
	game.entity(3).position = Hex.point([-6, 2])
	for tick in 6: game.step([])
	_check(game.entity(7).definition == "human_blueprint" and game.entity(7).construction.get("blocked", false), "completion waits for site occupants")
	game.entity(3).position = Hex.point([-5, 2])
	game.step([])
	_check(game.entity(7).definition == "turret" and int(game.entity(7).hp) == 75, "completion preserves blueprint damage fraction")
	game.entity(5).position = Hex.point([-3, 2])
	game.entity(3).position = Hex.point([-10, 0])
	game.entity(2).position = Hex.point([-10, 1])
	var enemy_hp := int(game.entity(5).hp)
	for tick in 12: game.step([])
	_check(int(game.entity(5).hp) < enemy_hp, "completed turret automatically attacks visible enemy")
	game = _game()
	game._spawn("engineer", 1, Hex.point([-6, 3]))
	game.step([_build(), {"kind": "construct", "player": 1, "actors": [7], "target": 8}, {"kind": "cancel_build", "player": 1, "actors": [2]}])
	_check(game.entity(8) != null and int(game.entity(8).construction.worker) == 7 and int(game.state.banks["1"]) == 65, "reassignment prevents stale worker cancellation")
	game = _game()
	game.state.banks["1"] = 0
	game.step([_build()])
	_check(game.entity(7) == null, "insufficient reserves reject placement")
	game.state.banks["1"] = 100
	game.step([_build()])
	game.entity(7).hp = 0
	game.step([])
	_check(int(game.state.banks["1"]) == 65 and game.entity(2).order.is_empty(), "destroyed blueprint loses cost and clears worker")
	var hash_value := _rollback()
	return {"checks": checks, "failures": failures, "hash": hash_value}

func _rollback() -> String:
	var a = Rollback.new(); var b = Rollback.new()
	a.initialize(_definitions(), _players(), 42, 0)
	b.initialize(_definitions(), _players(), 42, 0)
	var build := _build(); build.erase("player")
	var seen: Array = []
	b.events_confirmed.connect(func(events):
		for event in events:
			if event.type.begins_with("construction_"): seen.append(event))
	for tick in 85:
		for player in [1, 9]:
			var commands: Array = [build] if tick == 0 and player == 1 else []
			_check(a.receive(player, tick, commands), "reference accepts frame")
			if tick != 0 or player != 1: _check(b.receive(player, tick, commands), "peer accepts frame")
	for tick in 12: a.advance(); b.advance()
	_check(b.receive(1, 0, [build]) and b.rollbacks == 1, "late blueprint triggers rollback")
	for tick in 73: a.advance(); b.advance()
	_check(a.simulation.state_hash() == b.simulation.state_hash() and b.simulation.entity(7).definition == "turret", "late construction matches reference")
	var ids: Dictionary = {}
	var completed := 0
	for event in seen:
		ids[event.id] = true
		if event.type == "construction_completed": completed += 1
	_check(ids.size() == seen.size() and completed == 1, "construction events confirmed once")
	return b.simulation.state_hash()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
