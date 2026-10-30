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
	check(valid and sprites.regions.size() == 63, "all 63 prepared regions lie inside their imported atlases")
	for key in ["runner", "stalker", "brute", "scout", "jeep", "drill"]:
		check(is_equal_approx(sprites.rotation(key), PI), key + " corrects south-facing source art")
	check(not sprites.regions.has("unused_gate_frame") and not sprites.regions.has("gate"), "generated gate components are excluded")
	for key in ["ground_a", "ground_b", "cliff_top", "platform", "wall"]:
		check(is_zero_approx(sprites.rotation(key)), key + " uses corrected pointy-top batch 7 art")
	for key in ["turret", "laser_turret", "flame_turret"]:
		check(sprites.texture(key) != null and sprites.texture(key + "_head") != null, key + " has independent base and head")
	var game = load("res://scenes/top_down.tscn").instantiate(); game.initial_seed = 42
	root.add_child(game); game.set_process(false); game.begin_run()
	var sim = game.simulation
	var marine: SimUnit = sim.add_unit("marine", Vector3(20, 0, -10))
	var entry: Dictionary = game.sprites.manifest.sprites.marine
	var region: Rect2 = game.sprites.regions.marine.region
	var image: Image = game.sprites.textures[entry.sheet].get_image()
	var found := false
	# Pick an actual opaque rifle pixel outside the old circle, under camera rotation.
	game.camera_angle = 0.4
	var rect: Rect2 = game.sprites.sprite_rect("marine", game.zoom)
	for y in range(int(region.size.y / 3)):
		for x in range(0, int(region.size.x), 4):
			if image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a < 0.8: continue
			var local := rect.position + Vector2(x, y) / region.size * rect.size
			if local.length() < 8: continue
			var screen: Vector2 = game.world_to_screen(marine.position) + local.rotated(game.camera_angle)
			if game.pick(screen) == marine: found = true; break
		if found: break
	check(found, "opaque sprite extensions are selectable outside the former circular hit area")
	var clear: Vector2 = game.world_to_screen(marine.position) + (rect.position + Vector2(0.5, 0.5)).rotated(game.camera_angle)
	check(not game.sprites.hit(game, "marine", marine.position, 0, clear), "transparent sprite corners do not intercept terrain clicks")
	var gate: SimStructure = sim.add_structure("gate", Vector3(10, 0, -10))
	game.sprites.tick(game, 0); gate.gate_open = true; game.sprites.tick(game, 0.1)
	check(game.sprites.gates[gate.simulation_id] > 0 and game.sprites.gates[gate.simulation_id] < 1, "gate animation interpolates in view state")
	var state: String = sim.state_hash()
	game.sprites.tick(game, 0.5); game.queue_redraw(); await process_frame
	check(state == sim.state_hash(), "sprite orientation, effects, and gate animation never modify simulation state")
	game.queue_free(); await process_frame
	print("SPRITE_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
