extends Node2D
## Input and presentation adapter. All gameplay mutations enter the command queue.
const Simulation = preload("res://engine/simulation.gd")
const Rules = preload("res://engine/expedition_rules.gd")
const Hex = preload("res://engine/hex_grid.gd")
const Terrain = preload("res://engine/expedition_terrain.gd")
const Footprints = preload("res://engine/structure_footprints.gd")
const Power = preload("res://engine/expedition_power.gd")
const SelectionBox = preload("res://view/selection_box.gd")
const BUILD_KINDS = Simulation.BUILD_KINDS
const MINT = Simulation.MINT
const AMBER = Simulation.AMBER
const Primitives = preload("res://view/primitives.gd")
const RTSTheme = preload("res://view/rts_theme.gd")
@export var initial_seed := 0
var simulation # May be prepared by the loading screen before entering the tree.
var terrain_renderer: Node2D
var sprites = preload("res://view/sprite_library.gd").new()
var darkness: ColorRect
var selection_highlight: ColorRect
var selected: Array[SimEntity] = []
var selected_resource: Dictionary = {}
var build_kind := ""
var tactical_mode := ""
var patrol_queuing := false
var repair_mode := false
var expedition_mode := false
var mining_mode := false
var placement_direction := 0
var started := false
var focus := Vector2.ZERO
var zoom := 18.0
var camera_angle := 0.0
var accumulator := 0.0
var previous_positions: Dictionary = {}
var dragging := false
var selecting := false
var select_start := Vector2.ZERO
var wall_start := Vector3.INF
var mouse_world := Vector3.ZERO
var last_event := 0
var shown_ending := false
var ui_clock := 0.0
var notice_time := 0.0
var build_buttons: Dictionary = {}
var context_buttons: Dictionary = {}
var power_preview_label: Label
var hud: RefCounted
var world_bars: Control
var ui: Control
var selection_box: Control
var stats: Label
var objective_label: Label
var details: Label
var message: Label
var sensors: Label
var pause_button: Button
var command_panel: PanelContainer
var command_scroll: ScrollContainer
var command_content: VBoxContainer
var minimap: Control
var command_title: Label
var construction_panel: PanelContainer
var overlay: ColorRect
var overlay_title: Label
var overlay_text: Label
var overlay_button: Button

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	get_window().min_size = Vector2i(1100, 720)
	var seed_value := initial_seed if initial_seed > 0 else randi_range(1, 2147483647)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
	if simulation == null: simulation = Simulation.new()
	if not simulation.started: simulation.initialize(seed_value)
	for patch in simulation.resource_nodes: sprites.initial_resources[patch.position] = int(patch.remaining)
	hud = preload("res://view/game_hud.gd").new(); hud.setup(self)
	minimap = preload("res://view/minimap.gd").new(); ui.add_child(minimap); minimap.setup(self)
	darkness = preload("res://view/darkness.gd").new(); add_child(darkness); darkness.setup(self)
	terrain_renderer = preload("res://view/terrain_renderer.gd").new(); add_child(terrain_renderer); terrain_renderer.setup(self)
	selection_highlight = preload("res://view/selection_highlight.gd").new(); add_child(selection_highlight); selection_highlight.setup(self)
	get_viewport().size_changed.connect(func(): hud.fit(); queue_redraw())
	show_briefing(); refresh_ui()
	RenderingServer.set_default_clear_color(Color("080e16"))

func begin_run() -> void:
	started = true; overlay.visible = false
	selected.assign([simulation.core]); refresh_ui()

func submit(kind: String, extra: Dictionary = {}) -> void:
	var command := extra.duplicate(true)
	command.kind = kind; command.actors = selected.map(func(actor): return actor.simulation_id)
	command.append = extra.get("append", Input.is_physical_key_pressed(KEY_SHIFT))
	command.direction = placement_direction
	simulation.enqueue(command)

