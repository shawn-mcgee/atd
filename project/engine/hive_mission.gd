extends RefCounted
## The carrier is the single source of truth; boarding keeps the item with its owner.
const Structure = preload("res://engine/expedition_structure.gd")
const EXTRACTION_TIME := 60.0
const EXTRACTION_RADIUS := 7.0
var beacon: SimStructure
var hive: SimStructure
var item: SimEntity
var carrier: SimUnit
var beacon_discovered := false
var hive_discovered := false
var stolen := false
var dropped := false
var extraction := 0.0
var swarm_clock := 0.0

func setup(game) -> void:
	beacon = game.add_structure("beacon", game.layout.beacon_position, false)
	beacon.funded = true; beacon.visible = false
	hive = Structure.new(); hive.setup("hive", game.layout.hive_position, true); game.register_entity(hive); hive.visible = false
	item = SimEntity.new(); item.position = hive.position + Vector3(0, 1, 0); game.register_entity(item); item.visible = false
	game.director.add_group(hive.position, 80, 6)

func take(game, unit: SimUnit) -> bool:
	if unit.is_vehicle() or unit.aboard != null or unit.hp <= 0: return false
	if not stolen and not beacon.complete:
		game.notify("Repair the extraction beacon before stealing the Hive Core"); return false
	if SimEntity.valid(carrier): return false
	carrier = unit; stolen = true; dropped = false; swarm_clock = 0
	game.notify("Hive Core secured / Lightless swarms inbound / reach extraction")
	return true

func drop(unit: SimUnit) -> void:
	if carrier != unit: return
	item.position = unit.position + Vector3.UP * 0.5
	carrier = null; dropped = true; extraction = 0

func tick(game, dt: float) -> void:
	if not beacon_discovered and game.light.sample(beacon.position) > 0.05:
		beacon_discovered = true; game.notify("Extraction beacon discovered / repair it with an engineer")
	if not hive_discovered and game.light.sample(hive.position) > 0.05:
		hive_discovered = true; game.notify("Lightless Hive discovered / secure extraction before taking the core")
	beacon.visible = beacon_discovered and game.light.sample(beacon.position) > 0.05
	hive.visible = hive_discovered and game.light.sample(hive.position) > 0.05
	item.visible = stolen or (hive_discovered and game.light.sample(item.position) > 0.05)
	if beacon.hp <= 0:
		beacon.hp = 1; beacon.complete = false; beacon.progress = 0; extraction = 0; beacon.state_changed()
		game.notify("Extraction beacon destroyed / repair it to restart extraction")
	if SimEntity.valid(carrier) and carrier.hp <= 0: drop(carrier)
	if SimEntity.valid(carrier):
		item.position = (carrier.aboard.position if SimEntity.valid(carrier.aboard) else carrier.position) + Vector3.UP * 2
	for unit in game.units:
		if unit.order != "take_core": continue
		if unit.position.distance_to(item.position) < 3.2:
			take(game, unit); unit.order = "idle"; unit.path.clear()
		elif not unit.moving(): unit.travel(item.position, game.navigation)
	if dropped:
		for enemy in game.creatures:
			if enemy.hp > 0 and enemy.position.distance_to(item.position) < 2:
				game.finish(false, "The Lightless recovered the Hive Core."); return
	var inside := SimEntity.valid(carrier) and item.position.distance_to(beacon.position + Vector3.UP * 2) <= EXTRACTION_RADIUS
	if stolen and beacon.complete and beacon.hp > 0 and inside:
		extraction += dt
		if extraction >= EXTRACTION_TIME: game.finish(true, "Hive Core extracted. The expedition made it home.")
	else: extraction = 0
	if stolen:
		swarm_clock += dt
		if swarm_clock >= 7.5:
			swarm_clock = 0
			for group in game.director.groups:
				group.population = maxi(int(group.population), 6)
				game.director.spawn_member(game, group)

func destination() -> Vector3:
	return item.position if stolen else hive.position

func describe() -> String:
	return "%s\n%s\nExtract: %.0f / %.0fs" % ["[x] Extraction repaired" if beacon.complete else "[ ] Repair extraction beacon" if beacon_discovered else "[?] Scout for extraction", "[x] Hive Core secured" if stolen else "[ ] Steal Hive Core" if hive_discovered else "[?] Scout for the Lightless Hive", extraction, EXTRACTION_TIME]

func map_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if beacon_discovered: result.append({"point": beacon.position, "name": "EX", "color": Color("efbd77")})
	if hive_discovered or stolen: result.append({"point": item.position, "name": "CORE", "color": Color("cb7de4")})
	return result
