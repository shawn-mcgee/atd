class_name CommandSkin
extends RefCounted

static func panel() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = preload("res://assets/textures/command-metal.png")
	box.modulate_color = Color(0.48, 0.53, 0.5, 0.98)
	box.set_content_margin_all(12)
	return box

static func icon(kind: String) -> Texture2D:
	var path := "res://assets/icons/%s.svg" % kind
	return load(path) if ResourceLoader.exists(path) else preload("res://assets/icons/build.svg")

static func affordable(world: WorldState, owner_id: int, cost: Dictionary) -> bool:
	for resource in cost:
		if int(world.resources(owner_id).get(resource, 0)) < int(cost[resource]): return false
	return true

static func description(world: WorldState, e: Dictionary) -> String:
	if e.get("remembered", false):
		return "LAST SEEN %.1fs AGO\nLAST RECORDED HEALTH %d / %d\nCurrent condition unknown. Scout this location to update it.\nRight click to move to the last-known location." % [maxf(0, world.time_seconds - float(e.get("last_seen_seconds", 0))), ceili(e.hp), int(world.cfg.structures[e.kind].health)]
	if e.has("pos"):
		var d: Dictionary = world.cfg.units[e.kind]
		var armor := int(d.armor) + (int(world.cfg.upgrades.fabricatorArmor.armorPerPurchase) if e.owner >= 0 and world.players[e.owner].upgrades.has(e.kind) else 0)
		var text := "HEALTH %d / %d     ARMOR %d     SPEED %.1f\n" % [ceili(e.hp), d.health, armor, d.speedTilesPerSecond]
		if d.weapon != null:
			var weapon: Dictionary = world.cfg.weapons[d.weapon]
			text += "DAMAGE %s     INTERVAL %.2fs     RANGE %s\n" % [str(weapon.damagePerHit), float(weapon.intervalSeconds), str(weapon.rangeTiles)]
		else: text += "VISION %s     LIGHT %s\n" % [str(d.visionRangeTiles), str(d.illuminationRangeTiles)]
		if int(d.get("detectionRangeTiles", 0)) > 0: text += "DETECTION %d TILES (requires driver)\n" % int(d.detectionRangeTiles)
		var cargo: Array[String] = []
		for r in e.cargo:
			if int(e.cargo[r]) > 0: cargo.append("%d %s" % [int(e.cargo[r]), str(r).capitalize()])
		if int(d.get("cargoCapacity", 0)) > 0: text += "CARGO %d / %d  %s\n" % [world.cargo_amount(e), int(d.cargoCapacity), ", ".join(cargo)]
		if d.has("driverSeats"):
			var driver: Dictionary = world.units.get(int(e.driver), {})
			text += "DRIVER: %s   PASSENGERS %d / %d\n" % [("%s %d HP" % [str(driver.kind).to_upper(), ceili(driver.hp)]) if not driver.is_empty() else "NONE", e.passengers.size(), int(d.passengerSeats)]
			if driver.is_empty(): text += "NO DRIVER: movement, weapons, light and vision offline\n"
			for id in e.passengers:
				var passenger: Dictionary = world.units.get(int(id), {})
				if not passenger.is_empty(): text += "%s %d HP  " % [str(passenger.kind).capitalize(), ceili(passenger.hp)]
			if not e.passengers.is_empty(): text += "\n"
			text += "Right click with infantry to board; loaded workers transfer cargo.\n"
		if e.get("transition", "") != "": text += "%s: %.1fs remaining\n" % [str(e.transition).to_upper(), float(e.transition_remaining)]
		elif e.get("buried", false): text += "BURIED: stationary; requires detection to target\n"
		text += "ORDER: %s  /  %s" % [str(e.job.kind).to_upper(), str(e.stance).to_upper()]
		if e.job.get("automatic", false): text += "\nAUTOMATIC: nearby structure maintenance"
		if e.job.kind == "patrol": text += "\nPATROL: alternating between two waypoints"
		if e.job.kind == "escort":
			var escorted := world.entity(int(e.job.target))
			text += "\nESCORTING: %s" % (str(escorted.kind).to_upper() if not escorted.is_empty() else "TARGET LOST")
		if e.job.kind == "mine" and e.job.get("delivering", false):
			var destination: Dictionary = world.structures.get(int(e.job.get("deposit", 0)), {})
			if destination.is_empty(): text += "\nChoosing delivery destination"
			elif e.pos.distance_to(world.entity_position(destination)) <= float(world.cfg.structures[destination.kind].footprintRadiusTiles) + 1.2: text += "\nWAITING FOR STORAGE CAPACITY"
			else: text += "\nDelivering to %s #%d" % [str(destination.kind).capitalize(), int(destination.id)]
		elif e.job.kind == "mine" and int(e.job.get("facility", 0)) != 0:
			var facility: Dictionary = world.structures.get(int(e.job.facility), {})
			if not facility.is_empty() and not facility.powered: text += "\nFACILITY HAS NO POWER"
			elif not facility.is_empty() and int(facility.buffer) == 0: text += "\nWaiting for facility output"
		return text
	var d: Dictionary = world.cfg.structures[e.kind]
	var text := "HEALTH %d / %d     ARMOR %d\n" % [ceili(e.hp), d.health, int(WorldState.TargetRules.armor(world, e))]
	if e.owner < 0: return text + "GLOOM RANGE %d     REGEN %.1f HP/s" % [int(d.get("gloomRangeBeyondFootprintTiles", 0)), float(world.cfg.gloom.structureRegenerationPerSecond)]
	text += "GRID %d DEMAND / %d CAPACITY  ·  %s\n" % [int(e.get("grid_demand", 0)), int(e.get("grid_capacity", 0)), "OFF" if not e.enabled else "BLACKOUT" if e.blackout else "BROWNOUT" if e.brownout else "ONLINE" if e.powered else "UNPOWERED"]
	var shield := WorldState.TargetRules.shield_bonus(world, e)
	if shield > 0: text += "RAMPART: +%d ARMOR (included above)\n" % shield
	if e.kind == "relay": text += "RELAY %s · RANGE %d · NO POWER CONSUMED\nSwitch off to disconnect its downstream links.\n" % ["ON" if e.enabled else "OFF", world.electrical_reach("relay")]
	if e.kind == "gate": text += "%s / %s\nUnlocked gates open only for friendly routed passage.\n" % ["OPEN" if e.open else "CLOSED", "LOCKED" if e.locked else "AUTOMATIC"]
	if e.kind == "radar": text += "DETECTION RANGE %d TILES\nContacts reveal occupied tiles only. Shades evade radar.\nSelect a turret and right click a contact to override its target.\n" % int(d.detectionRangeBeyondFootprintTiles)
	if e.kind == "floodlight": text += "VISION %d TILES · LIGHT %d\nUnpowered vision: %d tiles.\n" % [world.structure_vision_range(e), int(d.illuminationRangeBeyondFootprintTiles) if e.powered and e.enabled and not e.blackout else 0, int(d.unpoweredVisionRangeBeyondFootprintTiles)]
	if e.kind == "womb": text += "BROOD: %s\n" % str(e.get("unit_type", "scavenger")).to_upper()
	if e.kind == "rampart": text += "SHIELD: +%d ARMOR, RANGE %d\nProtects friendly structures. Overlapping shields do not stack.\n" % [world.cfg.combat.rampartArmorBonus, world.cfg.combat.rampartRangeBeyondFootprintTiles]
	if d.has("weapon"):
		var weapon: Dictionary = world.cfg.weapons[d.weapon]
		text += "DAMAGE %s  RANGE %s  INTERVAL %.2fs\n" % [str(weapon.damagePerHit), str(weapon.rangeTiles), float(weapon.intervalSeconds)]
		var target := world.entity(int(e.get("target", 0)))
		text += "TARGET: %s\n" % ("NONE" if target.is_empty() else str(target.kind).to_upper() if WorldState.TargetRules.identifiable(world, target, e.owner) else "UNIDENTIFIED CONTACT")
	if e.kind == "depot": text += "CAPACITY: +%d %s%s\n" % [int(world.cfg.economy.depotCapacityPerResource), str(e.depot_type).to_upper(), " · RECONFIGURING %.1fs" % float(e.configuration_remaining) if float(e.configuration_remaining) > 0 else ""]
	if world.cfg.economy.recipes.has(e.kind):
		var recipe: Dictionary = world.cfg.economy.recipes[e.kind]
		text += "OUTPUT BUFFER %d / %d · %s\n" % [e.buffer, world.cfg.economy.extractorBufferCapacity if e.kind == "extractor" else world.cfg.economy.processorBufferCapacity, world._output_resource(e).to_upper()]
		text += "CYCLE %.1fs · %s" % [recipe.cycleSeconds, "WORKING" if e.powered and world._wants_power(e) else "WAITING FOR POWER / INPUTS / SPACE"]
		if recipe.has("inputs"):
			var inputs: Array[String] = []; var outputs: Array[String] = []
			for r in recipe.inputs: inputs.append("%d %s" % [recipe.inputs[r], str(r).capitalize()])
			for r in recipe.outputs: outputs.append("%d %s" % [recipe.outputs[r], str(r).capitalize()])
			text += "\n%s → %s" % [" + ".join(inputs), " + ".join(outputs)]
	if e.kind in ["generator", "reactor"]:
		var fuel: Dictionary = world.cfg.power.generatorFuel if e.kind == "generator" else world.cfg.power.reactorFuel
		text += "FUEL: %d %s / %.0fs\nCURRENT FUEL REMAINING %.1fs" % [fuel.unitsPerCycle, str(fuel.resource).capitalize(), fuel.cycleSeconds, float(e.fuel)]
	if e.kind in ["anchor", "cradle", "armory"]: text += "PERSONNEL %d / %d     KITS %d / %d\nFinished kits await an empty Operator." % [e.operators.size(), int(world.cfg.personnel.operatorQueueLimit), e.kits.size(), int(world.cfg.personnel.kitQueueLimit)]
	if e.kind == "factory":
		text += "VEHICLES %d / %d\n" % [e.vehicles.size(), int(world.cfg.personnel.vehicleQueueLimit)]
		if not e.vehicles.is_empty():
			var order: Dictionary = e.vehicles[0]
			text += "%s: %s\n" % [str(order.kind).to_upper(), "EXIT BLOCKED" if float(order.progress) >= float(world.cfg.units[order.kind].productionSeconds) else "ASSEMBLING" if e.powered else "PAUSED: NO POWER"]
		text += "Crew required. Right click a vehicle with infantry to board."
	if e.kind == "fabricator":
		var count := 0
		for u in world.units.values():
			if u.job.kind == "research" and int(u.job.target) == int(e.id) and u.pos.distance_to(world.entity_position(e)) <= 1.4: count += 1
		text += "ENGINEERS IN RANGE %d · %s\n" % [count, "RESEARCHING" if count > 0 and e.powered and not e.upgrades.is_empty() else "WAITING"]
		text += "Select Engineers, then right click here to assign work."
	return text

