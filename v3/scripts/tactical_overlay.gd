class_name TacticalOverlay
extends Control

var world: WorldState
var camera: RTSCamera
var renderer: WorldRenderer
var selected: Array = []
var hovered := 0
var owner_id := 0
var health_trails: Dictionary = {}
var feedback_cursor := 0
var damage_numbers: Array = []
var marker_position := Vector2.ZERO
var marker_time := 0.0
var selection_pulse := 0.0
var marker_color := Color("85e4cd")
var map_texture: ImageTexture
var map_timer := 0.0
var map_stamp: Array = []
var map_splats: Dictionary = {}
var clock := 0.0
var drag_selection := Rect2()
signal map_toggle_requested
var map_expanded := false
var map_toggle: Button
var expanded_view: ExpandedMap
var placement_kind := ""
var placement_cell := Vector2i.ZERO
const FONT := preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_toggle = Button.new(); map_toggle.text = "Map"; map_toggle.tooltip_text = "Open full-screen tactical map"
	map_toggle.focus_mode = Control.FOCUS_NONE; map_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	map_toggle.custom_minimum_size = Vector2(44, 24); map_toggle.add_theme_font_size_override("font_size", 12)
	map_toggle.pressed.connect(func(): map_toggle_requested.emit()); add_child(map_toggle)
	var map_layer := CanvasLayer.new(); map_layer.layer = 3; add_child(map_layer)
	expanded_view = ExpandedMap.new(); expanded_view.overlay = self; map_layer.add_child(expanded_view); expanded_view.hide()

func reset() -> void:
	set_map_expanded(false)
	health_trails.clear(); selection_pulse = 0; feedback_cursor = 0; damage_numbers.clear(); marker_time = 0; map_timer = 0; map_texture = null; map_stamp.clear(); map_splats.clear()

func set_map_expanded(value: bool) -> void:
	map_expanded = value
	if expanded_view != null: expanded_view.visible = value
	if map_toggle != null: map_toggle.visible = not value
	queue_redraw()

func minimap_rect() -> Rect2:
	if map_expanded:
		var side := maxf(100, minf(size.x - 64, size.y - 144))
		return Rect2((size - Vector2.ONE * side) * 0.5 + Vector2(0, 8), Vector2.ONE * side)
	return Rect2(14, size.y - 198, 208, 184)

func map_point(point: Vector2) -> Vector2:
	var rect := minimap_rect().grow(-12)
	return rect.get_center() + Vector2(point.x, point.y) / (world.radius * 2.15) * rect.size

func minimap_world(point: Vector2) -> Vector2:
	var rect := minimap_rect().grow(-12)
	return (point - rect.get_center()) / rect.size * (world.radius * 2.15)

func mark(point: Vector2, color: Color = Color("85e4cd")) -> void:
	marker_position = point; marker_time = 0.7; marker_color = color

func _process(delta: float) -> void:
	if not visible or world == null: return
	map_toggle.position = Vector2(170, size.y - 194)
	if map_expanded: expanded_view.queue_redraw()
	clock += delta
	selection_pulse = maxf(0, selection_pulse - delta)
	marker_time = maxf(0, marker_time - delta)
	for effect in damage_numbers: effect.time -= delta
	damage_numbers = damage_numbers.filter(func(effect): return effect.time > 0)
	_consume_feedback()
	for e in world.units.values() + world.observed_structures(owner_id):
		if not renderer.bodies.has(e.id) or not renderer.bodies[e.id].visible: continue
		if not health_trails.has(e.id): health_trails[e.id] = {"hp": float(e.hp), "trail": float(e.hp), "hold": 0.0}
		var bar: Dictionary = health_trails[e.id]
		if float(e.hp) == float(bar.hp) and float(bar.trail) == float(bar.hp) and float(bar.hold) <= 0: continue
		if float(e.hp) < float(bar.hp): bar.hold = 0.12
		bar.hp = float(e.hp)
		bar.hold = maxf(0, float(bar.hold) - delta)
		if bar.hold <= 0: bar.trail = lerpf(float(bar.trail), float(e.hp), 1 - exp(-delta / maxf(0.001, float(world.cfg.presentation.feedback.healthTrailSeconds))))
		bar.trail = maxf(float(e.hp), float(bar.trail))
	for id in health_trails.keys():
		if not renderer.bodies.has(id) or not renderer.bodies[id].visible: health_trails.erase(id)
	map_timer -= delta
	if map_timer <= 0: _refresh_map(); map_timer = 0.4
	queue_redraw()

