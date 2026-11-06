extends SceneTree

const ConfigRules = preload("res://scripts/settings.gd").ConfigRules

var assertions := 0
var failures: Array[String] = []
var settings: Dictionary

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message); printerr("FAIL: ", message)

func world(count: int = 1) -> WorldState:
	var config := settings.duplicate(true)
	config.map.radiusTiles = 14
	config.map.anchorEdgeInsetTiles = 6
	config.map.additionalFieldsPerPlayer = {"ore": 1, "gas": 1}
	var state := WorldState.new(config)
	state.reset(472, count)
	for id in state.units.keys():
		if state.units[id].owner == -1: state.units.erase(id)
	for s in state.structures.values():
		if s.kind == "medusa": s.passive = -10000.0
	return state

func advance(state: WorldState, seconds: float) -> void:
	for i in range(ceili(seconds * 20)): state.step(0.05)

func engineer(state: WorldState) -> Dictionary:
	for u in state.units.values():
		if u.kind == "engineer" and u.owner == 0: return u
	return {}

func run() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/prototype.json"))
	if "--config-only" in OS.get_cmdline_user_args():
		var errors := ConfigRules.validate(settings)
		for error in errors: printerr(error)
		print("Configuration checks: failures: ", errors.size())
		quit(0 if errors.is_empty() else 1); return
	if "--routes-only" in OS.get_cmdline_user_args():
		route_order_checks(); print("Route checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	for cell in HexGrid.disk(Vector2i.ZERO, 10): verify(HexGrid.cell(HexGrid.world(cell)) == cell, "Hex round trip")
	var a := world(5)
	var b := world(5)
	verify(JSON.stringify(a.snapshot(0)) == JSON.stringify(b.snapshot(0)), "Seeded map and deployment reproduce")
	for owner in a.players:
		var anchor: Dictionary = a.structures[int(a.players[owner].anchor)]
		var from := a.nearest_free(anchor.cell)
		var to := a.nearest_free(Vector2i.ZERO)
		verify(not a.navigation.get_point_path(a.point_ids[from], a.point_ids[to]).is_empty(), "All starting Anchors can reach Medusa")
	var w := world()
	var worker := engineer(w)
	verify(w.command(0, {"action": "move", "ids": [worker.id]}) == "Invalid order coordinates or target", "Malformed move is rejected before simulation mutation")
	verify(w.command(0, {"action": "move", "ids": "invalid"}) == "Invalid unit selection", "Malformed unit selection is rejected")
	var foreign_position: Vector2 = worker.pos
	w.command(1, {"action": "move", "ids": [worker.id], "x": 0, "z": 0})
	verify(worker.pos == foreign_position and worker.job.kind == "idle", "Unknown owner cannot command another player's unit")
	var source := Vector2i.ZERO
	for cell in w.known[0]:
		if w.tiles[cell].resource == "ore": source = cell; break
	w.players[0].resources.ore = 0
	var original := int(w.tiles[source].amount)
	w.command(0, {"action": "mine", "ids": [worker.id], "q": source.x, "r": source.y})
	advance(w, 40)
	verify(int(w.resources(0).ore) > 0, "Mining loop deposits physical cargo")
	verify(original - int(w.tiles[source].amount) == int(w.resources(0).ore) + w.cargo_amount(worker), "Gathering conserves every resource unit")
	w = world()
	worker = engineer(w)
	for cell in w.known[0]:
		if w.tiles[cell].resource == "ore": source = cell; break
	w.command(0, {"action": "mine", "ids": [worker.id], "q": source.x, "r": source.y})
	advance(w, 30)
	verify(int(w.resources(0).ore) == 100 and w.cargo_amount(worker) == 20, "Full storage preserves undeposited cargo")
	var stopped: Vector2 = worker.pos
	advance(w, 3)
	verify(worker.pos.distance_to(stopped) < 0.01, "Carrier waits stably at full storage")
	w = world()
	worker = engineer(w)
	var cell := HexGrid.cell(worker.pos) + Vector2i(1, 1)
	w.known[0][cell] = true
	w.tiles[cell].cliff = false
	var before := int(w.resources(0).ore)
	w.command(0, {"action": "build", "kind": "depot", "ids": [worker.id], "q": cell.x, "r": cell.y})
	var blueprint := int(worker.job.target)
	verify(int(w.resources(0).ore) == before - 20, "Blueprint pays immediately once")
	w.command(0, {"action": "cancel_build", "target": blueprint})
	verify(int(w.resources(0).ore) == before, "Unstarted blueprint refunds")
	w.command(0, {"action": "build", "kind": "depot", "ids": [worker.id], "q": cell.x, "r": cell.y})
	blueprint = int(worker.job.target)
	advance(w, 25)
	verify(w.structures.has(blueprint) and w.structures[blueprint].built, "Engineer reaches outside footprint and finishes building")
	verify(w.capacity(0, "ore") == 300, "Completed Depot expands only its configured capacity")
	verify(not HexGrid.cell(worker.pos) in w.footprint(w.structures[blueprint]), "Builder does not get trapped inside new structure")
	w = world()
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var flood := w.add_structure("floodlight", anchor.cell + Vector2i(3, 0), 0)
	var turret := w.add_structure("sentry", anchor.cell + Vector2i(3, -1), 0)
	w.step(0.05)
	verify(w.structures[flood].powered and w.structures[turret].powered, "Anchor powers one Floodlight and Sentry at full capacity")
	var relay := w.add_structure("relay", anchor.cell + Vector2i(3, 1), 0)
	w.step(0.05)
	verify(w.structures[flood].blackout, "Overload triggers blackout at rounded threshold")
	w.structures[relay].enabled = false
	w.step(0.05)
	verify(w.structures[flood].powered, "Blackout recovers at 100 percent")
	w = world()
	anchor = w.structures[int(w.players[0].anchor)]
	var armory := w.add_structure("armory", anchor.cell + Vector2i(3, 0), 0)
	for i in range(5): w.command(0, {"action": "kit", "kind": "marine", "target": armory, "personnel": false})
	verify(w.structures[armory].kits.size() == 5, "Five-kit limit accepts five orders")
	verify(w.command(0, {"action": "kit", "kind": "marine", "target": armory, "personnel": false}) == "Five-kit queue is full", "Sixth kit is rejected")
	advance(w, 42)
	var done := 0
	for kit in w.structures[armory].kits:
		if kit.done: done += 1
	verify(done == 5, "Completed kits do not block subsequent assembly")
	w = world()
	anchor = w.structures[int(w.players[0].anchor)]
	w.cfg.personnel.anchorOperatorSeconds = 1
	w.cfg.personnel.kits.engineer.seconds = 1
	w.command(0, {"action": "kit", "kind": "engineer", "target": anchor.id})
	advance(w, 4)
	var engineers := 0
	for u in w.units.values():
		if u.kind == "engineer": engineers += 1
	verify(engineers == 2 and anchor.kits.is_empty(), "Requested Operator equips Engineer kit at Anchor")
	var snapshot = JSON.parse_string(JSON.stringify(w.snapshot(0)))
	var client := world()
	client.apply_snapshot(snapshot, 0)
	verify(client.units.size() == w.units.size() and client.tick == w.tick, "JSON snapshot round trip preserves authoritative state")
	w = world(3)
	worker = engineer(w)
	worker.stance = "aggressive"
	worker.job = {"kind": "move"}
	w.eliminate(0)
	verify(worker.stance == "aggressive" and worker.job.kind == "move", "Elimination retains stance and last order")
	verify(w.capacity(0, "ore") == 100, "Disconnected player's surviving Anchor retains storage")
	verify(w.command(0, {"action": "move", "ids": [worker.id], "x": 0, "z": 0}) == "Player cannot issue orders", "Eliminated player cannot issue new orders")
	w = world()
	for tile in HexGrid.disk(Vector2i.ZERO, 4): w.tiles[tile].cliff = false
	w.visible[0] = w.flood(Vector2i.ZERO, 4)
	var flamer := w.add_unit("flamer", Vector2.ZERO, 0)
	var primary := w.add_unit("scavenger", Vector2(1, 0), -1)
	var secondary := w.add_unit("scavenger", Vector2(1, 0.2), -1)
	var outside := w.add_unit("scavenger", Vector2(0, 1), -1)
	var buried := w.add_unit("scavenger", Vector2(1, -0.2), -1)
	w.units[buried].buried = true
	w.units[flamer].target = primary
	w._fire(w.units[flamer], "flamer_flame", 0.05)
	verify(w.units[primary].hp == 29 and w.units[secondary].hp == 29, "Flame cone hits multiple enemies in its area")
	verify(w.units[outside].hp == 30 and w.units[buried].hp == 30, "Flame excludes targets outside cone and buried units")
	var armored := w.add_unit("marine", Vector2(2, 0), 1)
	w._weapon_damage(w.units[armored], w.cfg.weapons.flamer_flame)
	verify(w.units[armored].hp == 100, "Flat armor can reduce damage to zero")
	w.cfg.combat.minimumDamageMode = "minimum"
	w.cfg.combat.minimumDamagePerHit = 0.5
	w._weapon_damage(w.units[armored], w.cfg.weapons.flamer_flame)
	verify(w.units[armored].hp == 99.5, "Configured damage floor applies after armor")
	w = world()
	worker = engineer(w)
	anchor = w.structures[int(w.players[0].anchor)]
	worker.hp = 40.0
	anchor.hp -= 100.0
	advance(w, 1)
	verify(is_equal_approx(worker.hp, 44.0), "Anchor passively heals nearby biological units")
	verify(anchor.hp == 1900.0, "Anchor healing does not restore structures")
	w.command(0, {"action": "repair", "ids": [worker.id], "target": anchor.id})
	advance(w, 2)
	verify(anchor.hp > 1919 and int(w.resources(0).ore) <= 98, "Engineer repair restores structure health while spending Ore")
	w.command(0, {"action": "stop", "ids": [worker.id]})
	w.players[0].resources.ore = 100
	worker.cargo = {"ore": 20}
	w.command(0, {"action": "deposit", "ids": [worker.id], "target": anchor.id})
	advance(w, 1)
	verify(w.cargo_amount(worker) == 20 and worker.job.kind == "deposit", "Explicit delivery waits without losing cargo at full capacity")
	w.players[0].resources.ore = 90
	advance(w, 0.2)
	verify(w.cargo_amount(worker) == 10 and int(w.resources(0).ore) == 100, "Delivery resumes as capacity becomes available")
	w.command(0, {"action": "stop", "ids": [worker.id]})
	verify(worker.job.kind == "idle" and w.cargo_amount(worker) == 10, "Stop interrupts work and retains carried resources")
	w = world()
	worker = engineer(w)
	var companion := w.add_unit("operator", worker.pos, 0)
	advance(w, 1)
	verify(worker.pos.distance_to(w.units[companion].pos) >= 0.28, "Local separation resolves overlapping workers")
	var obstruction := HexGrid.cell(worker.pos) + Vector2i(1, 0)
	w.known[0][obstruction] = true; w.tiles[obstruction].cliff = true
	verify(w.placement_issue(0, "depot", obstruction) == "Footprint is obstructed", "Placement preview detects blocked construction sites")
	w = world()
	var soldier := w.add_unit("marine", Vector2(4, 0), 0)
	var enemy := w.add_unit("scavenger", Vector2(5, 0), -1)
	w.visible[0] = w.flood(HexGrid.cell(Vector2(4, 0)), 5)
	w.units[soldier].target = enemy
	w._fire(w.units[soldier], "marine_rifle", 0.05)
	var after_hit: float = w.units[enemy].hp
	w.units[soldier].cooldown = 0
	w.visible[0] = {}
	w._fire(w.units[soldier], "marine_rifle", 0.05)
	verify(w.units[enemy].hp == after_hit and w.units[soldier].target == 0, "Concealment prevents new unit-target attacks")
	w.visible[0] = w.flood(HexGrid.cell(Vector2(4, 0)), 10)
	w.units[enemy].pos = Vector2(10, 0)
	w.units[soldier].target = enemy
	w._fire(w.units[soldier], "marine_rifle", 0.05)
	verify(w.units[soldier].target != enemy, "Defensive units abandon targets outside their home leash")
	w = world()
	worker = engineer(w)
	var prober := w.add_unit("scavenger", worker.pos + Vector2(0.6, 0), -1)
	w.units[prober].job = {"kind": "probe", "pressure": 0.0, "damage_tick": -999}
	w.units[prober].last_damage = 1
	w._probe_step(w.units[prober], 0.05)
	verify(w.units[prober].job.kind == "retreat" and w.units[prober].target == 0, "A damaged uncommitted probe retreats to Gloom")
	w.units.erase(prober)
	prober = w.add_unit("scavenger", worker.pos + Vector2(0.6, 0), -1)
	var ally := w.add_unit("scavenger", worker.pos + Vector2(0.8, 0.2), -1)
	w._probe_step(w.units[prober], float(w.cfg.lightless.probeResistanceWindowSeconds) + 0.1)
	verify(w.units[prober].job.kind == "attack" and w.units[ally].job.kind == "attack", "An unopposed probe recruits nearby Scavengers to apply pressure")
	var lit_cell := HexGrid.cell(worker.pos)
	verify(w.dark_navigation.get_point_weight_scale(w.point_ids[lit_cell]) == float(w.cfg.lightless.darkPathLightPenalty), "Non-attacking Lightless navigation heavily penalizes illuminated tiles")
	w.gloom.clear(); w.gloom[Vector2i.ZERO] = 20.0
	w._update_gloom(0.5)
	verify(w.gloom.size() == 2, "Gloom grows from connected existing tiles or its structure")
	var medusa_id := 0
	for s in w.structures.values():
		if s.kind == "medusa": medusa_id = s.id
	w.structures.erase(medusa_id)
	w._update_gloom(1)
	verify(w.gloom[Vector2i.ZERO] == 19.0, "Unsupported Gloom persists while withering")
	w._update_gloom(20)
	verify(w.gloom.is_empty(), "Unsupported Gloom eventually disappears")
	w = world(2)
	var foreign_worker := engineer(w)
	w.command(1, {"action": "move", "ids": [foreign_worker.id], "x": 0, "z": 0})
	verify(foreign_worker.job.kind == "idle", "An accepted player cannot command another player's unit")
	w.players[0].resources.nacre = 499
	w.command(0, {"action": "extract", "target": w.players[0].anchor})
	verify(not w.players[0].extracting, "Extraction rejects cargo below the Nacre threshold")
	w.players[0].resources.nacre = 500
	w.command(0, {"action": "extract", "target": w.players[0].anchor})
	advance(w, 89)
	verify(w.players[0].extracting and not w.ended, "Extraction survives until the full configured countdown")
	advance(w, 2)
	verify(w.ended and w.result == "Player 1 extracted successfully", "First completed extraction ends multiplayer")
	w = world()
	anchor = w.structures[int(w.players[0].anchor)]
	var depot_id := w.add_structure("depot", anchor.cell + Vector2i(3, 0), 0)
	w.players[0].resources.ore = 250
	verify(w.command(0, {"action": "depot_type", "target": depot_id, "resource": "gas"}) == "Cannot remove capacity below stored supply", "Depot rejects capacity loss below stored inventory")
	w.players[0].resources.ore = 80
	w.command(0, {"action": "depot_type", "target": depot_id, "resource": "gas"})
	verify(w.capacity(0, "ore") == 100 and w.capacity(0, "gas") == 100, "Reconfiguration removes old capacity before providing new capacity")
	advance(w, 5.1)
	verify(w.capacity(0, "gas") == 300, "New Depot capacity arrives after the configuration cooldown")
	w.command(0, {"action": "operator", "target": anchor.id})
	w.command(0, {"action": "cancel_operator", "target": anchor.id, "index": 0})
	verify(int(w.resources(0).ore) == 80, "An unstarted Operator order refunds its cost")
	w = world()
	anchor = w.structures[int(w.players[0].anchor)]
	var fabricator := w.add_structure("fabricator", anchor.cell + Vector2i(3, 0), 0)
	w.players[0].resources.alloy = 100; w.players[0].resources.polymer = 100
	w.command(0, {"action": "upgrade", "target": fabricator, "kind": "engineer"})
	w.command(0, {"action": "cancel_upgrade", "target": fabricator, "index": 0})
	verify(int(w.resources(0).alloy) == 100, "An unstarted upgrade refunds its purchase")
	w.command(0, {"action": "upgrade", "target": fabricator, "kind": "engineer"})
	worker = engineer(w)
	w.command(0, {"action": "work", "target": fabricator, "ids": [worker.id]})
	advance(w, 0.2)
	var progress_before: float = w.structures[fabricator].upgrades[0].progress
	w.structures[fabricator].enabled = false
	advance(w, 1)
	verify(w.structures[fabricator].upgrades[0].progress == progress_before, "Research pauses without power and retains its progress")
	var paid_alloy := int(w.resources(0).alloy)
	w.command(0, {"action": "cancel_upgrade", "target": fabricator, "index": 0})
	verify(int(w.resources(0).alloy) == paid_alloy, "An active upgrade cancels without refund")
	w.structures[fabricator].enabled = true
	w.command(0, {"action": "upgrade", "target": fabricator, "kind": "engineer"})
	var second_engineer := w.add_unit("engineer", worker.pos + Vector2(0, 0.3), 0)
	w.command(0, {"action": "work", "target": fabricator, "ids": [worker.id, second_engineer]})
	advance(w, 11)
	verify(w.players[0].upgrades.has("engineer"), "Two Engineers complete a twenty-work-second upgrade in eleven seconds")
	w._destroy(w.structures[fabricator])
	worker.hp = 80.0
	w._weapon_damage(worker, w.cfg.weapons.marine_rifle)
	verify(worker.hp == 73.0, "Completed armor upgrade survives Fabricator destruction and reduces damage")
	var new_worker := w.add_unit("engineer", worker.pos, 0)
	w._weapon_damage(w.units[new_worker], w.cfg.weapons.marine_rifle)
	verify(w.units[new_worker].hp == 73.0, "Armor upgrades also affect newly produced specialists")
	var kit_source := w.add_structure("armory", anchor.cell + Vector2i(3, 1), 0)
	w.structures[kit_source].kits.append({"kind": "marine", "progress": 8.0, "done": true})
	w.command(0, {"action": "equip", "target": kit_source, "ids": [worker.id]})
	advance(w, 0.2)
	verify(worker.kind == "engineer", "Specialized units cannot collect a different specialization")
	w = world()
	anchor = w.structures[int(w.players[0].anchor)]
	var cradle := w.add_structure("cradle", anchor.cell + Vector2i(3, -1), 0)
	var configured_armory := w.add_structure("armory", anchor.cell + Vector2i(3, 0), 0)
	w.command(0, {"action": "personnel_settings", "target": configured_armory, "source": anchor.id})
	w.command(0, {"action": "kit", "target": configured_armory, "kind": "marine"})
	verify(anchor.operators.size() == 1 and w.structures[cradle].operators.is_empty(), "Kits request personnel from the configured source instead of the nearest one")
	w.command(0, {"action": "personnel_settings", "target": configured_armory, "enabled": false})
	w.command(0, {"action": "kit", "target": configured_armory, "kind": "marine"})
	verify(anchor.operators.size() == 1 and w.structures[configured_armory].kits.size() == 2, "Disabling personnel requests queues only the kit")
	advance(w, 0.2)
	var ore_paid := int(w.resources(0).ore)
	w.command(0, {"action": "cancel_operator", "target": anchor.id, "index": 0})
	verify(int(w.resources(0).ore) == ore_paid, "Started Operator production cancels without refund")
	vehicle_checks()
	sensor_checks()
	gate_checks()
	config_checks()
	feedback_checks()
	route_order_checks()
	print("Simulation checks: ", assertions, "; failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)

func vehicle_checks() -> void:
	var w := world(2)
	w.units.clear(); w.structures.clear()
	for tile in w.tiles.values(): tile.cliff = false
	w._rebuild_navigation()
	var vehicle_id := w.add_unit("ranger", Vector2.ZERO, 0)
	var vehicle: Dictionary = w.units[vehicle_id]
	var driver_id := w.add_unit("operator", Vector2(0.2, 0), 0)
	var driver: Dictionary = w.units[driver_id]
	w.command(0, {"action": "move", "ids": [vehicle_id], "x": 4, "z": 0})
	advance(w, 0.2)
	verify(vehicle.pos == Vector2.ZERO, "An uncrewed vehicle cannot move")
	w.update_visibility()
	verify(w.illuminated[0].is_empty(), "Uncrewed vehicles emit no light")
	w.command(0, {"action": "board", "ids": [driver_id], "target": vehicle_id})
	advance(w, 0.1)
	verify(int(vehicle.driver) == driver_id and int(driver.vehicle) == vehicle_id, "First boarding unit becomes the driver")
	w.update_visibility()
	verify(not w.illuminated[0].is_empty(), "A driver activates vehicle lighting")
	w.command(0, {"action": "stop", "ids": [vehicle_id]})
	for i in range(3):
		var rider := w.add_unit("marine", vehicle.pos, 0)
		w.command(0, {"action": "board", "ids": [rider], "target": vehicle_id})
		advance(w, 0.1)
	var extra := w.add_unit("operator", vehicle.pos, 0)
	verify(vehicle.passengers.size() == 3 and not w.can_board(w.units[extra], vehicle_id), "Ranger passenger capacity is independent of its driver")
	w.command(0, {"action": "unload", "ids": [vehicle_id]})
	verify(vehicle.passengers.is_empty() and int(vehicle.driver) == driver_id, "First unload preserves the driver when passengers were aboard")
	w.command(0, {"action": "unload", "ids": [vehicle_id]})
	verify(int(vehicle.driver) == 0 and int(driver.vehicle) == 0, "Second unload releases the remaining driver")
	var enemy := w.add_unit("engineer", vehicle.pos, 1)
	verify(w.can_board(w.units[enemy], vehicle_id), "Enemies can commandeer an empty vehicle")
	w.command(1, {"action": "board", "ids": [enemy], "target": vehicle_id})
	advance(w, 0.1)
	verify(vehicle.owner == 1 and int(vehicle.driver) == enemy and not w.can_board(driver, vehicle_id), "Commandeering transfers ownership and occupied enemy vehicles reject boarding")
	w.units[enemy].hp = 27.0; w.units[enemy].cargo = {"ore": 3}; vehicle.cargo = {"ore": 90}
	w._weapon_damage(w.units[enemy], w.cfg.weapons.lancer_laser)
	verify(w.units[enemy].hp == 27, "Crew cannot be damaged separately while inside a vehicle")
	w._destroy(vehicle)
	verify(w.units.has(enemy) and w.units[enemy].hp == 27 and w.units[enemy].vehicle == 0 and w.cargo_amount(w.units[enemy]) == 3, "Vehicle destruction unloads living crew with current health and personal cargo")
	verify(not w.units.has(vehicle_id), "Destroyed vehicle cargo disappears with its carrier")
	vehicle_id = w.add_unit("ranger", Vector2(5, 0), 0); vehicle = w.units[vehicle_id]
	driver.pos = vehicle.pos; driver.cargo = {"ore": 8, "gas": 7}; vehicle.cargo = {"ore": 95}
	w.command(0, {"action": "load_cargo", "ids": [driver_id], "target": vehicle_id})
	advance(w, 0.1)
	verify(w.cargo_amount(vehicle) == 100 and w.cargo_amount(driver) == 10, "Mixed cargo transfer obeys a shared whole-number capacity and retains overflow")
	var storage := w.add_structure("depot", Vector2i(6, 0), 0, true, "ore")
	w.resources(0).ore = 0
	driver.cargo = {"ore": 3, "nacre": 2}
	w.command(0, {"action": "deposit", "ids": [driver_id], "target": storage})
	verify(driver.job.kind == "deposit", "Mixed Nacre cargo can still be directed to a Depot for ordinary-resource unloading")
	w._deposit_cargo(driver, w.structures[storage])
	verify(w.resources(0).ore == 3 and driver.cargo.nacre == 2, "Depots accept ordinary resources while retaining Nacre aboard")
	vehicle_id = w.add_unit("scout", Vector2(0, -5), 0); vehicle = w.units[vehicle_id]
	driver.pos = vehicle.pos; driver.cargo = {}; driver.job = {"kind": "idle"}
	w.command(0, {"action": "board", "ids": [driver_id], "target": vehicle_id}); advance(w, 0.1)
	var gunner := w.add_unit("marine", vehicle.pos, 0)
	w.command(0, {"action": "board", "ids": [gunner], "target": vehicle_id}); advance(w, 0.1)
	w.units[gunner].stance = "aggressive"; vehicle.stance = "neutral"
	var target_id := w.add_unit("ravager", vehicle.pos + Vector2(0, -2), -1)
	var target: Dictionary = w.units[target_id]; target.stance = "neutral"; target.job = {"kind": "riding"}
	var hp := float(target.hp)
	advance(w, 0.2)
	verify(target.hp == hp, "A Scout passenger follows the Scout's neutral stance even if personally aggressive")
	vehicle.stance = "defensive"; w.units[gunner].stance = "neutral"
	w.command(0, {"action": "move", "ids": [vehicle_id], "x": 4, "z": -5})
	advance(w, 0.5)
	verify(target.hp < hp and vehicle.pos.x > 0, "A defensive Scout's neutral passenger can fire while its vehicle moves")
	verify(w.units[gunner].stance == "neutral", "Boarding does not overwrite a passenger's personal stance")
	vehicle.heading = 0
	verify(w.unit_area(vehicle, true).has(HexGrid.cell(vehicle.pos + Vector2(0, -4))) and not w.unit_area(vehicle, true).has(HexGrid.cell(vehicle.pos + Vector2(0, 4))), "Scout headlights extend forward rather than behind")
	vehicle_id = w.add_unit("excavator", Vector2(5, 5), 0); vehicle = w.units[vehicle_id]
	w.unload_vehicle(w.units[int(driver.vehicle)], true); driver.pos = vehicle.pos
	w.command(0, {"action": "board", "ids": [driver_id], "target": vehicle_id}); advance(w, 0.1)
	var cliff := HexGrid.cell(vehicle.pos) + Vector2i(1, 0)
	w.tiles[cliff].cliff = true; w.tiles[cliff].rock_health = 1.0; w.known[0][cliff] = true
	w.tiles[cliff].resource = "ore"; w.tiles[cliff].amount = 123
	vehicle.cargo = {"ore": 249}
	w.command(0, {"action": "excavate", "ids": [vehicle_id], "q": cliff.x, "r": cliff.y}); advance(w, 0.1)
	verify(not w.tiles[cliff].cliff and w.tiles[cliff].rubble and not w.blocked(cliff), "Excavation clears collision and leaves buildable rubble")
	verify(w.cargo_amount(vehicle) == 250 and int(w.tiles[cliff].amount) == 123, "Cliff yields respect cargo capacity without consuming buried deposits")
	w.update_visibility()
	var replica := world(2)
	replica.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(not replica.tiles[cliff].cliff and replica.tiles[cliff].rubble and int(replica.units[vehicle_id].driver) == driver_id, "Snapshots preserve excavation and vehicle crew")
	w.eliminate(0)
	verify(int(vehicle.driver) == 0 and int(driver.vehicle) == 0, "Elimination unloads every vehicle occupant")
	w = world()
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var factory_id := w.add_structure("factory", anchor.cell + Vector2i(4, 0), 0)
	var factory: Dictionary = w.structures[factory_id]
	w.resources(0).ore = 500; w.resources(0).alloy = 100
	var before := int(w.resources(0).ore)
	w.command(0, {"action": "vehicle", "target": factory_id, "kind": "scout"})
	verify(factory.vehicles.size() == 1 and anchor.operators.size() == 1 and w.resources(0).ore == before - int(w.cfg.units.scout.cost.ore) - int(w.cfg.personnel.operatorCost.ore), "Factory orders pay for the vehicle and a separately queued requested Operator")
	w.command(0, {"action": "cancel_vehicle", "target": factory_id, "index": 0})
	verify(factory.vehicles.is_empty() and anchor.operators.size() == 1 and w.resources(0).ore == before - int(w.cfg.personnel.operatorCost.ore), "Unstarted vehicle cancellation refunds the vehicle without cancelling its separate personnel order")
	w.command(0, {"action": "vehicle", "target": factory_id, "kind": "scout", "personnel": false})
	factory.powered = false; w._production(factory, 1)
	verify(factory.vehicles[0].progress == 0, "Unpowered Factory production pauses without losing its order")
	factory.powered = true; w._production(factory, float(w.cfg.units.scout.productionSeconds))
	var produced := 0
	for unit in w.units.values():
		if unit.kind == "scout": produced += 1; verify(unit.driver == 0, "Factory vehicles await a driver instead of operating uncrewed")
	verify(produced == 1 and factory.vehicles.is_empty(), "A powered Factory completes its vehicle order")

	for cell in HexGrid.disk(anchor.cell + Vector2i(4, 0), 4):
		if w.tiles.has(cell): w.tiles[cell].cliff = false
	w._rebuild_navigation()
	w.command(0, {"action": "vehicle", "target": factory_id, "kind": "scout"})
	factory.powered = true
	w._production(factory, float(w.cfg.units.scout.productionSeconds))
	w._production(anchor, float(w.cfg.personnel.anchorOperatorSeconds))
	w._production(anchor, float(w.cfg.personnel.anchorOperatorSeconds))
	advance(w, 30)
	var crewed := false
	for unit in w.units.values():
		if unit.kind == "scout" and int(unit.driver) != 0: crewed = true
	verify(crewed, "Requested personnel wait for and automatically board their assigned Factory vehicle")

func sensor_checks() -> void:
	var w := world(2)
	w.units.clear(); w.structures.clear()
	for tile in w.tiles.values(): tile.cliff = false
	w._rebuild_navigation()
	var radar := w.add_structure("radar", Vector2i.ZERO, 0)
	var turret := w.add_structure("sentry", Vector2i(1, 0), 0)
	w.structures[radar].powered = true; w.structures[turret].powered = true
	var marine := w.add_unit("marine", Vector2(1, 0), 0)
	var enemy := w.add_unit("ravager", Vector2(3, 0), 1)
	var cell := HexGrid.cell(w.units[enemy].pos)
	w.visible[0] = {}; w.known[0] = {}; w.illuminated[0] = {}; w.illuminated[1] = {}
	WorldState.RadarSystem.update(w)
	verify(w.detected[0].has(cell) and w.visible[0].is_empty() and w.known[0].is_empty(), "Radar detects occupied tiles without revealing vision or terrain")
	verify(WorldState.TargetRules.targetable(w, w.structures[turret], w.units[enemy]) and not WorldState.TargetRules.targetable(w, w.units[marine], w.units[enemy]), "Turrets can use radar in darkness; infantry still need vision")
	var packet := w.snapshot(0)
	verify(packet.units.size() == 1 and packet.contacts.size() == 1, "Radar-only snapshots expose contact tiles without enemy identities")
	w.command(0, {"action": "attack_tile", "ids": [turret], "q": cell.x, "r": cell.y})
	verify(int(w.structures[turret].target) == enemy, "Turrets accept manual radar-contact target overrides")
	w._fire(w.structures[turret], "sentry_gun", 1)
	verify(w.units[enemy].hp < float(w.cfg.units.ravager.health), "A radar-targeted turret actually damages an eligible dark target")
	var shade := w.add_unit("shade", Vector2(4, 0), 1)
	var shade_cell := HexGrid.cell(w.units[shade].pos)
	WorldState.RadarSystem.update(w)
	verify(not w.detected[0].has(shade_cell), "Shades are invisible to radar")
	w.visible[0][shade_cell] = true; w.known[0][shade_cell] = true
	verify(not WorldState.TargetRules.identifiable(w, w.units[shade], 0), "Vision without illumination cannot reveal a Shade")
	w.illuminated[1][shade_cell] = true
	verify(WorldState.TargetRules.identifiable(w, w.units[shade], 0) and WorldState.TargetRules.targetable(w, w.units[marine], w.units[shade]), "Enemy light can illuminate a visible Shade without granting vision")
	var replica := world(2)
	replica.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(replica.units.has(shade) and WorldState.TargetRules.identifiable(replica, replica.units[shade], 0), "Snapshots preserve shared illumination eligibility")
	w.visible[0].erase(shade_cell)
	verify(not WorldState.TargetRules.targetable(w, w.structures[turret], w.units[shade]), "Illumination without vision still cannot target a Shade")
	var thresher := w.add_unit("thresher", Vector2(2, 2), 0)
	var t: Dictionary = w.units[thresher]
	w.command(0, {"action": "burrow", "ids": [thresher]})
	w._unit_step(t, 1)
	verify(not t.get("buried", false) and t.transition == "burrow", "A Thresher remains above ground until its transition completes")
	w.command(0, {"action": "move", "ids": [thresher], "x": 8, "z": 0})
	verify(t.transition == "burrow" and t.route.is_empty(), "Move orders cannot interrupt burrowing")
	w._unit_step(t, 1)
	verify(t.buried and WorldState.BurrowRules.weapon(w, t) == "thresher_tentacle", "Burrowing completion changes concealment and weapon together")
	var original: Vector2 = t.pos
	w.move_to(t, Vector2(8, 0)); w._move(t, 1)
	verify(t.pos == original, "Buried Threshers cannot move")
	var hp := float(t.hp)
	w._weapon_damage(t, w.cfg.weapons.flamer_flame)
	verify(t.hp == hp, "Buried units are immune to area damage")
	w._weapon_damage(t, w.cfg.weapons.marine_rifle)
	verify(t.hp < hp, "Unit-target damage can hurt buried units")
	t.owner = 1
	var t_cell := HexGrid.cell(t.pos)
	WorldState.RadarSystem.update(w); w.visible[0].erase(t_cell)
	verify(WorldState.TargetRules.targetable(w, w.structures[turret], t) and not WorldState.TargetRules.targetable(w, w.units[marine], t), "Buried targets require radar, plus vision for infantry")
	w.visible[0][t_cell] = true
	verify(WorldState.TargetRules.targetable(w, w.units[marine], t), "Infantry can target a buried Thresher with vision and detection")
	var flamer := w.add_unit("flamer", Vector2(1, 1), 0)
	verify(not WorldState.TargetRules.targetable(w, w.units[flamer], t), "Area weapons cannot select buried unit targets")
	t.owner = 0; w.command(0, {"action": "burrow", "ids": [thresher]})
	w._unit_step(t, float(w.cfg.combat.thresherEmergeSeconds))
	verify(not t.buried and WorldState.BurrowRules.weapon(w, t) == "thresher_melee", "Emerging restores normal targeting and melee")
	var first := w.add_structure("rampart", Vector2i(0, 2), 0)
	var second := w.add_structure("rampart", Vector2i(1, 2), 0)
	w.structures[first].powered = true; w.structures[second].powered = true
	verify(WorldState.TargetRules.shield_bonus(w, w.structures[turret]) == int(w.cfg.combat.rampartArmorBonus), "Overlapping Ramparts apply one fixed armor bonus")
	verify(WorldState.TargetRules.shield_bonus(w, w.units[marine]) == 0, "Ramparts protect structures rather than infantry")
	hp = float(w.structures[turret].hp)
	w._weapon_damage(w.structures[turret], w.cfg.weapons.marine_rifle)
	verify(hp - float(w.structures[turret].hp) == maxf(0, float(w.cfg.weapons.marine_rifle.damagePerHit) - float(w.cfg.structures.sentry.armor) - float(w.cfg.combat.rampartArmorBonus)), "Shield armor participates in actual damage resolution")
	w.structures[first].enabled = false; w.structures[second].powered = false
	verify(WorldState.TargetRules.shield_bonus(w, w.structures[turret]) == 0, "Unpowered or disabled Ramparts stop protecting structures immediately")
	w.structures[radar].powered = false
	WorldState.RadarSystem.update(w)
	verify(w.detected[0].is_empty(), "Unpowered radar loses all contacts")
	var scout := w.add_unit("scout", Vector2.ZERO, 0)
	WorldState.RadarSystem.update(w)
	verify(w.detected[0].is_empty(), "Uncrewed Scouts cannot detect")
	w.units[scout].driver = marine; w.units[marine].vehicle = scout
	WorldState.RadarSystem.update(w)
	verify(w.detected[0].has(cell), "A driven Scout supplies detection")
	w.unload_vehicle(w.units[scout], true)
	verify(w.detected[0].is_empty(), "Unloading a Scout driver removes its detection")

func gate_checks() -> void:
	var w := world(2)
	w.units.clear(); w.structures.clear()
	for cell in w.tiles: w.tiles[cell].cliff = cell.y != 0
	var gate_id := w.add_structure("gate", Vector2i.ZERO, 0)
	var gate: Dictionary = w.structures[gate_id]
	w._rebuild_navigation()
	var worker := w.add_unit("operator", HexGrid.world(Vector2i(-3, 0)), 0)
	w.command(0, {"action": "move", "ids": [worker], "x": HexGrid.world(Vector2i(3, 0)).x, "z": 0})
	verify(w.units[worker].route.any(func(point): return HexGrid.cell(point) == Vector2i.ZERO), "Friendly routes can traverse closed unlocked gates")
	advance(w, 8)
	verify(w.units[worker].pos.x > 2.9, "A routed worker opens and passes through an automatic gate")
	advance(w, 2)
	verify(not gate.open and not gate.locked, "Automatic gates close after traffic clears without locking")
	w.command(0, {"action": "gate", "target": gate_id})
	advance(w, 3)
	verify(gate.open, "Manually opened gates remain open without traffic")
	w.command(0, {"action": "gate", "target": gate_id})
	w.command(0, {"action": "gate_lock", "target": gate_id})
	w.command(0, {"action": "move", "ids": [worker], "x": HexGrid.world(Vector2i(-3, 0)).x, "z": 0})
	advance(w, 8)
	verify(gate.locked and not gate.open and w.units[worker].pos.x > 0, "Locked closed gates prevent automatic passage")
	w.command(0, {"action": "gate_lock", "target": gate_id})
	var enemy := w.add_unit("operator", HexGrid.world(Vector2i(-3, 0)), 1)
	w.command(1, {"action": "move", "ids": [enemy], "x": HexGrid.world(Vector2i(3, 0)).x, "z": 0})
	advance(w, 8)
	verify(not gate.open and w.units[enemy].pos.x < 0, "Enemies cannot automatically open another player's gate")
	verify(w.blocks_sight(Vector2i.ZERO), "Closed gates block vision and light")
	w.command(0, {"action": "gate", "target": gate_id})
	verify(not w.blocks_sight(Vector2i.ZERO), "Open gates permit vision and light propagation")

func config_checks() -> void:
	verify(ConfigRules.validate(settings).is_empty(), "Shipped configuration validates before starting the game")
	var changed: Dictionary = ConfigRules.merged(settings, {"units": {"marine": {"armor": 7}}})
	verify(changed.units.marine.armor == 7 and settings.units.marine.armor == 1 and changed.units.marine.health == settings.units.marine.health, "Config patches merge recursively without mutating base definitions")
	changed.units.marine.weapon = "missing_weapon"
	verify(ConfigRules.validate(changed).any(func(error): return error.contains("units.marine.weapon")), "Configuration errors identify broken references by JSON path")
	changed = settings.duplicate(true); changed.units.ranger.cargoCapacity = 1.5
	verify(ConfigRules.validate(changed).any(func(error): return error.contains("units.ranger.cargoCapacity")), "Fractional cargo capacities fail validation")
	changed = settings.duplicate(true); changed.camera.defaultDistanceTiles += 1
	verify(ConfigRules.gameplay_hash(changed) == ConfigRules.gameplay_hash(settings), "Camera tuning does not break multiplayer gameplay compatibility")
	changed = settings.duplicate(true); changed.combat.rampartArmorBonus += 1
	verify(ConfigRules.gameplay_hash(changed) != ConfigRules.gameplay_hash(settings), "Mechanics tuning changes the multiplayer gameplay hash")

	changed = settings.duplicate(true); changed.targeting.unitRules.shade.requiresIllumination = "false"
	verify(ConfigRules.validate(changed).any(func(error): return error.contains("targeting.unitRules.shade.requiresIllumination")), "String booleans cannot silently change concealment rules")
	changed = settings.duplicate(true); changed.weapons.marine_rifle = null
	verify(ConfigRules.validate(changed).any(func(error): return error.contains("weapons.marine_rifle")), "Malformed weapon definitions return validation errors instead of crashing")

func feedback_checks() -> void:
	var w := world(2)
	w.units.clear(); w.structures.clear()
	for tile in w.tiles.values(): tile.cliff = false
	var shooter := w.add_unit("marine", Vector2.ZERO, 0)
	var target := w.add_unit("ravager", Vector2(2, 0), 1)
	var cell := HexGrid.cell(w.units[target].pos)
	w.visible[0] = {cell: true}; w.known[0] = {cell: true}
	w.units[shooter].target = target; w.units[shooter].job = {"kind": "attack"}
	w._fire(w.units[shooter], "marine_rifle", 0.05)
	var cursor := int(w.feedback_for(0).back().serial)
	verify(w.feedback_for(0).any(func(event): return event.kind == "fire") and w.feedback_for(0).any(func(event): return event.kind == "hit"), "Actual attacks emit fire and damage feedback")
	w.step(0.05)
	verify(w.shots.is_empty() and w.feedback_for(0).any(func(event): return event.kind == "fire"), "Feedback survives simulation ticks that clear transient shots")
	verify(w.feedback_for(0, cursor).is_empty(), "Independent feedback cursors do not replay consumed events")
	w.visible[0] = {}
	w._weapon_damage(w.units[target], w.cfg.weapons.flamer_flame)
	verify(w.feedback_for(0, cursor).is_empty(), "Damage to concealed enemies does not leak hit feedback")
	var packet := JSON.parse_string(JSON.stringify(w.snapshot(0))) as Dictionary
	verify(not packet.feedback.any(func(event): return event.has("audience")), "Snapshots do not expose feedback audience metadata")
	var replica := world(2)
	replica.apply_snapshot(packet, 0)
	var fire: Dictionary = replica.feedback_for(0).filter(func(event): return event.kind == "fire")[0]
	verify(fire.from is Vector2 and fire.to is Vector2 and fire.at is Vector2, "Feedback positions round-trip through JSON snapshots")
	var replica_cursor := int(replica.feedback_for(0).back().serial)
	replica.apply_snapshot(packet, 0)
	verify(replica.feedback_for(0, replica_cursor).is_empty(), "Repeated snapshots cannot replay effects past a consumer cursor")
	w.cfg.presentation.feedback.eventHistoryLimit = 3
	for i in range(8): w.emit_feedback("deposit", Vector2.ZERO, {"owner": 0, "amount": 1}, [0])
	verify(w.feedback_events.size() == 3 and int(w.feedback_events.back().serial) > cursor, "Feedback history is bounded while serial IDs remain monotonic")
	verify(WorldState.FeedbackRules.profile(w.cfg, "lance_laser").visual == "laser" and WorldState.FeedbackRules.profile(w.cfg, "flamer_flame").visual == "flame", "Weapon feedback uses configurable profiles rather than weapon-name substrings")
	w.reset(472, 1)
	verify(w.feedback_events.is_empty() and w.feedback_serial == 0, "Starting a new match resets presentation event history")

func route_order_checks() -> void:
	var w := world(2)
	w.units.clear(); w.structures.clear()
	for tile in w.tiles.values(): tile.cliff = false
	w._rebuild_navigation()
	var worker := w.add_unit("operator", Vector2.ZERO, 0)
	w.command(0, {"action": "patrol", "ids": [worker], "x": 4, "z": 0})
	advance(w, 2.7)
	verify(w.units[worker].job.kind == "patrol" and w.units[worker].job.leg == 0, "Patrol turns around at its far waypoint")
	advance(w, 3)
	verify(w.units[worker].job.leg == 1, "Patrol repeats instead of ending after a return trip")
	w.command(0, {"action": "move", "ids": [worker], "x": 1, "z": 0})
	verify(w.units[worker].job.kind == "move", "A manual order permanently replaces patrol")
	var leader := w.add_unit("operator", Vector2(2, 0), 0)
	var guard := w.add_unit("marine", Vector2.ZERO, 0)
	w.command(0, {"action": "escort", "ids": [guard], "target": leader})
	w.command(0, {"action": "move", "ids": [leader], "x": 8, "z": 0})
	advance(w, 6)
	verify(w.units[guard].job.kind == "escort" and w.units[guard].home.x > 6 and w.units[guard].pos.distance_to(w.units[guard].home) < 0.6, "Escort follows the target with a moving intended position")
	verify(absf(w.units[leader].pos.x - 8) < 0.05, "Escorts do not push a stopped leader away by chasing a slot in front of it")
	var before: Dictionary = w.units[guard].job.duplicate(true)
	w.command(0, {"action": "escort", "ids": [guard], "target": guard})
	verify(w.units[guard].job == before, "Self-escort is rejected without replacing existing orders")
	var enemy := w.add_unit("ravager", Vector2(10, 0), 1)
	w.command(0, {"action": "escort", "ids": [guard], "target": enemy})
	verify(w.units[guard].job == before, "Enemy targets cannot hijack an escort command")
	var replica := world(2)
	replica.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(replica.units[guard].job.offset is Array and replica.units[guard].job.kind == "escort", "Persistent routing orders round-trip through snapshots")
	w.units.erase(leader); advance(w, 0.1)
	verify(w.units[guard].job.kind == "idle", "Escorts stop cleanly when their target disappears")
	w = world(2); w.units.clear(); w.structures.clear()
	for tile in w.tiles.values(): tile.cliff = false
	w._rebuild_navigation()
	var patrol := w.add_unit("marine", Vector2.ZERO, 0)
	var intruder := w.add_unit("ravager", Vector2(1, 1), 1)
	w.update_visibility()
	w.command(0, {"action": "patrol", "ids": [patrol], "x": 8, "z": 0})
	advance(w, 0.1)
	verify(int(w.units[patrol].target) == intruder, "A defensive patrol engages enemies near its current path, not just near the far waypoint")
	w.units[intruder].pos = Vector2(12, 8); w.update_visibility(); advance(w, 6)
	verify(w.units[patrol].job.kind == "patrol" and w.units[patrol].pos.x > 1, "Patrol resumes after a target becomes concealed and its local search ends")
	var config := settings.duplicate(true)
	config.controls.commands.attack = "V"
	verify(ConfigRules.gameplay_hash(config) == ConfigRules.gameplay_hash(settings), "Local keybind changes do not split multiplayer gameplay compatibility")

