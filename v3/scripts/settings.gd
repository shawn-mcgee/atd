extends Node

var data: Dictionary
var network: Dictionary
var gameplay_hash := ""

func _ready() -> void:
	data = ConfigRules.read_json("res://config/prototype.json")
	network = _read("res://config/networking.json")
	var errors := ConfigRules.validate(data)
	errors.append_array(ConfigRules.validate_network(network))
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

	static func validate_network(config: Dictionary) -> Array[String]:
		var errors: Array[String] = []
		for section in ["signaling", "ice", "limits", "liveness"]:
			if not config.get(section) is Dictionary: errors.append("networking." + section + ": required object")
		if not errors.is_empty(): return errors
		var url = config.signaling.get("url")
		if not url is String or not (str(url).begins_with("wss://") or str(url).begins_with("ws://")): errors.append("networking.signaling.url: expected WebSocket URL")
		for path in ["signaling.connectTimeoutMs", "liveness.heartbeatIntervalMs", "liveness.peerTimeoutMs", "limits.maxPeers", "limits.maxPacketBytes", "limits.framePayloadBytes", "limits.bufferedAmountBytes", "limits.sendTimeoutMs", "limits.receiveFramesPerPoll", "limits.sendFramesPerPoll", "limits.compressionThresholdBytes", "limits.commandQueueLimit"]:
			var value = at_path(config, path)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0 or float(value) != floorf(float(value)): errors.append("networking." + path + ": expected positive whole number")
		if float(config.liveness.get("peerTimeoutMs", 0)) <= float(config.liveness.get("heartbeatIntervalMs", 0)): errors.append("networking.liveness.peerTimeoutMs: must exceed heartbeat interval")
		if float(config.limits.get("maxPeers", 0)) > 4: errors.append("networking.limits.maxPeers: maximum four guests")
		if float(config.limits.get("framePayloadBytes", 0)) > 1184: errors.append("networking.limits.framePayloadBytes: exceeds Godot's 1200-byte frame limit")
		if not config.ice.get("transportPolicy") in ["all", "relay"]: errors.append("networking.ice.transportPolicy: expected all or relay")
		if not config.ice.get("servers") is Array: errors.append("networking.ice.servers: expected array")
		else:
			for server in config.ice.servers:
				if not server is Dictionary or not server.get("urls") is String: errors.append("networking.ice.servers: each server requires a URL string")
		return errors

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
		var expeditions = config.get("expeditions")
		if not expeditions is Dictionary:
			errors.append("expeditions: required object is missing")
		else:
			for field in ["gatherRadiusTiles", "resourceSearchRadiusTiles", "regroupRadiusTiles", "escortRadiusTiles", "boardingTimeoutSeconds", "regroupTimeoutSeconds", "repathIntervalSeconds", "stuckTimeoutSeconds", "siteInactivitySeconds", "allocationRecheckSeconds"]:
				var value = expeditions.get(field)
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0: errors.append("expeditions." + field + ": must be positive")
			for field in ["driverPreference", "driverVehiclePreference", "passengerVehiclePreference", "workerBoardingPreference"]:
				var kinds = expeditions.get(field)
				if not kinds is Array or kinds.is_empty(): errors.append("expeditions." + field + ": expected unit preferences"); continue
				var seen: Array = []
				for kind in kinds:
					if not kind is String or not config.units.has(kind) or seen.has(kind): errors.append("expeditions." + field + ": expected unique unit types")
					seen.append(kind)

		var missions = config.get("missions")
		if not missions is Dictionary:
			errors.append("missions: required object is missing")
		else:
			for key in ["foothold", "industry", "extraction"]:
				var d = missions.get(key)
				var path: String = "missions." + key
				if not d is Dictionary: errors.append(path + ": required object is missing"); continue
				for field in ["title", "briefing"]:
					if not d.get(field) is String or str(d.get(field, "")).is_empty(): errors.append(path + "." + field + ": required text")
				for field in ["radiusTiles", "anchorEdgeInsetTiles", "extraEngineers", "extraMarines", "clearRadiusTiles"] + (["medusaHealth", "nestScavengers", "nestClearRadiusTiles", "nestSpawnRadiusTiles", "extractionMinimumNacre", "extractionSeconds", "assaultIntervalSeconds", "assaultWaveSize"] if key == "extraction" else ["deliveryTarget"]):
					var value = d.get(field)
					if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) != floorf(float(value)): errors.append(path + "." + field + ": expected a nonnegative whole number")
					elif not field in ["extraEngineers", "extraMarines", "nestScavengers"] and float(value) == 0: errors.append(path + "." + field + ": must be positive")
				if float(d.get("radiusTiles", 0)) <= float(d.get("anchorEdgeInsetTiles", 0)) + float(d.get("clearRadiusTiles", 0)): errors.append(path + ": radius must contain the cleared Anchor area")
				if not d.get("startingResources") is Dictionary: errors.append(path + ".startingResources: required object")
				else:
					for resource in ["ore", "gas", "alloy", "polymer", "crystal"]:
						var value = d.startingResources.get(resource)
						if not (value is int or value is float) or float(value) < 0 or float(value) != floorf(float(value)) or float(value) > float(config.map.anchorStorage.get(resource, 0)): errors.append(path + ".startingResources." + resource + ": expected whole inventory within Anchor capacity")
				if key == "extraction":
					if float(d.get("extractionMinimumNacre", 0)) > float(config.match.anchorNacreCapacity): errors.append(path + ".extractionMinimumNacre: exceeds Anchor capacity")
				else:
					if not d.get("deliveryResource", "") in ["ore", "alloy"]: errors.append(path + ".deliveryResource: expected ore or alloy")
					if not d.get("requiredStructures") is Array: errors.append(path + ".requiredStructures: required array")
					else:
						for kind in d.requiredStructures:
							if not config.structures.has(kind): errors.append(path + ".requiredStructures: unknown structure")
				if key == "industry":
					var value = d.get("additionalMarinesRequired")
					if not (value is int or value is float) or float(value) <= 0 or float(value) != floorf(float(value)): errors.append(path + ".additionalMarinesRequired: expected a positive whole number")
		var terrain_style = config.presentation.get("terrain", {})
		for key in ["scatterDensity", "contactShadowOpacity", "rockStrataStrength", "gasVaporOpacity", "groundNormalStrength"]:
			var value = terrain_style.get(key) if terrain_style is Dictionary else null
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 1: errors.append("presentation.terrain." + key + ": expected a number from 0 to 1")
		var fog = config.presentation.get("fog", {})
		if not fog is Dictionary or not fog.get("enabled") is bool: errors.append("presentation.fog.enabled: expected a boolean")
		for key in ["memoryOpacity", "edgeOpacity", "edgeReachTiles", "driftSpeed", "noiseScale", "heightTiles"]:
			var value = fog.get(key) if fog is Dictionary else null
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: errors.append("presentation.fog." + key + ": expected a finite nonnegative number")
			elif key in ["memoryOpacity", "edgeOpacity"] and float(value) > 1: errors.append("presentation.fog." + key + ": expected a number from 0 to 1")
			elif key in ["edgeReachTiles", "noiseScale"] and float(value) == 0: errors.append("presentation.fog." + key + ": must be positive")
		var lighting = config.presentation.get("lighting", {})
		var wash_opacity = lighting.get("serviceLightWashOpacity") if lighting is Dictionary else null
		if not (wash_opacity is int or wash_opacity is float) or not is_finite(float(wash_opacity)) or float(wash_opacity) < 0 or float(wash_opacity) > 1: errors.append("presentation.lighting.serviceLightWashOpacity: expected a number from 0 to 1")
		for key in ["ambientEnergy", "keyLightEnergy", "workLightEnergy", "groundBrightness"]:
			var value = lighting.get(key) if lighting is Dictionary else null
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: errors.append("presentation.lighting." + key + ": expected a finite nonnegative number")
		var memory_tint = config.presentation.get("structureMemoryTintStrength", 0.75)
		if not (memory_tint is int or memory_tint is float) or not is_finite(float(memory_tint)) or float(memory_tint) < 0 or float(memory_tint) > 1: errors.append("presentation.structureMemoryTintStrength: expected a number from 0 to 1")
		for path in ["presentation.motherMotion.stepCyclesPerSecond", "presentation.fatherMotion.hoverCyclesPerSecond", "presentation.fatherMotion.tentacleCyclesPerSecond", "presentation.activityIndicators.sizePixels", "presentation.activityIndicators.pulseSeconds", "camera.edgeBandLogicalPixels", "camera.edgeIndicatorSizeLogicalPixels", "camera.edgeIndicatorPulseSeconds", "match.simulationTicksPerSecond", "match.extractionSeconds", "map.radiusTiles", "economy.workerCycleSeconds", "construction.engineerHealthPerSecond", "construction.idleEngineerSearchRangeTiles", "construction.idleEngineerSearchIntervalSeconds", "targeting.refreshIntervalTicks", "lightless.combatRepathSeconds", "lightless.retreatRepathSeconds", "lightless.medusaPassiveScavengerSeconds", "lightless.medusaChymeCycleSeconds", "lightless.brainDecisionIntervalSeconds", "lightless.cpuExpansionIntervalSeconds", "lightless.structureGestationSeconds", "lightless.wombReconfigureSeconds", "lightless.postMedusaWombSpawnRateMultiplier"]:
			var value = at_path(config, path)
			if not (value is float or value is int) or float(value) <= 0: errors.append(path + ": must be a positive number")
		for key in ["cpuDesiredStomas", "cpuStomaMinOrganDistanceTiles", "cpuAdditionalWombsPerType"]:
			var value = config.lightless.get(key)
			var minimum := 1 if key == "cpuStomaMinOrganDistanceTiles" else 0
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < minimum or float(value) != floorf(float(value)): errors.append("lightless." + key + ": expected a whole number >= " + str(minimum))
		for key in ["cpuWombCapacityPressure", "cpuFatherRetreatHealthFraction", "cpuFatherResumeHealthFraction"]:
			var value = config.lightless.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0 or float(value) > 1: errors.append("lightless." + key + ": expected a fraction in (0, 1]")
		if float(config.lightless.get("cpuFatherRetreatHealthFraction", 0)) >= float(config.lightless.get("cpuFatherResumeHealthFraction", 1)): errors.append("lightless.cpuFatherRetreatHealthFraction: must be below resume health")
		var path_budget = config.lightless.get("maxPathQueriesPerDecision")
		if not (path_budget is int or path_budget is float) or not is_finite(float(path_budget)) or float(path_budget) < 1 or float(path_budget) != floorf(float(path_budget)): errors.append("lightless.maxPathQueriesPerDecision: expected a positive whole number")
		var human_ai = config.lightless.get("soloCommonwealthAI", {})
		for key in ["decisionIntervalSeconds", "desiredMarines", "attackGroupSize", "desiredEngineers", "gasReserveTarget", "baseDefenseRadiusTiles", "regroupRadiusTiles"]:
			var value = human_ai.get(key) if human_ai is Dictionary else null
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0 or (key != "decisionIntervalSeconds" and float(value) != floorf(float(value))): errors.append("lightless.soloCommonwealthAI." + key + ": expected a positive " + ("number" if key == "decisionIntervalSeconds" else "whole number"))
		for key in ["storageHeadroomRatio", "repairHealthFraction", "retreatHealthFraction", "resumeHealthFraction"]:
			var value = human_ai.get(key) if human_ai is Dictionary else null
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0 or float(value) > 1: errors.append("lightless.soloCommonwealthAI." + key + ": expected a fraction in (0, 1]")
		if human_ai is Dictionary and float(human_ai.get("retreatHealthFraction", 0)) >= float(human_ai.get("resumeHealthFraction", 1)): errors.append("lightless.soloCommonwealthAI.retreatHealthFraction: must be below resumeHealthFraction")
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
				if table == "units" and d.has("manualSpawnSeconds"):
					for key in ["manualSpawnSeconds", "wombPassiveSpawnSeconds"]:
						if not (d.get(key) is int or d.get(key) is float) or float(d.get(key, 0)) <= 0: errors.append(path + "." + key + ": must be positive")
				if table == "structures" and d.has("unpoweredVisionRangeBeyondFootprintTiles"):
					var value = d.unpoweredVisionRangeBeyondFootprintTiles
					if not (value is int or value is float) or float(value) < 0 or float(value) != floorf(float(value)) or float(value) > float(d.get("visionRangeBeyondFootprintTiles", 0)): errors.append(path + ".unpoweredVisionRangeBeyondFootprintTiles: expected a whole number from zero to the powered vision range")
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
		if not config.movement.get("pathfinding") is Dictionary: errors.append("movement.pathfinding: required object"); return errors
		if not config.movement.pathfinding.get("smoothingEnabled") is bool: errors.append("movement.pathfinding.smoothingEnabled: required boolean")
		for key in ["clearancePaddingTiles", "waypointToleranceTiles"]:
			var number = config.movement.pathfinding.get(key)
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0 or (key == "waypointToleranceTiles" and float(number) == 0):
				errors.append("movement.pathfinding.%s: expected a %s number" % [key, "nonnegative" if key == "clearancePaddingTiles" else "positive"])
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
		for key in ["commands", "buildHotkeys", "stanceHotkeys", "productionHotkeys", "depotHotkeys"]:
			if not controls.get(key) is Dictionary: errors.append("controls.%s: required object" % key); return errors
		for action in ["build", "mine", "attack", "stop", "patrol", "escort", "board", "loadCargo", "repair", "unload", "focusSelection", "focusAnchor", "pause", "cancel", "togglePersonnel"]:
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
		for group in ["stanceHotkeys", "productionHotkeys", "depotHotkeys"]:
			for action in controls[group]:
				if not controls[group][action] is String or OS.find_keycode_from_string(str(controls[group][action])) == KEY_NONE: errors.append("controls." + group + "." + action + ": expected a valid key name")
		var contexts := [["stanceHotkeys", ["neutral", "defensive", "aggressive"]], ["depotHotkeys", ["ore", "gas", "alloy", "polymer", "crystal"]], ["productionHotkeys", ["operator", "engineer"]], ["productionHotkeys", ["marine", "flamer", "lancer"]], ["productionHotkeys", ["scout", "ranger", "excavator", "reaper", "cremator", "javelin"]]]
		for context in contexts:
			var seen: Dictionary = {}
			for action in context[1]:
				var binding := str(controls[context[0]].get(action, "")).to_upper()
				if binding == "" or seen.has(binding): errors.append("controls." + str(context[0]) + ": missing or duplicate contextual key for " + str(action))
				seen[binding] = true
		var queue_limit = config.movement.get("orderQueueLimit", 0)
		if not (queue_limit is int or queue_limit is float) or float(queue_limit) != floorf(float(queue_limit)) or int(queue_limit) < 1 or int(queue_limit) > 128: errors.append("movement.orderQueueLimit: expected a whole number from 1 to 128")
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
