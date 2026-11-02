extends RefCounted
## JSON is configuration, not executable code. All errors include a field path.
const Canonical = preload("res://core/canonical.gd")
const ConfigFiles = preload("res://authoring/config_files.gd")
const CAPABILITIES := ["move", "weapon", "perception", "illumination", "detection", "factory", "veil_source", "chyme_collector", "chyme_receiver", "chyme_source", "metamorphosis", "mission_worker", "extraction_point"]
var data: Dictionary = {}
var errors: Array[String] = []

func load_file(path: String) -> bool:
	var project = ConfigFiles.new()
	if not project.open_file(path): errors.assign(project.errors); return false
	return load_project(project)

func load_project(project) -> bool:
	if not project.compile(): errors.assign(project.errors); return false
	if load_text(Canonical.text(project.data)): return true
	for index in errors.size(): errors[index] = project.relative_path(project.error_file(errors[index])) + ": " + errors[index]
	return false

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
	if candidate.has("imports"):
		errors.append("imports: load this project with load_file/load_project before validating merged content")
		return false
	if candidate.get("version") != 1:
		errors.append("version: expected 1")
	var settings = candidate.get("settings", {})
	if not settings is Dictionary:
		errors.append("settings: expected an object")
		return false
	for spec in [["tick_hz", 10, 60], ["map_radius", 8, 32], ["rollback_ticks", 16, 240], ["input_delay", 0, 6], ["minimum_damage", 0, 100]]:
		_number(settings, spec[0], spec[1], spec[2], "settings", true)
	if settings.has("mission"):
		if not settings.mission is Dictionary:
			errors.append("settings.mission: expected an object")
		else:
			if not settings.mission.get("enabled") is bool: errors.append("settings.mission.enabled: expected a boolean")
			for spec in [["nacre_amount", 1, 100000], ["threshold", 1, 100000], ["repair_ticks", 1, 10000], ["countdown_ticks", 1, 10000]]: _number(settings.mission, spec[0], spec[1], spec[2], "settings.mission", true)
	if settings.has("nest_loss"):
		if not settings.nest_loss is Dictionary:
			errors.append("settings.nest_loss: expected an object")
		else:
			_number(settings.nest_loss, "chyme_grant", 0, 1000000, "settings.nest_loss", true)
			for key in ["production_rate", "construction_rate"]: _number(settings.nest_loss, key, 1, 8, "settings.nest_loss", true)
			if not settings.nest_loss.get("affect_new_structures") is bool:
				errors.append("settings.nest_loss.affect_new_structures: expected a boolean")
	if settings.has("chyme"):
		if not settings.chyme is Dictionary:
			errors.append("settings.chyme: expected an object")
		else:
			_number(settings.chyme, "initial_reserve", 0, 1000000, "settings.chyme", true)
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
		if not visual is Dictionary:
			errors.append(path + ".visual: expected an object")
		else:
			if not visual.get("shape") in ["capsule", "cylinder"]:
				errors.append(path + ".visual.shape: expected capsule or cylinder")
			if not visual.get("color") is String or not Color.html_is_valid(visual.get("color", "")):
				errors.append(path + ".visual.color: expected a hexadecimal color")
			_number(visual, "radius", 0.05, 4, path + ".visual")
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
				"mission_worker":
					if definition.get("faction") != "human" or not caps.has("move"): errors.append(cap_path + ": requires a mobile Human worker")
					for spec in [["capacity", 1, 10000], ["mining_amount", 1, 10000], ["mining_interval_ticks", 1, 10000]]: _number(caps[cap], spec[0], spec[1], spec[2], cap_path, true)
					_number(caps[cap], "work_range", 0.1, 4, cap_path)
				"extraction_point":
					if definition.get("faction") != "human" or caps.has("move"): errors.append(cap_path + ": requires a stationary Human extraction point")
				"metamorphosis":
					if definition.get("faction") != "lightless" or not caps.has("move") or caps.has("chyme_collector") or caps.has("factory"):
						errors.append(cap_path + ": requires a mobile Lightless builder without cargo or factory")
					_metamorphosis(caps[cap], definitions, cap_path)
				"chyme_collector", "chyme_receiver", "chyme_source":
					if definition.get("faction") != "lightless":
						errors.append(cap_path + ": requires Lightless faction")
					if cap == "chyme_collector":
						_number(caps[cap], "capacity", 1, 10000, cap_path, true)
						_number(caps[cap], "yield_per_damage", 1, 100, cap_path, true)
						if not caps.has("move") or not caps.has("weapon"):
							errors.append(cap_path + ": requires move and weapon capabilities")
					else:
						if caps.has("move"):
							errors.append(cap_path + ": requires a stationary Lightless structure")
						if cap == "chyme_receiver":
							_number(caps[cap], "radius", 0.1, 4, cap_path)
						else:
							_number(caps[cap], "amount", 1, 10000, cap_path, true)
							_number(caps[cap], "interval_ticks", 1, 3600, cap_path, true)
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
							elif product == "nest": errors.append(cap_path + ".produces: the Nest cannot be rebuilt")
							elif definitions[product].get("capabilities", {}) is Dictionary and definitions[product].get("capabilities", {}).has("extraction_point"): errors.append(cap_path + ".produces: mission extraction points cannot be rebuilt")
	for required in ["hq", "nest", "engineer", "marine", "scavenger"]:
		if not definitions.has(required):
			errors.append("units: missing starting definition " + required)
		elif definitions[required] is Dictionary:
			var expected := "lightless" if required in ["nest", "scavenger"] else "human"
			if definitions[required].get("faction") != expected:
				errors.append("units." + required + ".faction: starting definition must be " + expected)
	if settings.get("mission") is Dictionary:
		var mission: Dictionary = settings.mission
		if (mission.get("threshold") is int or mission.get("threshold") is float) and (mission.get("nacre_amount") is int or mission.get("nacre_amount") is float) and mission.threshold > mission.nacre_amount:
			errors.append("settings.mission.threshold: cannot exceed available nacre_amount")
		var id = settings.mission.get("extraction_definition")
		if not id is String or not definitions.get(id) is Dictionary or not definitions[id].get("capabilities") is Dictionary or not definitions[id].capabilities.has("extraction_point"):
			errors.append("settings.mission.extraction_definition: expected an extraction_point definition")
	if not errors.is_empty():
		return false
	data = Canonical.normalize(candidate)
	return true