static func task_icon(task: String) -> String:
	return {"idle": "neutral", "standby": "neutral", "move": "move", "mine": "mine", "deposit": "depot", "build": "build", "repair": "repair", "research": "upgrade", "equip": "engineer", "produce": "factory", "crew_wait": "operator", "riding": "scout", "board": "scout", "load_cargo": "depot", "attack": "aggressive", "escort": "escort", "patrol": "patrol", "excavate": "excavator", "configure": "depot"}.get(task, "neutral")

static func task_text(a: Dictionary) -> String:
	var text: String = {"idle": "Idle", "standby": "Standing by", "move": "Moving", "mine": "Mining", "deposit": "Delivering cargo", "build": "Building", "repair": "Repairing", "research": "Researching", "equip": "Equipping", "produce": "Producing", "crew_wait": "Awaiting vehicle", "riding": "Aboard vehicle", "board": "Boarding", "load_cargo": "Loading cargo", "attack": "Attacking", "escort": "Escorting", "patrol": "Patrolling", "excavate": "Clearing cliff", "configure": "Configuring", "remembered": "Last seen"}.get(str(a.task), str(a.task).capitalize())
	if a.task in ["mine", "produce"] and not str(a.resource).is_empty(): text += " " + str(a.resource).capitalize()
	return text

