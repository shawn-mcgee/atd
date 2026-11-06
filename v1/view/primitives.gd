extends RefCounted
## Presentation-only geometry. World elevation remains authoritative in the core.
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
const Rules = preload("res://engine/expedition_rules.gd")
const Power = preload("res://engine/expedition_power.gd")
const TILE_CORNERS := [Vector2i(1, 1), Vector2i(0, 2), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(0, -2), Vector2i(1, -1)]
const COLORS := {"engineer": Color("edbd6a"), "marine": Color("7bb5ec"), "flamer": Color("ed8265"), "jeep": Color("8cd0a8"), "scout": Color("aed776"), "drill": Color("cea77a"), "core": Color("76c9d1"), "generator": Color("e9b866"), "barracks": Color("7099c7"), "garage": Color("85b49e"), "gas_tank": Color("a4bf7b"), "depot": Color("7ac8c1"), "beacon": Color("dac886"), "hive": Color("aa607d")}
const ABBREVIATIONS := {"core": "HQ", "generator": "GEN", "barracks": "BAR", "garage": "GAR", "repeater": "R", "floodlight": "L", "turret": "T", "laser_turret": "LT", "flame_turret": "FT", "depot": "MAT", "gas_tank": "GAS", "scanner": "S", "extractor": "EXT", "platform": "+", "ramp": "/", "beacon": "EX", "hive": "HIVE", "gate": "G"}

static func unit_radius(actor: SimEntity) -> float:
	return 0.75 if actor is SimUnit and actor.is_vehicle() else 0.44 if actor is SimPredator and actor.kind == "brute" else 0.34

static func hexagon(game, point: Vector3, radius: float) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in range(6):
		var angle := i * TAU / 6.0 + PI / 6.0
		polygon.append(game.world_to_screen(point + Vector3(cos(angle), 0, sin(angle)) * radius))
	return polygon

static func footprint_polygon(game, kind: String, point: Vector3, direction: int) -> PackedVector2Array:
	var cells := Footprints.cells(kind, point, direction)
	if cells.size() == 1: return hexagon(game, point, Terrain.CELL * (1.0 if kind == "wall" else 0.8))
	var vertices := PackedVector2Array()
	for cell in cells: vertices.append(game.world_to_screen(Hex.to_world(cell, Terrain.CELL)))
	if vertices.size() == 2:
		var side: Vector2 = (vertices[1] - vertices[0]).orthogonal().normalized() * game.zoom * 0.65
		return PackedVector2Array([vertices[0] + side, vertices[1] + side, vertices[1] - side, vertices[0] - side])
	var hull := Geometry2D.convex_hull(vertices)
	if hull.size() > 1: hull.remove_at(hull.size() - 1)
	return hull

static func structure_polygon(game, building: SimStructure) -> PackedVector2Array:
	return footprint_polygon(game, building.kind, building.position, building.build_direction)

static func placement_polygon(game, kind: String, point: Vector3, direction: int) -> PackedVector2Array:
	# Integer corner coordinates let adjacent hexes cancel shared edges exactly.
	var edges: Dictionary = {}
	for cell in Footprints.cells(kind, point, direction):
		var center := Vector2i(2 * cell.x + cell.y, 3 * cell.y)
		for i in range(6):
			var a: Vector2i = center + TILE_CORNERS[i]
			var b: Vector2i = center + TILE_CORNERS[(i + 1) % 6]
			var reverse := Vector4i(b.x, b.y, a.x, a.y)
			if edges.has(reverse): edges.erase(reverse)
			else: edges[Vector4i(a.x, a.y, b.x, b.y)] = true
	var outline_edges: Dictionary = {}
	for edge in edges: outline_edges[Vector2i(edge.x, edge.y)] = Vector2i(edge.z, edge.w)
	var polygon := PackedVector2Array()
	if outline_edges.is_empty(): return polygon
	var corner: Vector2i = outline_edges.keys()[0]
	for i in range(outline_edges.size()):
		var vertex := Vector3(corner.x * Hex.SQRT_3 * 0.5 * Terrain.CELL, point.y, corner.y * 0.5 * Terrain.CELL)
		polygon.append(game.world_to_screen(vertex))
		corner = outline_edges[corner]
	return polygon

