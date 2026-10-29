extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.set_process(false); game.begin_run()
	check(game.HOME == Vector3.ZERO and game.core.position == Vector3.ZERO, "Command Center starts at the center of the large hexagonal map")
	check(game.Terrain.contains(Vector3(85, 0, 0)) and not game.Terrain.contains(Vector3(90, 0, 80)), "large map accepts distant interior cells and excludes rectangular corners")
	var path: PackedVector3Array = game.navigation.path(game.jeep.position, game.DEPOSIT)
	var length := 0.0
	for i in range(1, path.size()): length += path[i].distance_to(path[i - 1])
	print("CANYON_ROUTE points=", path.size(), " length=", length)
	check(path.size() > 2 and length > game.jeep.position.distance_to(game.DEPOSIT) * 1.15, "connected cliff cells force a detour to the mineral objective")
	var reachable := true
	for resource in game.resource_nodes:
		var route: PackedVector3Array = game.navigation.path(game.jeep.position, resource.position)
		if route.is_empty() or route[-1].distance_to(resource.position) > 4: reachable = false; print("UNREACHABLE ", resource.position)
	check(reachable, "every resource patch remains reachable through canyon passages or ramps")
	var aligned := true
	for obstacle in game.rocks:
		if not obstacle.has("cell") or obstacle.position.distance_to(game.Hex.snap(obstacle.position, 2)) > 3.1: aligned = false
	check(aligned and game.rocks.size() > 50, "natural cliffs occupy whole grid-aligned hex cells")
	var ramp_low: Vector3 = game.Terrain.NATURAL_RAMP_HIGH - Vector3(9, 0, 0)
	var ramp_high: Vector3 = game.Terrain.NATURAL_RAMP_HIGH + Vector3(2, 3, 0)
	check(game.navigation.clear_segment(ramp_low, ramp_high), "natural ramp provides a gradual climb onto the hex mesa")
	check(not game.navigation.clear_segment(Vector3(52, 0, -5), Vector3(52, 3, 4)), "units cannot climb a sheer mesa edge")
	var ramp_path: PackedVector3Array = game.navigation.path(ramp_low, game.GAS_DEPOSIT)
	check(not ramp_path.is_empty() and ramp_path[-1].y == 3, "pathfinding reaches elevated gas at the correct height")
	var walker: ExpeditionUnit = game.add_unit("marine", ramp_low)
	game.set_order(walker, "move", game.GAS_DEPOSIT)
	var smooth := true
	for i in range(500):
		var before := walker.position
		game.advance_movement(0.05)
		if absf(walker.position.y - before.y) > 0.2: smooth = false
	check(smooth and walker.position.distance_to(game.GAS_DEPOSIT) < 1, "units climb natural ramps smoothly instead of teleporting up cliff faces")
	# Isolate constructed elevation and connected fortification geometry.
	game.rocks.clear(); game.rebuild_navigation()
	var center: Vector3 = game.Hex.snap(Vector3(-12, 0, -12), 2)
	var hub: ExpeditionStructure = game.add_structure("wall", center)
	for index in [0, 1, 2]: game.add_structure("wall", center + game.Terrain.direction(index) * game.Terrain.SPACING)
	var gate: ExpeditionStructure = game.add_structure("gate", center + game.Terrain.direction(3) * game.Terrain.SPACING)
	game.rebuild_navigation(); game.power.tick(game.structures, game.economy, 0)
	check(hub.connections.size() == 4 and gate.connections.has(hub.position - gate.position), "walls branch toward all adjacent wall and gate cells")
	check(game.navigation.blocked(gate.position), "closed connected gate blocks passage")
	check(game.set_gate(gate, true) and not game.navigation.blocked(gate.position), "opening a connected gate makes its center traversable")
	var platform: ExpeditionStructure = game.add_structure("platform", Vector3(-40, 0, 0))
	var anchor: Vector3 = platform.position - game.Terrain.direction(0) * game.Terrain.SPACING
	game.add_structure("ramp", anchor, true, 0)
	game.rebuild_navigation()
	check(game.navigation.terrain.height(anchor + Vector3(0, 0, 1.7)) > 2 and game.navigation.terrain.height(anchor + Vector3(0, 0, 3)) == 0, "ramps fill their two hex tiles without extending into adjacent rows")
	var low: Vector3 = anchor - game.Terrain.direction(0) * game.Terrain.SPACING * 1.6
	var raised: PackedVector3Array = game.navigation.path(low, platform.position)
	check(not raised.is_empty() and raised[-1].y == 3 and game.navigation.terrain.height(anchor) > 2, "built ramp connects ground navigation to a raised platform")
	var builder: ExpeditionUnit = game.add_unit("engineer", low)
	game.set_order(builder, "move", platform.position)
	for i in range(300): game.advance_movement(0.05)
	check(builder.position.distance_to(platform.position + Vector3.UP * 3) < 1, "engineer walks onto a player-built platform via its ramp")
	await physics_frame; await process_frame
	game.focus = platform.position; game.update_camera()
	var ray: Dictionary = game.terrain_raycast(game.camera.unproject_position(platform.position + Vector3.UP * 3))
	check(not ray.is_empty() and absf(ray.position.y - 3) < 0.05, "terrain raycasts hit the raised platform deck")
	var ramp_ray: Dictionary = game.terrain_raycast(game.camera.unproject_position(anchor + Vector3.UP * 2.25))
	check(not ramp_ray.is_empty() and absf(ramp_ray.position.y - 2.25) < 0.1, "two-hex ramp collision matches the visible sloping surface")
	var engineer: ExpeditionUnit = game.units[1]
	game.select_actor(engineer)
	var bank: int = game.economy.minerals
	var funded_platform: ExpeditionStructure = game.order_build("platform", Vector3(10, 0, -6))
	if funded_platform != null:
		for i in range(250):
			game.advance_movement(0.1); game.process_order(engineer, 0.1)
			if funded_platform.complete: break
	check(funded_platform != null and funded_platform.complete and game.economy.minerals == bank - 35, "engineer can fund and complete a raised hex tile through normal construction orders")
	if funded_platform != null:
		game.placement_direction = 5
		var ramp_site: Vector3 = funded_platform.position - game.Terrain.direction(5) * game.Terrain.SPACING
		var funded_ramp: ExpeditionStructure = game.order_build("ramp", ramp_site)
		if funded_ramp != null:
			for i in range(250):
				game.advance_movement(0.1); game.process_order(engineer, 0.1)
				if funded_ramp.complete: break
		check(funded_ramp != null and funded_ramp.complete and funded_ramp.build_direction == 5 and game.economy.minerals == bank - 65, "rotated two-tile ramp can be funded and completed beside the raised tile")
	# Discovery cannot skip a nearer active resource patch of either type.
	game.select_actor(game.jeep); game.scan()
	check(not game.scan_found, "scan cannot be used without selecting the Command Center")
	game.select_actor(game.core); game.scan()
	check(game.resource_nodes[0].discovered and game.resource_nodes[1].discovered and not game.resource_nodes[2].discovered, "first Command Center scan reveals only the nearest patch of each kind")
	check(game.core.scan_charge == 0, "scan consumes the full 120-electricity capacitor charge")
	game.scan_cooldown = 0; game.core.scan_charge = 120
	game.scan()
	check(not game.resource_nodes[2].discovered and game.core.scan_charge == 120, "rescanning cannot skip an active nearer patch or waste scan energy")
	game.resource_nodes[0].remaining = 0
	game.scan()
	check(game.resource_nodes[2].discovered and not game.resource_nodes[3].discovered, "depleting minerals unlocks the next mineral patch while active gas still blocks farther gas")
	game.power.tick(game.structures, game.economy, 5)
	check(game.core.scan_charge > 0 and game.power.used > 4, "recharging scan energy draws spare electricity from the Command Center network")
	game.core.hp = 0; game.cleanup_dead()
	await process_frame
	game.refresh_ui()
	check(not game.context_buttons.scan.visible, "destroying the Command Center removes its scan command safely")
	print("TERRAIN_WORLD_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
