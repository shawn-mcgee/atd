extends RefCounted
## JSON is configuration, not executable code. All errors include a field path.
const Canonical = preload("res://core/canonical.gd")
const CAPABILITIES := ["move", "weapon", "perception", "illumination", "detection", "factory", "veil_source"]
var data: Dictionary = {}
var errors: Array[String] = []

func load_text(source: String) -> bool:
	errors.clear()
	var parser := JSON.new()
	if parser.parse(source) != OK:
		errors.append("JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return false
	if not parser.data is Dictionary:
		errors.append("content: expected an object")
		return false
	var candidate: Dictionary = parser.data
	if candidate.get("version") != 1:
		errors.append("version: expected 1")
	var settings = candidate.get("settings", {})
	if not settings is Dictionary:
		errors.append("settings: expected an object")
		return false
	for spec in [["tick_hz", 10, 60], ["map_radius", 8, 32], ["rollback_ticks", 16, 240], ["input_delay", 0, 6], ["minimum_damage", 0, 100]]:
		_number(settings, spec[0], spec[1], spec[2], "settings", true)
	if settings.has("veil"):
		if not settings.veil is Dictionary:
			errors.append("settings.veil: expected an object")
		else:
			for spec in [["tile_hp", 1, 10000], ["light_damage_per_tick", 1, 1000], ["decay_per_tick", 1, 1000], ["alert_cooldown_ticks", 1, 600], ["memory_ticks", 1, 3600]]:
				_number(settings.veil, spec[0], spec[1], spec[2], "settings.veil", true)
	var definitions = candidate.get("units", {})
	if not definitions is Dictionary or definitions.is_empty() or definitions.size() > 64:
		errors.append("units: expected 1–64 named definitions")
		return false
	for id in definitions:
		var path := "units.%s" % id
		var definition = definitions[id]
		if not definition is Dictionary:
			errors.append(path + ": expected an object")
			continue
		if not definition.get("name") is String or definition.get("name", "").is_empty():
			errors.append(path + ".name: expected a nonempty string")
		elif definition.name.length() > 64:
			errors.append(path + ".name: maximum 64 characters")
		if not definition.get("faction") in ["human", "lightless"]:
			errors.append(path + ".faction: expected human or lightless")
		for spec in [["hp", 1, 10000], ["armor", 0, 1000], ["cost", 0, 10000], ["production_ticks", 1, 10000]]:
			_number(definition, spec[0], spec[1], spec[2], path, true)
		var visual = definition.get("visual", {})
		if not visual is Dictionary or not visual.get("shape") in ["box", "sphere", "capsule", "prism", "cylinder"]:
			errors.append(path + ".visual.shape: expected box, sphere, capsule, prism or cylinder")
		elif not visual.get("color") is String or not Color.html_is_valid(visual.get("color", "")):
			errors.append(path + ".visual.color: expected a hexadecimal color")
		var caps = definition.get("capabilities", {})
		if not caps is Dictionary:
			errors.append(path + ".capabilities: expected an object")
			continue
		for cap in caps:
			var cap_path := path + ".capabilities." + str(cap)
			if not cap in CAPABILITIES or not caps[cap] is Dictionary:
				errors.append(cap_path + ": unknown capability or invalid parameters")
				continue
			match cap:
				"move": _number(caps[cap], "speed", 0.1, 15, cap_path)
				"veil_source":
					_number(caps[cap], "radius", 1, 16, cap_path, true)
					_number(caps[cap], "growth_interval_ticks", 1, 600, cap_path, true)
					_number(caps[cap], "growth_tiles", 1, 64, cap_path, true)
					if definition.get("faction") != "lightless" or caps.has("move"):
						errors.append(cap_path + ": requires a stationary Lightless structure")
				"perception", "illumination", "detection": _number(caps[cap], "radius", 0, 24, cap_path)
				"weapon":
					_number(caps[cap], "damage", 0, 1000, cap_path, true)
					_number(caps[cap], "range", 0.1, 24, cap_path)
					_number(caps[cap], "interval_ticks", 1, 1000, cap_path, true)
					if caps[cap].has("turret") and not caps[cap].turret is bool:
						errors.append(cap_path + ".turret: expected a boolean")
				"factory":
					if not caps[cap].get("produces") is Array:
						errors.append(cap_path + ".produces: expected an array of definition IDs")
					else:
						for product in caps[cap].produces:
							if not product is String or not definitions.has(product) or not definitions[product] is Dictionary or definitions[product].get("faction") != definition.get("faction"):
								errors.append(cap_path + ".produces: missing or wrong-faction definition " + str(product))
	for required in ["hq", "nest", "engineer", "marine", "scavenger"]:
		if not definitions.has(required):
			errors.append("units: missing starting definition " + required)
		elif definitions[required] is Dictionary:
			var expected := "lightless" if required in ["nest", "scavenger"] else "human"
			if definitions[required].get("faction") != expected:
				errors.append("units." + required + ".faction: starting definition must be " + expected)
	if not errors.is_empty():
		return false
	data = Canonical.normalize(candidate)
	return true

func _number(object: Dictionary, key: String, low: float, high: float, path: String, integral: bool = false) -> void:
	var value = object.get(key)
	if not (value is int or value is float) or not is_finite(float(value)):
		errors.append(path + "." + key + ": expected a finite number")
	elif value < low or value > high or (integral and value != floor(value)):
		errors.append(path + "." + key + ": expected %s in [%s, %s]" % ["integer" if integral else "number", low, high])

func fingerprint() -> String:
	return Canonical.hash_of(data)