func _process(dt: float) -> void:
	if started and not simulation.ended and not simulation.paused:
		accumulator += dt
		while accumulator + 0.000000001 >= Simulation.TICK:
			previous_positions.clear()
			for actor in simulation.units + simulation.creatures: previous_positions[actor.simulation_id] = actor.position
			simulation.step(); accumulator = maxf(0, accumulator - Simulation.TICK)
		var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		focus += pan.rotated(-camera_angle) * dt * 480.0 / zoom
	for event in simulation.events:
		if event.serial > last_event:
			if event.type == "message": notify(event.text)
		last_event = maxi(last_event, event.serial)
	selected = selected.filter(func(actor): return SimEntity.valid(actor) and actor.hp > 0 and (not actor is SimUnit or actor.aboard == null))
	sprites.tick(self, 0.0 if simulation.paused else dt)
	notice_time = maxf(0, notice_time - dt)
	if simulation.ended and not shown_ending:
		shown_ending = true; overlay.visible = true
		overlay_title.text = "Hive Core secured." if simulation.victorious else "Expedition lost."
		overlay_text.text = message.tooltip_text + "\n\nSeed %d / Mission time %.1fs" % [scenario_seed, elapsed]
		overlay_button.text = "Restart expedition"
	ui_clock += dt
	if ui_clock >= 0.1: refresh_ui(); ui_clock = 0
	mouse_world = ground_point(get_viewport().get_mouse_position())
	queue_redraw()

func actor_position(actor: SimEntity) -> Vector3:
	var previous: Vector3 = previous_positions.get(actor.simulation_id, actor.position)
	return previous.lerp(actor.position, clampf(accumulator / Simulation.TICK, 0, 1))

func world_to_screen(point: Vector3) -> Vector2:
	return (Vector2(point.x, point.z) - focus).rotated(camera_angle) * zoom + get_viewport_rect().size * 0.5

func ground_point(screen: Vector2) -> Vector3:
	var flat := (screen - get_viewport_rect().size * 0.5).rotated(-camera_angle) / zoom + focus
	return simulation.navigation.terrain.surface(Vector3(flat.x, 0, flat.y))

func pick(screen: Vector2) -> SimEntity:
	# Screen geometry alone participates; labels and status bars never do.
	var candidates: Array = simulation.units + simulation.creatures
	candidates.reverse()
	for actor in candidates:
		if actor.hp <= 0 or not actor.visible or (actor is SimUnit and actor.aboard != null): continue
		if sprites.hit(self, actor.kind, actor_position(actor), sprites.actor_angle(actor), screen): return actor
		if screen.distance_to(world_to_screen(actor_position(actor))) <= maxf(6, Primitives.unit_radius(actor) * zoom): return actor
	var buildings: Array = simulation.structures + [simulation.mission.hive]
	buildings.reverse()
	for building in buildings:
		if building.hp <= 0 or not building.visible: continue
		if sprites.hit_building(self, building, Primitives.structure_polygon(self, building), screen): return building
		if Geometry2D.is_point_in_polygon(screen, Primitives.structure_polygon(self, building)): return building
	return null

func resource_visible(patch: Dictionary) -> bool:
	return patch.discovered and patch.remaining > 0 and resource_fields.covering_extractor(simulation, patch.position) == null

func pick_resource(screen: Vector2) -> Dictionary:
	var patches: Array = simulation.resource_nodes.duplicate(); patches.reverse()
	for patch in patches:
		if resource_visible(patch) and sprites.hit(self, sprites.resource_key(patch), patch.position, 0, screen): return patch
	return {}

func _draw() -> void:
	if simulation.started:
		terrain_renderer.sync()
		Primitives.draw_world(self)

func _exit_tree() -> void:
	simulation.dispose()

func refresh_ui() -> void:
	if hud == null: return
	if not selected_resource.is_empty() and not resource_visible(selected_resource): selected_resource = {}
	refresh_context_commands(); hud.update()

