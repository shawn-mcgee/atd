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
	if e.kind == "gate": text += "%s / %s\nUnlocked gates open only for friendly routed passage.\n" % ["OPEN" if e.open else "CLOSED", "LOCKED" if e.locked else "AUTOMATIC"]
	if e.kind == "radar": text += "DETECTION RANGE %d TILES\nContacts reveal occupied tiles only. Shades evade radar.\nSelect a turret and right click a contact to override its target.\n" % int(d.detectionRangeBeyondFootprintTiles)
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
