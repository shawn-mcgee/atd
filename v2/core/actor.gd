class_name ATDActor
extends RefCounted
## Typed live actor. Only the explicit dictionary representation enters checkpoints.
const Capabilities = preload("res://core/actor_capabilities.gd")
var id: int = 0
var owner: int = 0
var definition: String = ""
var position: Array = [0, 0, 0]
var rotation: int = 0
var hp: int = 0
var order: Dictionary = {}
var construction: Dictionary = {}
var veil_networks: Array = []
var veil_stance: Dictionary = {"mode": "neutral", "network": 0, "order": 0, "target": [], "expires": 0}
var rally_point: Array = []
var motion := Capabilities.Motion.new()
var combat := Capabilities.Combat.new()
var production_state := Capabilities.Production.new()
var cargo := Capabilities.Cargo.new()
var _capabilities: Dictionary = {}

var velocity: Array:
	get: return motion.velocity
	set(value): motion.velocity = value
var facing: Array:
	get: return motion.facing
	set(value): motion.facing = value
var navigation: Dictionary:
	get: return motion.navigation
	set(value): motion.navigation = value
var avoidance: Dictionary:
	get: return motion.avoidance
	set(value): motion.avoidance = value
var ready_tick: int:
	get: return combat.ready_tick
	set(value): combat.ready_tick = value
var production: Array:
	get: return production_state.queue
	set(value): production_state.queue = value
var spawn_source: int:
	get: return production_state.spawn_source
	set(value): production_state.spawn_source = value
var passive_started_tick: int:
	get: return production_state.passive_started_tick
	set(value): production_state.passive_started_tick = value
var passive_remaining: int:
	get: return production_state.passive_remaining
	set(value): production_state.passive_remaining = value
var chyme: int:
	get: return cargo.chyme
	set(value): cargo.chyme = value
var nacre: int:
	get: return cargo.nacre
	set(value): cargo.nacre = value
var next_chyme_tick: int:
	get: return cargo.next_chyme_tick
	set(value): cargo.next_chyme_tick = value
var mining_ready_tick: int:
	get: return cargo.mining_ready_tick
	set(value): cargo.mining_ready_tick = value

func compose(data: Dictionary) -> void:
	_capabilities = data.capabilities
	motion.enabled = _capabilities.has("move")
	combat.enabled = _capabilities.has("weapon")
	production_state.enabled = _capabilities.has("factory") or _capabilities.has("passive_spawner")
	cargo.enabled = _capabilities.has("chyme_collector") or _capabilities.has("chyme_source") or _capabilities.has("mission_worker")

func has_capability(kind: String) -> bool:
	return _capabilities.has(kind)

func to_dict() -> Dictionary:
	return {"id": id, "owner": owner, "definition": definition, "position": position,
		"rotation": rotation, "hp": hp, "order": order, "navigation": motion.navigation,
		"velocity": motion.velocity, "avoidance": motion.avoidance, "facing": motion.facing,
		"ready_tick": combat.ready_tick, "production": production_state.queue, "construction": construction,
		"veil_networks": veil_networks, "veil_stance": veil_stance, "rally_point": rally_point,
		"spawn_source": production_state.spawn_source, "passive_started_tick": production_state.passive_started_tick,
		"passive_remaining": production_state.passive_remaining, "chyme": cargo.chyme, "next_chyme_tick": cargo.next_chyme_tick,
		"nacre": cargo.nacre, "mining_ready_tick": cargo.mining_ready_tick}

static func from_dict(data: Dictionary) -> ATDActor:
	var actor := ATDActor.new()
	for key in data: actor.set(key, data[key])
	return actor

func duplicate(deep: bool = true) -> ATDActor:
	var actor := from_dict(to_dict().duplicate(deep))
	if not _capabilities.is_empty(): actor.compose({"capabilities": _capabilities})
	return actor
