extends SceneTree

const ConfigRules = preload("res://scripts/settings.gd").ConfigRules

class CountingWorld:
	extends WorldState
	var path_queries := 0
	func _route_path(unit: Dictionary, start: Vector2i, finish: Vector2i, partial: bool = false) -> PackedVector2Array:
		path_queries += 1
		return super._route_path(unit, start, finish, partial)

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
	state.lightless_brain_time = -10000.0
	return state

func advance(state: WorldState, seconds: float) -> void:
	for i in range(ceili(seconds * 20)): state.step(0.05)

func engineer(state: WorldState) -> Dictionary:
	for u in state.units.values():
		if u.kind == "engineer" and u.owner == 0: return u
	return {}

func queued_order_checks() -> void:
	var w := movement_world()
	var id := w.add_unit("engineer", Vector2.ZERO, 0)
	var u: Dictionary = w.units[id]
	w.command(0, {"action": "move", "ids": [id], "x": 2, "z": 0})
	w.command(0, {"action": "move", "ids": [id], "x": 4, "z": 0, "queued": true})
	verify(u.job.kind == "move" and u.home.x == 2 and u.orders.size() == 1, "Shift orders append without replacing the active route")
	advance(w, 3)
	verify(u.pos.distance_to(Vector2(4, 0)) < 0.1 and u.orders.is_empty(), "A completed move dispatches the next queued move")
	w.cfg.movement.orderQueueLimit = 2
	for x in [5, 6, 7]: w.command(0, {"action": "move", "ids": [id], "x": x, "z": 0, "queued": true})
	verify(u.orders.size() == 2, "The host bounds each unit's queued orders")
	w.command(0, {"action": "stance", "ids": [id], "stance": "defensive"})
	verify(u.orders.size() == 2, "Changing stance preserves queued work")
	w.command(0, {"action": "move", "ids": [id], "x": -2, "z": 0})
	verify(u.orders.is_empty(), "An ordinary replacement order discards the previous plan")
	w.command(0, {"action": "move", "ids": [id], "x": 4, "z": 0, "queued": true})
	w.command(0, {"action": "stop", "ids": [id]})
	verify(u.job.kind == "idle" and u.orders.is_empty() and u.route.is_empty(), "Stop clears active and queued orders")
	var enemy := w.add_unit("marine", Vector2(2, 1), 1)
	w.command(0, {"action": "move", "ids": [enemy], "x": 4, "z": 0, "queued": true})
	verify(w.units[enemy].orders.is_empty(), "Queued orders cannot control another player's units")
	w.command(0, {"action": "move", "ids": [id], "x": 3, "z": 0, "queued": true})
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot(0)))
	var client := WorldState.new(w.cfg); client.reset(472, 2); client.apply_snapshot(snapshot, 0)
	verify(client.units[id].orders.size() == 1, "Owned queued orders survive browser snapshot serialization")
	w = movement_world(); id = w.add_unit("marine", Vector2.ZERO, 0); u = w.units[id]
	enemy = w.add_unit("marine", Vector2(2, 0), 1)
	w.visible[0] = {HexGrid.cell(Vector2(2, 0)): true}
	w.command(0, {"action": "attack", "ids": [id], "target": enemy, "queued": true})
	w.command(0, {"action": "move", "ids": [id], "x": 4, "z": 0, "queued": true})
	w.visible[0].clear(); w.step(0.05)
	verify(u.target != enemy and u.job.kind == "move" and u.orders.is_empty(), "Queued attacks recheck visibility and advance safely when their target disappears")
	w = movement_world(); id = w.add_unit("engineer", Vector2.ZERO, 0); u = w.units[id]
	w.cfg.units.engineer.speedTilesPerSecond = 10
	w.cfg.construction.engineerHealthPerSecond = 1000
	for cell in [Vector2i(2, 0), Vector2i(4, 0)]: w.known[0][cell] = true
	w.command(0, {"action": "move", "ids": [id], "x": 1, "z": 0})
	var ore := int(w.resources(0).ore)
	for q in [2, 4]: w.command(0, {"action": "build", "kind": "depot", "q": q, "r": 0, "ids": [id], "queued": true})
	verify(w.structures.size() == 2 and u.orders.size() == 2 and int(w.resources(0).ore) == ore - 2 * int(w.cfg.structures.depot.cost.ore), "Queued construction places and pays for every blueprint immediately")
	advance(w, 4)
	verify(w.structures.values().all(func(s): return s.built) and u.orders.is_empty(), "Engineers finish multiple Shift-queued construction sites in order")
	w = world(2)
	w.command(0, {"action": "global_personnel", "enabled": false})
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var armory := w.add_structure("armory", anchor.cell + Vector2i(3, 0), 0)
	verify(not w.structures[armory].request_personnel and w.players[1].request_personnel, "Global Operator setting applies to future friendly facilities without changing opponents")
	w.command(0, {"action": "kit", "target": armory, "kind": "marine"})
	verify(anchor.operators.is_empty() and w.structures[armory].kits.size() == 1, "Global off queues kits without automatically requesting personnel")
	w.command(0, {"action": "global_personnel", "enabled": true})
	w.command(0, {"action": "kit", "target": armory, "kind": "marine"})
	verify(anchor.operators.size() == 1 and w.structures[armory].kits.size() == 2, "Global on affects new orders and leaves existing kit orders unchanged")

func performance_cache_checks() -> void:
	var w := movement_world()
	var unit := w.add_unit("operator", Vector2(-2, 0), 0)
	var gate := w.add_structure("gate", Vector2i.ZERO, 0)
	w._rebuild_navigation()
	for i in range(2): verify(not WorldState.RouteNavigation.clear_segment(w, w.units[unit], Vector2(-1, 0), Vector2(1, 0)), "Warm collision caches retain closed gates")
	w.command(0, {"action": "gate", "target": gate})
	verify(WorldState.RouteNavigation.clear_segment(w, w.units[unit], Vector2(-1, 0), Vector2(1, 0)), "Opening a gate invalidates cached collision neighborhoods")
	w.command(0, {"action": "gate", "target": gate})
	verify(not WorldState.RouteNavigation.clear_segment(w, w.units[unit], Vector2(-1, 0), Vector2(1, 0)), "Closing a gate invalidates cached clear paths")
	var point := HexGrid.world(Vector2i(0, 3))
	verify(WorldState.RouteNavigation.clear_segment(w, w.units[unit], point, point + Vector2(0.1, 0)), "An empty infantry neighborhood admits same-cell movement")
	w.tiles[Vector2i(0, 3)].cliff = true; w._rebuild_navigation()
	verify(not WorldState.RouteNavigation.clear_segment(w, w.units[unit], point, point + Vector2(0.1, 0)), "A new obstacle invalidates the open-cell fast path")
	w = movement_world()
	var first := w.add_unit("marine", Vector2(-2, 2), 0)
	var second := w.add_unit("marine", Vector2(2, 2), 0)
	w._separate_units(0.05); w._separate_units(0.05)
	w.units[second].pos = w.units[first].pos
	w._separate_units(0.05)
	verify(w.units[first].pos.distance_to(w.units[second].pos) > 0, "Moving a unit invalidates stationary separation reuse")
	w = movement_world()
	var radar := w.add_structure("radar", Vector2i.ZERO, 0)
	w.structures[radar].powered = true
	var contact := w.add_unit("scavenger", HexGrid.world(Vector2i(2, 0)), -1)
	WorldState.RadarSystem.update(w); WorldState.RadarSystem.update(w)
	verify(w.detected[0].has(Vector2i(2, 0)), "Cached Radar coverage still reports hostile occupied cells")
	w.units[contact].pos = HexGrid.world(Vector2i(3, 0)); WorldState.RadarSystem.update(w)
	verify(not w.detected[0].has(Vector2i(2, 0)) and w.detected[0].has(Vector2i(3, 0)), "Cached coverage does not freeze moving Radar contacts")
	w.structures[radar].powered = false; WorldState.RadarSystem.update(w)
	verify(w.detected[0].is_empty(), "Power loss invalidates Radar coverage immediately")

func medusa_spawn_checks() -> void:
	var config: Dictionary = world().cfg
	var locations: Dictionary = {}
	for map_seed in [1, 2, 3, 7, 91, 472]:
		for count in [1, 5]:
			var w := WorldState.new(config); w.reset(map_seed, count)
			var medusa: Dictionary = {}
			for s in w.structures.values():
				if s.kind == "medusa": medusa = s
			var corners: Array[Vector2i] = []
			for direction in HexGrid.DIRECTIONS: corners.append(direction * (w.radius - int(config.map.anchorEdgeInsetTiles)))
			verify(medusa.cell in corners and medusa.cell != Vector2i.ZERO, "Medusa starts at an inset corner (seed %d, players %d)" % [map_seed, count])
			locations[medusa.cell] = true
			for owner in w.players:
				var anchor: Dictionary = w.structures[int(w.players[owner].anchor)]
				verify(anchor.cell != medusa.cell and not w.structure_visible(owner, medusa), "Medusa has a separate undiscovered corner for player %d" % owner)
				var from := w.nearest_free(anchor.cell); var to := w.nearest_free(medusa.cell)
				verify(not w.navigation.get_point_path(w.point_ids[from], w.point_ids[to]).is_empty(), "A player can reach the corner nest without excavation")
			var nearby_scavengers := 0
			for u in w.units.values():
				if u.owner < 0 and u.kind == "scavenger" and HexGrid.distance(HexGrid.cell(u.pos), medusa.cell) == 2: nearby_scavengers += 1
			verify(nearby_scavengers == int(config.lightless.startingScavengers), "Starting Scavengers follow the corner nest")
			var valid_gloom := w.gloom.has(medusa.cell)
			for cell in w.gloom:
				if not w.tiles.has(cell): valid_gloom = false
			verify(valid_gloom, "Initial Gloom follows the nest and stays inside the map")
	verify(locations.size() > 1, "Different seeds choose different nest corners")
	var w := WorldState.new(config); w.reset(472, 1)
	var medusa: Dictionary = {}
	for s in w.structures.values():
		if s.kind == "medusa": medusa = s
	var site: Vector2i = medusa.cell
	var center_resource: String = w.tiles[Vector2i.ZERO].resource
	w._destroy(medusa)
	verify(w.corpse == site and w.tiles[site].resource == "nacre" and w.tiles[Vector2i.ZERO].resource == center_resource, "Medusa death creates Nacre at the actual nest, leaving the center alone")
	var client := WorldState.new(config); client.reset(472, 1)
	client.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(client.medusa_dead and client.corpse == null and client.tiles[Vector2i.ZERO].resource == center_resource, "An undiscovered death does not reveal a corpse or create central Nacre on clients")
	w.known[0][site] = true; w.visible[0][site] = true
	client.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(client.corpse == site and client.tiles[site].resource == "nacre" and client.tiles[site].amount == w.tiles[site].amount, "Scouting the remains synchronizes their location and infinite Nacre supply")
	w.reset(91, 1)
	verify(w.corpse == null and not w.medusa_dead, "Starting a new match clears the previous corpse")

func activity_checks() -> void:
	var w := movement_world()
	var id := w.add_unit("engineer", Vector2.ZERO, 0)
	var u: Dictionary = w.units[id]
	var depot := w.add_structure("depot", Vector2i(1, 0), 0)
	u.cargo = {"ore": 10}; u.job = {"kind": "deposit", "target": depot}
	w.resources(0).ore = w.capacity(0, "ore")
	verify(w.activity(u).blocker == "storage_full" and w.activity(u).target == depot, "Delivery identifies the full storage resource and highlights its actual destination")
	w.resources(0).ore -= 5
	verify(w.activity(u).blocker == "", "Delivery is not blocked while any carried resource can be deposited")
	u.pos = Vector2(-5, 0); u.route.clear()
	verify(w.activity(u).blocker == "no_route", "An unreachable delivery is distinguished from full storage")
	u.pos = Vector2.ZERO; u.cargo.clear()
	var facility := w.add_structure("foundry", Vector2i(0, 1), 0)
	w.structures[facility].powered = false
	u.job = {"kind": "mine", "source": HexGrid.key(Vector2i(0, 1)), "facility": facility, "delivering": false, "deposit": 0}
	verify(w.activity(u).blocker == "no_power", "A collector waiting at an empty facility identifies power loss")
	w.structures[facility].powered = true
	verify(w.activity(u).blocker == "output_pending", "A powered empty facility reports waiting for output")
	w.structures[facility].buffer = 5
	verify(w.activity(u).blocker == "", "Buffered output can be collected immediately")
	u.job = {"kind": "repair", "target": depot}; w.structures[depot].hp -= 10; w.resources(0).ore = 0; u.work = 0
	verify(w.activity(u).blocker == "no_resources" and w.activity(u).resource == "ore", "Repair explains its missing Ore")
	var vehicle := w.add_unit("ranger", Vector2(2, 0), 0)
	verify(w.activity(w.units[vehicle]).blocker == "no_driver", "Undriven vehicles explain why they cannot act")
	var site := w.add_structure("wall", Vector2i(-1, 0), 0, false)
	u.job = {"kind": "build", "target": site}
	var traffic := w.add_unit("operator", HexGrid.world(Vector2i(-1, 0)), 0)
	verify(w.activity(u).blocker == "site_occupied", "A builder identifies footprint traffic instead of a generic waiting state")
	w.units.erase(traffic)
	verify(w.activity(u).blocker == "", "The footprint blocker clears as soon as traffic leaves")
	w.resources(0).ore = 0
	verify(w.activity(w.structures[facility]).blocker == "no_resources", "Industrial buildings identify missing recipe inputs")
	var before := JSON.stringify([u, w.resources(0), w.structures[site]])
	w.activity(u)
	verify(JSON.stringify([u, w.resources(0), w.structures[site]]) == before, "Status inspection does not mutate simulation or resources")
	var enemy := w.add_unit("marine", Vector2(0, 2), 1)
	w.visible[0] = {HexGrid.cell(w.units[enemy].pos): true}
	var packet: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot(0)))
	verify(packet.units.any(func(e): return int(e.id) == id and e.has("activity")) and packet.units.all(func(e): return int(e.owner) == 0 or not e.has("activity")), "Snapshots include authoritative blockers only for the owning player")
	var client := WorldState.new(w.cfg); client.reset(472, 1); client.apply_snapshot(packet, 0)
	verify(client.activity(client.units[id]).blocker == w.activity(u).blocker, "Client blocker status does not depend on stripped host routes")

func blueprint_recovery_checks() -> void:
	var w := movement_world()
	for c in w.tiles: w.known[0][c] = true
	var worker := w.add_unit("engineer", Vector2.ZERO, 0)
	var cell := Vector2i(2, 0)
	var before: Dictionary = w.resources(0).duplicate()
	w.command(0, {"action": "build", "kind": "wall", "q": cell.x, "r": cell.y, "ids": [worker]})
	var site: int = w.units[worker].job.target
	w.units[worker].pos = HexGrid.world(Vector2i(1, 0)); w.units[worker].route.clear()
	var traffic := w.add_unit("operator", HexGrid.world(cell), 0)
	w.command(0, {"action": "move", "ids": [traffic], "x": 5, "z": 0})
	w.command(0, {"action": "move", "ids": [traffic], "x": 6, "z": 0, "queued": true})
	w._build(w.units[worker], 0.05)
	verify(w.structures.has(site) and not w.structures[site].started and w.units[traffic].orders.size() == 1 and w.units[traffic].home.x == 5, "Passing traffic keeps its route and queued orders while the paid blueprint waits")
	w.units[traffic].pos = Vector2(5, 0)
	var enemy := w.add_unit("scavenger", HexGrid.world(cell), -1)
	w._build(w.units[worker], 0.05)
	verify(w.structures.has(site) and not w.structures[site].started, "Enemy occupancy waits without silently canceling a blueprint")
	w.units.erase(enemy)
	w.tiles[cell].cliff = true; w._rebuild_navigation(); w._build(w.units[worker], 0.05)
	verify(w.structures.has(site) and not w.structures[site].started, "A newly obstructed site retains its paid cost until explicit cancellation")
	w.command(0, {"action": "cancel_build", "target": site})
	verify(before.keys().all(func(r): return int(w.resources(0)[r]) == int(before[r])), "Explicit cancellation of an obstructed unstarted site refunds its full cost")
	w.command(0, {"action": "cancel_build", "target": site})
	verify(before.keys().all(func(r): return int(w.resources(0)[r]) == int(before[r])), "Repeated cancellation cannot duplicate a refund")
	w.tiles[cell].cliff = false; w._rebuild_navigation()
	w.command(0, {"action": "build", "kind": "wall", "q": cell.x, "r": cell.y, "ids": [worker]})
	site = w.units[worker].job.target; w.units[worker].route.clear(); w._build(w.units[worker], 0.05)
	verify(w.structures[site].started, "A clear site starts once the Engineer can work")
	var hp: float = w.structures[site].hp
	w.units[worker].pos = Vector2(-8, 0); w.units[worker].route.clear()
	for c in HexGrid.disk(cell, 1):
		if c != cell: w.tiles[c].cliff = true
	w._rebuild_navigation(); w._build(w.units[worker], 0.05)
	verify(w.structures.has(site) and w.structures[site].hp == hp, "Losing access after construction starts preserves work without deleting the site")
	w.command(0, {"action": "stop", "ids": [worker]})
	verify(w.structures.has(site), "Stopping a builder leaves its paid site intact")
	w.command(0, {"action": "cancel_build", "target": site})
	verify(int(w.resources(0).ore) == int(before.ore) - int(w.cfg.structures.wall.cost.ore), "Explicit cancellation after actual work retains the documented resource loss")