func _refresh_map() -> void:
	var stamp: Array = [world.known.get(owner_id, {}).hash(), world.visible.get(owner_id, {}).hash(), world.illuminated.hash(), world.tiles.hash()]
	if stamp == map_stamp: return
	map_stamp = stamp
	var pixels := PackedInt32Array(); pixels.resize(144 * 144); pixels.fill(Color("070d15").to_abgr32() - (1 << 32))
	var light: Dictionary = {}
	for area in world.illuminated.values(): light.merge(area, true)
	for cell in world.known.get(owner_id, {}):
		var p := HexGrid.world(cell) / (world.radius * 2.15) * 144 + Vector2(72, 72)
		var color := Color("293d48") if world.visible.get(owner_id, {}).has(cell) else Color("17242f")
		if light.has(cell): color = Color("779a91")
		if world.tiles[cell].cliff: color = Color("5a6873")
		elif world.tiles[cell].resource != "" and int(world.tiles[cell].amount) > 0: color = Color("cda365") if world.tiles[cell].resource == "ore" else Color("55c9ca")
		if not map_splats.has(cell):
			var splat := PackedInt32Array()
			for x in range(-1, 2):
				for y in range(-1, 2):
					var pixel := Vector2i(p) + Vector2i(x, y)
					if pixel.x >= 0 and pixel.y >= 0 and pixel.x < 144 and pixel.y < 144: splat.append(pixel.y * 144 + pixel.x)
			map_splats[cell] = splat
		var value := color.to_abgr32() - (1 << 32)
		for index in map_splats[cell]: pixels[index] = value
	var image := Image.create_from_data(144, 144, false, Image.FORMAT_RGBA8, pixels.to_byte_array())
	if map_texture == null: map_texture = ImageTexture.create_from_image(image)
	else: map_texture.update(image)

func _observed_entity(id: int) -> Dictionary:
	return world.observed_entity(id, owner_id)

func _project(point: Vector2, height: float = 0.15) -> Vector2:
	return camera.unproject_position(Vector3(point.x, height, point.y))

