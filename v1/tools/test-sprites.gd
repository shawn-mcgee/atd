extends SceneTree
const Sprites = preload("res://view/sprite_library.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sprites = Sprites.new()
	var valid := true
	for key in sprites.regions:
		var region: Rect2 = sprites.regions[key].region
		var atlas: Texture2D = sprites.regions[key].atlas
		if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region): valid = false
	check(valid and sprites.regions.size() == 94, "all 94 prepared regions lie inside their imported atlases")
	for key in ["runner", "stalker", "brute", "scout", "jeep", "drill"]:
		check(is_equal_approx(sprites.rotation(key), PI), key + " corrects south-facing source art")
	check(sprites.texture("gate") == sprites.regions.gate_frame and sprites.regions.has("gate_closed") and sprites.regions.has("gate_open"), "gates use the updated frame and both leaf states")
	for key in ["ground_a", "ground_b", "cliff_top", "platform", "wall"]:
		check(is_zero_approx(sprites.rotation(key)), key + " uses corrected pointy-top batch 7 art")
	for key in ["turret", "laser_turret", "flame_turret"]:
		check(sprites.texture(key) != null and sprites.texture(key + "_head") != null, key + " has independent base and head")
	var game = load("res://scenes/top_down.tscn").instantiate(); game.initial_seed = 42
	root.add_child(game); game.set_process(false); game.begin_run()
	var sim = game.simulation
	var wall: SimStructure = sim.add_structure("wall", Vector3(15, 0, -12))
	var layout: Dictionary = sprites.building_layout(game, wall, game.Primitives.structure_polygon(game, wall))
	check(layout.point == wall.position and is_equal_approx(layout.size.x, 1.82), "walls use a centered full-tile sprite instead of compact structure bounds")
	var marine: SimUnit = sim.add_unit("marine", Vector3(20, 0, -10))
	var entry: Dictionary = game.sprites.manifest.sprites.marine
	var region: Rect2 = game.sprites.regions.marine.region
	var image: Image = game.sprites.textures[entry.sheet].get_image()
	var found := false
	# Pick an actual opaque rifle pixel outside the old circle, under camera rotation.
	game.camera_angle = 0.4
	var rect: Rect2 = game.sprites.sprite_rect("marine", game.zoom)
	for y in range(int(region.size.y * 0.7), int(region.size.y)):
		for x in range(0, int(region.size.x), 4):
			if image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a < 0.8: continue
			var local := rect.position + Vector2(x, y) / region.size * rect.size
			if local.length() < 8: continue
			var screen: Vector2 = game.world_to_screen(marine.position) + local.rotated(game.camera_angle + game.sprites.rotation("marine"))
			if game.pick(screen) == marine: found = true; break
		if found: break
	check(found, "opaque sprite extensions are selectable outside the former circular hit area")
	var clear: Vector2 = game.world_to_screen(marine.position) + (rect.position + Vector2(0.5, 0.5)).rotated(game.camera_angle)
	check(not game.sprites.hit(game, "marine", marine.position, 0, clear), "transparent sprite corners do not intercept terrain clicks")
	var gate: SimStructure = sim.add_structure("gate", Vector3(10, 0, -10))
	var frame_rect: Rect2 = game.sprites.sprite_rect("gate_frame", 1)
	check(frame_rect == game.sprites.sprite_rect("gate_closed", 1) and frame_rect == game.sprites.sprite_rect("gate_open", 1), "gate layers retain shared scale and registration")
	check(not game.sprites.hit_building(game, gate, PackedVector2Array(), game.world_to_screen(gate.position + Vector3(0, 0, 0.43))), "transparent space beside rotated gate panels does not become a sprite hit")
	var gate_layout: Dictionary = game.sprites.building_layout(game, gate, PackedVector2Array())
	check(is_equal_approx(gate_layout.angle, PI / 2), "gate art spans the wall line rather than turning the passage sideways")
	var gate_hits := true
	for direction in range(6):
		gate.build_direction = direction
		var offset := Vector2(0, 0.69).rotated(direction * PI / 3 + PI / 2)
		gate_hits = gate_hits and game.sprites.hit_building(game, gate, PackedVector2Array(), game.world_to_screen(gate.position + Vector3(offset.x, 0, offset.y)))
	check(gate_hits, "rotated gate posts remain selectable at all six build directions under camera rotation")
	gate.build_direction = 0
	game.sprites.tick(game, 0); gate.gate_open = true; game.sprites.tick(game, 0.1)
	check(game.sprites.gates[gate.simulation_id] > 0 and game.sprites.gates[gate.simulation_id] < 1, "gate animation interpolates in view state")
	var moving_parts: Array[Dictionary] = game.sprites.gate_parts(gate)
	check(moving_parts.size() == 5 and game.sprites.manifest.sprites.gate_open.slide_distance > 0, "both gate panels slide toward their registered open positions")
	game.sprites.tick(game, 1)
	check(game.sprites.gate_parts(gate)[1].key == "gate_open" and not game.sprites.hit_building(game, gate, PackedVector2Array(), game.world_to_screen(gate.position)), "open gate art leaves its central passage clear for alpha picking")
	var state: String = sim.state_hash()
	game.sprites.tick(game, 0.5); game.queue_redraw(); await process_frame
	check(state == sim.state_hash(), "sprite orientation, effects, and gate animation never modify simulation state")
	game.queue_free(); await process_frame
	print("SPRITE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