func build_mission_structure(w: WorldState, worker: Dictionary, kind: String) -> int:
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	for cell in HexGrid.disk(anchor.cell, 4):
		if HexGrid.distance(anchor.cell, cell) < 2 or w.tiles.get(cell, {}).get("resource", "") != "": continue
		if w.placement_issue(0, kind, cell) != "": continue
		var response := w.command(0, {"action": "build", "kind": kind, "q": cell.x, "r": cell.y, "ids": [worker.id]})
		verify(response == "Blueprint placed", "Mission construction uses the ordinary paid command")
		var id := int(worker.job.target)
		advance(w, 60)
		verify(w.structures.has(id) and w.structures[id].built, "Mission builders can finish " + kind)
		return id
	verify(false, "Mission has a revealed affordable site for " + kind)
	return 0

func mission_playthrough_checks() -> void:
	for key in ["foothold", "industry"]:
		var w := WorldState.new(settings); w.reset(472, 1)
		w.command(0, {"action": "start_mission", "mission": key})
		var worker := engineer(w)
		var miners: Array = w.units.values().filter(func(u): return u.kind == "engineer" and u.id != worker.id)
		var source := Vector2i.ZERO
		for cell in w.known[0]:
			if w.tiles[cell].resource == "ore": source = cell; break
		if key == "foothold":
			build_mission_structure(w, worker, "depot")
			build_mission_structure(w, worker, "floodlight")
			w.command(0, {"action": "mine", "ids": [worker.id], "q": source.x, "r": source.y})
			advance(w, 180)
		else:
			w.command(0, {"action": "mine", "ids": [miners[0].id], "q": source.x, "r": source.y})
			var foundry := build_mission_structure(w, worker, "foundry")
			advance(w, 180)
			var armory := build_mission_structure(w, worker, "armory")
			if foundry == 0 or armory == 0: continue
			verify(w.command(0, {"action": "kit", "target": armory, "kind": "marine"}) == "Kit queued", "The industry budget supports a Marine kit and its requested Operator")
			var cell: Vector2i = w.structures[foundry].cell
			w.command(0, {"action": "mine", "ids": [worker.id], "q": cell.x, "r": cell.y, "facility": foundry})
			advance(w, 180)
		verify(w.ended and w.result.ends_with("complete"), "A real command-driven playthrough can finish " + key + " without injecting progress or resources")
	var w := WorldState.new(settings); w.reset(472, 1)
	w.command(0, {"action": "start_mission", "mission": "extraction"})
	var marines: Array = w.units.values().filter(func(u): return u.kind == "marine").map(func(u): return u.id)
	w.command(0, {"action": "move", "ids": marines, "x": 2, "z": 0})
	advance(w, 25)
	for s in w.structures.values():
		if s.kind == "medusa": w.command(0, {"action": "attack", "ids": marines, "target": s.id})
	advance(w, 30)
	verify(w.medusa_dead, "The supplied extraction squad can scout and destroy the nest through ordinary combat")
	var workers: Array = w.units.values().filter(func(u): return u.kind == "engineer").map(func(u): return u.id)
	w.command(0, {"action": "mine", "ids": workers, "q": 0, "r": 0})
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var home := HexGrid.world(anchor.cell + Vector2i(2, 0))
	w.command(0, {"action": "move", "ids": marines, "x": home.x, "z": home.y})
	advance(w, 240)
	verify(int(w.resources(0).get("nacre", 0)) >= int(w.cfg.match.extractionMinimumNacre), "Workers can physically recover and deliver the mission's Nacre threshold")
	w.command(0, {"action": "extract", "target": anchor.id})
	advance(w, float(w.cfg.match.extractionSeconds) + 0.1)
	verify(w.ended and w.result.contains("extracted"), "The extraction mission is completable through commands, combat and physical cargo delivery")

func mission_checks() -> void:
	for key in settings.missions:
		var w := WorldState.new(settings); w.reset(472, 1)
		var b := WorldState.new(settings); b.reset(472, 1)
		verify(w.command(0, {"action": "start_mission", "mission": key}) == "Mission deployed", "Every mission can be selected without an unlock: " + key)
		b.command(0, {"action": "start_mission", "mission": key})
		verify(JSON.stringify(w.snapshot(0)) == JSON.stringify(b.snapshot(0)), "Mission setup repeats from its seed: " + key)
		verify(settings.map.radiusTiles != w.cfg.map.radiusTiles and not settings.match.extractionMinimumNacre == 60, "Mission overrides do not mutate shared settings")
		verify(w.command(0, {"action": "start_mission", "mission": key}) != "Mission deployed", "A deployed mission cannot reset itself through a gameplay command")
		var copy := WorldState.new(w.cfg); copy.reset(472, 1)
		copy.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
		verify(copy.mission.id == w.mission.id and int(copy.mission.initial_marines) == int(w.mission.initial_marines) and copy.mission.delivered.is_empty() and is_equal_approx(float(copy.mission.wave_remaining), float(w.mission.wave_remaining)), "Mission progress survives JSON serialization")
		if key != "extraction":
			advance(w, 2)
			verify(not w.ended and w.units.values().all(func(u): return u.owner == 0), "Peaceful missions neither complete early nor spawn a colony")
			var d: Dictionary = w.cfg.missions[key]
			var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
			var worker := engineer(w)
			worker.cargo = {d.deliveryResource: int(d.deliveryTarget)}
			verify(not WorldState.Missions.requirements(w)[0].done, "Carried resources do not count as delivered mission objectives")
			if key == "foothold": w.resources(0).ore -= int(d.deliveryTarget)
			w._deposit_cargo(worker, anchor)
			for kind in d.requiredStructures:
				var id := w.add_structure(kind, anchor.cell + Vector2i(3, 0) if kind == d.requiredStructures[0] else anchor.cell + Vector2i(0, 3), 0)
				w.structures[id].powered = true
			if key == "industry": w.add_unit("marine", worker.pos, 0)
			WorldState.Missions.update(w, 0.05)
			verify(w.ended and w.result.ends_with("complete"), "Combined delivery, power, construction and personnel objectives complete the mission")
		else:
			var nest: Dictionary = {}
			for s in w.structures.values():
				if s.kind == "medusa": nest = s
			verify(nest.cell == Vector2i.ZERO and nest.hp == w.cfg.missions.extraction.medusaHealth, "Extraction uses the compact central nest")
			w._destroy(nest)
			w.resources(0).nacre = int(w.cfg.match.extractionMinimumNacre) - 1
			var anchor_id := int(w.players[0].anchor)
			w.command(0, {"action": "extract", "target": anchor_id})
			verify(not w.players[0].extracting, "Extraction still requires delivered Nacre")
			w.resources(0).nacre += 1; w.command(0, {"action": "extract", "target": anchor_id})
			var count: int = w.units.size(); WorldState.Missions.update(w, 0.05)
			verify(w.units.size() == count + int(w.cfg.missions.extraction.assaultWaveSize), "Manual extraction begins the configured assault")
			advance(w, float(w.cfg.match.extractionSeconds) + 0.1)
			verify(w.ended and w.result.contains("extracted"), "Surviving the mission extraction countdown produces victory")
	var multi := world(2)
	verify(multi.command(0, {"action": "start_mission", "mission": "foothold"}) != "Mission deployed" and multi.mission.is_empty(), "Multiplayer cannot activate single-player scenarios")

func idle_engineer_checks() -> void:
	var w := movement_world()
	w.cfg.construction.engineerHealthPerSecond = 1200
	w.cfg.construction.repairHealthPerSecond = 1000
	var worker := w.add_unit("engineer", Vector2.ZERO, 0)
	var u: Dictionary = w.units[worker]
	var repair := w.add_structure("wall", Vector2i(0, 2), 0)
	w.structures[repair].hp -= 20
	var site := w.add_structure("wall", Vector2i(2, 0), 0, false)
	var far_site := w.add_structure("wall", Vector2i(10, 0), 0, false)
	var enemy := w.add_structure("wall", Vector2i(1, -2), 1)
	w.structures[enemy].hp -= 20
	w._rebuild_navigation()
	var ore := int(w.resources(0).ore)
	w._unit_step(u, 0.05)
	verify(u.job.kind == "build" and int(u.job.target) == site and u.job.automatic, "Idle Engineers prioritize nearby construction over repair")
	advance(w, 5)
	verify(w.structures[site].built and w.structures[repair].hp == w.cfg.structures.wall.health, "Idle Engineers finish construction and then repair nearby damage")
	verify(int(w.resources(0).ore) == ore - int(w.cfg.construction.repairOrePerCycle), "Automatic construction charges no second fee and repair pays its normal Ore cost")
	verify(not w.structures[far_site].started and w.structures[enemy].hp == float(w.cfg.structures.wall.health) - 20, "Engineers leave distant and enemy structures alone")
	w.structures[repair].hp -= 100
	u.auto_work_remaining = 0; w._unit_step(u, 0.05)
	w.command(0, {"action": "move", "ids": [worker], "x": -4, "z": 0, "queued": true})
	w.step(0.05)
	verify(u.job.kind == "move" and not u.job.get("automatic", false) and u.orders.is_empty(), "Queued player orders interrupt automatic work")
	u.job = {"kind": "mine", "source": "0,0", "facility": 0, "delivering": false, "deposit": 0}
	w._idle_engineer_work(u, 1)
	verify(u.job.kind == "mine", "Automatic work never steals an active player job")
	w = movement_world(); worker = w.add_unit("engineer", Vector2.ZERO, 0); u = w.units[worker]
	site = w.add_structure("wall", Vector2i(3, 0), 0, false)
	for cell in HexGrid.disk(Vector2i(3, 0), 1):
		if cell != Vector2i(3, 0): w.tiles[cell].cliff = true
	var reachable := w.add_structure("wall", Vector2i(0, 3), 0, false)
	w._rebuild_navigation(); w._unit_step(u, 0.05)
	verify(u.job.get("target", 0) == reachable and w.structures.has(site), "An unreachable nearby site is skipped without canceling it")
	w = movement_world(); worker = w.add_unit("engineer", Vector2.ZERO, 0); u = w.units[worker]
	repair = w.add_structure("wall", Vector2i(1, 0), 0); w.structures[repair].hp -= 30
	w.resources(0).ore = 0; w._unit_step(u, 0.05)
	verify(u.job.kind == "idle" and w.structures[repair].hp < w.cfg.structures.wall.health, "Automatic repairs cannot spend nonexistent Ore")

func wall_line_checks() -> void:
	var w := movement_world()
	for cell in w.tiles: w.known[0][cell] = true
	var worker := w.add_unit("engineer", HexGrid.world(Vector2i(-2, -2)), 0)
	w.add_structure("wall", Vector2i(4, 0), 0)
	w.tiles[Vector2i(2, 0)].cliff = true
	w.resources(0).ore = int(w.cfg.structures.wall.cost.ore) * 3
	var plan := w.wall_line_plan(0, Vector2i.ZERO, Vector2i(5, 0))
	verify(plan.count == 3 and plan.sites.size() == 6 and not plan.sites[2].valid and not plan.sites[4].valid and not plan.sites[5].valid, "Wall line preview skips obstructions and accounts for its whole budget")
	w.command(0, {"action": "build_line", "ids": [worker], "q": 0, "r": 0, "end_q": 5, "end_r": 0})
	verify(w.structures.size() == 4 and w.resources(0).ore == 0 and w.units[worker].orders.size() == 2, "A wall stroke charges once per placed cell and queues every segment after the first")
	w.resources(0).ore = 100
	w.command(0, {"action": "move", "ids": [worker], "x": -4, "z": 0})
	w.command(0, {"action": "build_line", "ids": [worker], "q": 0, "r": 1, "end_q": 2, "end_r": 1, "queued": true})
	verify(w.units[worker].job.kind == "move" and w.units[worker].orders.size() == 3, "Shift wall strokes append to the existing plan")
	var count := w.structures.size()
	w.command(0, {"action": "build_line", "ids": [worker], "q": 0, "r": 2, "end_q": 1000000, "end_r": 0})
	verify(w.structures.size() == count, "Wall line commands reject out-of-map endpoints before allocating a line")
	w.command(1, {"action": "build_line", "ids": [worker], "q": 0, "r": 2, "end_q": 2, "end_r": 2})
	verify(w.structures.size() == count, "Wall line commands cannot use an opponent's Engineer")
	w.cfg.movement.orderQueueLimit = 3
	w.command(0, {"action": "build_line", "ids": [worker], "q": 0, "r": -2, "end_q": 3, "end_r": -2, "queued": true})
	verify(w.structures.size() == count, "A full order queue does not create unassigned wall blueprints")

func visibility_optimization_checks() -> void:
	var w := world()
	w.units.clear(); w.structures.clear(); w._index_structures()
	var gate := w.add_structure("gate", Vector2i(1, 0), 0)
	w.add_structure("wall", Vector2i(0, 1), 0)
	for case in range(12):
		w.structures[gate].open = case % 2 == 0
		w._refresh_sight_topology()
		var sources: Dictionary = {}
		var expected: Dictionary = {}
		for index in range(8):
			var cell := Vector2i((index * 7 + case) % 9 - 4, (index * 3 + case) % 7 - 3)
			var reach := (index + case) % 6
			w._sight_source(sources, cell, reach)
			expected.merge(w.flood(cell, reach), true)
		verify(w._sight_union(sources) == expected, "Batched sight exactly matches independent floods with cliffs, opaque sources and gates: %d" % case)
	var cell := Vector2i(-2, -2)
	w._cached_sight(cell, 5)
	w.tiles[Vector2i(-1, -2)].cliff = not w.tiles[Vector2i(-1, -2)].cliff
	w.update_visibility()
	verify(w._cached_sight(cell, 5) == w.flood(cell, 5), "Cliff changes invalidate cached personal sight")
	w.structures[gate].open = not w.structures[gate].open
	w.update_visibility()
	verify(w._cached_sight(cell, 5) == w.flood(cell, 5), "Gate changes invalidate cached personal sight")
	w._rebuild_navigation()
	var points: Dictionary = w.point_ids.duplicate()
	var connections := w.navigation.get_point_connections(int(points[Vector2i.ZERO]))
	w.structures[gate].open = true; w.tiles[Vector2i(1, 0)].cliff = false; w._rebuild_navigation()
	verify(w.point_ids == points and w.navigation.get_point_connections(int(points[Vector2i.ZERO])) == connections and not w.navigation.is_point_disabled(int(points[Vector2i(1, 0)])), "Opening a gate retains graph topology and updates admission")
	w.structures[gate].open = false; w._rebuild_navigation()
	verify(w.navigation.is_point_disabled(int(points[Vector2i(1, 0)])), "Closing a gate updates retained graph admission")