func _draw_activities() -> void:
	var marker_size := float(world.cfg.presentation.activityIndicators.sizePixels)
	var shown_groups: Dictionary = {}
	for id in selected:
		var e := _observed_entity(int(id))
		if e.is_empty() or e.owner != owner_id or e.get("remembered", false): continue
		var a := world.activity(e)
		var color := CommandSkin.activity_color(a)
		var point := _project(world.entity_position(e), 1.5) - Vector2(0, marker_size)
		draw_circle(point, marker_size * 0.7, Color("0c1c23"))
		draw_texture_rect(CommandSkin.icon(CommandSkin.task_icon(str(a.task))), Rect2(point - Vector2.ONE * marker_size * 0.5, Vector2.ONE * marker_size), false, color)
		if a.has("group") and not shown_groups.has(int(a.group)):
			shown_groups[int(a.group)] = true
			var source := _project(Vector2(float(a.source[0]), float(a.source[1])))
			draw_arc(source, marker_size * 1.3, 0, TAU, 24, color, 2, true)
			draw_texture_rect(CommandSkin.icon(CommandSkin.task_icon(str(a.task))), Rect2(source - Vector2.ONE * 8, Vector2.ONE * 16), false, color)
			var dropoff := world.observed_entity(int(a.get("destination", 0)), owner_id)
			if not dropoff.is_empty(): draw_dashed_line(source, _project(world.entity_position(dropoff)), Color(color, 0.45), 1, 8, true)
		if a.phase != "waiting": continue
		var pulse := 0.55 + 0.45 * (sin(clock * TAU / float(world.cfg.presentation.activityIndicators.pulseSeconds)) * 0.5 + 0.5)
		draw_arc(point, marker_size * 0.8, 0, TAU, 24, Color(color, pulse), 2, true)
		draw_string(FONT, point + Vector2(marker_size * 0.7, -marker_size * 0.4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		var target := world.observed_entity(int(a.target), owner_id)
		if not target.is_empty() and target.owner == owner_id:
			var destination := _project(world.entity_position(target))
			draw_dashed_line(point, destination, Color(color, pulse * 0.6), 1.5, 7, true)
			draw_arc(destination, marker_size * 1.5, 0, TAU, 32, Color(color, pulse), 2, true)
		elif a.has("cell"):
			var cell := Vector2i(int(a.cell[0]), int(a.cell[1]))
			if world.known.get(owner_id, {}).has(cell): draw_arc(_project(HexGrid.world(cell)), marker_size, 0, TAU, 24, Color(color, pulse), 2, true)

func _draw() -> void:
	if world == null or camera == null or map_expanded: return
	var font := FONT
	_draw_activities()
	if selection_pulse > 0:
		var ratio := selection_pulse / float(world.cfg.controls.selectionPulseSeconds)
		for id in selected.slice(0, 32):
			var entity_data := _observed_entity(int(id))
			if not entity_data.is_empty(): draw_arc(_project(world.entity_position(entity_data)), 17 + ratio * 10, 0, TAU, 24, Color(0.77, 0.83, 0.68, ratio * 0.65), 1.5, true)
	var contact_color := Color("e4ae68")
	for cell in world.unknown_contacts(owner_id):
		var position := _project(HexGrid.world(cell))
		var extent := 8.0 + sin(clock * 3) * 1.5
		draw_rect(Rect2(position - Vector2.ONE * extent, Vector2.ONE * extent * 2), Color(contact_color, 0.7), false, 1.5)
		draw_circle(position, 2, contact_color)
		if position.distance_to(get_viewport().get_mouse_position()) < 24:
			draw_string(font, position + Vector2(14, -8), "UNIDENTIFIED CONTACT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, contact_color)
	for id in selected:
		var emitter := _observed_entity(int(id))
		if emitter.is_empty() or emitter.owner != owner_id: continue
		if emitter.has("pos"):
			var definition: Dictionary = world.cfg.units[emitter.kind]
			if int(definition.get("detectionRangeTiles", 0)) > 0:
				_range_outline(HexGrid.cell(emitter.pos), int(definition.detectionRangeTiles), Color("e4ae68") if int(emitter.get("driver", 0)) != 0 else Color("657470"))
		if emitter.kind == "relay": _draw_electrical_links("relay", emitter.cell, int(emitter.id), bool(emitter.enabled))
		if emitter.kind == "radar": _range_outline(emitter.cell, int(world.cfg.structures.radar.detectionRangeBeyondFootprintTiles) + int(world.cfg.structures.radar.footprintRadiusTiles), Color("e4ae68"))
		if emitter.kind == "rampart": _range_outline(emitter.cell, int(world.cfg.combat.rampartRangeBeyondFootprintTiles) + int(world.cfg.structures.rampart.footprintRadiusTiles), Color("91c5bc"))
	if placement_kind != "":
		if placement_kind == "radar": _range_outline(placement_cell, int(world.cfg.structures.radar.detectionRangeBeyondFootprintTiles) + int(world.cfg.structures.radar.footprintRadiusTiles), Color("e4ae68"))
		if placement_kind == "rampart": _range_outline(placement_cell, int(world.cfg.combat.rampartRangeBeyondFootprintTiles) + int(world.cfg.structures.rampart.footprintRadiusTiles), Color("91c5bc"))
		if world.electrical_structure(placement_kind): _draw_electrical_links(placement_kind, placement_cell)
	if drag_selection.size.length() > 8:
		draw_rect(drag_selection, Color(0.72, 0.78, 0.64, 0.08))
		draw_rect(drag_selection, Color("a5b7a1"), false, 1)
	for id in selected.slice(0, 8):
		var u := _observed_entity(int(id))
		if u.is_empty() or not u.has("route") or u.owner != owner_id: continue
		if u.job.kind == "patrol":
			var a := Vector2(float(u.job.a[0]), float(u.job.a[1]))
			var b := Vector2(float(u.job.b[0]), float(u.job.b[1]))
			draw_dashed_line(_project(a), _project(b), Color(0.75, 0.7, 0.48, 0.5), 1.5, 6, true, true)
			for endpoint in [a, b]: draw_circle(_project(endpoint), 5, Color("c3b47c"), false, 1.5)
		if u.job.kind == "escort":
			var target := _observed_entity(int(u.job.target))
			if not target.is_empty(): draw_dashed_line(_project(u.pos), _project(world.entity_position(target)), Color(0.5, 0.75, 0.73, 0.55), 1.5, 5, true, true)
		var previous := _project(u.pos)
		for point in u.route:
			var screen := _project(point)
			draw_dashed_line(previous, screen, Color(0.7, 0.77, 0.65, 0.24), 1, 4, true, true)
			previous = screen
		var planned := previous
		for order in u.get("orders", []):
			var point := Vector2.ZERO
			if order.has("x") and order.has("z"): point = Vector2(float(order.x), float(order.z))
			elif order.has("q") and order.has("r"): point = HexGrid.world(Vector2i(int(order.q), int(order.r)))
			elif order.has("target"):
				var target := _observed_entity(int(order.target))
				if target.is_empty(): continue
				point = world.entity_position(target)
			else: continue
			var projected := _project(point)
			draw_dashed_line(planned, projected, Color(0.7, 0.8, 0.6, 0.5), 1.5, 4, true, true)
			draw_circle(projected, 4, Color("c3d1a1"), false, 1)
			planned = projected
	for e in world.units.values() + world.observed_structures(owner_id):
		if not renderer.bodies.has(e.id) or not renderer.bodies[e.id].visible: continue
		var maximum := float(world.cfg.structures[e.kind].health) if e.has("cell") else float(world.cfg.units[e.kind].health)
		var selected_here: bool = e.id in selected or e.id == hovered
		if e.owner == owner_id and e.has("cell") and e.built and int(world.cfg.structures[e.kind].powerDemand) > 0 and e.enabled and not e.powered:
			var warning := _project(world.entity_position(e), 1.65)
			draw_string(font, warning + Vector2(-8, -6), "! BLACKOUT" if e.get("blackout", false) and selected_here else "! NO POWER" if selected_here else "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("df937a"))
		if e.owner == owner_id and e.has("pos") and world.cfg.units[e.kind].has("driverSeats") and int(e.driver) == 0 and selected_here:
			draw_string(font, _project(e.pos, 1.2) + Vector2(-35, -10), "DRIVER REQUIRED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("d7ae73"))
		if not (selected_here or float(e.hp) < maximum): continue
		var point := _project(world.entity_position(e), 2.7 if e.kind == "anchor" else 1.35 if e.has("cell") else 0.9)
		var width := 62.0 if e.has("cell") else 38.0
		var rect := Rect2(point - Vector2(width / 2, 0), Vector2(width, 5))
		draw_rect(rect.grow(1), Color("080f18"))
		var trail := float(health_trails.get(e.id, {}).get("trail", e.hp))
		draw_rect(Rect2(rect.position, Vector2(width * clampf(trail / maximum, 0, 1), 5)), Color("c4ae83"))
		var color := Color("adc3a7") if e.owner == owner_id else Color("c38573")
		if e.has("built") and not e.built: color = Color("e3b56c")
		draw_rect(Rect2(rect.position, Vector2(width * clampf(float(e.hp) / maximum, 0, 1), 5)), color)
		if e.id == hovered: draw_string(font, point + Vector2(-width / 2, -6), str(e.kind).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c9e1e4"))
		if e.has("cargo") and e.id in selected and world.cargo_amount(e) > 0:
			draw_string(font, point + Vector2(-width / 2, 19), "%d / %d cargo" % [world.cargo_amount(e), world.cfg.units[e.kind].cargoCapacity], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e3b56c"))
	for effect in damage_numbers:
		var life := float(world.cfg.presentation.feedback.labelSeconds)
		var point := _project(effect.position, 1.0) + Vector2(8, -(life - float(effect.time)) * 27)
		var label := str(effect.label)
		if effect.kind == "hit": label = "-%d" % ceili(effect.amount) if float(effect.amount) > 0 else "ARMOR"
		draw_string(font, point + Vector2.ONE, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.02, 0.04, 0.05, minf(1, float(effect.time) * 4)))
		draw_string(font, point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(effect.color, minf(1, float(effect.time) * 4)))
	if marker_time > 0:
		var point := _project(marker_position)
		var radius := 9 + marker_time * 18
		draw_arc(point, radius * 0.65, 0, TAU, 32, Color(marker_color, marker_time * 0.5), 1, true)
		for i in range(4):
			var angle := i * PI / 2
			var direction := Vector2(cos(angle), sin(angle))
			var tip := point + direction * radius
			var side := direction.rotated(PI / 2) * 4
			draw_line(tip + direction * 5 + side, tip, Color(marker_color, marker_time * 1.4), 2, true)
			draw_line(tip + direction * 5 - side, tip, Color(marker_color, marker_time * 1.4), 2, true)
	_draw_map(self)

func _draw_map(canvas: Control) -> void:
	var font := FONT
	var map_rect := minimap_rect()
	canvas.draw_style_box(_map_style(), map_rect)
	if map_texture != null: canvas.draw_texture_rect(map_texture, map_rect.grow(-12), false)
	for e in world.units.values() + world.observed_structures(owner_id):
		if not renderer.bodies.has(e.id) or not renderer.bodies[e.id].visible: continue
		var point := map_point(world.entity_position(e))
		var color := Color("697d87") if e.get("remembered", false) else Color("80e5d0") if e.owner == owner_id else Color("ec7c8d")
		if e.has("cell"): canvas.draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), color)
		else: canvas.draw_circle(point, 3 if map_expanded else 1.7, color)
	for cell in world.unknown_contacts(owner_id):
		canvas.draw_rect(Rect2(map_point(HexGrid.world(cell)) - Vector2.ONE * 2, Vector2.ONE * 4), Color("e4ae68"), false, 1)
	var viewport_points := PackedVector2Array()
	for point in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), Vector2.ZERO]:
		var ground := camera.ground(point)
		var mapped := map_point(Vector2(ground.x, ground.z))
		viewport_points.append(mapped.clamp(map_rect.position + Vector2(2, 2), map_rect.end - Vector2(2, 2)))
	canvas.draw_polyline(viewport_points, Color(0.65, 0.91, 0.86, 0.65), 1, true)
	canvas.draw_string(font, map_rect.position + Vector2(10, 16), "TACTICAL MAP" if map_expanded else "TACTICAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8aa6b2"))

class ExpandedMap:
	extends Control
	var overlay: TacticalOverlay
	var close_button: Button

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		close_button = Button.new(); close_button.text = "Close map  [Esc]"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.add_theme_font_override("font", TacticalOverlay.FONT)
		add_child(close_button)
		close_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		close_button.offset_left = -180; close_button.offset_right = -24; close_button.offset_top = 20; close_button.offset_bottom = 54
		close_button.pressed.connect(func(): overlay.map_toggle_requested.emit())

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("060d13"))
		draw_string(TacticalOverlay.FONT, Vector2(28, 42), "TACTICAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("d1ddd2"))
		overlay._draw_map(self)
		draw_string(TacticalOverlay.FONT, Vector2(28, size.y - 24), "Drag to pan  /  Right click to order  /  Shift to queue", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("90aaa7"))
		var x := size.x - 420
		for entry in [["Allies", Color("80e5d0")], ["Enemies", Color("ec7c8d")], ["Contacts", Color("e4ae68")], ["Ore", Color("cda365")], ["Gas", Color("55c9ca")]]:
			draw_circle(Vector2(x, size.y - 28), 3, entry[1])
			draw_string(TacticalOverlay.FONT, Vector2(x + 9, size.y - 24), entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("90aaa7"))
			x += 78

func _map_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0a141e"); style.border_color = Color("314c58"); style.set_border_width_all(1); style.set_corner_radius_all(5)
	return style

func electrical_links(kind: String, cell: Vector2i, exclude: int = 0) -> Array:
	var links: Array = []
	if not world.electrical_structure(kind): return links
	for structure in world.observed_structures(owner_id):
		if int(structure.id) == exclude or structure.owner != owner_id or not structure.built or not structure.enabled: continue
		if not world.electrical_structure(structure.kind): continue
		if HexGrid.distance(structure.cell, cell) <= world.electrical_reach(kind) + world.electrical_reach(structure.kind): links.append(structure)
	return links

func _draw_electrical_links(kind: String, cell: Vector2i, exclude: int = 0, enabled: bool = true) -> void:
	var links := electrical_links(kind, cell, exclude)
	var supplied := links.any(func(s): return s.powered and int(s.get("grid_capacity", 0)) > 0)
	var tint := Color("b7d8b0") if supplied and enabled else Color("d5a473") if enabled else Color("849091")
	_range_outline(cell, world.electrical_reach(kind), tint)
	var origin := _project(HexGrid.world(cell))
	for structure in links:
		var point := _project(HexGrid.world(structure.cell))
		draw_dashed_line(origin, point, Color(tint, 0.85 if enabled else 0.4), 2, 6, true, true)
		draw_circle(point, 7, tint, false, 2, true)
		_range_outline(structure.cell, world.electrical_reach(structure.kind), Color(tint, 0.4))
	var label := "LINKS: %d · %s" % [links.size(), "CONNECTED" if exclude != 0 and enabled else "WOULD CONNECT" if exclude == 0 else "OFF / POTENTIAL LINKS"]
	if links.is_empty(): label = "NO GRID LINKS IN RANGE"
	draw_string(FONT, _project(HexGrid.world(cell), 2.6) + Vector2(12, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)

func _range_outline(cell: Vector2i, reach: int, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(7): points.append(_project(HexGrid.world(cell) + HexGrid.world(HexGrid.DIRECTIONS[i % 6]) * (reach + 0.5)))
	draw_colored_polygon(points.slice(0, 6), Color(color, 0.035 * color.a))
	draw_polyline(points, Color(color, 0.5 * color.a), 1.5, true)

func _consume_feedback() -> void:
	for event in world.feedback_for(owner_id, feedback_cursor):
		feedback_cursor = maxi(feedback_cursor, int(event.serial))
		if world.tick - int(event.tick) > int(world.cfg.presentation.feedback.maxCatchupTicks): continue
		if event.kind == "hit" and not world.cfg.presentation.damageNumbers: continue
		if not event.kind in ["hit", "deposit", "ready"]: continue
		var color := Color("9fc9b4")
		var label := str(event.get("label", ""))
		if event.kind == "deposit": label = "+%d DELIVERED" % int(event.amount)
		if event.kind == "hit": color = Color("9ed8d0") if event.shielded else Color("e4b58e")
		var combined := false
		if event.kind in ["hit", "deposit"]:
			for entry in damage_numbers:
				if entry.kind == event.kind and int(entry.target) == int(event.target) and int(event.tick) - int(entry.first_tick) <= ceili(float(world.cfg.presentation.feedback.damageNumberGroupSeconds) * float(world.cfg.match.simulationTicksPerSecond)):
					entry.amount += float(event.amount); entry.time = float(world.cfg.presentation.feedback.labelSeconds)
					if event.kind == "deposit": entry.label = "+%d DELIVERED" % int(entry.amount)
					combined = true; break
		if not combined: damage_numbers.append({"kind": event.kind, "first_tick": event.tick, "position": event.at, "target": int(event.get("target", 0)), "amount": float(event.get("amount", 0)), "label": label, "color": color, "time": float(world.cfg.presentation.feedback.labelSeconds)})
		while damage_numbers.size() > int(world.cfg.presentation.feedback.maxLabels): damage_numbers.pop_front()