func toggle_pause() -> void:
	simulation.paused = not simulation.paused
	refresh_ui()

func choose_build(kind: String) -> void:
	if kind not in BUILD_KINDS or selected_engineers().is_empty(): return
	build_kind = "" if build_kind == kind else kind
	tactical_mode = ""; expedition_mode = false; repair_mode = false
	hud.show_tab("build"); notify("Place %s / T rotates / Shift queues / right-click cancels" % Rules.title(kind))

func choose_expedition(mining: bool = false) -> void:
	var crew: Array = complex_commands.expedition_selection(selected)
	if not (complex_commands.mining_available(crew) if mining else complex_commands.expedition_available(crew)): return
	expedition_mode = not expedition_mode or mining_mode != mining; mining_mode = mining
	build_kind = ""; tactical_mode = ""; repair_mode = false
	notify("Choose a resource field, extractor, or storage building" if mining else "Choose terrain to explore")

func choose_tactical(mode: String) -> void:
	if not tactical_groups.available(selected) and not selected.any(func(actor): return actor is SimUnit and actor.kind == "drill"): return
	patrol_queuing = false
	tactical_mode = "" if tactical_mode == mode else mode; build_kind = ""; expedition_mode = false; repair_mode = false
	notify(mode.capitalize() + " / click a destination / Shift queues")

func choose_repair() -> void:
	if selected_engineers().is_empty() and not selected_turrets().is_empty(): reload_selected_turrets(); return
	if selected_engineers().is_empty(): return
	repair_mode = not repair_mode; build_kind = ""; tactical_mode = ""; expedition_mode = false
	notify("Choose a structure to build or repair")

func numbered_command(index: int) -> void:
	var factory := selected_factory()
	if factory != null:
		var kinds: Array = Rules.PRODUCTION[factory.kind]
		if index < kinds.size(): train_unit(kinds[index])
	elif not selected_engineers().is_empty() and index < BUILD_KINDS.size(): choose_build(BUILD_KINDS[index])

func command_click(screen: Vector2, append: bool, button: int) -> void:
	# Once Shift has added patrol points, a plain left click only finishes input.
	if tactical_mode == "patrol" and patrol_queuing and not append and button == MOUSE_BUTTON_LEFT:
		tactical_mode = ""; patrol_queuing = false; return
	target_click(screen, append)