func power_balance_checks() -> void:
	verify(int(settings.structures.anchor.powerCapacity) == 4 and int(settings.structures.floodlight.powerDemand) == 1 and int(settings.structures.relay.powerDemand) == 0, "Starting power and passive Relay match the requested budget")
	for kind in ["sentry", "torch", "lance"]: verify(int(settings.structures[kind].powerDemand) >= 3, "Every turret requires at least three power")
	var w := world()
	w.units.clear(); w.structures.clear(); w._index_structures()
	for cell in w.tiles: w.tiles[cell].cliff = false
	var flood := w.add_structure("floodlight", Vector2i.ZERO, 0)
	var generator := w.add_structure("generator", Vector2i(2, 0), 0)
	w._rebuild_navigation(); w._update_power(0); w.update_visibility()
	var far := Vector2i(-6, 0)
	verify(w.visible[0].has(far), "Powered Floodlight provides its full vision")
	w.structures[generator].enabled = false; w._update_power(0); w.update_visibility()
	verify(not w.visible[0].has(far) and w.visible[0].has(Vector2i(1, 0)), "Power loss reduces Floodlight vision to the local fallback")
	verify(w.known[0].has(far) and not w.illuminated[0].has(far), "Lost Floodlight coverage retains explored terrain without current vision or light")
	w.structures[generator].enabled = true; w._update_power(0); w.update_visibility()
	verify(w.visible[0].has(far), "Restoring power restores Floodlight vision")
	w.structures[flood].enabled = false; w._update_power(0); w.update_visibility()
	verify(not w.visible[0].has(far), "Manually disabled Floodlight also loses long-range vision")
	w.structures.clear(); w._index_structures()
	w.add_structure("anchor", Vector2i(-8, 0), 0)
	var relay := w.add_structure("relay", Vector2i.ZERO, 0)
	flood = w.add_structure("floodlight", Vector2i(8, 0), 0)
	w._update_power(0)
	verify(w.structures[flood].powered and int(w.structures[flood].grid_demand) == 1, "A zero-demand Relay still connects a distant consumer to its source")
	w.paused = true
	var tick_before := w.tick
	w.command(0, {"action": "toggle", "target": relay})
	verify(not w.structures[flood].powered, "Disabling the Relay breaks the remote grid connection")
	w.command(0, {"action": "toggle", "target": relay})
	verify(w.structures[flood].powered and w.tick == tick_before, "Relay switching recomputes the grid without advancing paused simulation")

func colony_production_checks() -> void:
	var w := world()
	var medusa: Dictionary = {}
	for s in w.structures.values():
		if s.kind == "medusa": medusa = s
	w.cfg.units.scavenger.basePopulationCap = 1
	var before := w.lightless_chyme
	verify(WorldState.LightlessColony.queue_spawn(w, medusa, "scavenger") == "", "Paid Medusa production accepts an unlocked type")
	verify(w.lightless_chyme == before - int(w.cfg.units.scavenger.manualSpawnCost.chyme), "Manual production pays Chyme immediately")
	medusa.spawn_queue[0].progress = float(w.cfg.units.scavenger.manualSpawnSeconds)
	medusa.passive = float(w.cfg.lightless.medusaPassiveScavengerSeconds)
	WorldState.LightlessColony.update(w, 0)
	verify(w._population("scavenger") == 1 and medusa.spawn_queue.is_empty() and medusa.passive > 0, "Manual completion claims the last cap slot before a ready passive unit")
	for id in w.units.keys():
		if w.units[id].owner < 0: w.units.erase(id)
	WorldState.LightlessColony.update(w, 0)
	verify(w._population("scavenger") == 1 and medusa.passive == 0 and w.lightless_chyme == before - 5, "Waiting passive spawn resumes for free when capacity opens")
	verify(WorldState.LightlessColony.queue_spawn(w, medusa, "ravager") != "", "Medusa cannot produce a Womb-locked type")
	before = w.lightless_chyme
	WorldState.LightlessColony.queue_spawn(w, medusa, "mother")
	WorldState.LightlessColony.cancel_spawn(w, medusa, 0)
	verify(w.lightless_chyme == before, "Unstarted manual spawn cancellation refunds its own cost")
	WorldState.LightlessColony.queue_spawn(w, medusa, "mother")
	medusa.spawn_queue[0].progress = 0.1
	WorldState.LightlessColony.cancel_spawn(w, medusa, 0)
	verify(w.lightless_chyme == before - int(w.cfg.units.mother.manualSpawnCost.chyme), "Started manual spawn cancellation does not refund")
	var index := 0
	for kind in ["stalker", "ravager", "thresher", "shade"]:
		var id := w.add_structure("womb", Vector2i(3 - index * 2, 3), -1)
		var womb: Dictionary = w.structures[id]; womb.unit_type = kind
		womb.passive = float(w.cfg.units[kind].wombPassiveSpawnSeconds)
		index += 1
	WorldState.LightlessColony.update(w, 0)
	for kind in ["stalker", "ravager", "thresher", "shade"]: verify(w._population(kind) == 1, "A completed Womb passively produces " + kind)
	var ravager_womb: Dictionary = {}
	for s in w.structures.values():
		if s.kind == "womb" and s.unit_type == "ravager": ravager_womb = s
	w.lightless_chyme = 500
	WorldState.LightlessColony.queue_spawn(w, medusa, "ravager")
	medusa.spawn_queue[0].progress = 2.0
	w._destroy(ravager_womb)
	WorldState.LightlessColony.update(w, 0.5)
	verify(float(medusa.spawn_queue[0].progress) == 2.0 and w._population("ravager") == 1, "Losing the unlock pauses paid progress and retains existing over-cap units")
	w._destroy(medusa)
	var stalker_before := w._population("stalker")
	WorldState.LightlessColony.update(w, float(w.cfg.units.stalker.wombPassiveSpawnSeconds) / float(w.cfg.lightless.postMedusaWombSpawnRateMultiplier))
	verify(w._population("stalker") > stalker_before, "Surviving Wombs receive the post-Medusa passive spawn buff")
	var a := colony_fixture(); var b := colony_fixture()
	advance(a, 20); advance(b, 20)
	for kind in ["stalker", "ravager", "thresher", "shade"]: verify(a._population(kind) > 0, "CPU pays for Mothers, grows Wombs, and produces " + kind)
	verify(JSON.stringify(a.snapshot(0)) == JSON.stringify(b.snapshot(0)) and a.lightless_chyme == b.lightless_chyme, "Colony development replays deterministically")

func colony_fixture() -> WorldState:
	var w := world()
	w.lightless_brain_time = 0; w.lightless_chyme = 1000
	w.cfg.lightless.brainDecisionIntervalSeconds = 0.1
	w.cfg.lightless.cpuExpansionIntervalSeconds = 0.2
	w.cfg.lightless.structureGestationSeconds = 0.3
	w.cfg.units.mother.manualSpawnSeconds = 0.2
	w.cfg.units.mother.speedTilesPerSecond = 8.0
	w.cfg.lightless.cpuWombPriority = ["scavenger", "stalker", "ravager", "thresher", "shade"]
	for kind in w.cfg.lightless.cpuWombPriority:
		w.cfg.units[kind].wombPassiveSpawnSeconds = 1.5
		w.cfg.units[kind].wombPopulationIncrease = 2
	w.cfg.units.scavenger.basePopulationCap = 2
	return w

func gland_checks() -> void:
	var w := world()
	w.lightless_brain_time = -10000
	w.cfg.lightless.medusaChymePerCycle = 0
	var center := Vector2i.ZERO
	for cell in HexGrid.disk(center, 2):
		w.tiles[cell].cliff = false; w.tiles[cell].resource = ""; w.gloom[cell] = 100.0
	for id in w.units.keys(): w.units.erase(id)
	var womb: Dictionary = w.structures[w.add_structure("womb", center, -1)]
	womb.unit_type = "scavenger"
	w.lightless_chyme = 500
	var first: Vector2i = center + HexGrid.DIRECTIONS[0]
	var second: Vector2i = center + HexGrid.DIRECTIONS[1]
	verify(WorldState.LightlessColony.place_gland(w, womb, "gland", first), "A Womb pays to grow an adjacent armor Gland")
	verify(WorldState.LightlessColony.place_gland(w, womb, "chyme_gland", second), "A Womb pays to grow an adjacent Chyme Gland")
	var armor: Dictionary = {}; var income: Dictionary = {}
	for s in w.structures.values():
		if s.kind == "gland": armor = s
		if s.kind == "chyme_gland": income = s
	var target: Dictionary = w.units[w.add_unit("scavenger", Vector2(4, 0), -1)]
	var base := float(w.cfg.units.scavenger.armor)
	verify(WorldState.TargetRules.armor(w, target) == base and w.lightless_chyme == 410, "Gestating Glands have no effect and costs are paid once")
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.glandGestationSeconds))
	verify(armor.built and income.built and WorldState.TargetRules.armor(w, target) == base + 1, "Completed connected Gland grants type-wide armor")
	var before := w.lightless_chyme
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.chymeGlandCycleSeconds))
	verify(w.lightless_chyme == before + int(w.cfg.lightless.chymeGlandChymePerCycle), "Connected Chyme Gland produces income")
	w._destroy(womb)
	before = w.lightless_chyme
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.chymeGlandCycleSeconds))
	verify(w.lightless_chyme == before and WorldState.TargetRules.armor(w, target) == base, "Destroying a Womb disables both surviving Glands")
	var replacement: Dictionary = w.structures[w.add_structure("womb", center, -1)]
	replacement.unit_type = "scavenger"
	WorldState.LightlessColony.update(w, 0)
	verify(int(armor.connected_womb) == int(replacement.id) and int(income.connected_womb) == int(replacement.id) and WorldState.TargetRules.armor(w, target) == base + 1, "A replacement Womb reconnects surviving matching Glands")
	w.cfg.lightless.cpuArmorGlandsPerTypeBeforeMoreExpansion = 2
	w.lightless_expansion_time = float(w.cfg.lightless.cpuExpansionIntervalSeconds)
	WorldState.LightlessColony.develop(w, {})
	verify(w.structures.values().filter(func(s): return s.kind == "gland").size() == 2, "The CPU develops surviving Wombs after Medusa loss")

func lightless_defend_stance_checks() -> void:
	var w := world()
	for cell in HexGrid.disk(Vector2i.ZERO, 6): w.tiles[cell].cliff = false
	w._rebuild_navigation(); w._sight_areas.clear(); w._sight_topology_valid = false
	var father: Dictionary = w.units[w.add_unit("father", Vector2.ZERO, -1)]
	var unit: Dictionary = w.units[w.add_unit("scavenger", Vector2(0.5, 0), -1)]
	var enemy: Dictionary = w.units[w.add_unit("engineer", Vector2(1.0, 0), 0)]
	father.group_stance = "defend"
	WorldState.LightlessCoordination.recruit(w, father, unit, w.gloom)
	var hp := float(enemy.hp)
	w._unit_step(unit, 0.05)
	verify(unit.job.kind == "defend_stance" and float(enemy.hp) < hp, "A Father's Defend stance engages visible enemies nearby")
	enemy.pos = Vector2(float(w.cfg.lightless.defendRadiusTiles) + 2, 0)
	w._unit_step(unit, 0.05)
	verify(int(unit.target) == 0, "A Defend recruit does not pursue a target outside its Father's radius")
	unit.pos = Vector2(float(w.cfg.lightless.defendRadiusTiles) + 2, 0)
	unit.route.clear(); unit.job.repath_remaining = 0.0
	w._unit_step(unit, 0.05)
	verify(not unit.route.is_empty() and unit.route.back().distance_to(father.pos) < 2, "A defender outside its radius returns toward its Father")
	var thresher: Dictionary = w.units[w.add_unit("thresher", Vector2.ZERO, -1)]
	WorldState.LightlessCoordination.recruit(w, father, thresher, w.gloom)
	thresher.buried = true
	var nearby: Dictionary = w.units[w.add_unit("engineer", Vector2(1.0, 0), 0)]
	w.shots.clear()
	w._unit_step(thresher, 0.05)
	verify(not w.shots.is_empty() and w.shots.back().weapon == "thresher_tentacle" and float(nearby.hp) < float(w.cfg.units.engineer.health), "A buried Defend Thresher uses its buried weapon")

func lightless_defense_checks() -> void:
	var w := world()
	w.gloom.clear()
	for cell in HexGrid.disk(Vector2i.ZERO, 4): w.gloom[cell] = 20.0
	var a: Dictionary = w.structures[w.add_structure("womb", Vector2i(-2, 0), -1)]
	var b: Dictionary = w.structures[w.add_structure("womb", Vector2i(2, 0), -1)]
	var enemy_a: Dictionary = w.units[w.add_unit("marine", w.entity_position(a) + Vector2(0.3, 0), 0)]
	var enemy_b: Dictionary = w.units[w.add_unit("marine", w.entity_position(b) + Vector2(0.3, 0), 0)]
	var defender_a: Dictionary = w.units[w.add_unit("scavenger", HexGrid.world(Vector2i(-1, 0)), -1)]
	var defender_b: Dictionary = w.units[w.add_unit("scavenger", HexGrid.world(Vector2i(1, 0)), -1)]
	var father: Dictionary = w.units[w.add_unit("father", Vector2.ZERO, -1)]
	var recruit: Dictionary = w.units[w.add_unit("scavenger", Vector2.ZERO, -1)]
	father.group_stance = "gather"
	WorldState.LightlessCoordination.recruit(w, father, recruit, w.gloom)
	var remote: Dictionary = w.units[w.add_unit("scavenger", HexGrid.world(Vector2i(8, 0)), -1)]
	var weapon: Dictionary = w.cfg.weapons.marine_rifle
	w._weapon_damage(a, weapon, enemy_a); w._weapon_damage(b, weapon, enemy_b)
	WorldState.LightlessCoordination.update_defense(w)
	verify(defender_a.job.kind == "lightless_defend" and defender_b.job.kind == "lightless_defend" and int(defender_a.job.site) != int(defender_b.job.site), "Connected available defenders distribute across threatened structures")
	verify(int(recruit.father_id) == int(father.id) and recruit.stance == "gather" and recruit.job.kind != "lightless_defend", "Defense calls cannot take a Father's recruits")
	verify(remote.job.kind != "lightless_defend", "Units off Gloom do not receive a remote defense call")
	w.gloom[HexGrid.cell(remote.pos)] = 20.0
	WorldState.LightlessCoordination.update_defense(w)
	verify(remote.job.kind == "lightless_defend", "A unit on a remote isolated Gloom patch can answer a global defense call")
	var selected: Dictionary = defender_a if int(defender_a.job.site) == int(a.id) else defender_b
	selected.pos = enemy_a.pos + Vector2(0.4, 0)
	var hp := float(enemy_a.hp)
	w._unit_step(selected, 0.05)
	verify(float(enemy_a.hp) < hp, "A defender attacks the threat to its assigned structure")
	w.gloom.erase(HexGrid.cell(selected.pos))
	WorldState.LightlessCoordination.update_defense(w)
	verify(selected.job.kind == "lightless_defend", "A defender retains an active call after leaving Gloom")
	w.visible[0][HexGrid.cell(selected.pos)] = true
	var snapshot := w.snapshot(0)
	verify(snapshot.structures.all(func(s): return not s.has("defense_attacker")), "Defense requests do not expose unseen attacker IDs in snapshots")
	var observed: Array = snapshot.units.filter(func(u): return int(u.id) == int(selected.id))
	verify(not observed.is_empty() and int(observed[0].target) == 0 and not observed[0].has("last_target_position"), "Visible defenders do not disclose the position or identity of their unseen target")
	w._destroy(enemy_a); w._destroy(enemy_b)
	WorldState.LightlessCoordination.update_defense(w)
	verify(defender_a.job.kind == "idle" and defender_b.job.kind == "idle" and remote.job.kind == "idle", "Defenders return to their stance after threats disappear")

