extends RefCounted
const Content = preload("res://core/content.gd")
const Sim = preload("res://core/simulation.gd")
const Canonical = preload("res://core/canonical.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var definitions: Dictionary = content.data.duplicate(true)
	definitions.settings.mission.enabled = false
	for shape in ["box", "rectangle", "square", "prism", "sphere"]:
		var invalid: Dictionary = definitions.duplicate(true)
		invalid.units.engineer.visual.shape = shape
		_check(not content.load_text(Canonical.text(invalid)) and "units.engineer.visual.shape" in " ".join(content.errors), "unsupported shapes are rejected with a useful field path")
	for radius in [0, -1, 4.1, "large", null]:
		var invalid: Dictionary = definitions.duplicate(true)
		invalid.units.engineer.visual.radius = radius
		_check(not content.load_text(Canonical.text(invalid)) and "units.engineer.visual.radius" in " ".join(content.errors), "invalid visual radius is rejected")
	var missing: Dictionary = definitions.duplicate(true)
	missing.units.engineer.visual.erase("radius")
	_check(not content.load_text(Canonical.text(missing)), "visual radius is required")
	for shape in ["capsule", "cylinder"]:
		for radius in [0.05, 4]:
			var valid: Dictionary = definitions.duplicate(true)
			valid.units.engineer.visual = {"shape": shape, "radius": radius, "color": "ffffff"}
			_check(content.load_text(Canonical.text(valid)), "both shapes accept supported radius bounds")
	var players := [{"id": 1, "faction": "human", "controller": "human"}, {"id": 9, "faction": "lightless", "controller": "human"}]
	var game = Sim.new()
	game.initialize(definitions, players, 42)
	_check(game.entity(2).facing == Vector3i(0, 0, -Sim.SCALE), "actors start facing the negative-r hex direction")
	var point := [int(game.entity(2).position[0]) + 1024, 0, int(game.entity(2).position[2]) + 1024]
	game.step([{"player": 1, "kind": "move", "actors": [2], "point": point}])
	_check(game.entity(2).facing == Vector3i(1024, 0, 1024), "movement records an integer axial facing")
	var saved: Dictionary = Canonical.normalize(JSON.parse_string(Canonical.text(game.checkpoint())))
	for tick in 40: game.step([])
	var idle: Vector3i = game.entity(2).facing
	var expected: String = game.state_hash()
	game.restore(saved)
	for tick in 40: game.step([])
	_check(game.state_hash() == expected, "JSON checkpoint replay reproduces facing after movement and arrival")
	game.step([{"player": 1, "kind": "stop", "actors": [2]}])
	game.step([{"player": 1, "kind": "move", "actors": [2], "point": game.entity(2).position.duplicate()}])
	_check(game.entity(2).facing == idle, "stopping and zero-length movement preserve a valid orientation")
	var turret: Dictionary = definitions.duplicate(true)
	turret.units.marine.capabilities.erase("move")
	turret.units.marine.capabilities.weapon.range = 24
	turret.units.marine.capabilities.perception.radius = 24
	game.initialize(turret, players, 42)
	var position: Array = game.entity(3).position.duplicate()
	game.entity(3).ready_tick = 100
	game.step([{"player": 1, "kind": "attack", "actors": [3], "target": 4}])
	_check(game.entity(3).position == position and int(game.entity(3).facing[0]) > 0, "stationary weapons turn toward a visible target even during cooldown")
	game.initialize(definitions, players, 42)
	game.entity(5).position = [7 * Sim.SCALE, 0, 0]
	game.entity(5).chyme = 2
	game.step([{"player": 9, "kind": "deliver_chyme", "actors": [5], "target": 4}])
	_check(game.entity(5).facing == Vector3i(Sim.SCALE, 0, 0), "delivery faces its receiver without requiring movement")
	var larger: Dictionary = definitions.duplicate(true)
	larger.units.engineer.visual = {"shape": "cylinder", "radius": 3, "color": "eac45e"}
	var twin = Sim.new()
	game.initialize(definitions, players, 42)
	twin.initialize(larger, players, 42)
	for tick in 10:
		var commands := [{"player": 1, "kind": "move", "actors": [2], "point": point}] if tick == 0 else []
		game.step(commands); twin.step(commands)
	_check(game.state.actors == twin.state.actors and game.state.banks == twin.state.banks, "changing shape and radius does not change gameplay")
	return {"checks": checks, "failures": failures, "hash": game.state_hash()}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