static func blocker_text(a: Dictionary) -> String:
	var names := {"no_driver": "Needs driver", "buried": "Buried", "vehicle_pending": "Vehicle not ready", "no_route": "Cannot reach target", "depleted": "Deposit depleted", "switched_off": "Switched off", "no_power": "No power", "output_pending": "Waiting for output", "no_dropoff": "No drop-off available", "storage_full": "Storage full", "anchor_required": "Nacre needs an Anchor", "target_lost": "Target unavailable", "site_blocked": "Site obstructed", "site_occupied": "Clear the footprint", "no_resources": "Needs resources", "no_research": "No research queued", "unload_cargo": "Unload cargo first", "no_kit": "No kit queued", "kit_pending": "Kit not ready", "cargo_full": "Vehicle cargo full", "no_engineer": "Needs Engineer", "buffer_full": "Output buffer full", "exit_blocked": "Vehicle exit blocked", "line_blocked": "Line of fire blocked", "kit_pickup": "Kits ready for pickup"}
	var text: String = names.get(str(a.blocker), "")
	if a.blocker in ["storage_full", "no_resources"] and not str(a.get("blocker_resource", a.resource)).is_empty(): text = ("Storage full: " if a.blocker == "storage_full" else "Needs ") + str(a.get("blocker_resource", a.resource)).capitalize()
	return text