func global_gloom_vision_checks() -> void:
	var config := settings.duplicate(true)
	config.map.radiusTiles = 24
	var w := WorldState.new(config); w.reset(472, 3)
	w.command(0, {"action": "control_lightless", "slot": 1})
	var remote := Vector2i.ZERO
	for cell in HexGrid.disk(remote, 5): w.tiles[cell].cliff = false; w.tiles[cell].resource = ""
	w._rebuild_navigation()
	verify(not w.visible[-1].has(remote) and not w.gloom.has(remote), "Global Gloom test starts outside personal vision and the colony's network")
	var intruder: Dictionary = w.units[w.add_unit("marine", HexGrid.world(remote), 0)]
	w.gloom[remote] = 0.1
	w.update_visibility()
	verify(w.visible[-1].get(remote, false) is bool and w.visible[-1].get(remote, false) and w.known[-1].has(remote), "Even an isolated unsupported Gloom tile grants global Lightless vision")
	verify(WorldState.TargetRules.identifiable(w, intruder, -1), "Global Gloom sight identifies ordinary enemy occupants without a nearby Lightless unit")
	verify(not w.visible[2].has(remote), "Gloom does not grant another Commonwealth player shared vision")
	var packet: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot(-1)))
	var client := WorldState.new(w.cfg); client.reset(472, 3); client.apply_snapshot(packet, -1)
	verify(client.visible[-1].has(remote) and client.units.has(int(intruder.id)), "Remote Gloom visibility and occupants reach a Lightless network client")
	w._update_gloom(1)
	verify(not w.gloom.has(remote) and not w.visible[-1].has(remote) and w.known[-1].has(remote), "Withered remote Gloom immediately loses active sight while preserving explored terrain")
	verify(not WorldState.TargetRules.identifiable(w, intruder, -1) and w.snapshot(-1).units.all(func(unit): return int(unit.id) != int(intruder.id)), "Enemies disappear from snapshots as soon as their remote Gloom sight is lost")
	w.cfg.structures.stoma.visionRangeBeyondFootprintTiles = 0
	w.cfg.gloom.newTilesPerStructurePerInterval = 1
	var organ_cell := Vector2i(0, 3)
	w.add_structure("stoma", organ_cell, -1)
	w.gloom[organ_cell] = float(w.cfg.gloom.tileHealth)
	w.update_visibility()
	var before: Dictionary = w.gloom.duplicate()
	w.gloom_spread_time = float(w.cfg.gloom.spreadIntervalSeconds)
	w._update_gloom(0)
	var grown: Array = w.gloom.keys().filter(func(cell): return not before.has(cell))
	verify(not grown.is_empty() and grown.all(func(cell): return w.visible[-1].get(cell, false) == true and w.known[-1].has(cell)), "New Gloom grants immediate global vision beyond an organ's personal sight")

func controlled_lightless_autonomy_checks() -> void:
	for slot in [0, 1]:
		for stance in ["probe", "attack", "gather"]:
			var config := settings.duplicate(true)
			config.map.radiusTiles = 24
			config.units.scavenger.speedTilesPerSecond = 0.8
			var w := WorldState.new(config); w.reset(472, 2)
			w.command(0, {"action": "control_lightless", "slot": slot})
			var medusa: Dictionary = w.structures[int(w.players[-1].anchor)]
			medusa.passive = -10000
			var enemy_owner := 1 - int(slot)
			var anchor: Dictionary = w.structures[int(w.players[enemy_owner].anchor)]
			verify(not w.known[-1].has(anchor.cell), "Autonomy regression starts with an unexplored enemy Anchor")
			var raiders: Array = w.units.values().filter(func(unit): return unit.owner == -1 and unit.kind == "scavenger")
			var origins: Dictionary = {}
			for unit in raiders: origins[int(unit.id)] = unit.pos
			w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": stance})
			var enemy_health := float(anchor.hp)
			advance(w, 3)
			verify(raiders.any(func(unit): return unit.pos.distance_to(origins[int(unit.id)]) > 0.5 and not unit.route.is_empty()), "Player-controlled %s units autonomously advance through fog for slot %d" % [stance, slot])
			verify(float(anchor.hp) == enemy_health and not w.known[-1].has(anchor.cell), "Planning a raid neither reveals nor damages an unseen distant Anchor")
			var packet := w.snapshot(-1)
			verify(packet.structures.all(func(site): return int(site.id) != int(anchor.id)), "Autonomous planning does not disclose an enemy Anchor in the player snapshot")
			for unit in packet.units:
				if unit.owner == -1: verify(int(unit.target) != int(anchor.id) and int(unit.get("activity", {}).get("target", 0)) != int(anchor.id) and not unit.has("last_target_position") and not unit.job.has("path_search"), "Owned autonomous units do not disclose hidden target identities or coordinates")
			verify(float(medusa.hp) == float(w.cfg.structures.medusa.health), "Default autonomous behavior never attacks the Medusa")
			if int(slot) == 0 and stance == "attack":
				w.cfg.units.scavenger.speedTilesPerSecond = 8
				var engaged := false
				for tick_index in range(400):
					w.step(0.05)
					if float(anchor.hp) < enemy_health: engaged = true; break
				verify(engaged and w.structure_visible(-1, anchor), "An autonomous raid discovers and damages its enemy Anchor without player orders")

func lightless_player_checks() -> void:
	for slot in [0, 1]:
		var regression := world(2)
		regression.command(0, {"action": "control_lightless", "slot": slot})
		var own_medusa: Dictionary = regression.structures[int(regression.players[-1].anchor)]
		var raider: Dictionary = regression.units[regression.add_unit("scavenger", HexGrid.world(regression.nearest_free(own_medusa.cell)), -1)]
		for opponent in regression.players:
			if int(opponent) >= 0: regression.known[-1].erase(regression.structures[int(regression.players[opponent].anchor)].cell)
		raider.erase("raid_owner")
		verify(WorldState.LightlessTactics.assigned_anchor(regression, raider).get("owner", -1) >= 0, "An unassigned Lightless raid selects an opposing Commonwealth player, never its own Medusa")
		raider.raid_owner = -1
		regression.command(-1, {"action": "medusa_stance", "target": own_medusa.id, "stance": "attack"})
		var health := float(own_medusa.hp)
		advance(regression, 1)
		verify(int(raider.target) != int(own_medusa.id) and float(own_medusa.hp) == health, "Attack stance preserves the Medusa when no enemy Anchor is known, for either player slot")
		raider.target = own_medusa.id; raider.job = {"kind": "attack"}
		WorldState.LightlessTactics.prepare_attack(regression, raider)
		verify(int(raider.target) != int(own_medusa.id), "Automatic attacks discard or replace stale friendly objectives")
		var enemy_owner := 1 - int(slot)
		var enemy_anchor: Dictionary = regression.structures[int(regression.players[enemy_owner].anchor)]
		regression.known[-1][enemy_anchor.cell] = true
		verify(WorldState.LightlessTactics.assigned_anchor(regression, raider).get("id", 0) == enemy_anchor.id, "Attack stance selects a discovered opposing Commonwealth Anchor")
	var w := world(3)
	w.command(1, {"action": "control_lightless", "slot": 1})
	verify(not w.lightless_controlled, "Guests cannot assign the Lightless role")
	w.command(0, {"action": "control_lightless", "slot": 1})
	verify(w.lightless_controlled and w.players.has(-1) and not w.players.has(1) and w.players.has(0) and w.players.has(2), "One multiplayer slot becomes Lightless without removing opponents")
	verify(w.units.values().all(func(unit): return unit.owner != 1) and w.structures.values().all(func(site): return site.owner != 1), "The Lightless slot retains no Commonwealth assets")
	w.command(0, {"action": "control_lightless", "slot": 2})
	verify(w.players.has(2) and w.players.size() == 3, "A second Lightless player cannot be assigned")
	var medusa: Dictionary = w.structures[int(w.players[-1].anchor)]
	var father: Dictionary = w.units.values().filter(func(unit): return unit.kind == "father")[0]
	var id := w.add_unit("scavenger", father.pos, -1)
	w.command(-1, {"action": "father_stance", "ids": [father.id], "stance": "gather"})
	w.command(-1, {"action": "recruit", "ids": [father.id], "target": id})
	verify(w.units[id].stance == "gather" and int(w.units[id].father_id) == int(father.id), "Player Father controls recruit and apply stance through WorldState")
	w.lightless_brain_time = 0
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.brainDecisionIntervalSeconds))
	verify(father.group_stance == "gather", "The CPU does not override a player-controlled colony")
	w.command(-1, {"action": "release", "ids": [father.id]})
	verify(not w.units[id].has("father_id"), "Player release commands end recruitment")
	w.lightless_chyme = 500
	var before := w.lightless_chyme
	w.command(-1, {"action": "spawn", "target": medusa.id, "kind": "mother"})
	verify(medusa.spawn_queue.size() == 1 and w.lightless_chyme < before, "Lightless production commands pay Chyme immediately")
	w.command(-1, {"action": "cancel_spawn", "target": medusa.id, "index": 0})
	verify(medusa.spawn_queue.is_empty() and w.lightless_chyme == before, "Unstarted player spawn orders refund their Chyme")
	for payload in [{"action": "cancel_spawn"}, {"action": "move", "x": "bad", "z": 0}, {"action": "spawn", "target": medusa.id, "kind": "marine"}]:
		w.command(-1, payload)
	verify(w.lightless_chyme == before, "Malformed Lightless orders do not mutate resources")
	var goal: Vector2 = father.pos + (father.pos - w.entity_position(medusa)).normalized() * 0.3
	var origin: Vector2 = father.pos
	w.command(-1, {"action": "move", "ids": [father.id], "x": goal.x, "z": goal.y})
	w._unit_step(father, 0.1)
	verify(father.pos != origin, "Player movement actually moves a Father")
	var thresher: Dictionary = w.units[w.add_unit("thresher", father.pos, -1)]
	thresher.buried = true
	var enemy: Dictionary = engineer(w)
	enemy.pos = father.pos + Vector2(1, 0); w.update_visibility()
	for action in ["move", "attack", "stop", "burrow"]:
		w.command(-1, {"action": action, "ids": [thresher.id], "target": enemy.id, "x": goal.x, "z": goal.y})
		verify(thresher.job.kind == "idle" and int(thresher.target) == 0 and thresher.buried, "Combat units reject direct " + action + " orders")
	WorldState.LightlessCoordination.recruit(w, father, thresher, w.gloom)
	var previous_position: Vector2 = father.pos
	father.pos += Vector2(3, 0)
	w._unit_step(thresher, 0.05)
	verify(thresher.transition == "emerge", "A buried recruit autonomously emerges to follow its Father")
	w._unit_step(thresher, float(w.cfg.combat.thresherEmergeSeconds))
	verify(not thresher.buried, "Father-guided movement completes the autonomous emerge transition")
	father.pos = previous_position
	w.command(-1, {"action": "father_stance", "ids": [father.id], "stance": "defend"})
	thresher.job = {"kind": "defend_stance", "site": 0, "repath_remaining": 0.0}; thresher.route.clear()
	w._unit_step(thresher, 0.05)
	verify(thresher.transition == "burrow", "A recruit autonomously burrows again when it reaches its defensive position")
	var mother := w.add_unit("mother", father.pos, -1)
	var candidates: Array = w.gloom.keys().filter(func(cell): return not w.blocked(cell) and w.tiles[cell].resource == "" and w.structure_cells.get(cell, []).is_empty())
	var site: Dictionary = {}
	for cell in candidates:
		w.command(-1, {"action": "build", "kind": "womb", "unit_type": "thresher", "ids": [mother], "q": cell.x, "r": cell.y})
		for organ in w.structures.values():
			if organ.kind == "womb": site = organ; break
		if not site.is_empty(): break
	verify(not site.is_empty() and site.unit_type == "thresher" and w.units[mother].job.kind == "grow", "Player Mothers place typed Wombs and travel to grow them")
	w.command(-1, {"action": "cancel_build", "target": site.id})
	verify(not w.structures.has(int(site.id)) and w.lightless_chyme == before, "Canceling a player blueprint refunds its paid cost")
	w.update_visibility()
	verify(w.gloom.keys().all(func(cell): return w.visible[-1].has(cell)), "Lightless players see Gloom without revealing it to Commonwealth players")
	var packet: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot(-1)))
	var replica := WorldState.new(w.cfg); replica.reset(472, 3); replica.apply_snapshot(packet, -1)
	verify(replica.lightless_controlled and replica.lightless_chyme == w.lightless_chyme and replica.players.has(-1), "Lightless ownership, resources and visibility survive network snapshots")
	verify(float(w.snapshot(0).lightless_chyme) == 0, "Enemy snapshots do not disclose colony Chyme")
	w.eliminate(0); w.eliminate(2)
	verify(w.ended and w.result.contains("Lightless win"), "Lightless win after all opposing Anchors are eliminated")
	w = world(2); w.command(0, {"action": "control_lightless", "slot": 1})
	w.eliminate(-1)
	verify(not w.lightless_controlled and not w.players.has(-1) and not w.ended, "A departing Lightless player hands the colony back to the CPU")
	w = world(2); w.command(0, {"action": "control_lightless", "slot": 0})
	verify(w.players.has(-1) and not w.players.has(0) and w.players.has(1) and w.commonwealth_ai.is_empty(), "The multiplayer host can be Lightless while its guest remains human-controlled Commonwealth")
	w = world(); w.command(0, {"action": "control_lightless", "slot": 0, "solo_ai": true})
	w.cfg.lightless.soloCommonwealthAI.decisionIntervalSeconds = 0.2
	w.cfg.lightless.soloCommonwealthAI.desiredMarines = 3
	w.cfg.lightless.soloCommonwealthAI.attackGroupSize = 2
	advance(w, 75)
	verify(w.structures.values().any(func(organ): return organ.owner == 0 and organ.kind == "armory" and organ.built), "Solo Commonwealth AI builds an Armory using normal resources and Engineer work")
	verify(w.units.values().filter(func(unit): return unit.owner == 0 and unit.kind == "marine").size() >= 2, "Solo Commonwealth AI produces and equips reinforcements")
	verify(w.commonwealth_ai.size() > 0 and w.players[0].alive and w.players[-1].alive, "Solo Lightless play has an active opposing Commonwealth controller")

func thresher_fixture() -> CountingWorld:
	var cfg: Dictionary = settings.duplicate(true); cfg.map.radiusTiles = 12
	var w := CountingWorld.new(cfg)
	w.reset(472, 1); w.units.clear(); w.structures.clear(); w.gloom.clear(); w.illuminated.clear()
	for tile in w.tiles.values(): tile.cliff = false; tile.resource = ""
	w.players[0].anchor = w.add_structure("anchor", Vector2i(5, 0), 0)
	w._rebuild_navigation(); w.update_visibility()
	w.path_queries = 0
	return w

func thresher_navigation_checks() -> void:
	var w := thresher_fixture()
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var unit: Dictionary = w.units[w.add_unit("thresher", HexGrid.world(Vector2i(-1, 0)), -1)]
	for cell in w.tiles:
		if cell.x in [0, 1]: w.tiles[cell].cliff = true
	w._rebuild_navigation()
	unit.stance = "probe"
	for i in range(100): w._unit_step(unit, 0.05)
	verify(w.path_queries > 0 and w.path_queries <= 15, "Unreachable Thresher probes retry on simulation-time cooldown instead of issuing a full path query every tick")
	print("Unreachable Thresher probe: ", w.path_queries, " path queries over 100 ticks")
	w.path_queries = 0; unit.stance = "attack"; unit.job = {"kind": "attack"}; unit.target = anchor.id
	WorldState.LightlessTactics.approach(w, unit, anchor, w.cfg.weapons.thresher_tentacle)
	verify(w.path_queries > 0 and w.path_queries <= int(w.cfg.lightless.maxPathQueriesPerDecision), "Unreachable firing-position searches have a bounded full-path query budget")
	w.path_queries = 0
	for cell in HexGrid.disk(Vector2i(6, -3), 2): w.gloom[cell] = 20.0
	WorldState.LightlessTactics.retreat(w, unit)
	verify(w.path_queries > 0 and w.path_queries <= int(w.cfg.lightless.maxPathQueriesPerDecision), "Unreachable remote Gloom retreat searches share the bounded path-query budget")
	for cell in w.tiles: w.tiles[cell].cliff = false
	w._rebuild_navigation(); unit.job.repath_remaining = 0
	WorldState.LightlessTactics.approach(w, unit, anchor, w.cfg.weapons.thresher_tentacle)
	verify(not unit.route.is_empty(), "A bounded firing-position search resumes and finds a route after the obstruction clears")
	w = thresher_fixture(); anchor = w.structures[int(w.players[0].anchor)]
	unit = w.units[w.add_unit("thresher", w.entity_position(anchor) - Vector2(3, 0), -1)]
	unit.buried = true; unit.stance = "probe"; unit.target = anchor.id
	unit.job = {"kind": "probe", "pressure": 0.0, "damage_tick": int(unit.last_damage)}
	var health := float(anchor.hp)
	w._unit_step(unit, 0.05)
	verify(unit.buried and unit.get("transition", "") == "" and anchor.hp < health and w.path_queries == 0, "Buried Probe Threshers fire their ranged tentacle without planning impossible melee movement")
	unit.buried = false; unit.job = {"kind": "attack", "objective": anchor.id}; unit.target = anchor.id; unit.route = [w.entity_position(anchor)]
	w._unit_step(unit, 0.05)
	verify(unit.transition == "burrow" and int(unit.target) == int(anchor.id) and int(unit.job.objective) == int(anchor.id) and unit.route.is_empty(), "Automatic deployment stops travel at tentacle range while preserving the combat objective")
	w._unit_step(unit, float(w.cfg.combat.thresherBurrowSeconds))
	w.tiles[Vector2i(4, 0)].cliff = true; w._rebuild_navigation()
	w._unit_step(unit, 0.05)
	verify(unit.transition == "emerge" and int(unit.target) == int(anchor.id) and int(unit.job.objective) == int(anchor.id), "An obstructed buried Thresher emerges without losing its objective")
	w._unit_step(unit, float(w.cfg.combat.thresherEmergeSeconds))
	var start: Vector2 = unit.pos
	for i in range(60): w._unit_step(unit, 0.05)
	verify(unit.pos.distance_to(start) > 0.1, "An emerged Thresher actually navigates around the obstruction instead of remaining stuck in deployment transitions")

