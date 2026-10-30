extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
## Internal currency keys stay stable; UI names are Materials and Methane.
static var STRUCTURES: Dictionary = Config.data.get("structures", {})
static var TURRETS: Dictionary = Config.data.get("turrets", {})
static var UNITS: Dictionary = Config.data.get("units", {})
static var PREDATORS: Dictionary = Config.data.get("predators", {})

static var PRODUCTION: Dictionary = Config.data.get("production", {})

static func cost(kind: String) -> Dictionary:
	var data: Dictionary = STRUCTURES[kind] if STRUCTURES.has(kind) else UNITS[kind]
	return {"minerals": int(data.minerals), "gas": int(data.gas)}

static func title(kind: String) -> String:
	return STRUCTURES[kind].name if STRUCTURES.has(kind) else UNITS[kind].name
