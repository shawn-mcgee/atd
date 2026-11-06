extends Node

var data: Dictionary
var network: Dictionary
var gameplay_hash := ""

func _ready() -> void:
	data = ConfigRules.read_json("res://config/prototype.json")
	network = _read("res://config/networking.json")
	var errors := ConfigRules.validate(data)
	if not errors.is_empty():
		for error in errors: push_error("Configuration: " + error)
		get_tree().quit(1); return
	gameplay_hash = ConfigRules.gameplay_hash(data)
	Engine.physics_ticks_per_second = int(data.match.simulationTicksPerSecond)

func _read(path: String) -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(value is Dictionary, "Invalid JSON: " + path)
	return value


class ConfigRules:
	extends RefCounted
	## Configuration boundary shared by the game, headless tests, and authoring tools.
	## Validation returns every error with its JSON path; it never fills in missing tuning.

	static func read_json(path: String) -> Dictionary:
		var parser := JSON.new()
		var error := parser.parse(FileAccess.get_file_as_string(path))
		if error != OK:
			push_error("%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
			return {}
		if not parser.data is Dictionary:
			push_error(path + ": expected an object at the root")
			return {}
		return parser.data

	static func merged(base: Dictionary, patch: Dictionary) -> Dictionary:
		## Objects merge recursively; arrays/scalars replace. Neither argument is mutated.
		var result := base.duplicate(true)
		for key in patch:
			if result.get(key) is Dictionary and patch[key] is Dictionary:
				result[key] = merged(result[key], patch[key])
			elif patch[key] is Dictionary or patch[key] is Array:
				result[key] = patch[key].duplicate(true)
			else:
				result[key] = patch[key]
		return result

	static func gameplay_hash(config: Dictionary) -> String:
		var simulation := config.duplicate(true)
		for section in ["camera", "metadata", "presentation", "controls"]: simulation.erase(section)
		return JSON.stringify(simulation, "", true).sha256_text()

	static func validate(config: Dictionary) -> Array[String]:
		var errors: Array[String] = []
		for section in ["metadata", "features", "match", "map", "economy", "construction", "personnel", "power", "combat", "gloom", "lightless", "units", "structures", "weapons", "movement", "presentation", "camera", "upgrades", "targeting", "controls"]:
			if not config.get(section) is Dictionary: errors.append(section + ": required object is missing")
		if not errors.is_empty(): return errors
		_check_numbers(config, "", errors)
		for path in ["match.simulationTicksPerSecond", "match.extractionSeconds", "map.radiusTiles", "economy.workerCycleSeconds", "construction.engineerHealthPerSecond", "targeting.refreshIntervalTicks"]:
			var value = at_path(config, path)
			if not (value is float or value is int) or float(value) <= 0: errors.append(path + ": must be a positive number")
		if float(config.map.get("anchorEdgeInsetTiles", 0)) >= float(config.map.get("radiusTiles", 0)): errors.append("map.anchorEdgeInsetTiles: must be less than map.radiusTiles")
		if not config.combat.get("minimumDamageMode", "") in ["zero_floor", "minimum_floor"]: errors.append("combat.minimumDamageMode: expected zero_floor or minimum_floor")
		for table in ["units", "structures"]:
			for kind in config[table]:
				var d = config[table][kind]
				var path := "%s.%s" % [table, kind]
				if not d is Dictionary: errors.append(path + ": expected an object"); continue
				for key in ["health", "armor"]:
					if not d.get(key) is float and not d.get(key) is int: errors.append(path + "." + key + ": required number")
				if float(d.get("health", 0)) <= 0: errors.append(path + ".health: must be positive")
				for key in ["weapon", "buriedWeapon"]:
					if d.get(key) != null and not config.weapons.has(d[key]): errors.append(path + "." + key + ": unknown weapon " + str(d[key]))
				if d.has("driverSeats"):
					for key in ["driverSeats", "passengerSeats", "cargoCapacity", "productionSeconds", "cost"]:
						if not d.has(key): errors.append(path + "." + key + ": required for vehicles")
		for kind in config.weapons:
			if not config.weapons[kind] is Dictionary:
				errors.append("weapons.%s: expected an object" % kind); continue
			var d: Dictionary = config.weapons[kind]
			for key in ["damagePerHit", "rangeTiles", "mechanism"]:
				if not d.has(key): errors.append("weapons.%s.%s: required" % [kind, key])
			for key in ["damagePerHit", "rangeTiles"]:
				if not d.get(key) is float and not d.get(key) is int: errors.append("weapons.%s.%s: required number" % [kind, key])
			if not d.get("mechanism", "") in ["unit_target", "cone"]: errors.append("weapons.%s.mechanism: unsupported mechanism" % kind)
			if float(d.get("intervalSeconds", config.combat.get("defaultAttackIntervalSeconds", 0))) <= 0: errors.append("weapons.%s.intervalSeconds: requires a positive interval or combat.defaultAttackIntervalSeconds" % kind)
		if not config.targeting.get("unitRules") is Dictionary:
			errors.append("targeting.unitRules: required object"); return errors
		if float(config.targeting.get("refreshIntervalTicks", 0)) != floorf(float(config.targeting.get("refreshIntervalTicks", 0))): errors.append("targeting.refreshIntervalTicks: must be a whole number")
		if not config.targeting.get("buriedImmuneToArea") is bool: errors.append("targeting.buriedImmuneToArea: required boolean")
		for kind in config.targeting.unitRules:
			if not config.units.has(kind): errors.append("targeting.unitRules.%s: unknown unit" % kind)
			var rules = config.targeting.unitRules[kind]
			if not rules is Dictionary:
				errors.append("targeting.unitRules.%s: expected an object" % kind); continue
			for flag in ["requiresIllumination", "radarInvisible"]:
				if rules.has(flag) and not rules[flag] is bool: errors.append("targeting.unitRules.%s.%s: expected a boolean" % [kind, flag])
		if not config.personnel.get("kits") is Dictionary:
			errors.append("personnel.kits: required object"); return errors
		for kind in config.personnel.kits:
			if not config.personnel.kits[kind] is Dictionary or not config.personnel.kits[kind].get("sources") is Array:
				errors.append("personnel.kits.%s.sources: required array" % kind); continue
			if not config.units.has(kind): errors.append("personnel.kits.%s: unknown specialization" % kind)
			for source in config.personnel.kits[kind].sources:
				if not config.structures.has(source): errors.append("personnel.kits.%s.sources: unknown structure %s" % [kind, source])
		for path in ["presentation.feedback", "presentation.feedback.profiles", "presentation.feedback.weaponProfiles"]:
			if not at_path(config, path) is Dictionary: errors.append(path + ": required object")
		if not errors.is_empty(): return errors
		var feedback: Dictionary = config.presentation.feedback
		for key in ["eventHistoryLimit", "maxTraces", "maxLabels", "maxCatchupTicks", "audioVoiceCount", "maxImpactRings"]:
			var value := float(feedback.get(key, 0))
			if value <= 0 or value != floorf(value): errors.append("presentation.feedback.%s: must be a positive whole number" % key)
		for key in ["hitFlashSeconds", "hitFlashGapSeconds", "healthTrailSeconds", "labelSeconds", "impactRingSeconds", "deathSeconds", "audioMaxDistanceTiles", "audioUnitSizeTiles", "damageNumberGroupSeconds", "shieldSoundIntervalSeconds", "depositSoundIntervalSeconds"]:
			if float(feedback.get(key, 0)) <= 0: errors.append("presentation.feedback.%s: must be positive" % key)
		if not feedback.get("hitFlashesEnabled") is bool: errors.append("presentation.feedback.hitFlashesEnabled: required boolean")
		for name in feedback.profiles:
			var profile = feedback.profiles[name]
			if not profile is Dictionary: errors.append("presentation.feedback.profiles.%s: expected object" % name); continue
			if not profile.get("visual", "") in ["rifle", "heavy", "laser", "flame", "melee"]: errors.append("presentation.feedback.profiles.%s.visual: unsupported style" % name)
			for key in ["traceSeconds", "soundIntervalSeconds"]:
				if float(profile.get(key, 0)) <= 0: errors.append("presentation.feedback.profiles.%s.%s: must be positive" % [name, key])
			for key in ["traceWidthTiles", "recoilTiles", "impactParticles", "gainDb"]:
				if not profile.get(key) is float and not profile.get(key) is int: errors.append("presentation.feedback.profiles.%s.%s: required number" % [name, key])
			var sound := str(profile.get("sound", ""))
			if "/" in sound or ".." in sound or not ResourceLoader.exists("res://assets/audio/%s.wav" % sound): errors.append("presentation.feedback.profiles.%s.sound: missing audio WAV basename" % name)
		for weapon in feedback.weaponProfiles:
			if not config.weapons.has(weapon) or not feedback.profiles.has(feedback.weaponProfiles[weapon]): errors.append("presentation.feedback.weaponProfiles.%s: unknown weapon or profile" % weapon)
		if not feedback.profiles.has("rifle"): errors.append("presentation.feedback.profiles.rifle: required fallback")
		for kind in config.presentation.get("creatureScales", {}):
			var scale_by = config.presentation.creatureScales[kind]
			if not scale_by is Array or scale_by.size() != 3:
				errors.append("presentation.creatureScales.%s: expected three scale values" % kind); continue
			for value in scale_by:
				if not (value is float or value is int) or float(value) <= 0: errors.append("presentation.creatureScales.%s: scales must be positive numbers" % kind)
		if not config.movement.get("routeOrders") is Dictionary: errors.append("movement.routeOrders: required object"); return errors
		for key in ["arrivalRadiusTiles", "escortDistanceTiles", "repathSeconds"]:
			if float(config.movement.routeOrders.get(key, 0)) <= 0: errors.append("movement.routeOrders.%s: must be positive" % key)
		var slots := float(config.movement.routeOrders.get("escortSlotsPerRing", 0))
		if slots < 1 or slots != floorf(slots): errors.append("movement.routeOrders.escortSlotsPerRing: must be a positive whole number")
		var rear_arc := float(config.movement.routeOrders.get("escortRearArcDegrees", -1))
		if rear_arc < 0 or rear_arc > 180: errors.append("movement.routeOrders.escortRearArcDegrees: expected 0 to 180 degrees")
		var controls: Dictionary = config.controls
		for key in ["dragThresholdPixels", "groupDoubleTapSeconds", "selectionPulseSeconds"]:
			if float(controls.get(key, 0)) <= 0: errors.append("controls.%s: must be positive" % key)
		if not config.camera.get("panBindings") is Dictionary: errors.append("camera.panBindings: required object"); return errors
		var pan_keys: Array = []
		for direction in ["up", "down", "left", "right"]:
			if not config.camera.panBindings.get(direction) is String: errors.append("camera.panBindings.%s: required key aliases" % direction); continue
			for binding in str(config.camera.panBindings[direction]).split("|"):
				if OS.find_keycode_from_string(binding) == KEY_NONE: errors.append("camera.panBindings.%s: unknown key" % direction)
				pan_keys.append(binding.to_upper())
		for key in ["commands", "buildHotkeys"]:
			if not controls.get(key) is Dictionary: errors.append("controls.%s: required object" % key); return errors
		for action in ["build", "mine", "attack", "stop", "patrol", "escort", "board", "loadCargo", "repair", "unload", "focusSelection", "focusAnchor", "pause", "cancel"]:
			if not controls.commands.get(action) is String: errors.append("controls.commands.%s: required key name" % action)
		if not controls.get("buildOrder") is Array: errors.append("controls.buildOrder: required array"); return errors
		for kind in controls.buildOrder:
			if not config.structures.has(kind) or not controls.buildHotkeys.has(kind): errors.append("controls.buildOrder: unknown structure or missing hotkey " + str(kind))
		var used: Dictionary = {}
		for action in controls.commands:
			var binding := str(controls.commands[action]).to_upper()
			if OS.find_keycode_from_string(binding) == KEY_NONE: errors.append("controls.commands.%s: unknown key" % action)
			if binding in pan_keys: errors.append("controls.commands.%s: conflicts with camera pan" % action)
			if used.has(binding): errors.append("controls.commands.%s: duplicate key" % action)
			used[binding] = true
		used.clear()
		for kind in controls.buildHotkeys:
			var binding := str(controls.buildHotkeys[kind]).to_upper()
			if not config.structures.has(kind) or OS.find_keycode_from_string(binding) == KEY_NONE: errors.append("controls.buildHotkeys.%s: unknown structure or key" % kind)
			if binding.length() != 1: errors.append("controls.buildHotkeys.%s: use a single letter or number" % kind)
			if used.has(binding) or binding == str(controls.commands.build).to_upper() or binding == str(controls.commands.cancel).to_upper(): errors.append("controls.buildHotkeys.%s: duplicate or reserved key" % kind)
			used[binding] = true
		if int(controls.get("selectionLimit", 0)) < 1 or int(controls.get("selectionLimit", 0)) > 128: errors.append("controls.selectionLimit: must be between 1 and 128")
		if int(controls.get("controlGroupCount", 0)) < 1 or int(controls.get("controlGroupCount", 0)) > 9: errors.append("controls.controlGroupCount: must be between 1 and 9")
		return errors

	static func at_path(config: Dictionary, path: String) -> Variant:
		var value: Variant = config
		for key in path.split("."):
			if not value is Dictionary or not value.has(key): return null
			value = value[key]
		return value

	static func _check_numbers(value: Variant, path: String, errors: Array[String]) -> void:
		if value is Dictionary:
			for key in value: _check_numbers(value[key], str(key) if path == "" else path + "." + str(key), errors)
		elif value is Array:
			for index in range(value.size()): _check_numbers(value[index], path + "[%d]" % index, errors)
		elif value is float or value is int:
			if not is_finite(float(value)): errors.append(path + ": must be finite")
			# Signed audio dB values are valid. Other configured quantities are nonnegative.
			if float(value) < 0 and not path.ends_with("Db"): errors.append(path + ": must be nonnegative")
			var key := path.get_slice(".", path.get_slice_count(".") - 1)
			if key in ["ore", "gas", "alloy", "polymer", "crystal", "nacre", "chyme"] or key.ends_with("Capacity") or key.ends_with("QueueLimit") or key.ends_with("Seats") or key.ends_with("Count") or key == "impactParticles":
				if float(value) != floorf(float(value)): errors.append(path + ": must be a whole number")
