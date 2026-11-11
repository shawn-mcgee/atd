extends SceneTree

# Bounded, repeatable CPU benchmark; excludes loading, GPU work and frame pacing.
func _initialize() -> void:
	call_deferred("run")

func measure(label: String, action: Callable, count: int = 60) -> Dictionary:
	var samples: Array[float] = []
	for i in range(count + 5):
		var start := Time.get_ticks_usec()
		action.call()
		if i >= 5: samples.append((Time.get_ticks_usec() - start) / 1000.0)
	return report(label, samples)

func report(label: String, samples: Array[float]) -> Dictionary:
	var total := 0.0
	for sample in samples: total += sample
	samples.sort()
	var result := {"mean_ms": snappedf(total / samples.size(), 0.001), "p95_ms": samples[int(samples.size() * 0.95)], "max_ms": samples.back()}
	print(label, ": ", JSON.stringify(result))
	return result

func run() -> void:
	if "--snapshot-copy" in OS.get_cmdline_user_args():
		snapshot_copy_profile(); quit(); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted = true
	game._start_game(472, 1)
	game.set_process(false); game.set_physics_process(false); game.tactical.set_process(false); game.camera.set_process(false)
	var world: WorldState = game.state
	var stress := "--stress" in OS.get_cmdline_user_args()
	var scale := 1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scale="): scale = maxi(1, int(argument.trim_prefix("--scale=")))
	var center := Vector2i.ZERO
	if stress:
		if not stress_fixture(world, scale): quit(1); return
	else:
		var anchor: Dictionary = world.structures[int(world.players[0].anchor)]
		center = anchor.cell - anchor.cell.sign() * 7
		var cells: Array[Vector2i] = []
		for cell in HexGrid.disk(center, 9):
			if world.tiles.has(cell) and not world.tiles[cell].cliff and not world.structure_cells.has(cell): cells.append(cell)
		var friendly_ids: Array[int] = []
		for i in range(96):
			var id := world.add_unit("marine" if i % 4 else "engineer", HexGrid.world(cells[i]), 0)
			friendly_ids.append(id)
			if not "--active" in OS.get_cmdline_user_args(): world.units[id].stance = "neutral"
		for i in range(24): world.add_structure("relay" if i % 3 else "floodlight", cells[100 + i * 2], 0)
		world._rebuild_navigation(); world._update_power(0); world.update_visibility()
		if "--active" in OS.get_cmdline_user_args():
			for i in range(12): world.add_unit("scavenger", HexGrid.world(cells[180 + i]), -1)
			for i in range(0, 96, 3):
				var unit: Dictionary = world.units[friendly_ids[i]]
				var goal := HexGrid.world(cells[(130 + i) % cells.size()])
				unit.home = goal; unit.job = {"kind": "move"}; world.move_to(unit, goal)
	var position := HexGrid.world(center)
	game.camera.focus = Vector3(position.x, 0, position.y); game.camera._update_transform()
	game.renderer.refresh_entities(); game.renderer.refresh_tiles()
	print("Fixture: ", world.units.size(), " units, ", world.structures.size(), " structures, ", world.tiles.size(), " tiles")
	var results := {}
	var initial_counts := Vector2i(world.units.size(), world.structures.size())
	print("CPU: ", OS.get_processor_name())
	if "--frames" in OS.get_cmdline_user_args():
		var callbacks: Array[float] = []
		var engine: Array[float] = []
		for frame in range(125):
			await process_frame
			var start := Time.get_ticks_usec()
			if frame % 3 == 0: game._physics_process(1.0 / 20)
			game._process(1.0 / 60); game.tactical._process(1.0 / 60)
			if frame >= 5:
				callbacks.append((Time.get_ticks_usec() - start) / 1000.0)
				engine.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		results.callbacks = report("game_callbacks_60fps_20hz", callbacks)
		results.engine = report("engine_process_including_render", engine)
	results.step = measure("simulation_step", func(): world.step(1.0 / 60))
	results.live_step = measure("simulation_tick_20hz", func(): world.step(1.0 / 20))
	results.visibility = measure("visibility", func(): world.update_visibility(), 20)
	results.topology = measure("sight_topology", func(): world._refresh_sight_topology(), 20)
	results.radar = measure("radar", func(): WorldState.RadarSystem.update(world))
	results.power = measure("power", func(): world._update_power(0))
	results.units = measure("unit_logic", func():
		for u in world.units.values(): world._unit_step(u, 1.0 / 60))
	if "--detail" in OS.get_cmdline_user_args():
		var details: Array = []
		for u in world.units.values():
			var start := Time.get_ticks_usec()
			for i in range(5): world._unit_step(u, 1.0 / 60)
			details.append({"kind": u.kind, "job": u.job.kind, "owner": u.owner, "us": (Time.get_ticks_usec() - start) / 5.0})
		details.sort_custom(func(a, b): return a.us > b.us)
		print("Slowest units: ", JSON.stringify(details.slice(0, 10)))
	results.separation = measure("separation", func(): world._separate_units(1.0 / 60))
	results.gloom = measure("gloom", func(): world._update_gloom(0), 20)
	results.tiles = measure("terrain_refresh", func(): game.renderer.refresh_tiles(), 20)
	results.fog_texture = measure("fog_texture", func(): game.renderer._update_visibility_texture(world.known[0], world.visible[0], world.illuminated[0]), 20)
	results.navigation = measure("navigation_update", func(): world._rebuild_navigation(), 10)
	results.entities = measure("entity_presentation", func(): game.renderer.refresh_entities())
	results.occlusion = measure("occlusion", func(): game.renderer._highlight_occluded_units())
	results.pick = measure("picking", func(): game._pick(Vector2(640, 400)))
	results.overlay = measure("tactical_process", func(): game.tactical._process(1.0 / 60))
	results.hud = measure("hud", func(): game._update_hud(), 20)
	results.fixture = {"units": world.units.size(), "structures": world.structures.size(), "tiles": world.tiles.size(), "active": "--active" in OS.get_cmdline_user_args(), "engine": Engine.get_version_info().string, "initial_units": initial_counts.x, "initial_structures": initial_counts.y}
	DirAccess.make_dir_recursive_absolute("res://build/profiles")
	var file := FileAccess.open("res://build/profiles/core-%s.json" % (("stress-%du-%ds-" % [initial_counts.x, initial_counts.y] if stress else "") + ("active" if "--active" in OS.get_cmdline_user_args() else "idle")), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t")); file.close()
	quit()

func stress_fixture(world: WorldState, scale: int) -> bool:
	# Exact population: legal, mixed structures; infantry, workers and hostile probes.
	world.units.clear()
	world.lightless_brain_time = -100000; world.lightless_expansion_time = -100000
	for s in world.structures.values():
		if s.kind == "medusa": s.passive = -100000
	for resource in world.resources(0): world.resources(0)[resource] = 100000
	var candidates := HexGrid.disk(Vector2i.ZERO, world.radius - 3)
	var kinds := ["relay", "wall", "floodlight", "generator", "depot", "armory", "radar", "sentry"]
	var cursor := 0
	while world.structures.size() < 100 * scale:
		var kind: String = kinds[(world.structures.size() - 2) % kinds.size()]
		var placed := false
		while cursor < candidates.size():
			var cell: Vector2i = candidates[cursor]; cursor += 1
			var clear := true
			for occupied in HexGrid.disk(cell, int(world.cfg.structures[kind].footprintRadiusTiles) + 1):
				if world.blocked(occupied) or world.structure_cells.has(occupied): clear = false; break
			if not clear: continue
			var id := world.add_structure(kind, cell, 0)
			if kind == "armory": world.structures[id].kits.append({"kind": "marine", "progress": 0.0, "done": false})
			placed = true; break
		if not placed: printerr("Insufficient legal structure sites for scale ", scale); return false
	world._rebuild_navigation(); world._update_power(0)
	var cells: Array[Vector2i] = []
	for cell in candidates:
		if not world.blocked(cell): cells.append(cell)
	if cells.size() < 200 * scale: printerr("Insufficient legal unit sites for scale ", scale); return false
	var active := "--active" in OS.get_cmdline_user_args()
	for i in range(200 * scale):
		var hostile := active and i % 5 == 0
		var kind := "scavenger" if hostile else "engineer" if i % 7 == 0 else "marine"
		var cell: Vector2i = cells[i]
		var id := world.add_unit(kind, HexGrid.world(cell), -1 if hostile else 0)
		if not active: world.units[id].stance = "neutral"
		if active and not hostile and i % 3 == 0:
			var goal := HexGrid.world(cells[(i + 100) % cells.size()])
			world.command(0, {"action": "patrol", "ids": [id], "x": goal.x, "z": goal.y})
	# Preserve combat workload/population throughout the short timing window.
	for definition in world.cfg.units.values(): definition.health *= 1000
	for definition in world.cfg.structures.values(): definition.health *= 1000
	for u in world.units.values(): u.hp = float(world.cfg.units[u.kind].health)
	for s in world.structures.values(): s.hp = float(world.cfg.structures[s.kind].health)
	world.update_visibility()
	return true

func snapshot_copy_profile() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/prototype.json"))
	var world := WorldState.new(config); world.reset(472, 1)
	var source: Dictionary = world.units.values()[0]
	for route_length in [8, 64]:
		var units: Array = []
		for index in range(100):
			var unit: Dictionary = source.duplicate(true)
			for point in range(route_length): unit.route.append(Vector2(point, index))
			units.append(unit)
		measure("100_units_%d_waypoints_copy_then_discard" % route_length, func(): copy_batch(units, false), 40)
		measure("100_units_%d_waypoints_omit_then_copy" % route_length, func(): copy_batch(units, true), 40)

func copy_batch(units: Array, optimized: bool) -> void:
	for unit in units:
		var copy: Dictionary
		if optimized:
			var fields: Dictionary = unit.duplicate(false); fields.erase("route")
			copy = fields.duplicate(true)
		else: copy = unit.duplicate(true)
		copy.erase("route")
