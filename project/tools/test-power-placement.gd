extends SceneTree
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ", description)
	else: failures += 1; push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://scenes/prototype.tscn").instantiate()
	game.layout = preload("res://tools/fixtures/legacy_layout.gd").new()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.begin_run()
	check(game.Power.GENERATOR_RANGE < game.Power.LINK_RANGE and game.Power.GENERATOR_RANGE <= game.Terrain.SPACING * 2.1, "generators cover two tile steps and repeaters have the longer reach")
	var generator: ExpeditionStructure = game.add_structure("generator", Vector3.ZERO)
	var relay: ExpeditionStructure = game.add_structure("repeater", Vector3(3, 0, 0))
	var consumer: ExpeditionStructure = game.add_structure("floodlight", Vector3(12, 0, 0))
	generator.position = Vector3.ZERO; relay.position = Vector3(3, 0, 0); consumer.position = Vector3(12, 0, 0)
	var network: Array = [generator, relay, consumer]
	game.power.tick(network, game.economy, 0)
	check(relay.connected and consumer.powered, "repeater receives nearby generation and powers more distant consumers")
	var boundary := Vector3(game.Power.GENERATOR_RANGE, 0, 0)
	check(game.Power.covers(generator, boundary) and not game.Power.covers(generator, boundary + Vector3.RIGHT * 0.01), "connection radius has a consistent center-to-center boundary")
	var result: Dictionary = game.Power.placement_connection("turret", boundary, [generator])
	check(result.state == "ready" and result.source == generator, "placement query matches the real link boundary")
	result = game.Power.placement_connection("turret", boundary * 1.5, [generator])
	check(result.state == "missing", "overlapping circles do not falsely connect centers beyond the link radius")
	var overlay = game.power_placement
	result = overlay.update_preview("turret", Vector3(12, 0, 0), network)
	check(overlay.visible and overlay.source_rings.size() == 2 and overlay.connector.visible and result.source == relay, "placement shows generator/repeater ranges and the chosen relay connection")
	check(is_equal_approx(overlay.preview_ring.mesh.get_aabb().size.x, game.Power.LINK_RANGE * 2), "preview circle diameter agrees with actual grid range")
	check(overlay.preview_ring.position.distance_to(Vector3(12, 0.12, 0)) < 0.001, "prospective connection circle follows the placement point")
	for i in range(3):
		var turret: ExpeditionStructure = game.add_structure("turret", Vector3(5 + i, 0, -2 - i))
		network.append(turret)
	game.power.tick(network, game.economy, 0)
	result = overlay.update_preview("turret", Vector3(12, 0, 0), network)
	check(result.state == "overload", "preview warns when an otherwise connected placement exceeds generation")
	game.economy.gas = 0; game.power.tick(network, game.economy, 0.1)
	result = overlay.update_preview("turret", Vector3(12, 0, 0), network)
	check(result.state == "offline" and overlay.connector.visible, "fuel outages show a physical connection with an offline warning")
	relay.complete = false; game.power.tick(network, game.economy, 0)
	result = overlay.update_preview("turret", Vector3(12, 0, 0), network)
	check(result.state == "planned", "unfinished repeaters are identified as planned sources")
	relay.complete = true; relay.position = Vector3(100, 0, 0)
	game.economy.gas = 20; game.power.tick(network, game.economy, 0)
	result = overlay.update_preview("turret", Vector3(110, 0, 0), network)
	check(result.state == "offline" and not relay.connected, "isolated repeaters show an offline warning rather than promising usable power")
	result = overlay.update_preview("generator", Vector3(100, 0, 100), network)
	check(result.state == "source", "new generators may establish independent grids")
	result = overlay.update_preview("scanner", Vector3(100, 0, 100), network)
	check(result.state == "missing" and not overlay.connector.visible, "unconnected electrical placements have no false source line")
	overlay.update_preview("wall", Vector3.ZERO, network)
	check(not overlay.visible, "non-electrical construction hides all connection range overlays")
	relay.complete = true; relay.hp = 0
	overlay.update_preview("turret", Vector3(10, 0, 0), network)
	check(overlay.source_rings.size() == 1, "destroyed nodes are removed from the range overlay")
	game.select_actor(game.units[0]); game.mouse_world = game.HOME + Vector3(8, 0, -5)
	game.choose_build("floodlight"); game.refresh_ui()
	await process_frame
	await process_frame
	check(game.power_placement.visible and game.power_preview_label.visible, "electrical build commands reveal the in-game overlay and connection status")
	check(game.construction_panel.get_global_rect().end.y <= root.get_visible_rect().size.y - 17, "connection status expands construction menu upward without clipping its buttons")
	game.select_actor(game.units[2]); game.refresh_ui()
	check(not game.power_placement.visible and not game.power_preview_label.visible and game.build_kind.is_empty(), "changing away from engineer cancels placement and hides range UI")
	print("POWER_PLACEMENT_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