func strategy_recovery_checks() -> void:
	var w := world()
	w.command(0, {"action": "control_lightless", "slot": 0, "solo_ai": true})
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	for id in w.units.keys():
		if w.units[id].owner == 0: w._destroy(w.units[id])
	w.resources(0).ore = 200; w.resources(0).gas = 100
	advance(w, 35)
	verify(w.units.values().any(func(unit): return unit.owner == 0 and unit.kind == "engineer"), "Commonwealth AI replaces its last lost Engineer through ordinary kits and personnel")
	var marine: Dictionary = w.units[w.add_unit("marine", w.entity_position(anchor) + Vector2(6, 0), 0)]
	marine.hp = 1; w.commonwealth_ai.timer = 0
	WorldState.CommonwealthAI.update(w, 0.1)
	verify(w.commonwealth_ai.recovering.has(int(marine.id)) and marine.job.kind == "move", "Wounded Commonwealth Marines withdraw toward their healing Anchor")
	marine.hp = float(w.cfg.units.marine.health); w.commonwealth_ai.timer = 0
	WorldState.CommonwealthAI.update(w, 0.1)
	verify(not w.commonwealth_ai.recovering.has(int(marine.id)), "Recovered Commonwealth Marines rejoin available forces")
	w = world()
	var medusa: Dictionary = {}
	for site in w.structures.values():
		if site.kind == "medusa": medusa = site; break
	var father: Dictionary = w.units[w.add_unit("father", Vector2.ZERO, -1)]
	var recruit: Dictionary = w.units[w.add_unit("scavenger", Vector2(0.5, 0), -1)]
	WorldState.LightlessColony.develop(w, medusa)
	father.hp = 1
	WorldState.LightlessColony.develop(w, medusa)
	verify(father.recovering and recruit.stance == "gather", "Wounded CPU Fathers recall their existing recruits with a Gather override")
	father.hp = float(w.cfg.units.father.health)
	WorldState.LightlessColony.develop(w, medusa)
	verify(not father.recovering and recruit.stance == "attack" and int(recruit.raid_owner) == int(WorldState.LightlessTactics.assigned_anchor(w, father).owner), "Recovered Fathers restore their recruits' Attack stance and coordinate the same opposing Anchor")
	w.cfg.lightless.cpuWombPriority = ["scavenger"]
	w.cfg.lightless.cpuArmorGlandsPerTypeBeforeMoreExpansion = 0; w.cfg.lightless.cpuChymeGlandsPerWombTarget = 0
	var womb_cell: Vector2i = w.gloom.keys().filter(func(cell): return not w.blocked(cell) and w.tiles[cell].resource == "" and w.structure_cells.get(cell, []).is_empty())[0]
	w.add_structure("womb", womb_cell, -1)
	while w._population("scavenger") < WorldState.LightlessColony.cap(w, "scavenger"): w.add_unit("scavenger", Vector2.ZERO, -1)
	w.add_unit("mother", w.entity_position(medusa), -1)
	w.lightless_chyme = 500; w.lightless_expansion_time = float(w.cfg.lightless.cpuExpansionIntervalSeconds)
	WorldState.LightlessColony.develop(w, medusa)
	verify(w.structures.values().filter(func(site): return site.kind == "womb").size() == 2, "CPU grows another typed Womb when the initial Womb's population capacity fills")
	w = world(2); w.units.clear()
	for owner in [0, 1]:
		w.resources(owner).nacre = int(w.cfg.match.extractionMinimumNacre)
		w.command(owner, {"action": "extract", "target": w.players[owner].anchor})
	w.players[0].remaining = 0.01; w.players[1].remaining = 0.02
	w.step(0.1)
	verify(w.ended and w.result == "Player 1 extracted successfully", "Competing extractions completing in one tick award the earlier countdown rather than the last player iterated")
	w = movement_world()
	var worker: Dictionary = w.units[w.add_unit("operator", Vector2.ZERO, 0)]
	for cell in w.tiles:
		if cell.x == 2: w.tiles[cell].cliff = true
	w._rebuild_navigation()
	var destination := HexGrid.world(Vector2i(4, 0))
	w.command(0, {"action": "move", "ids": [worker.id], "x": destination.x, "z": destination.y})
	for i in range(50): w._unit_step(worker, 0.1)
	verify(worker.job.kind == "move" and worker.home == destination and worker.pos.distance_to(destination) > 1, "A blocked move retains the requested destination after exhausting its partial route")
	for cell in w.tiles:
		if cell.x == 2: w.tiles[cell].cliff = false
	w._rebuild_navigation()
	for i in range(150): w._unit_step(worker, 0.1)
	verify(worker.job.kind == "idle" and worker.pos.distance_to(destination) < 0.1, "Clearing a blocked route resumes and completes the original move without another command")

func womb_reconfiguration_checks() -> void:
	var w := world(2)
	w.command(0, {"action": "control_lightless", "slot": 1})
	w.lightless_chyme = 500; w.cfg.lightless.medusaChymePerCycle = 0
	for cell in HexGrid.disk(Vector2i.ZERO, 4): w.tiles[cell].cliff = false; w.tiles[cell].resource = ""
	var medusa: Dictionary = w.structures[int(w.players[-1].anchor)]
	var womb: Dictionary = w.structures[w.add_structure("womb", Vector2i.ZERO, -1)]
	var old_cap := WorldState.LightlessColony.cap(w, "scavenger")
	var base := int(w.cfg.units.scavenger.basePopulationCap)
	for i in range(base + 1): w.add_unit("scavenger", w.entity_position(medusa), -1)
	w.command(-1, {"action": "womb_type", "target": womb.id, "unit_type": "stalker"})
	verify(womb.unit_type == "scavenger" and WorldState.LightlessColony.cap(w, "scavenger") == old_cap, "A Womb cannot reconfigure if removing capacity would exceed the old type's cap")
	var last := 0
	for unit in w.units.values():
		if unit.owner == -1 and unit.kind == "scavenger": last = int(unit.id)
	w.units.erase(last)
	w.command(-1, {"action": "spawn", "target": womb.id, "kind": "scavenger"})
	w.command(-1, {"action": "womb_type", "target": womb.id, "unit_type": "stalker"})
	verify(womb.unit_type == "scavenger" and womb.spawn_queue.size() == 1, "Reconfiguration preserves paid orders by requiring the source queue to be cleared first")
	w.command(-1, {"action": "cancel_spawn", "target": womb.id, "index": 0})
	var gland: Dictionary = w.structures[w.add_structure("gland", Vector2i(1, 0), -1)]
	gland.unit_type = "scavenger"
	WorldState.LightlessColony.connect_glands(w)
	verify(WorldState.LightlessColony.connected(w, gland), "An original typed Gland starts connected")
	womb.passive = 9.0
	w.command(0, {"action": "womb_type", "target": womb.id, "unit_type": "stalker"})
	verify(womb.unit_type == "scavenger", "Commonwealth players cannot reconfigure the colony's Wombs")
	w.command(-1, {"action": "womb_type", "target": womb.id, "unit_type": "stalker"})
	verify(womb.unit_type == "stalker" and float(womb.configuration_remaining) > 0 and float(womb.passive) == 0, "A safe reconfiguration starts a cooldown and resets passive progress")
	verify(WorldState.LightlessColony.cap(w, "scavenger") == base and WorldState.LightlessColony.cap(w, "stalker") == int(w.cfg.units.stalker.basePopulationCap), "Old capacity is removed immediately and new capacity waits for the cooldown")
	verify(not WorldState.LightlessColony.unlocked(w, medusa, "stalker") and not WorldState.LightlessColony.connected(w, gland) and gland.unit_type == "scavenger", "Cooldowns grant no unlock, and old Glands retain their type without providing mismatched upgrades")
	verify(w.activity(womb).task == "configure", "Womb reconfiguration exposes progress to the inspector")
	var replica := WorldState.new(w.cfg); replica.reset(472, 2)
	replica.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(-1))), -1)
	verify(replica.structures[int(womb.id)].unit_type == "stalker" and replica.structures[int(womb.id)].configuration_remaining == womb.configuration_remaining and WorldState.LightlessColony.cap(replica, "scavenger") == base, "Womb type, cooldown and capacity survive network snapshots")
	var duration := float(womb.configuration_remaining)
	w.step(0.05)
	verify(is_equal_approx(float(womb.configuration_remaining), duration - 0.05), "Womb cooldown advances once per simulation step")
	WorldState.LightlessColony.update(w, float(womb.configuration_remaining) * 0.5)
	verify(float(womb.passive) == 0 and w._population("stalker") == 0, "A reconfiguring Womb does not progress passive production")
	WorldState.LightlessColony.update(w, float(womb.configuration_remaining))
	verify(WorldState.LightlessColony.cap(w, "stalker") > 0 and WorldState.LightlessColony.unlocked(w, medusa, "stalker"), "Cooldown completion enables the new type's capacity and Medusa unlock")
	WorldState.LightlessColony.queue_spawn(w, medusa, "stalker")
	medusa.spawn_queue[0].progress = 1.0
	w.command(-1, {"action": "womb_type", "target": womb.id, "unit_type": "scavenger"})
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.wombReconfigureSeconds))
	verify(float(medusa.spawn_queue[0].progress) == 1.0, "Losing the last typed Womb pauses a paid Medusa order without losing its progress")
	verify(WorldState.LightlessColony.connected(w, gland), "Returning to a matching Womb type reconnects its preserved Glands")
	womb.passive = float(w.cfg.units.scavenger.wombPassiveSpawnSeconds)
	WorldState.LightlessColony.update(w, 0)
	verify(w._population("scavenger") == base + 1, "The reconfigured Womb produces its new type within its restored cap")
	w._destroy(womb)
	verify(w._population("scavenger") == base + 1 and not WorldState.LightlessColony.spawn(w, medusa, "scavenger"), "Destroyed capacity preserves over-cap survivors and blocks further spawning")
	var blueprint: Dictionary = w.structures[w.add_structure("womb", Vector2i(3, 0), -1, false)]
	w.command(-1, {"action": "womb_type", "target": blueprint.id, "unit_type": "ravager"})
	verify(blueprint.unit_type == "ravager" and float(blueprint.configuration_remaining) == 0 and WorldState.LightlessColony.cap(w, "ravager") == int(w.cfg.units.ravager.basePopulationCap), "Unstarted Womb blueprints change type without granting premature capacity")
	blueprint.started = true
	w.command(-1, {"action": "womb_type", "target": blueprint.id, "unit_type": "shade"})
	verify(blueprint.unit_type == "ravager", "Gestating Wombs cannot change type")

func stoma_fixture() -> WorldState:
	var w := movement_world()
	w.cfg.lightless.cpuWombPriority = []; w.cfg.lightless.cpuDesiredFathers = 0
	w.cfg.lightless.cpuDesiredMothers = 1; w.cfg.lightless.cpuDesiredStomas = 1
	w.cfg.lightless.medusaChymePerCycle = 0
	w.lightless_chyme = 200; w.lightless_brain_time = -10000
	w.lightless_expansion_time = float(w.cfg.lightless.cpuExpansionIntervalSeconds)
	var medusa := w.add_structure("medusa", Vector2i(-8, 0), -1)
	w.structures[medusa].passive = -10000
	for q in range(-8, 2):
		var cell := Vector2i(q, 0)
		w.gloom[cell] = 100.0; w.tiles[cell].resource = ""
	var carrier := w.add_unit("scavenger", HexGrid.world(Vector2i(1, 0)), -1)
	w.units[carrier].chyme = 5.0
	w.add_unit("mother", HexGrid.world(Vector2i(-5, 0)), -1)
	w._rebuild_navigation()
	return w

func stoma_checks() -> void:
	var w := stoma_fixture()
	var medusa: Dictionary = w.structures.values()[0]
	var mother: Dictionary = w.units.values().filter(func(u): return u.kind == "mother")[0]
	var carrier: Dictionary = w.units.values().filter(func(u): return u.kind == "scavenger")[0]
	var cost := int(w.cfg.structures.stoma.cost.chyme)
	var reserve := int(w.cfg.lightless.cpuMinimumChymeReserve)
	carrier.chyme = 0
	verify(WorldState.LightlessColony.stoma_sites(w).is_empty(), "The CPU does not build drop-offs without distant Chyme carriers")
	carrier.chyme = 5.0
	w.lightless_chyme = reserve + cost - 1
	WorldState.LightlessColony.develop(w, medusa)
	verify(w.structures.size() == 1 and w.lightless_chyme == reserve + cost - 1, "Stoma construction preserves the CPU reserve when unaffordable")
	w.lightless_chyme = 200
	var replay := stoma_fixture()
	WorldState.LightlessColony.develop(w, medusa)
	WorldState.LightlessColony.develop(replay, replay.structures.values()[0])
	var site: Dictionary = w.structures.values().filter(func(s): return s.kind == "stoma")[0]
	verify(site.cell == replay.structures.values().filter(func(s): return s.kind == "stoma")[0].cell and w.lightless_chyme == replay.lightless_chyme, "Stoma placement and payment replay deterministically")
	verify(w.lightless_chyme == 200 - cost and not site.started and mother.job.kind == "grow", "A Mother travels to a Stoma blueprint paid exactly once")
	verify(HexGrid.distance(site.cell, medusa.cell) >= int(w.cfg.lightless.cpuStomaMinOrganDistanceTiles) and site.cell != HexGrid.cell(carrier.pos), "Forward drop-offs respect organ spacing and occupied cells")
	verify(WorldState.LightlessColony.stoma_sites(w).is_empty(), "Unstarted Stomas count toward the configured construction limit")
	w._destroy(mother)
	WorldState.LightlessColony.develop(w, medusa)
	verify(medusa.spawn_queue.any(func(job): return job.kind == "mother"), "The CPU requests a replacement Mother for an orphaned Stoma")
	mother = w.units[w.add_unit("mother", HexGrid.world(Vector2i(-5, 0)), -1)]
	var paid := w.lightless_chyme
	WorldState.LightlessColony.develop(w, medusa)
	verify(mother.job.kind == "grow" and int(mother.job.target) == int(site.id) and w.lightless_chyme == paid, "A replacement Mother resumes the existing paid Stoma")
	mother.pos = HexGrid.world(site.cell)
	WorldState.LightlessColony.mother_step(w, mother, 0)
	verify(site.started and not site.built and not w.units.has(int(mother.id)), "Starting Stoma gestation consumes its Mother")
	carrier.pos = HexGrid.world(site.cell + Vector2i(1, 0))
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.structureGestationSeconds) * 0.5)
	w._unit_step(carrier, 0)
	verify(not site.built and carrier.chyme == 5.0, "Gestating Stomas cannot accept Chyme")
	site.hp -= 10
	WorldState.LightlessColony.update(w, float(w.cfg.lightless.structureGestationSeconds) * 0.5)
	verify(not site.built, "Damage delays Stoma gestation")
	WorldState.LightlessColony.update(w, 1)
	paid = w.lightless_chyme
	w._unit_step(carrier, 0)
	verify(site.built and carrier.chyme == 0 and w.lightless_chyme == paid + 5, "Completed forward Stomas accept physically delivered Chyme")
	w = stoma_fixture(); medusa = w.structures.values()[0]
	for cell in w.gloom: w.tiles[cell].cliff = true
	w._rebuild_navigation()
	WorldState.LightlessColony.develop(w, medusa)
	verify(w.structures.size() == 1 and w.lightless_chyme == 200, "Blocked Stoma sites do not spend Chyme or create blueprints")
	w.cfg.lightless.cpuDesiredStomas = 0
	verify(WorldState.LightlessColony.stoma_sites(w).is_empty(), "A zero Stoma target disables CPU construction")