func target_click(screen: Vector2, append: bool) -> void:
	var actor := pick(screen)
	var point := actor.position if actor != null else ground_point(screen)
	if expedition_mode:
		if mining_mode and actor is SimStructure and actor.kind == "extractor":
			var deposit: Dictionary = resource_fields.extractor_resource(simulation, actor)
			if deposit.is_empty(): notify("No resources remain beneath this extractor"); return
			point = deposit.position
		if mining_mode and actor is SimStructure and actor.kind in ["core", "depot", "gas_tank"]:
			var nearest := INF
			for patch in resource_nodes:
				if not patch.discovered or patch.remaining <= 0 or (actor.kind != "core" and patch.kind != ("minerals" if actor.kind == "depot" else "gas")): continue
				var distance: float = patch.position.distance_squared_to(actor.position)
				if distance < nearest: nearest = distance; point = patch.position
		var patch: Dictionary = simulation.resource_at(point)
		if mining_mode and (patch.is_empty() or not patch.discovered or patch.remaining <= 0) and not (actor is SimStructure and actor.kind == "extractor"): notify("Mining requires a surveyed resource field or extractor"); return
		submit("expedition", {"point": point, "mining": mining_mode, "append": append}); expedition_mode = false
	elif tactical_mode != "":
		var mode := "attack" if tactical_mode == "attack_move" and (actor is SimPredator or actor == mission.hive) else tactical_mode
		submit("tactical", {"point": point, "mode": mode, "target": actor.simulation_id if actor != null else 0, "append": append})
		patrol_queuing = tactical_mode == "patrol" and append
		if not append: tactical_mode = ""
	elif repair_mode:
		if actor is SimStructure and actor.complete and actor.hp < float(Rules.STRUCTURES[actor.kind].hp):
			submit("repair", {"target": actor.simulation_id}); repair_mode = false
		elif actor != null: selected.assign([actor]); repair_mode = false; refresh_ui()
	elif build_kind != "":
		if actor is SimStructure and not (actor.kind in ["platform", "ramp"] and actor.complete):
			selected.assign([actor]); build_kind = ""; refresh_ui(); return
		point = ground_point(screen)
		if not simulation.valid_site(build_kind, Hex.snap(point, Terrain.CELL), placement_direction) or not economy.can_spend(Rules.cost(build_kind)):
			notify("Use clear terrain in or beside illumination and check available resources"); return
		submit("build", {"building": build_kind, "point": Hex.snap(point, Terrain.CELL)})
		if not append: build_kind = ""
	else: submit("context", {"point": point, "target": actor.simulation_id if actor != null else 0, "append": append})

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if dragging:
			if event.alt_pressed: camera_angle += event.relative.x * 0.006
			else: focus -= event.relative.rotated(-camera_angle) / zoom
		if selecting:
			selection_box.rectangle = Rect2(select_start, event.position - select_start).abs()
			selection_box.active = event.position.distance_to(select_start) > 8; selection_box.queue_redraw()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE: dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT:
			if wall_start.is_finite():
				if get_viewport().gui_get_hovered_control() == null: submit("walls", {"start": wall_start, "point": ground_point(event.position)})
				wall_start = Vector3.INF
				if not event.shift_pressed: build_kind = ""
			if selecting:
				if not event.shift_pressed: selected.clear()
				selected_resource = {}
				if selection_box.active:
					for unit in simulation.units:
						if unit.aboard == null and selection_box.rectangle.has_point(world_to_screen(actor_position(unit))) and not selected.has(unit): selected.append(unit)
				else:
					var actor := pick(select_start)
					if actor != null:
						if event.double_click and actor is SimUnit:
							for unit in simulation.units:
								if unit.kind == actor.kind and unit.aboard == null and get_viewport_rect().has_point(world_to_screen(unit.position)) and not selected.has(unit): selected.append(unit)
						elif not selected.has(actor): selected.append(actor)
						elif event.shift_pressed: selected.erase(actor)
					else: selected_resource = pick_resource(select_start)
				selecting = false; selection_box.active = false; selection_box.queue_redraw(); refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not started: begin_run(); return
		if event.keycode == KEY_F1: hud.toggle_help(); return
		if not started or ended: return
		if event.keycode >= KEY_0 and event.keycode <= KEY_9: numbered_command(9 if event.keycode == KEY_0 else event.keycode - KEY_1)
		match event.keycode:
			KEY_Q: choose_tactical("attack_move")
			KEY_V: choose_tactical("defend")
			KEY_P: choose_tactical("patrol")
			KEY_C: choose_tactical("drill")
			KEY_E: choose_expedition(false)
			KEY_M: choose_expedition(true)
			KEY_R: choose_repair()
			KEY_B: board_squad()
			KEY_U: unload()
			KEY_L: load_nearest()
			KEY_J: stock_depot()
			KEY_H: return_home()
			KEY_G: escort()
			KEY_Y: toggle_repeater()
			KEY_Z: toggle_turret_reload()
			KEY_O: toggle_gate()
			KEY_K: toggle_gate_lock()
			KEY_X: stop_selected()
			KEY_DELETE: destroy_selected()
			KEY_SPACE: toggle_pause()
			KEY_T: placement_direction = (placement_direction + 1) % 6
			KEY_F: focus = Vector2.ZERO
			KEY_COMMA: camera_angle -= PI / 6
			KEY_PERIOD: camera_angle += PI / 6
			KEY_HOME: focus = Vector2.ZERO; camera_angle = 0; zoom = 18
			KEY_ESCAPE:
				patrol_queuing = false
				if hud.help_overlay.visible: hud.toggle_help()
				else:
					if build_kind == "" and tactical_mode == "" and not repair_mode and not expedition_mode: selected.clear()
					build_kind = ""; tactical_mode = ""; repair_mode = false; expedition_mode = false; wall_start = Vector3.INF
	if not started or ended: return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE: dragging = true
			MOUSE_BUTTON_WHEEL_UP: zoom = minf(160, zoom * 1.1)
			MOUSE_BUTTON_WHEEL_DOWN: zoom = maxf(3, zoom / 1.1)
			MOUSE_BUTTON_RIGHT:
				if build_kind != "" or repair_mode: build_kind = ""; repair_mode = false; wall_start = Vector3.INF
				else: command_click(event.position, event.shift_pressed, MOUSE_BUTTON_RIGHT)
			MOUSE_BUTTON_LEFT:
				if build_kind == "wall": wall_start = ground_point(event.position)
				elif build_kind != "" or repair_mode or tactical_mode != "" or expedition_mode: command_click(event.position, event.shift_pressed, MOUSE_BUTTON_LEFT)
				elif event.double_click:
					var actor := pick(event.position)
					if actor is SimUnit:
						if not event.shift_pressed: selected.clear()
						for unit in simulation.units:
							if unit.kind == actor.kind and unit.aboard == null and get_viewport_rect().has_point(world_to_screen(actor_position(unit))) and not selected.has(unit): selected.append(unit)
						refresh_ui()
				else: select_start = event.position; selecting = true