func _metamorphosis(cap: Dictionary, definitions: Dictionary, path: String) -> void:
	var womb = cap.get("womb")
	if not womb is String or not definitions.get(womb) is Dictionary:
		errors.append(path + ".womb: expected an existing definition ID")
	else:
		var definition: Dictionary = definitions[womb]
		if womb == "nest" or definition.get("faction") != "lightless" or not definition.get("capabilities") is Dictionary or not definition.get("capabilities", {}).is_empty():
			errors.append(path + ".womb: requires a Lightless definition with no active capabilities")
	var structures = cap.get("structures")
	if not structures is Array or structures.is_empty() or structures.size() > 16:
		errors.append(path + ".structures: expected 1–16 structure IDs")
		return
	for type in structures:
		if not type is String or not definitions.get(type) is Dictionary:
			errors.append(path + ".structures: missing definition " + str(type))
			continue
		var definition: Dictionary = definitions[type]
		var caps = definition.get("capabilities")
		if type == "nest" or type == womb or definition.get("faction") != "lightless" or not caps is Dictionary or caps.has("move"):
			errors.append(path + ".structures: requires stationary Lightless structures other than Nest/Womb")
		_number(definition, "construction_ticks", 1, 10000, "units." + type, true)

func _number(object: Dictionary, key: String, low: float, high: float, path: String, integral: bool = false) -> void:
	var value = object.get(key)
	if not (value is int or value is float) or not is_finite(float(value)):
		errors.append(path + "." + key + ": expected a finite number")
	elif value < low or value > high or (integral and value != floor(value)):
		errors.append(path + "." + key + ": expected %s in [%s, %s]" % ["integer" if integral else "number", low, high])

func fingerprint() -> String:
	return Canonical.hash_of(data)