func medusa_stance_checks() -> void:
	var w := world()
	var medusa: Dictionary = {}
	for organ in w.structures.values():
		if organ.kind == "medusa": medusa = organ; break
	var line := HexGrid.line(medusa.cell, Vector2i.ZERO)
	w.gloom.clear()
	for i in range(4): w.gloom[line[i]] = 20.0
	w.gloom[line[5]] = 20.0
	var connected: Dictionary = w.units[w.add_unit("scavenger", HexGrid.world(line[3]), -1)]
	var isolated: Dictionary = w.units[w.add_unit("scavenger", HexGrid.world(line[5]), -1)]
	var father: Dictionary = w.units[w.add_unit("father", HexGrid.world(line[1]), -1)]
	var recruit: Dictionary = w.units[w.add_unit("scavenger", father.pos, -1)]
	var mother: Dictionary = w.units[w.add_unit("mother", father.pos, -1)]
	father.group_stance = "gather"
	WorldState.LightlessCoordination.recruit(w, father, recruit, w.gloom)
	var baseline := str(w.cfg.lightless.startingStance)
	var friendly := engineer(w)
	var friendly_stance := str(friendly.stance)
	for payload in [{"stance": "invalid", "target": medusa.id}, {"stance": 1, "target": medusa.id}, {"stance": "attack", "target": "bad"}, {"stance": "attack", "target": float(medusa.id) + 0.5}, {"stance": "attack", "target": father.id}, {"stance": "attack"}]:
		payload.action = "medusa_stance"
		w.command(-1, payload)
	verify(medusa.network_stance == baseline and connected.stance == baseline, "Malformed Medusa stance orders leave colony state unchanged")
	w.command(0, {"action": "medusa_stance", "target": medusa.id, "stance": "attack"})
	w.command(-2, {"action": "medusa_stance", "target": medusa.id, "stance": "attack"})
	verify(medusa.network_stance == baseline, "Commonwealth and unknown actors cannot command the Medusa")
	medusa.built = false
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "attack"})
	verify(medusa.network_stance == baseline, "Unfinished Medusas cannot command a network")
	medusa.built = true
	w.ended = true
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "attack"})
	verify(medusa.network_stance == baseline, "Ended matches reject Medusa stance changes")
	w.ended = false
	w.paused = true
	for stance in ["attack", "defend", "gather", "probe"]:
		w.command(-1, {"action": "medusa_stance", "target": float(medusa.id), "stance": stance})
		verify(connected.stance == stance and isolated.stance == stance and medusa.network_stance == stance, "Medusa propagates %s globally across separate Gloom patches while paused" % stance)
	verify(isolated.stance == baseline and recruit.stance == "gather" and mother.stance == baseline and father.group_stance == "gather" and friendly.stance == friendly_stance, "Global Gloom commands preserve Father overrides, support units and Commonwealth stances")
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "defend"})
	connected.job = {"kind": "move"}; connected.route = [Vector2.ZERO]; connected.target = 123
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "defend"})
	verify(connected.job.kind == "move" and connected.route.size() == 1 and int(connected.target) == 123, "Repeated network stances preserve existing orders")
	w.gloom.erase(line[2])
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "attack"})
	verify(connected.stance == "attack" and isolated.stance == "attack", "Removing a Gloom bridge does not block global Medusa commands")
	connected.job = {"kind": "move"}; connected.route = [Vector2.ZERO]; connected.target = 123
	w.gloom.erase(line[3])
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "gather"})
	verify(connected.stance == "attack" and connected.job.kind == "move" and isolated.stance == "gather", "Only leaving Gloom retains the last stance and orders")
	w.gloom[line[3]] = 20.0
	WorldState.LightlessCoordination.update(w)
	verify(connected.stance == "gather" and connected.job.kind == "idle", "Returning to any Gloom patch applies the latest global stance")
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "attack"})
	var spawned: Dictionary = w.units[w.add_unit("scavenger", connected.pos, -1)]
	WorldState.LightlessCoordination.update(w)
	verify(spawned.stance == "attack", "New Lightless adopt the current global Gloom stance")
	WorldState.LightlessCoordination.release(w, recruit, w.gloom)
	verify(recruit.stance == "attack", "Released recruits adopt the current Medusa stance")
	WorldState.LightlessCoordination.recruit(w, father, recruit, w.gloom)
	w.gloom.erase(line[1])
	WorldState.LightlessCoordination.release(w, recruit, w.gloom)
	verify(recruit.stance == "gather", "Recruits released without a Medusa connection retain their Father's last stance")
	w.gloom[line[1]] = 20.0
	WorldState.LightlessCoordination.recruit(w, father, recruit, w.gloom)
	w.gloom.erase(medusa.cell)
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "defend"})
	verify(connected.stance == "defend" and isolated.stance == "defend", "The Medusa can broadcast even when its own tile is not Gloom")
	w.visible[0][medusa.cell] = true
	var client := WorldState.new(w.cfg); client.reset(472)
	client.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(client.structures.has(int(medusa.id)) and client.structures[int(medusa.id)].network_stance == "defend", "Observed Medusa stance survives a JSON snapshot round trip")
	w._destroy(medusa)
	WorldState.LightlessCoordination.update(w)
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "probe"})
	verify(connected.stance == "attack" and isolated.stance == "attack" and recruit.stance == "gather", "Medusa death supersedes network commands while preserving Father recruits")
	WorldState.LightlessCoordination.release(w, recruit, w.gloom)
	verify(recruit.stance == "attack", "Post-Medusa release removes the Father override")

func father_coordination_checks() -> void:
	var w := world()
	w.gloom.clear()
	for q in range(9): w.gloom[Vector2i(q, 0)] = 20.0
	w.cfg.lightless.fatherLocalRangeTiles = 1
	w.cfg.lightless.fatherRecruitLimit = 1
	var father: Dictionary = w.units[w.add_unit("father", HexGrid.world(Vector2i.ZERO), -1)]
	var other: Dictionary = w.units[w.add_unit("father", HexGrid.world(Vector2i(8, 0)), -1)]
	var unit: Dictionary = w.units[w.add_unit("scavenger", HexGrid.world(Vector2i(8, 0)), -1)]
	var extra: Dictionary = w.units[w.add_unit("stalker", other.pos, -1)]
	father.group_stance = "gather"; other.group_stance = "probe"
	var network := w.gloom
	verify(WorldState.LightlessCoordination.recruit(w, father, unit, network) and unit.stance == "gather", "A Father recruits a remote unit through global Gloom and applies its stance")
	verify(not WorldState.LightlessCoordination.set_stance(w, father, "invalid") and unit.stance == "gather", "Invalid Father stances do not change recruits")
	verify(WorldState.LightlessCoordination.set_stance(w, father, "probe") and unit.stance == "probe", "Changing a Father's stance updates its existing recruits")
	verify(not WorldState.LightlessCoordination.recruit(w, father, extra, network), "A Father cannot exceed its recruit limit")
	verify(WorldState.LightlessCoordination.recruit(w, other, extra, network), "A Father recruits locally without a network requirement")
	verify(not WorldState.LightlessCoordination.recruit(w, other, unit, network) and int(unit.father_id) == int(father.id), "A failed transfer leaves the original Father's assignment intact")
	w.gloom.erase(Vector2i(4, 0))
	WorldState.LightlessCoordination.update(w)
	verify(int(unit.father_id) == int(father.id), "Breaking the Gloom path does not end global recruitment")
	w.gloom.erase(Vector2i(8, 0))
	WorldState.LightlessCoordination.update(w)
	verify(not unit.has("father_id") and int(extra.father_id) == int(other.id), "A remote recruit releases only after leaving Gloom; local recruits remain assigned")
	w.gloom.erase(Vector2i.ZERO); w.gloom[Vector2i(8, 0)] = 20.0
	verify(WorldState.LightlessCoordination.recruit(w, father, unit, w.gloom), "A Father off Gloom can remotely recruit a unit standing on an isolated Gloom patch")
	w.medusa_dead = true
	WorldState.LightlessCoordination.release(w, extra, w.gloom)
	verify(extra.stance == "attack", "Released recruits adopt Attack after Medusa death")
	w = world()
	father = w.units[w.add_unit("father", Vector2.ZERO, -1)]
	unit = w.units[w.add_unit("scavenger", Vector2.ZERO, -1)]
	father.group_stance = "gather"
	WorldState.LightlessCoordination.recruit(w, father, unit, w.gloom)
	for organ in w.structures.values():
		if organ.kind == "medusa": w._destroy(organ); break
	verify(unit.stance == "gather" and int(unit.father_id) == int(father.id), "Medusa death does not override a Father's recruited stance")
	w._destroy(father)
	WorldState.LightlessCoordination.update(w)
	verify(not unit.has("father_id") and unit.stance == "attack", "A Father's death releases recruits to the post-Medusa stance")
	w = world()
	w.cfg.lightless.cpuWombPriority = []
	w.lightless_chyme = 500
	var medusa: Dictionary = {}
	for organ in w.structures.values():
		if organ.kind == "medusa": medusa = organ; break
	WorldState.LightlessColony.develop(w, medusa)
	verify(medusa.spawn_queue.any(func(job): return job.kind == "father"), "The CPU queues a Father after its initial Womb goals")
	father = w.units[w.add_unit("father", Vector2.ZERO, -1)]
	unit = w.units[w.add_unit("scavenger", Vector2(0.5, 0), -1)]
	WorldState.LightlessColony.develop(w, medusa)
	verify(int(unit.get("father_id", 0)) == int(father.id) and unit.stance == "attack", "A CPU Father recruits nearby available units and applies its attack stance")

func gather_checks() -> void:
	var w := world()
	var medusa: Dictionary = {}
	for s in w.structures.values():
		if s.kind == "medusa": medusa = s; break
	var id := w.add_unit("scavenger", w.entity_position(medusa) + Vector2(4, 0), -1)
	var u: Dictionary = w.units[id]
	w.command(-1, {"action": "medusa_stance", "target": medusa.id, "stance": "gather"})
	u.chyme = float(w.cfg.units.scavenger.chymeCapacity)
	var before := w.lightless_chyme
	w._unit_step(u, 0.05)
	verify(u.job.kind == "gather_return" and not u.route.is_empty(), "A full Gather unit routes to a reachable delivery organ")
	advance(w, 8)
	verify(w.lightless_chyme >= before + float(w.cfg.units.scavenger.chymeCapacity) and float(u.chyme) < float(w.cfg.units.scavenger.chymeCapacity), "Gather delivers its cargo before seeking another target")
	w = world(); medusa = {}
	for s in w.structures.values():
		if s.kind == "medusa": medusa = s; break
	w._destroy(medusa)
	id = w.add_unit("scavenger", Vector2.ZERO, -1); u = w.units[id]
	u.stance = "gather"; u.chyme = float(w.cfg.units.scavenger.chymeCapacity)
	before = w.lightless_chyme
	w._unit_step(u, 0.05)
	verify(u.job.kind == "gather_return" and u.chyme == float(w.cfg.units.scavenger.chymeCapacity) and w.lightless_chyme == before, "Gather retains cargo when no delivery organ exists")

func extraction_assault_checks() -> void:
	var w := world(3)
	var unit: Dictionary = w.units[w.add_unit("scavenger", Vector2.ZERO, -1)]
	var original := int(unit.raid_owner)
	var first := (original + 1) % 3
	var second := (original + 2) % 3
	w.players[first].extracting = true; w.players[first].remaining = 30.0
	w.players[second].extracting = true; w.players[second].remaining = 20.0
	verify(int(WorldState.LightlessTactics.assigned_anchor(w, unit).owner) == second, "Assault prioritizes the extraction closest to completion")
	w.players[second].extracting = false
	verify(int(WorldState.LightlessTactics.assigned_anchor(w, unit).owner) == first, "Assault retargets another extracting Anchor")
	w.players[first].extracting = false
	verify(int(WorldState.LightlessTactics.assigned_anchor(w, unit).owner) == original, "After extraction threats end, the original raid assignment resumes")

func chyme_collection_checks() -> void:
	var w := world()
	var attacker: Dictionary = w.units[w.add_unit("scavenger", Vector2.ZERO, -1)]
	var victim: Dictionary = w.units[w.add_unit("marine", Vector2.ZERO, 0)]
	var weapon: Dictionary = w.cfg.weapons.marine_rifle.duplicate(true)
	weapon.damagePerHit = 1000
	victim.hp = 4.5
	var initial := w.lightless_chyme
	w._weapon_damage(victim, weapon, attacker)
	verify(attacker.chyme == 4.5 and w.lightless_chyme == initial, "Combat Chyme uses actual health removed and remains carried")
	victim = w.units[w.add_unit("marine", Vector2.ZERO, 0)]
	w._weapon_damage(victim, weapon, attacker)
	verify(attacker.chyme == float(w.cfg.units.scavenger.chymeCapacity), "Combat Chyme cannot exceed carrying capacity")
	var medusa: Dictionary = {}
	for organ in w.structures.values():
		if organ.kind == "medusa": medusa = organ; break
	attacker.pos = w.entity_position(medusa)
	w._unit_step(attacker, 0.0)
	verify(attacker.chyme == 0 and w.lightless_chyme == initial + float(w.cfg.units.scavenger.chymeCapacity), "Chyme reaches the colony only at an eligible organ")