func _get(property: StringName):
	return simulation.get(property) if simulation != null else null

func style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = RTSTheme.EDGE
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


func panel(parent: Node) -> PanelContainer:
	var node = preload("res://view/rts_panel.gd").new()
	node.add_theme_stylebox_override("panel", style(RTSTheme.PANEL))
	parent.add_child(node)
	return node


func label(parent: Node, text: String, size: int = 15, color: Color = RTSTheme.TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node


func button(parent: Node, text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 34
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	RTSTheme.apply_button(node)
	node.pressed.connect(callback)
	parent.add_child(node)
	return node


func show_briefing() -> void:
	overlay_title.text = "People keep the lights on."
	overlay_text.text = "You land with HQ, one engineer, and one marine. HQ stores both resources and provides a small emergency grid. Scout the darkness to find extraction and the Lightless Hive.\n\n1. Scout for and repair the extraction beacon with an engineer.\n2. Scout for the hive, then send infantry to steal its core.\n3. Bring the carrier to extraction and hold for 60 seconds.\n\nThe core drops if its carrier dies. If the Lightless recover it, or HQ is destroyed, the mission is lost. Leaving extraction or losing the beacon resets the timer.\n\nScout with units to discover resources; HQ starts beside a small material field and one methane patch. M starts mining at a patch or receiver; E explores terrain. Q attack-moves, V defends, P patrols. Shift adds orders and patrol points. Units recover health near HQ."

func cost_label(kind: String) -> String:
	var cost := Rules.cost(kind)
	return "%d MAT%s" % [cost.minerals, " + %d CH4" % cost.gas if int(cost.gas) > 0 else ""]


func selected_vehicles() -> Array[SimUnit]:
	var result: Array[SimUnit] = []
	for actor in selected:
		if SimEntity.valid(actor) and actor is SimUnit and actor.is_vehicle() and actor.hp > 0: result.append(actor)
	return result


func selected_jeep() -> SimUnit:
	for actor in selected:
		if SimEntity.valid(actor) and actor is SimUnit and actor.is_vehicle() and actor.hp > 0: return actor
	return null


func selected_infantry() -> Array[SimUnit]:
	var result: Array[SimUnit] = []
	for actor in selected:
		if SimEntity.valid(actor) and actor is SimUnit and not actor.is_vehicle() and actor.aboard == null and actor.hp > 0: result.append(actor)
	return result


func selected_engineers() -> Array[SimUnit]:
	var result: Array[SimUnit] = []
	for unit in selected_infantry():
		if unit.kind == "engineer": result.append(unit)
	return result


func selected_turrets() -> Array[SimStructure]:
	var result: Array[SimStructure] = []
	for actor in selected:
		if actor is SimStructure and Rules.TURRETS.has(actor.kind): result.append(actor)
	return result


func selected_factory() -> SimStructure:
	for actor in selected:
		if actor is SimStructure and actor.complete and actor.kind in ["barracks", "garage", "core"]: return actor
	return null


func selected_gate() -> SimStructure:
	for actor in selected:
		if actor is SimStructure and actor.complete and actor.kind == "gate": return actor
	return null


func refresh_context_commands() -> void:
	if construction_panel == null: return
	var engineers := selected_engineers()
	var infantry := selected_infantry()
	var vehicle := selected_jeep()
	var factory := selected_factory()
	var gate := selected_gate()
	var has_engineer := not engineers.is_empty()
	var has_infantry := not infantry.is_empty()
	var has_vehicle := vehicle != null
	var fallback := nearest_vehicle(infantry[0].position, true) if has_infantry else null
	var visible_commands := {
		"reload_turret": selected_turrets().any(func(turret): return Rules.TURRETS[turret.kind].magazine > 0),
		"auto_reload": selected_turrets().any(func(turret): return Rules.TURRETS[turret.kind].magazine > 0),
		"mining": complex_commands.mining_available(complex_commands.expedition_selection(selected)),
		"attack": tactical_groups.available(selected), "defend": tactical_groups.available(selected), "patrol": tactical_groups.available(selected),
		"drill_order": selected.any(func(actor): return actor is SimUnit and actor.kind == "drill"),
		"destroy": selected.any(func(actor): return actor is SimUnit or (actor is SimStructure and actor != mission.hive)),
		"repeater": selected.any(func(actor): return actor is SimStructure and actor.kind == "repeater"),
		"drill": factory != null and factory.kind == "garage",
		"expedition": complex_commands.expedition_available(complex_commands.expedition_selection(selected)),
		"board": fallback != null or (has_vehicle and vehicle.occupied_seats() < vehicle.seat_capacity()),
		"unload": has_vehicle and vehicle.occupied_seats() > 0,
		"load": has_vehicle,
		"stock": has_vehicle and vehicle.cargo_total() > 0,
		"home": has_vehicle,
		"escort": has_infantry and nearest_vehicle(infantry[0].position) != null,
		"repair": has_engineer,
		"stop": has_vehicle or has_infantry,
		"gate": gate != null,
		"gate_lock": gate != null,
		"engineer": factory != null and factory.kind in ["barracks", "core"],
		"marine": factory != null and factory.kind == "barracks",
		"flamer": factory != null and factory.kind == "barracks",
		"scout": factory != null and Rules.PRODUCTION[factory.kind].has("scout"),
		"jeep": factory != null and factory.kind == "garage",
		"cancel_train": factory != null and not factory.queue.is_empty()
	}
	var changed := false
	if expedition_mode and not visible_commands.expedition:
		expedition_mode = false
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if expedition_mode or tactical_mode != "" else Input.CURSOR_ARROW)
	for key in context_buttons:
		var show: bool = visible_commands[key]
		changed = changed or context_buttons[key].visible != show
		context_buttons[key].visible = show
		if Rules.UNITS.has(key):
			context_buttons[key].disabled = not economy.can_spend(Rules.cost(key))
			if factory != null and Rules.PRODUCTION[factory.kind].has(key):
				context_buttons[key].text = "%d %s\n%s" % [Rules.PRODUCTION[factory.kind].find(key) + 1, Rules.title(key), cost_label(key)]
	if not selected_turrets().is_empty(): context_buttons.auto_reload.text = "Auto: %s [Z]" % ("ON" if selected_turrets()[0].auto_reload else "OFF")
	context_buttons.board.text = "Board units [B]" if has_infantry else "Board squad [B]"
	context_buttons.expedition.text = "Explore target [E]" if expedition_mode and not mining_mode else "Explore [E]"
	context_buttons.unload.text = "Unload passengers [U]" if has_vehicle and not vehicle.passengers.is_empty() else "Unload driver [U]"
	context_buttons.home.disabled = has_vehicle and not vehicle.has_driver()
	context_buttons.stock.disabled = has_vehicle and not vehicle.has_driver()
	context_buttons.gate.text = "Close gate [O]" if gate != null and gate.gate_open else "Open gate [O]"
	if gate != null and gate.gate_open and not gate.powered: context_buttons.gate.text = "Manual close [O]"
	if gate != null: context_buttons.gate.disabled = not gate.gate_open and (not gate.powered or gate.gate_locked)
	context_buttons.gate_lock.text = "Unlock gate [K]" if gate != null and gate.gate_locked else "Lock gate [K]"
	command_title.text = "SELECTION COMMANDS" if has_vehicle or has_infantry else "PRODUCTION" if factory != null else "STRUCTURE DETAILS" if not selected.is_empty() else "SELECT A UNIT"
	if not has_engineer: build_kind = ""; repair_mode = false
	for kind in build_buttons: build_buttons[kind].disabled = not economy.can_spend(Rules.cost(kind))
	if hud != null: hud.after_context()
	if changed: hud.fit()


func nearest_vehicle(point: Vector3, free_seat: bool = false) -> SimUnit:
	return simulation.nearest_vehicle(point, free_seat)
func notify(text: String) -> void:
	message.text = text.split(" / ")[0]; message.tooltip_text = text; notice_time = 3.5

var scenario_seed:
	get: return simulation.scenario_seed
var tactical_groups:
	get: return simulation.tactical_groups
var mission:
	get: return simulation.mission
var resource_fields:
	get: return simulation.resource_fields
var economy:
	get: return simulation.economy
var power:
	get: return simulation.power
var wrecks:
	get: return simulation.wrecks
var resource_nodes:
	get: return simulation.resource_nodes
var navigation:
	get: return simulation.navigation
var light:
	get: return simulation.light
var units:
	get: return simulation.units
var complex_commands:
	get: return simulation.complex_commands
var structures:
	get: return simulation.structures
var creatures:
	get: return simulation.creatures
var core:
	get: return simulation.core
var elapsed:
	get: return simulation.elapsed
var paused:
	get: return simulation.paused
var ended:
	get: return simulation.ended
var victorious:
	get: return simulation.victorious
var tick_number:
	get: return simulation.tick_number
var sensor_activity:
	get: return simulation.sensor_activity
var sensor_blips:
	get: return simulation.sensor_blips

func board_squad() -> void:
	submit("board_squad")

func unload() -> void:
	submit("unload")

func load_nearest() -> void:
	submit("load_nearest")

func stock_depot() -> void:
	submit("stock_depot")

func return_home() -> void:
	submit("return_home")

func escort() -> void:
	submit("escort")

func toggle_auto_recharge() -> void:
	submit("toggle_auto_recharge")

func reload_selected_turrets() -> void:
	submit("reload_selected_turrets")

func toggle_turret_reload() -> void:
	submit("toggle_turret_reload")

func toggle_repeater() -> void:
	submit("toggle_repeater")

func toggle_gate() -> void:
	submit("toggle_gate")

func toggle_gate_lock() -> void:
	submit("toggle_gate_lock")

func stop_selected() -> void:
	build_kind = ""; tactical_mode = ""; expedition_mode = false; repair_mode = false
	submit("stop_selected")

func destroy_selected() -> void:
	submit("destroy_selected")

func cancel_training() -> void:
	submit("cancel_training")

func train_unit(kind: String) -> void:
	submit("train", {"unit": kind})