static func activity_color(a: Dictionary) -> Color:
	return Color("efbc70") if a.phase == "waiting" else Color("87cfc1") if a.phase == "working" else Color("91b9d8") if a.phase == "moving" else Color("97a39d")

class StatusPanel:
	extends Control
	var world: WorldState
	var entities: Array = []
	var activities: Array = []
	var owner_id := 0
	var cargo_contents: Dictionary = {}

	func _ready() -> void:
		custom_minimum_size = Vector2(180, 108)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func refresh(w: WorldState, selection: Array, owner: int) -> void:
		world = w; entities = selection; owner_id = owner; activities.clear(); cargo_contents.clear()
		for e in entities:
			activities.append(world.activity(e) if e.owner == owner else {"task": "standby", "phase": "idle", "blocker": "", "resource": "", "target": 0, "progress": -1.0})
			if e.owner == owner:
				for resource in e.get("cargo", {}):
					if int(e.cargo[resource]) > 0: cargo_contents[resource] = int(cargo_contents.get(resource, 0)) + int(e.cargo[resource])
		var columns := maxi(1, int(maxf(180, size.x) / 90))
		custom_minimum_size.y = 108 + ceili(float(cargo_contents.size()) / columns) * 20
		queue_redraw()

	func _draw() -> void:
		if entities.is_empty(): return
		var font = preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")
		var a: Dictionary = activities[0]
		var health := 0.0; var maximum := 0.0; var cargo := 0; var capacity := 0
		for e in entities:
			var d: Dictionary = world.cfg.structures[e.kind] if e.has("cell") else world.cfg.units[e.kind]
			health += float(e.hp); maximum += float(d.health)
			if e.has("cargo"): cargo += world.cargo_amount(e); capacity += int(d.get("cargoCapacity", 0))
		var color := CommandSkin.activity_color(a)
		var title := CommandSkin.task_text(a)
		var target := world.observed_entity(int(a.target), owner_id)
		if entities.size() == 1 and not target.is_empty() and target.owner == owner_id and a.task in ["build", "repair", "research", "equip", "board", "escort", "load_cargo"]: title += " " + str(target.kind).capitalize()
		var reason := CommandSkin.blocker_text(a)
		if entities.size() > 1:
			var tasks: Dictionary = {}; var blocked := 0
			for item in activities:
				var name := CommandSkin.task_text(item)
				tasks[name] = int(tasks.get(name, 0)) + 1
				if item.phase == "waiting": blocked += 1
			var parts: Array[String] = []
			for key in tasks: parts.append("%s x%d" % [key, tasks[key]])
			title = " / ".join(parts)
			reason = "%d blocked / %d selected" % [blocked, entities.size()] if blocked > 0 else "Orders in progress" if tasks.size() > 1 else str(a.phase).capitalize()
			if blocked > 0: color = Color("efbc70")
		draw_texture_rect(CommandSkin.icon(CommandSkin.task_icon(str(a.task))), Rect2(0, 0, 22, 22), false, color)
		draw_string(font, Vector2(30, 17), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 16, Color("d8dfd1"))
		if entities.size() == 1 and float(a.progress) >= 0:
			draw_rect(Rect2(30, 23, size.x - 30, 3), Color("1b3036"))
			draw_rect(Rect2(30, 23, (size.x - 30) * clampf(float(a.progress), 0, 1), 3), color)
		if reason.is_empty(): reason = "On the way" if a.phase == "moving" else "Working" if a.phase == "working" else "Ready for orders"
		draw_style_box(_pill(color), Rect2(0, 33, size.x, 24))
		if a.phase == "waiting" or (entities.size() > 1 and reason.contains("blocked")):
			draw_colored_polygon(PackedVector2Array([Vector2(10, 49), Vector2(16, 38), Vector2(22, 49)]), color)
			draw_string(font, Vector2(26, 50), reason, HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 13, color)
		else: draw_string(font, Vector2(10, 50), reason, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 13, color)
		_meter(font, 66, "HP", ceili(health), ceili(maximum), Color("88b88b"))
		if capacity > 0: _meter(font, 90, "Cargo", cargo, capacity, Color("cbb889"))
		elif entities.size() == 1 and entities[0].has("cell") and entities[0].owner == owner_id:
			var e: Dictionary = entities[0]
			draw_texture_rect(CommandSkin.icon("relay"), Rect2(0, 89, 15, 15), false)
			draw_string(font, Vector2(21, 102), "Grid %d / %d%s" % [int(e.get("grid_demand", 0)), int(e.get("grid_capacity", 0)), "  |  Buffer %d" % int(e.buffer) if world.cfg.economy.recipes.has(e.kind) else ""], HORIZONTAL_ALIGNMENT_LEFT, size.x - 21, 12, Color("a4b7b2"))
		elif entities.size() == 1 and entities[0].has("stance"):
			draw_texture_rect(CommandSkin.icon(str(entities[0].stance)), Rect2(0, 89, 15, 15), false)
			draw_string(font, Vector2(21, 102), str(entities[0].stance).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 21, 12, Color("a4b7b2"))
		_draw_cargo(font)

	func _draw_cargo(font: Font) -> void:
		var columns := maxi(1, int(size.x / 90))
		var index := 0
		for resource in ResourceStrip.TYPES:
			if not cargo_contents.has(resource): continue
			var tint: Color = ResourceStrip.TINTS[ResourceStrip.TYPES.find(resource)]
			var point := Vector2((index % columns) * size.x / columns + 6, 119 + (index / columns) * 20)
			if resource == "gas":
				for j in range(3): draw_circle(point + Vector2((j - 1) * 3, abs(j - 1) * 3 - 1), 2, tint, false, 1, true)
			elif resource in ["alloy", "polymer"]:
				for j in range(3): draw_line(point + Vector2(-4, j * 3 - 3), point + Vector2(4, j * 3 - 3), tint, 1, true)
			else: draw_colored_polygon(PackedVector2Array([point + Vector2(0, -5), point + Vector2(4, 0), point + Vector2(0, 5), point + Vector2(-4, 0)]), tint)
			draw_string(font, point + Vector2(11, 4), "%d %s" % [cargo_contents[resource], str(resource).capitalize()], HORIZONTAL_ALIGNMENT_LEFT, size.x / columns - 20, 12, tint)
			index += 1

	func _pill(color: Color) -> StyleBoxFlat:
		var box := StyleBoxFlat.new(); box.bg_color = Color(color, 0.08); box.border_color = Color(color, 0.3); box.set_border_width_all(1); box.set_corner_radius_all(3); return box

	func _meter(font: Font, y: float, label: String, value: int, limit: int, color: Color) -> void:
		draw_string(font, Vector2(0, y + 9), label, HORIZONTAL_ALIGNMENT_LEFT, 40, 11, color)
		draw_string(font, Vector2(45, y + 9), "%d / %d" % [value, limit], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 45, 11, Color("c5cec5"))
		draw_rect(Rect2(0, y + 13, size.x, 3), Color("1c2b30"))
		draw_rect(Rect2(0, y + 13, size.x * clampf(float(value) / maxf(1, limit), 0, 1), 3), color)
