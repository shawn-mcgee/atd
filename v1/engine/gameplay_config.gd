extends RefCounted
## Read once at startup; restart to apply edits. No runtime/global RNG state.
const PATH := "res://config/gameplay.json"
static var error_message := ""
static var data: Dictionary = read_config()
static func read_config() -> Dictionary:
	var json := JSON.new()
	var code := json.parse(FileAccess.get_file_as_string(PATH))
	if code != OK or not json.data is Dictionary:
		error_message = "Invalid gameplay.json: " + json.get_error_message()
		return {}
	var result: Dictionary = json.data
	for section in ["structures", "units", "predators", "turrets", "production", "power", "simulation", "world", "lighting", "resources", "economy", "vehicles", "mission", "predators_ai", "maintenance", "exploration", "patrol", "scouting", "tactics"]:
		if not result.get(section) is Dictionary:
			error_message = "Missing gameplay.json section: " + section; return {}
	if not valid_values(result):
		error_message = "gameplay.json contains a negative or non-finite number."; return {}
	for entry in [["simulation", "tick"], ["simulation", "harvest_seconds"], ["world", "level"], ["world", "reference_radius"], ["resources", "reach"], ["vehicles", "drill_seconds"]]:
		if float(result[entry[0]].get(entry[1], 0)) <= 0:
			error_message = "gameplay.json requires a positive " + entry[1]; return {}
	if float(result.world.get("map_radius", 0)) < 8 or float(result.world.map_radius) > 256:
		error_message = "gameplay.json map_radius must be between 8 and 256."; return {}
	if float(result.world.ridge_steps_min) > float(result.world.ridge_steps_max) or result.world.field_yields.size() != 6:
		error_message = "gameplay.json requires ordered ridge lengths and six field yields."; return {}
	return result
static func valid_values(value) -> bool:
	if value is Dictionary:
		for item in value.values():
			if not valid_values(item): return false
	elif value is Array:
		for item in value:
			if not valid_values(item): return false
	elif value is float or value is int: return is_finite(value) and value >= 0
	return true
static func value(section: String, key: String) -> float:
	return float(data.get(section, {}).get(key, 0))