func run() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/prototype.json"))
	global_gloom_vision_checks(); controlled_lightless_autonomy_checks(); lightless_player_checks(); womb_reconfiguration_checks(); strategy_recovery_checks(); thresher_navigation_checks()
	if "--lightless-only" in OS.get_cmdline_user_args(): print("Lightless checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	chyme_collection_checks(); gland_checks(); gather_checks(); extraction_assault_checks(); stoma_checks(); medusa_stance_checks(); father_coordination_checks(); lightless_defense_checks(); lightless_defend_stance_checks()
	if "--missions-only" in OS.get_cmdline_user_args():
		mission_playthrough_checks(); print("Mission checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--complex-only" in OS.get_cmdline_user_args():
		complex_command_checks(); print("Complex command checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--performance-only" in OS.get_cmdline_user_args():
		performance_cache_checks(); print("Performance cache checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--spawns-only" in OS.get_cmdline_user_args():
		medusa_spawn_checks(); print("Spawn checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--construction-only" in OS.get_cmdline_user_args():
		idle_engineer_checks(); wall_line_checks(); print("Construction checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--visibility-only" in OS.get_cmdline_user_args():
		visibility_optimization_checks(); print("Visibility checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--power-only" in OS.get_cmdline_user_args():
		power_balance_checks(); print("Power checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--balance-only" in OS.get_cmdline_user_args():
		power_balance_checks(); colony_production_checks(); print("Power and colony checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--orders-only" in OS.get_cmdline_user_args():
		queued_order_checks(); print("Queued order checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--ai-only" in OS.get_cmdline_user_args():
		multiplayer_pressure_checks(); lightless_behavior_checks(); print("Lightless checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--movement-only" in OS.get_cmdline_user_args():
		movement_checks(); print("Movement checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--memory-only" in OS.get_cmdline_user_args():
		structure_memory_checks(); print("Structure memory checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	if "--config-only" in OS.get_cmdline_user_args():
		var errors := ConfigRules.validate(settings)
		for error in errors: printerr(error)
		print("Configuration checks: failures: ", errors.size())
		quit(0 if errors.is_empty() else 1); return
	if "--routes-only" in OS.get_cmdline_user_args():
		route_order_checks(); print("Route checks: ", assertions, "; failures: ", failures.size()); quit(0 if failures.is_empty() else 1); return
	complex_command_checks(); multiplayer_pressure_checks(); activity_checks(); blueprint_recovery_checks(); mission_checks(); mission_playthrough_checks()
	power_balance_checks(); colony_production_checks(); queued_order_checks(); visibility_optimization_checks(); idle_engineer_checks(); wall_line_checks(); medusa_spawn_checks(); performance_cache_checks()
	for cell in HexGrid.disk(Vector2i.ZERO, 10): verify(HexGrid.cell(HexGrid.world(cell)) == cell, "Hex round trip")
	var a := world(5)
	var b := world(5)
	verify(JSON.stringify(a.snapshot(0)) == JSON.stringify(b.snapshot(0)), "Seeded map and deployment reproduce")
	var nest := Vector2i.ZERO
	for s in a.structures.values():
		if s.kind == "medusa": nest = s.cell
	for owner in a.players:
		var anchor: Dictionary = a.structures[int(a.players[owner].anchor)]
		var from := a.nearest_free(anchor.cell)
		var to := a.nearest_free(nest)
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
	verify(w.structures[flood].powered and w.structures[relay].powered, "A zero-demand Relay does not overload the starting grid")
	var extra_turret := w.add_structure("sentry", anchor.cell + Vector2i(2, 1), 0)
	w.step(0.05)
	verify(w.structures[flood].blackout, "Overload triggers blackout at rounded threshold")
	w.structures[extra_turret].enabled = false
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
	worker.auto_work_remaining = 2.0 # Isolate Anchor healing from idle Engineer repairs.
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
	w.cfg.units.engineer.armor = 100
	w._probe_step(w.units[prober], float(w.cfg.lightless.probeResistanceWindowSeconds) + 0.1)
	verify(w.units[prober].job.kind == "probe" and float(w.units[prober].job.pressure) == 0, "A probe cannot signal an attack when armor prevents damage")
	w.cfg.units.engineer.armor = 0
	w.units.erase(prober)
	prober = w.add_unit("scavenger", worker.pos + Vector2(0.6, 0), -1)
	var ally := w.add_unit("scavenger", worker.pos + Vector2(0.8, 0.2), -1)
	w._probe_step(w.units[prober], 0.05)
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
	movement_checks()
	structure_memory_checks()
	lightless_behavior_checks()
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
	w.command(0, {"action": "stop", "ids": [worker]}) # Keep friendly retry traffic out of the enemy-only check.
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
	for patch in [{"cpuDesiredStomas": -1}, {"cpuDesiredStomas": 1.5}, {"cpuStomaMinOrganDistanceTiles": 0}, {"cpuStomaMinOrganDistanceTiles": "six"}]:
		var invalid := settings.duplicate(true)
		invalid.lightless.merge(patch, true)
		verify(ConfigRules.validate(invalid).any(func(error): return error.contains("lightless." + str(patch.keys()[0]))), "Invalid Stoma tuning reports its configuration path")
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


func ai_world() -> WorldState:
	var w := world()
	w.units.clear(); w.structures.clear(); w.gloom.clear()
	for cell in w.tiles: w.tiles[cell].cliff = false
	var anchor := w.add_structure("anchor", Vector2i(5, 0), 0)
	w.players[0].anchor = anchor
	var medusa := w.add_structure("medusa", Vector2i(-6, 0), -1)
	w.structures[medusa].passive = -10000.0
	w._rebuild_navigation(); w.update_visibility()
	return w

func multiplayer_pressure_checks() -> void:
	for count in range(2, 6):
		var w := world(count)
		w.lightless_dispatches.clear()
		var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
		var position := HexGrid.world(anchor.cell + Vector2i(2, 0))
		for kind in ["scavenger", "stalker"]:
			var assignments: Dictionary = {}
			for i in range(count * 3):
				var id := w.add_unit(kind, position, -1)
				var owner := int(w.units[id].raid_owner)
				assignments[owner] = int(assignments.get(owner, 0)) + 1
				verify(WorldState.LightlessTactics.assigned_anchor(w, w.units[id]).owner == owner, "Raid assignments stay stable on repeated decisions")
			verify(assignments.size() == count and assignments.values().all(func(amount): return amount == 3), "Each unit type is evenly dispatched despite every spawn being closest to player one")
		var old := w.lightless_dispatches.duplicate(true)
		for u in w.units.values():
			if u.owner == -1 and u.get("raid_owner", -1) == 0: w.units.erase(u.id)
		for i in range(count): w.add_unit("scavenger", position, -1)
		for owner in range(count): verify(int(w.lightless_dispatches.scavenger[owner]) == int(old.scavenger[owner]) + 1, "Casualties do not redirect all replacements toward the closest player")
	var mixed := world(5); mixed.lightless_dispatches.clear()
	for kind in ["scavenger", "stalker", "ravager", "thresher", "shade"]:
		var id := mixed.add_unit(kind, Vector2.ZERO, -1)
		WorldState.LightlessTactics.assigned_anchor(mixed, mixed.units[id])
	verify(mixed.lightless_dispatches._total.size() == 5 and mixed.lightless_dispatches._total.values().all(func(amount): return amount == 1), "Small mixed-type cohorts spread across all players rather than giving each new type to the nearest base")
	var w := world(3); w.lightless_dispatches.clear()
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var raiders: Array = []
	for i in range(3): raiders.append(w.units[w.add_unit("scavenger", HexGrid.world(anchor.cell + Vector2i(2, 0)), -1)])
	var leader: Dictionary = raiders.filter(func(u): return int(u.raid_owner) == 0)[0]
	leader.pos = w.entity_position(anchor) + Vector2(0.5, 0)
	w._probe_step(leader, 0.05)
	w._probe_step(leader, float(w.cfg.lightless.probeResistanceWindowSeconds) + 0.1)
	verify(leader.job.kind == "attack", "The closest player's assigned probe still commits normally")
	verify(raiders.filter(func(u): return int(u.raid_owner) != 0).all(func(u): return u.stance == "probe" and u.job.kind == "idle"), "Local recruitment cannot hijack probes assigned to other players")
	for s in w.structures.values():
		if s.kind == "medusa": w._destroy(s); break
	for u in raiders:
		w._unit_step(u, 0.05)
		verify(w.entity(int(u.target)).get("owner", -2) == int(u.raid_owner), "Post-Medusa attackers retain their assigned player instead of choosing the nearest Anchor")
	w.eliminate(0)
	var reassigned := WorldState.LightlessTactics.assigned_anchor(w, leader)
	verify(not reassigned.is_empty() and reassigned.owner != 0, "Raiders retarget after elimination even when the eliminated Anchor survives")
	var snapshot: Dictionary = w.snapshot(1)
	verify(snapshot.units.all(func(u): return u.owner >= 0 or not u.has("raid_owner")), "Enemy raid assignments are not exposed in player snapshots")
	w.reset(472, 3)
	var replay := WorldState.new(w.cfg); replay.reset(472, 3)
	verify(w.lightless_dispatches == replay.lightless_dispatches and w.units == replay.units, "Seeded raid assignments reset and replay deterministically")

func lightless_behavior_checks() -> void:
	var w := ai_world()
	var anchor: Dictionary = w.structures[int(w.players[0].anchor)]
	var scavenger := w.add_unit("scavenger", Vector2(-2, 0), -1)
	var ally := w.add_unit("scavenger", Vector2(-2, 0.4), -1)
	var original_health := float(anchor.hp)
	advance(w, 15)
	verify(float(anchor.hp) < original_health, "Scavengers cross an unopposed light perimeter and damage the known Anchor")
	verify(w.units[scavenger].job.kind == "attack" and w.units[ally].job.kind == "attack", "Nearby probes commit together instead of accumulating outside illumination")

	w = ai_world(); anchor = w.structures[int(w.players[0].anchor)]
	for cell in HexGrid.disk(anchor.cell, 3):
		if HexGrid.distance(cell, anchor.cell) == 3: w.add_structure("wall", cell, 0)
	w._rebuild_navigation(); w.update_visibility()
	scavenger = w.add_unit("scavenger", Vector2.ZERO, -1)
	var unit: Dictionary = w.units[scavenger]
	unit.job = {"kind": "attack"}; unit.target = anchor.id
	advance(w, 5)
	var obstruction: Dictionary = w.entity(int(unit.target))
	verify(not obstruction.is_empty() and obstruction.kind == "wall" and float(obstruction.hp) < float(w.cfg.structures.wall.health), "Committed attackers damage the visible enclosing wall instead of idling against it")
	verify(int(unit.job.get("objective", 0)) == int(anchor.id), "Attacking an obstruction preserves the original objective")
	if not obstruction.is_empty() and obstruction.kind == "wall":
		w._destroy(obstruction)
		w._unit_step(unit, 0.05)
		verify(int(unit.target) == int(anchor.id), "Attackers resume their objective after the blocking wall is destroyed")

	w = ai_world()
	var isolated := Vector2i(-2, 0)
	var reachable := Vector2i(-5, 3)
	for direction in HexGrid.DIRECTIONS: w.tiles[isolated + direction].cliff = true
	w.gloom[isolated] = 20.0; w.gloom[reachable] = 20.0
	w._rebuild_navigation(); w.update_visibility()
	scavenger = w.add_unit("scavenger", HexGrid.world(Vector2i(0, -3)), -1)
	unit = w.units[scavenger]; unit.hp = 15; unit.job = {"kind": "retreat"}
	WorldState.LightlessTactics.retreat(w, unit)
	verify(not unit.route.is_empty() and HexGrid.cell(unit.route.back()) == reachable, "Retreat chooses reachable Gloom rather than a closer isolated patch")
	unit.route.clear(); unit.job.repath_remaining = 0.0
	w._unit_step(unit, 0.05)
	verify(not unit.route.is_empty(), "An interrupted retreat retries its route while wounded")

	w = ai_world()
	var scout := w.add_unit("scout", Vector2.ZERO, 0)
	var passenger := w.add_unit("marine", Vector2(-0.2, 0), 0)
	w.units[passenger].vehicle = scout; w.units[scout].passengers.append(passenger)
	scavenger = w.add_unit("scavenger", Vector2(-1, 0), -1)
	w._probe_step(w.units[scavenger], float(w.cfg.lightless.probeResistanceWindowSeconds) + 0.1)
	verify(int(w.units[scavenger].target) == scout, "Probes target the vehicle rather than its protected passenger")
	for seed_value in [472, 91]:
		w = world(); w.reset(seed_value, 1); w.units.clear()
		for structure in w.structures.values():
			if structure.kind == "medusa": structure.passive = -10000.0
		anchor = w.structures[int(w.players[0].anchor)]
		original_health = float(anchor.hp)
		var nest_cell := Vector2i.ZERO
		for structure in w.structures.values():
			if structure.kind == "medusa": nest_cell = structure.cell
		for i in range(3): w.add_unit("scavenger", HexGrid.world(w.nearest_free(nest_cell + HexGrid.DIRECTIONS[i] * 2)), -1)
		advance(w, 90)
		verify(float(anchor.hp) < original_health, "Scavengers reach and pressure an undefended base across generated cliffs (seed %d)" % seed_value)

	var first := ai_world()
	var second := ai_world()
	for state in [first, second]:
		state.add_unit("scavenger", Vector2(-2, 0), -1)
		state.add_unit("scavenger", Vector2(-2, 0.4), -1)
		advance(state, 15)
	verify(JSON.stringify(first.snapshot(0)) == JSON.stringify(second.snapshot(0)), "Lightless approach, pressure and combat decisions replay deterministically")

func movement_world() -> WorldState:
	var w := world(2)
	w.units.clear(); w.structures.clear(); w.gloom.clear(); w.illuminated.clear()
	for tile in w.tiles.values(): tile.cliff = false
	w._rebuild_navigation()
	return w

func probe_contact_planning_checks() -> void:
	var w := thresher_fixture()
	var probe: Dictionary = w.units[w.add_unit("scavenger", Vector2.ZERO, -1)]
	var victim: Dictionary = w.units[w.add_unit("marine", Vector2(0.5, 0), 0)]
	probe.stance = "probe"; w.path_queries = 0
	w._unit_step(probe, 0.05)
	verify(w.path_queries == 0 and victim.hp < float(w.cfg.units.marine.health), "A Probe engages an adjacent visible enemy without first planning an unused route to the distant Anchor")

func movement_filter_equivalence_checks() -> void:
	var w := movement_world()
	var unit: Dictionary = w.units[w.add_unit("ravager", Vector2.ZERO, -1)]
	var random := RandomNumberGenerator.new(); random.seed = 472
	var matches := true; var checks := 0
	for layout in range(64):
		for cell in HexGrid.disk(Vector2i.ZERO, 3): w.tiles[cell].cliff = random.randf() < 0.3
		w.tiles[Vector2i.ZERO].cliff = false
		w.tiles[Vector2i(1, 0)].cliff = false
		w._rebuild_navigation()
		w.navigation.query_world = weakref(w); w.navigation.query_unit = unit
		for radius in [0.15, HexGrid.RADIUS * 0.5, 0.289, 0.37, 0.49, 0.5, 0.6]:
			w.cfg.units.ravager.collisionRadiusTiles = radius - float(w.cfg.movement.pathfinding.clearancePaddingTiles)
			for direction in HexGrid.DIRECTIONS:
				if w.tiles[direction].cliff: continue
				var filtered: bool = not w.wide_navigation.are_points_connected(w.point_ids[Vector2i.ZERO], w.point_ids[direction]) if WorldState.RouteNavigation.uses_wide_graph(radius) else w.navigation._filter_neighbor(w.point_ids[Vector2i.ZERO], w.point_ids[direction])
				var exact: bool = not WorldState.RouteNavigation.clear_segment(w, unit, Vector2.ZERO, HexGrid.world(direction), true)
				if filtered != exact: matches = false
				checks += 1
	verify(matches, "Fast adjacent-edge clearance matches exact swept geometry across %d seeded obstacle/radius cases" % checks)
	w = movement_world(); unit = w.units[w.add_unit("ravager", Vector2.ZERO, -1)]
	var gate: Dictionary = w.structures[w.add_structure("gate", Vector2i(0, 1), 0)]
	for owner in [-1, 0]:
		unit.owner = owner
		for opened in [false, true]:
			gate.open = opened
			for locked in [false, true]:
				gate.locked = locked; w._rebuild_navigation()
				w.navigation.query_world = weakref(w); w.navigation.query_unit = unit
				var admitted := {gate.cell: true} if gate.owner == owner and not locked and not opened else {}
				w._refresh_wide_edges(admitted, admitted, w.wide_navigation)
				verify(w.wide_navigation.are_points_connected(w.point_ids[Vector2i.ZERO], w.point_ids[Vector2i(1, 0)]) == WorldState.RouteNavigation.clear_segment(w, unit, Vector2.ZERO, Vector2.RIGHT, true), "Native clearance preserves friendly/enemy gate opening and locking")
				w._refresh_wide_edges(admitted, {}, w.wide_navigation)
				var before: bool = w.wide_navigation.are_points_connected(w.point_ids[Vector2i.ZERO], w.point_ids[Vector2i(1, 0)])
				unit.job = {"kind": "attack"}
				w._route_path(unit, Vector2i.ZERO, Vector2i(1, 0))
				verify(w.wide_navigation.are_points_connected(w.point_ids[Vector2i.ZERO], w.point_ids[Vector2i(1, 0)]) == before and w.wide_navigation.is_point_disabled(w.point_ids[gate.cell]) == w.blocked(gate.cell), "Temporary gate admission cannot leak into later native path queries")

func movement_checks() -> void:
	probe_contact_planning_checks()
	movement_filter_equivalence_checks()
	var w := movement_world()
	var id := w.add_unit("operator", Vector2(0.42, 0.12), 0)
	var u: Dictionary = w.units[id]
	var goal := Vector2(4.3, 1.13)
	w.move_to(u, goal)
	verify(u.route.size() == 1 and u.route[0] == goal, "Clear off-grid orders use one straight segment to the exact click")
	var forward := true
	for i in range(20):
		var before: Vector2 = u.pos
		w.move_to(u, goal)
		w._move(u, 0.05)
		if u.pos.distance_to(goal) >= before.distance_to(goal): forward = false
	verify(forward, "Repeated orders keep advancing rather than returning to a tile center")
	for i in range(100): w._move(u, 0.05)
	verify(u.pos.distance_to(goal) < 0.00001, "Continuous routing preserves the exact off-grid destination")
	u.pos = Vector2(0.3, 0.1); goal = Vector2(0.45, 0.2)
	w.move_to(u, goal); w._move(u, 1)
	verify(u.pos == goal, "A move inside the current hex never detours through its center")
	u.pos = Vector2.ZERO; u.route = [Vector2(0.005, 0), Vector2(0.08, 0), Vector2(1, 0)]
	w._move(u, 0.1)
	verify(absf(u.pos.x - float(w.cfg.units.operator.speedTilesPerSecond) * 0.1) < 0.00001, "Movement spends its whole tick budget across short waypoints")

	w = movement_world(); w.tiles[Vector2i.ZERO].cliff = true; w._rebuild_navigation()
	id = w.add_unit("scout", Vector2(-1, 0), 0); u = w.units[id]
	var driver := w.add_unit("operator", Vector2(-5, -5), 0)
	u.driver = driver; w.units[driver].vehicle = id
	goal = HexGrid.world(Vector2i(0, -1))
	w.move_to(u, goal)
	verify(u.route.size() > 1, "Wide vehicles route around a cliff corner that a center-point ray would clip")
	var safe := true
	for i in range(100):
		w._move(u, 0.05)
		for j in range(16):
			var edge: Vector2 = u.pos + Vector2.from_angle(TAU * j / 16) * float(w.cfg.units.scout.collisionRadiusTiles)
			if HexGrid.cell(edge) == Vector2i.ZERO: safe = false
	verify(safe and u.pos.distance_to(goal) < 0.001, "Vehicle bodies clear the entire cliff corner and reach their destination")

	w = movement_world()
	id = w.add_unit("operator", Vector2(-4, 0), 0); u = w.units[id]
	w.move_to(u, Vector2(4, 0))
	w.add_structure("wall", Vector2i.ZERO, 0)
	w._move(u, 10)
	verify(u.pos.x < -0.5 and u.route.is_empty(), "A newly placed obstacle cannot be tunneled through by a long movement step")
	var replica := movement_world()
	replica.apply_snapshot(JSON.parse_string(JSON.stringify(w.snapshot(0))), 0)
	verify(replica.blocked(Vector2i.ZERO), "JSON snapshots rebuild structure collision occupancy with normalized IDs")

	w = movement_world()
	var gate_id := w.add_structure("gate", Vector2i.ZERO, 0)
	w.structures[gate_id].open = true; w._rebuild_navigation()
	id = w.add_unit("operator", Vector2(-4, 0), 0); u = w.units[id]
	w.move_to(u, Vector2(4, 0))
	w.structures[gate_id].open = false; w.structures[gate_id].locked = true; w._rebuild_navigation()
	w._move(u, 10)
	verify(u.pos.x < -0.5 and not w.structures[gate_id].open, "A gate locked after route planning still stops a smoothed path")

	w = movement_world()
	w.illuminated[0] = {}
	for cell in HexGrid.disk(Vector2i.ZERO, 1):
		w.illuminated[0][cell] = true
		w.dark_navigation.set_point_weight_scale(w.point_ids[cell], float(w.cfg.lightless.darkPathLightPenalty))
	id = w.add_unit("scavenger", Vector2(-4, 0), -1); u = w.units[id]
	w.move_to(u, Vector2(4, 0))
	verify(u.route.size() > 1, "Smoothing retains a non-attacking Lightless detour around illumination")
	u.job = {"kind": "attack"}
	w.move_to(u, Vector2(4, 0))
	verify(u.route.size() == 1, "Committed Lightless attacks can take a direct route across light")

func structure_memory_checks() -> void:
	var w := movement_world()
	w.visible[0] = {}; w.visible[1] = {}; w.structure_memory.clear()
	var cell := Vector2i.ZERO
	w.known[0][cell] = true
	var enemy := w.add_structure("wall", cell, 1)
	verify(w.observed_entity(enemy, 0).is_empty(), "Explored terrain alone does not reveal a newly built enemy structure")
	w.visible[0][cell] = true; w.time_seconds = 10; w.tick = 200; w._remember_structures()
	var recorded_hp := float(w.structures[enemy].hp)
	verify(not w.observed_entity(enemy, 0).get("remembered", false), "Visible structures use current observations")
	w.visible[0].clear(); w._remember_structures()
	w.structures[enemy].hp = 17; w.structures[enemy].powered = false; w.structures[enemy].buffer = 123
	var memory := w.observed_entity(enemy, 0)
	verify(memory.get("remembered", false) and float(memory.hp) == recorded_hp and int(memory.buffer) == 0, "Hidden structure damage and inventory changes do not alter last-seen records")
	verify(float(w.observed_entity(enemy, 1).hp) == 17, "Owners retain live information about their own hidden structures")
	var soldier := w.add_unit("marine", Vector2(-5, 0), 0)
	var denial := w.command(0, {"action": "attack", "ids": [soldier], "target": enemy})
	verify(denial == "Rediscover this structure before targeting it", "A stale scouting record is not a live combat target")
	var newer := w.add_structure("depot", Vector2i(1, 0), 1)
	w.known[0][Vector2i(1, 0)] = true
	w._remember_structures()
	var packet := w.snapshot(0)
	verify(not packet.structures.any(func(e): return int(e.id) == newer), "New construction on previously explored fog is omitted from snapshots")
	var encoded: Dictionary = packet.structures.filter(func(e): return int(e.id) == enemy)[0]
	verify(encoded.remembered and float(encoded.hp) == recorded_hp and int(encoded.last_seen_tick) == 200, "Snapshots export frozen observed state and its last-seen timestamp")
	var replica := movement_world()
	replica.apply_snapshot(JSON.parse_string(JSON.stringify(packet)), 0)
	verify(replica.entity(enemy).is_empty() and replica.observed_entity(enemy, 0).get("remembered", false), "Client replicas keep scouting records separate from live entities")
	verify(not replica.blocked(cell), "Remembered structures do not become authoritative collision obstacles")
	w._destroy(w.structures[enemy])
	verify(not w.observed_entity(enemy, 0).is_empty() and not w.blocked(cell), "A hidden demolition preserves its silhouette without affecting real collision")
	verify(w.command(0, {"action": "attack", "ids": [soldier], "target": enemy}) == denial, "Targeting responses do not disclose whether a remembered structure was demolished")
	verify(not w.structure_memory.get(1, {}).has(enemy), "Destroyed owned structures do not leave owned ghosts")
	w.visible[0][cell] = true; w._remember_structures()
	verify(w.observed_entity(enemy, 0).is_empty() and w.known[0].has(cell), "Scouting an empty old footprint clears the structure while retaining explored terrain")

	var large := w.add_structure("factory", Vector2i(4, 0), 1)
	w.visible[0] = {Vector2i(3, 0): true}; w._remember_structures()
	verify(w.structure_visible(0, w.structures[large]) and not w.visible[0].has(Vector2i(4, 0)), "Seeing part of a large structure reveals it without requiring its center tile")
	w.visible[0].clear(); w._remember_structures()
	w.structures[large].hp = 9
	verify(float(w.observed_entity(large, 0).hp) != 9, "Large structures also freeze when their footprint leaves vision")
	w.visible[0][Vector2i(3, 0)] = true; w._remember_structures()
	verify(float(w.observed_entity(large, 0).hp) == 9 and not w.observed_entity(large, 0).get("remembered", false), "Rediscovery replaces stale information with current structure state")
	w._destroy(w.structures[large])
	verify(w.observed_entity(large, 0).is_empty(), "Visible destruction removes both live and remembered views immediately")
	var creature := w.add_unit("scavenger", Vector2(-3, 0), -1)
	w.visible[0] = {Vector2i(-3, 0): true}; w._remember_structures()
	verify(not w.observed_entity(creature, 0).is_empty(), "A visible enemy unit can be inspected")
	w.visible[0].clear(); w._remember_structures()
	verify(w.observed_entity(creature, 0).is_empty(), "Mobile enemies do not acquire fog-of-war memory")
	w = movement_world(); w.visible[0] = {Vector2i.ZERO: true}
	enemy = w.add_structure("wall", Vector2i.ZERO, 1)
	w._remember_structures(); w.structures[enemy].hp = 123
	w.update_visibility()
	verify(w.observed_entity(enemy, 0).get("remembered", false) and float(w.observed_entity(enemy, 0).hp) == 123, "Losing sight captures the latest observed state rather than an older refresh")

func complex_fixture() -> WorldState:
	var w := movement_world()
	for cell in w.tiles:
		w.tiles[cell].resource = ""; w.tiles[cell].amount = 0; w.known[0][cell] = true
	var anchor := w.add_structure("anchor", Vector2i(-5, 0), 0)
	w.players[0].anchor = anchor
	w.resources(0).ore = 0
	w.tiles[Vector2i(3, 0)].resource = "ore"; w.tiles[Vector2i(3, 0)].amount = 500
	return w

func complex_command_checks() -> void:
	var w := complex_fixture()
	var worker := w.add_unit("engineer", Vector2.ZERO, 0)
	var guard := w.add_unit("marine", Vector2(0, 1), 0)
	var unrelated := w.add_unit("operator", Vector2(1, 1), 0)
	w.command(0, {"action": "mine", "ids": [guard, worker], "q": 3, "r": 0})
	verify(w.command_groups.size() == 1 and w.units[guard].get("group_role") == "escort", "Mixed mining selections create a persistent expedition with military escorts")
	verify(not w.units[unrelated].has("command_group"), "Expeditions never recruit nearby unselected workers")
	advance(w, 30)
	verify(w.resources(0).ore > 0, "Foot expeditions gather and physically deliver resources")
	verify(w.units[guard].pos.distance_to(HexGrid.world(Vector2i(3, 0))) < 7 or w.units[guard].pos.distance_to(w.units[worker].pos) < 7, "Guards travel with workers and defend the current worksite or delivery")
	verify(w.units[guard].stance == "defensive", "Complex commands preserve combat stance")
	var a := w.activity(w.units[guard])
	verify(a.get("group", 0) > 0 and a.get("role") == "escort" and a.has("source"), "Selected guards expose their expedition role, phase and source")
	var old: Dictionary = w.units[worker].job.duplicate(true)
	w.command(0, {"action": "mine", "ids": [worker, guard], "q": 11, "r": 0})
	verify(w.units[worker].job == old and w.command_groups.size() == 1, "Invalid complex targets leave current orders intact")
	w.command(0, {"action": "stop", "ids": [worker]})
	advance(w, 2)
	verify(not w.units[worker].has("command_group") and w.activity(w.units[guard]).blocker == "no_workers", "Interrupted workers permanently leave while escorts retain the expedition and report no workers")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0)
	guard = w.add_unit("marine", Vector2(0, 1), 0)
	var ranger := w.add_unit("ranger", Vector2(0, 2), 0)
	w.command(0, {"action": "mine", "ids": [worker, guard, ranger], "q": 3, "r": 0})
	advance(w, 10)
	verify(int(w.units[ranger].driver) == guard and w.units[worker].get("group_role") == "worker", "Military drives a Ranger while the only Engineer remains a gatherer")
	w.cfg.units.ranger.cargoCapacity = 10
	advance(w, 120)
	var total := int(w.resources(0).ore) + int(w.tiles[Vector2i(3, 0)].amount)
	for u in w.units.values(): total += int(u.cargo.get("ore", 0))
	verify(w.resources(0).ore > 20, "Vehicle expedition performs repeated physical hauling cycles")
	verify(total == 500, "Repeated convoy hauling conserves every resource item")
	verify(int(w.units[ranger].driver) == guard, "Deploying and unloading workers retains the real driver")
	var expedition_id := int(w.units[ranger].command_group)
	w.command(0, {"action": "move", "ids": [ranger], "x": -4, "z": 4})
	verify(w.units[ranger].get("command_group", 0) != expedition_id and w.units[guard].get("command_group", 0) != expedition_id, "Manually redirecting a vehicle also releases its actual crew")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); ranger = w.add_unit("ranger", Vector2(0, 1), 0)
	w.command(0, {"action": "mine", "ids": [worker, ranger], "q": 3, "r": 0})
	advance(w, 30)
	verify(int(w.units[ranger].driver) == 0 and w.resources(0).ore > 0 and w.activity(w.units[ranger]).blocker == "no_driver", "One Engineer plus an empty Ranger falls back to a foot expedition with a visible staffing blocker")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	var wall := w.add_structure("wall", Vector2i(3, 0), 0)
	w.structures[wall].hp = 10; w.resources(0).ore = 100
	w.command(0, {"action": "repair", "ids": [guard, worker], "target": wall})
	advance(w, 2)
	verify(w.units[guard].has("command_group") and w.units[guard].home.distance_to(w.entity_position(w.structures[wall])) < 6, "Repair orders place military into defensive positions around the repair target")
	advance(w, 65)
	verify(float(w.structures[wall].hp) == float(w.cfg.structures.wall.health) and w.command_groups.is_empty(), "Repair groups finish the actual repair and release participants")
	w.command(0, {"action": "patrol", "ids": [worker, guard], "x": -7, "z": 0})
	advance(w, 8)
	verify(w.command_groups.size() == 1 and w.units[worker].pos.distance_to(w.units[guard].pos) < 5, "Mixed patrol groups follow a common route together")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(w.snapshot(0)))
	var client := WorldState.new(w.cfg); client.apply_snapshot(snap, 0)
	verify(client.activity(client.units[guard]).get("group", 0) > 0, "Group activity survives multiplayer snapshot serialization")
	w.command(0, {"action": "stop", "ids": [worker, guard]})
	w.command(0, {"action": "move", "ids": [worker], "x": 0, "z": 0})
	w.command(0, {"action": "move", "ids": [guard], "x": 0, "z": 1})
	w.command(0, {"action": "repair", "ids": [worker, guard], "target": wall, "queued": true})
	advance(w, 20)
	verify(w.command_groups.is_empty() and w.units[worker].orders.is_empty() and w.units[guard].orders.is_empty(), "Queued group commands synchronize participants after their preceding orders")


	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	w.resources(0).ore = 100
	w.command(0, {"action": "mine", "ids": [worker, guard], "q": 3, "r": 0})
	advance(w, 30)
	verify(w.activity(w.units[worker]).blocker == "storage_full" and w.cargo_amount(w.units[worker]) == 20, "Expeditions keep cargo and expose full-storage blockers")
	w.resources(0).ore = 0; advance(w, 10)
	verify(w.resources(0).ore > 0, "A waiting expedition resumes when storage becomes available")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	w.tiles[Vector2i(3, 0)].amount = 2
	w.tiles[Vector2i(4, 0)].resource = "ore"; w.tiles[Vector2i(4, 0)].amount = 40
	w.command(0, {"action": "mine", "ids": [worker, guard], "q": 3, "r": 0})
	advance(w, 40)
	verify(w.resources(0).ore > 2, "Depleted mining sites find another known reachable patch of the same resource")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	var facility := w.add_structure("foundry", Vector2i(3, 0), 0)
	w.structures[facility].enabled = false; w.structures[facility].buffer = 6
	w.command(0, {"action": "mine", "ids": [worker, guard], "q": 3, "r": 0, "facility": facility})
	advance(w, 30)
	verify(w.resources(0).alloy > 0 and int(w.structures[facility].buffer) == 0, "Expeditions recover buffered output from stopped facilities and deliver a partial load")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	ranger = w.add_unit("ranger", Vector2(0, 2), 0)
	w.command(0, {"action": "board", "ids": [guard], "target": ranger}); advance(w, 2)
	w.command(0, {"action": "board", "ids": [worker], "target": ranger}); advance(w, 2)
	w.command(0, {"action": "mine", "ids": [ranger], "q": 3, "r": 0})
	verify(w.command_groups.size() == 1 and w.command_groups.values()[0].members.size() == 3, "Selecting an occupied vehicle includes its actual friendly crew")
	var replacement := w.add_unit("operator", Vector2(0, 3), 0)
	w.command(0, {"action": "mine", "ids": [ranger, replacement], "q": 3, "r": 0})
	advance(w, 5); w._destroy(w.units[guard]); advance(w, 12)
	verify(int(w.units[ranger].driver) == replacement, "A lost driver is replaced only by an existing expedition member while retaining a gatherer")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	ranger = w.add_unit("ranger", Vector2(0, 4), 0)
	w.command(0, {"action": "mine", "ids": [worker, guard, ranger], "q": 3, "r": 0})
	w._destroy(w.units[ranger]); advance(w, 2)
	verify(w.command_groups.values()[0].seats.values().all(func(id): return int(id) != ranger), "Destroyed convoy vehicles immediately relinquish stale seat reservations")
	advance(w, 60)
	verify(w.resources(0).ore > 0, "Surviving convoy members continue harvesting and delivering on foot after vehicle loss")
	w = complex_fixture()
	worker = w.add_unit("engineer", Vector2.ZERO, 0); guard = w.add_unit("marine", Vector2(0, 1), 0)
	var escorted := w.add_unit("operator", Vector2(3, 0), 0)
	w.command(0, {"action": "escort", "ids": [worker, guard], "target": escorted})
	w.command(0, {"action": "move", "ids": [escorted], "x": 3, "z": 8})
	advance(w, 25)
	verify(w.units[worker].pos.y > 3 and w.units[guard].pos.y > 3, "Mixed escorts follow a moving target with a shared defensive formation")
	var enemy_packet := w.snapshot(1)
	verify(enemy_packet.units.all(func(u): return not u.has("command_group") and not u.has("activity")), "Enemy snapshots do not disclose group membership or orders")
