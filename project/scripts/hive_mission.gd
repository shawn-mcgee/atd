extends RefCounted
## The carrier is the single source of truth; boarding keeps the item with its owner.
const Visual = preload("res://scripts/expedition_visuals.gd")
const Structure = preload("res://scripts/expedition_structure.gd")
const EXTRACTION_TIME := 30.0
const EXTRACTION_RADIUS := 7.0
var beacon: ExpeditionStructure
var hive: ExpeditionStructure
var item: Node3D
var carrier: ExpeditionUnit
var stolen := false
var dropped := false
var extraction := 0.0
var swarm_clock := 0.0

func setup(game) -> void:
	beacon = game.add_structure("beacon", Vector3(-45, 0, 14), false)
	beacon.funded = true
	hive = Structure.new(); hive.setup("hive", Vector3(64, 0, -42), true); game.add_child(hive); hive.visible = false
	item = (load("res://scenes/props/power_relay.tscn") as PackedScene).instantiate()
	item.scale = Vector3.ONE * 0.25; item.position = hive.position + Vector3(0, 1, 0); game.add_child(item)
	Visual.paint(item, Visual.material(Color("cb7de4"), true))
	var ring := Visual.ring(beacon, EXTRACTION_RADIUS, Color("efbd77")); ring.position.y = 0.12
	game.director.add_group(hive.position, 80, 6)

func register(game) -> void:
	if game.picker != null: game.picker.register_actor(hive)
	if game.occluded_units != null: game.occluded_units.register_occluder(hive)

func take(game, unit: ExpeditionUnit) -> bool:
	if unit.is_vehicle() or unit.aboard != null or unit.hp <= 0: return false
	if not stolen and not beacon.complete:
		game.notify("Repair the extraction beacon before stealing the Hive Core"); return false
	if is_instance_valid(carrier): return false
	carrier = unit; stolen = true; dropped = false; swarm_clock = 0
	game.notify("Hive Core secured / Lightless swarms inbound / reach extraction")
	return true

func drop(unit: ExpeditionUnit) -> void:
	if carrier != unit: return
	item.position = unit.position + Vector3.UP * 0.5
	carrier = null; dropped = true; extraction = 0

func tick(game, dt: float) -> void:
	if beacon.hp <= 0:
		beacon.hp = 1; beacon.complete = false; beacon.progress = 0; extraction = 0; beacon.update_visual()
		game.notify("Extraction beacon destroyed / repair it to restart extraction")
	if is_instance_valid(carrier) and carrier.hp <= 0: drop(carrier)
	if is_instance_valid(carrier):
		item.position = (carrier.aboard.position if is_instance_valid(carrier.aboard) else carrier.position) + Vector3.UP * 2
	for unit in game.units:
		if unit.order != "take_core": continue
		if unit.position.distance_to(item.position) < 3.2:
			take(game, unit); unit.order = "idle"; unit.path.clear()
		elif not unit.moving(): unit.travel(item.position, game.navigation)
	if dropped:
		for enemy in game.creatures:
			if enemy.hp > 0 and enemy.position.distance_to(item.position) < 2:
				game.finish(false, "The Lightless recovered the Hive Core."); return
	var inside := is_instance_valid(carrier) and item.position.distance_to(beacon.position + Vector3.UP * 2) <= EXTRACTION_RADIUS
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
	return "%s Repair extraction beacon\n%s Steal Hive Core\nExtract: %.0f / %.0fs\nKeep the carrier inside the beacon radius" % ["[x]" if beacon.complete else "[ ]", "[x]" if stolen else "[ ]", extraction, EXTRACTION_TIME]
