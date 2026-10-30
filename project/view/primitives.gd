extends RefCounted
## Presentation-only geometry. World elevation remains authoritative in the core.
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
const Rules = preload("res://engine/expedition_rules.gd")
const Power = preload("res://engine/expedition_power.gd")
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
	if cells.size() == 1: return hexagon(game, point, Terrain.CELL * 0.8)
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

static func outline(game, polygon: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	if polygon.is_empty(): return
	var loop := polygon.duplicate(); loop.append(polygon[0])
	game.draw_polyline(loop, color, width, true)

static func draw_world(game) -> void:
	var viewport: Rect2 = game.get_viewport_rect().grow(80)
	for cell in game.simulation.explored:
		var point := Hex.to_world(cell, Terrain.CELL)
		if not viewport.has_point(game.world_to_screen(point)): continue
		var strength: float = game.light.sample(point)
		var type: String = game.simulation.explored[cell]
		var base := Color("283643") if type == "ground" else Color("6a7277") if type == "cliff" else Color("475e64")
		var color := Color("101925").lerp(base, 0.25 + 0.75 * strength)
		var polygon := hexagon(game, point, Terrain.CELL * 0.98)
		game.draw_colored_polygon(polygon, color)
		outline(game, polygon, Color(0.45, 0.65, 0.7, 0.08 + strength * 0.14))
	for patch in game.resource_nodes:
		if not patch.discovered or patch.remaining <= 0: continue
		var color := Color("7be0cb") if patch.kind == "minerals" else Color("b2cd73")
		color.a = 0.9 if game.light.sample(patch.position) > 0.05 else 0.3
		var polygon := hexagon(game, patch.position, Terrain.CELL * 0.65)
		game.draw_colored_polygon(polygon, Color(color, color.a * 0.25)); outline(game, polygon, color, 2)
	for rock in game.rocks:
		if not game.simulation.explored.has(rock.cell): continue
		var polygon := hexagon(game, rock.position, Terrain.CELL * 0.98)
		var lit: float = game.light.sample(rock.position)
		game.draw_colored_polygon(polygon, Color("29353f").lerp(Color("667580"), lit)); outline(game, polygon, Color("8397a1") * (0.4 + lit * 0.6), 2)
	var font := ThemeDB.fallback_font
	for building in game.structures + [game.mission.hive]:
		if not building.visible or building.hp <= 0: continue
		var polygon := structure_polygon(game, building)
		var center := Vector2.ZERO
		for vertex in polygon: center += vertex
		center /= polygon.size()
		var color: Color = COLORS.get(building.kind, Color("8aa4b0"))
		var fill := color.darkened(0.5 if building.complete else 0.75)
		if building.kind == "gate" and building.gate_open: fill.a = 0.2
		game.draw_colored_polygon(polygon, fill)
		outline(game, polygon, game.MINT if game.selected.has(building) else color, 2)
		for offset in building.connections: game.draw_line(game.world_to_screen(building.position), game.world_to_screen(building.position + offset * 0.5), color, maxf(3, game.zoom * 0.35), true)
		if game.zoom >= 10:
			var text: String = ABBREVIATIONS.get(building.kind, "")
			game.draw_string(font, center - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x / 2, -4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e0edf1"))
		if not building.complete:
			game.draw_line(center + Vector2(-14, 15), center + Vector2(-14 + 28 * building.progress, 15), game.AMBER, 3)
		if Power.is_electrical(building.kind) and not building.powered and building.complete:
			game.draw_circle(center + Vector2(10, -10), 3, Color("ef886a"))
	for wreck in game.wrecks:
		game.draw_circle(game.world_to_screen(wreck.node.position), game.zoom * 0.7, Color("50433a"))
	for actor in game.units + game.creatures:
		if actor.hp <= 0 or not actor.visible or (actor is SimUnit and actor.aboard != null): continue
		var center: Vector2 = game.world_to_screen(game.actor_position(actor))
		var radius: float = unit_radius(actor) * game.zoom
		var color: Color = Color("dc7185") if actor is SimPredator else COLORS.get(actor.kind, Color.WHITE)
		game.draw_circle(center, radius, color.darkened(0.25))
		game.draw_arc(center, radius, 0, TAU, 24, color, 1.5, true)
		if game.selected.has(actor):
			game.draw_arc(center, radius + 4, 0, TAU, 24, game.MINT, 1.5, true)
			var target: SimEntity = actor.focus_target if SimEntity.valid(actor.focus_target) else actor.target
			if SimEntity.valid(target): game.draw_line(center, game.world_to_screen(target.position), Color(game.MINT, 0.5), 1, true)
			elif actor is SimUnit and actor.moving(): game.draw_line(center, game.world_to_screen(actor.goal), Color(game.MINT, 0.3), 1, true)
		if actor is SimUnit:
			var facing := Vector2(actor.facing.x, actor.facing.z).rotated(game.camera_angle)
			game.draw_line(center, center + facing * radius * 1.3, Color("15252d"), 2, true)
			if actor.is_vehicle() and not actor.has_driver(): game.draw_circle(center, 2, game.AMBER)
	for blip in game.sensor_blips: game.draw_arc(game.world_to_screen(blip.position), game.zoom, 0, TAU, 24, Color(game.AMBER, 0.7), 1, true)
	if game.mission.item.visible:
		var point: Vector2 = game.world_to_screen(game.mission.item.position)
		game.draw_circle(point, 4, Color("ffd790"))
	for event in game.simulation.events:
		if event.type == "shot" and game.tick_number - int(event.tick) <= 1: game.draw_line(game.world_to_screen(event.a), game.world_to_screen(event.b), event.color, 2, true)
	if game.build_kind != "" and game.mouse_world.is_finite():
		var point := Hex.snap(game.mouse_world, Terrain.CELL)
		var valid: bool = game.simulation.valid_site(game.build_kind, point, game.placement_direction)
		var polygon := footprint_polygon(game, game.build_kind, point, game.placement_direction)
		var color := Color("7bf4d0") if valid else Color("ee7185")
		game.draw_colored_polygon(polygon, Color(color, 0.3)); outline(game, polygon, color, 2)
		if Power.is_electrical(game.build_kind):
			for source in game.structures:
				if source.kind in Power.SOURCES:
					game.draw_arc(game.world_to_screen(source.position), Power.source_range(source) * game.zoom, 0, TAU, 80, Color("588eae"), 1, true)
			var reach := Power.LINK_RANGE if game.build_kind == "repeater" else Power.GENERATOR_RANGE if game.build_kind == "generator" else Power.CORE_RANGE if game.build_kind == "core" else Power.LINK_RANGE
			game.draw_arc(game.world_to_screen(point), reach * game.zoom, 0, TAU, 80, Color(color, 0.5), 1, true)
		if game.wall_start.is_finite():
			game.draw_line(game.world_to_screen(game.wall_start), game.world_to_screen(point), Color(color, 0.6), 3, true)
