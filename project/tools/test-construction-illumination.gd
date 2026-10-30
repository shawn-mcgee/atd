extends SceneTree
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = preload("res://tools/fixtures/simulation_fixture.gd").new()
	game.rocks.clear(); game.structures.clear(); game.resource_nodes.clear()
	game.navigation.terrain.natural_enabled = false; game.rebuild_navigation()
	var center := Hex.to_world(Vector2i(12, 12), Terrain.CELL)
	# Only the source's own tile is lit, making the extra ring unambiguous.
	game.light.clear(); game.light.add_source(center, Terrain.SPACING * 0.8)
	check(game.valid_site("wall", center), "directly illuminated terrain remains buildable")
	for offset in Hex.NEIGHBORS:
		var edge := center + Hex.to_world(offset, Terrain.CELL)
		check(game.light.sample(edge) == 0 and game.valid_site("wall", edge), "one dark hex beyond the light is buildable in direction %s" % offset)
		check(game.valid_site("generator", edge), "multi-cell structures receive the same center placement allowance in direction %s" % offset)
	for q in range(-2, 3):
		for r in range(-2, 3):
			if maxi(absi(q), maxi(absi(r), absi(q + r))) != 2: continue
			check(not game.valid_site("wall", center + Hex.to_world(Vector2i(q, r), Terrain.CELL)), "second-ring darkness remains unbuildable at %s" % Vector2i(q, r))
	var edge := center + Hex.to_world(Hex.NEIGHBORS[0], Terrain.CELL)
	game.light.clear(); game.light.add_source(center, Terrain.SPACING * 0.8, Vector3.ZERO, -1.0, 0.054)
	check(not game.valid_site("wall", edge), "adjacent illumination must still meet the existing brightness threshold")
	game.light.clear()
	check(not game.valid_site("wall", center), "placement without nearby light remains forbidden")
	game.light.add_source(center, Terrain.SPACING * 0.8)
	var worker: SimUnit = game.add_unit("engineer", center)
	game.select_actor(worker)
	var site: SimStructure = game.order_build("wall", edge)
	check(site != null and site.funded and worker.target == site, "authoritative build orders fund and assign construction on the extra ring")
	check(not game.valid_site("wall", edge), "the extra ring still rejects occupied footprints")
	check(game.order_wall_line(center + Hex.to_world(Hex.NEIGHBORS[3], Terrain.CELL), center + Hex.to_world(Hex.NEIGHBORS[3] * 2, Terrain.CELL)) == 1, "wall lines accept the extra ring and skip the next dark tile")
	game.add_structure("platform", center + Hex.to_world(Hex.NEIGHBORS[1], Terrain.CELL))
	game.rebuild_navigation()
	check(not game.valid_site("wall", center + Hex.to_world(Hex.NEIGHBORS[1], Terrain.CELL)), "ground light cannot grant placement on an unlit raised platform")
	game.dispose()
	print("CONSTRUCTION_ILLUMINATION_TEST_RESULT: ", failures, " failures")
	quit(1 if failures else 0)