static func outline(game, polygon: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	if polygon.is_empty(): return
	var loop := polygon.duplicate(); loop.append(polygon[0])
	game.draw_polyline(loop, color, width, true)

static func draw_world(game) -> void:
	var font := ThemeDB.fallback_font
	draw_power_network(game)
	var buildings: Array = game.structures + [game.mission.hive]
	buildings.sort_custom(func(a, b):
		if (a.kind == "platform") != (b.kind == "platform"): return a.kind == "platform"
		return game.world_to_screen(a.position).y < game.world_to_screen(b.position).y)
	for building in buildings:
		if not building.visible or building.hp <= 0: continue
		var polygon := structure_polygon(game, building)
		var center := Vector2.ZERO
		for vertex in polygon: center += vertex
		center /= polygon.size()
		var color: Color = COLORS.get(building.kind, Color("8aa4b0"))
		var strength: float = game.light.sample(building.position)
		var brightness := 0.45 + strength * 0.55
		if Power.is_electrical(building.kind) and not building.powered: brightness *= 0.7
		var tint := Color(brightness, brightness, brightness, 1.0 if building.complete else 0.5)
		var key: String = building.kind
		if key == "beacon" and not building.complete: key = "beacon_ruined"
		if key == "hive" and (game.mission.stolen or building.hp < 400): key = "hive_breached"
		if Rules.TURRETS.has(key): key += "_base"
		if building.kind == "gate": game.sprites.draw_gate(game, building, tint)
		else:
			game.sprites.draw_building(game, building, polygon, tint)
		if Rules.TURRETS.has(building.kind):
			var head_angle: float = game.sprites.headings.get(building.simulation_id, 0.0)
			game.sprites.draw(game, building.kind + "_head", building.position, head_angle, tint)
		if building.kind == "core": game.draw_circle(game.world_to_screen(building.position) + Vector2(0, -3), 1.8, game.AMBER)
		if game.selected.has(building) and game.zoom >= 10:
			var text: String = ABBREVIATIONS.get(building.kind, "")
			game.draw_string(font, center + Vector2(-12, -18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e0edf1"))
		if not building.complete:
			game.draw_line(center + Vector2(-14, 15), center + Vector2(-14 + 28 * building.progress, 15), game.AMBER, 3)
		if Power.is_electrical(building.kind) and not building.powered and building.complete:
			game.draw_circle(center + Vector2(10, -10), 3, Color("ef886a"))
			if game.zoom >= 12: game.draw_string(font, center + Vector2(-26, 27), "NO POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ef886a"))
	for wreck in game.wrecks:
		game.sprites.draw(game, wreck.node.kind + "_wreck", wreck.node.position, -wreck.node.yaw, Color(1, 1, 1, minf(1, float(wreck.life) / 5)))
	for actor in game.units + game.creatures:
		if actor.hp <= 0 or not actor.visible or (actor is SimUnit and actor.aboard != null): continue
		var center: Vector2 = game.world_to_screen(game.actor_position(actor))
		var radius: float = unit_radius(actor) * game.zoom
		var color: Color = Color("dc7185") if actor is SimPredator else COLORS.get(actor.kind, Color.WHITE)
		game.sprites.draw(game, actor.kind, game.actor_position(actor), game.sprites.actor_angle(actor))
		if game.selected.has(actor):
			var target: SimEntity = actor.focus_target if SimEntity.valid(actor.focus_target) else actor.target
			if SimEntity.valid(target): game.draw_line(center, game.world_to_screen(target.position), Color(game.MINT, 0.5), 1, true)
			elif actor is SimUnit and actor.moving(): game.draw_line(center, game.world_to_screen(actor.goal), Color(game.MINT, 0.3), 1, true)
		if actor is SimUnit:
			if actor.is_vehicle():
				game.draw_circle(center, 1.4, game.AMBER)
				if actor.has_driver():
					var facing := Vector2(actor.facing.x, actor.facing.z).rotated(game.camera_angle)
					game.draw_circle(center + facing * radius, 1.4, Color("dcf5e6"))
			if actor.order in ["build", "repair"] and SimEntity.valid(actor.target) and actor.position.distance_to(actor.target.position) < 3.5:
				game.sprites.draw(game, "repair_sparks_0%d" % (int(game.elapsed * 8) % 2), actor.position.lerp(actor.target.position, 0.6), 0, Color.WHITE, Vector2.ONE * 0.5)
	for blip in game.sensor_blips: game.draw_arc(game.world_to_screen(blip.position), game.zoom, 0, TAU, 24, Color(game.AMBER, 0.7), 1, true)
	if game.mission.item.visible:
		var point: Vector2 = game.world_to_screen(game.mission.item.position)
		game.sprites.draw(game, "hive_core", game.mission.item.position)
	game.sprites.draw_effects(game)
	if game.build_kind != "" and game.mouse_world.is_finite():
		var point := Hex.snap(game.mouse_world, Terrain.CELL)
		var valid: bool = game.simulation.valid_site(game.build_kind, point, game.placement_direction)
		var polygon := placement_polygon(game, game.build_kind, point, game.placement_direction)
		var color := Color("7bf4d0") if valid else Color("ee7185")
		game.draw_colored_polygon(polygon, Color(color, 0.3))
		var key: String = game.build_kind + "_base" if Rules.TURRETS.has(game.build_kind) else game.build_kind
		if game.build_kind == "gate":
			var ghost := SimStructure.new(); ghost.setup("gate", point, false, game.placement_direction)
			game.sprites.draw_gate(game, ghost, Color(color, 0.6))
		else: game.sprites.polygon(game, key, polygon, point, game.placement_direction * PI / 3, Color(color, 0.6))
		outline(game, polygon, color, 2)
		if Power.is_electrical(game.build_kind):
			for source in game.structures:
				if source.kind in Power.SOURCES and source.hp > 0 and source.visible:
					game.draw_arc(game.world_to_screen(source.position), Power.source_range(source) * game.zoom, 0, TAU, 80, Color("588eae"), 1, true)
			if game.build_kind in Power.SOURCES:
				var reach := Power.LINK_RANGE if game.build_kind == "repeater" else Power.GENERATOR_RANGE if game.build_kind == "generator" else Power.CORE_RANGE
				game.draw_arc(game.world_to_screen(point), reach * game.zoom, 0, TAU, 80, Color(color, 0.5), 1, true)
		if game.wall_start.is_finite():
			game.draw_line(game.world_to_screen(game.wall_start), game.world_to_screen(point), Color(color, 0.6), 3, true)

static func draw_power_network(game) -> void:
	var networks: Dictionary = {}
	for actor in game.selected:
		if actor is SimStructure and Power.is_electrical(actor.kind) and actor.network >= 0: networks[actor.network] = true
	if networks.is_empty(): return
	var sources: Dictionary = {}
	for source in game.structures:
		if source.kind not in Power.SOURCES or not source.visible or source.hp <= 0 or not networks.has(source.network): continue
		sources[source.position] = true
		var color := Color("79bfab") if source.powered else Color("ef886a")
		game.draw_arc(game.world_to_screen(source.position), Power.source_range(source) * game.zoom, 0, TAU, 80, Color(color, 0.4), 1, true)
	for link in game.power.links:
		if sources.has(link.a) or sources.has(link.b): game.draw_line(game.world_to_screen(link.a), game.world_to_screen(link.b), Color("79bfab"), 1.5, true)
