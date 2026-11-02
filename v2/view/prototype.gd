extends Node3D
## Presentation/input only. Meshes and labels never drive gameplay.
const Geometry = preload("res://core/geometry.gd")
const FootprintMesh = preload("res://view/footprint_mesh.gd")
const Content = preload("res://core/content.gd")
const Session = preload("res://net/match_session.gd")
const Simulation = preload("res://core/simulation.gd")
const Transport = preload("res://net/coordinator_transport.gd")
const Hex = preload("res://core/hex_cells.gd")
const VisibilityGround = preload("res://view/visibility_ground.gd")
const VeilOverlay = preload("res://view/veil_overlay.gd")
const Construction = preload("res://core/construction.gd")
const Escalation = preload("res://core/nest_escalation.gd")
const Mission = preload("res://core/mission.gd")
const ConfigEditor = preload("res://view/config_editor.gd")
const Rally = preload("res://core/rally.gd")
const Spawning = preload("res://core/spawning.gd")
var session = Session.new()
var camera: Camera3D
var actors_root: Node3D
var actor_nodes: Dictionary = {}
var field_nodes: Dictionary = {}
var mission_status: Label
var extract_button: Button
var selected: Array = []
var accumulator := 0.0
var refresh_time := 0.0
var _syncing_meshes := false
var _light_snapshot: Dictionary = {}
var _frame_signature: Array = []
var _order_signature: Array = []
var lobby: Control
var editor_panel: Control
var hud: Control
const MENU_PLAY := 0
const MENU_MULTIPLAYER := 1
const MENU_SETUP := 2
const MENU_CONTENT := 3
const MENU_GUIDE := 4
var menu_tabs: TabContainer
var menu_navigation: VBoxContainer
var menu_buttons: Array[Button] = []
var network_lobby: Control
var diagnostics: Label
var selection_panel: Control
var selection_hint: Label
var production_panel: Control
var construction_panel: Control
var stance_panel: Control
var context_controls: Dictionary = {}
var editor: TextEdit
var config_editor
var status: Label
var lobby_players: Label
var stats: Label
var inspector: Label
var event_log: Label
var faction: OptionButton
var sandbox_control: OptionButton
var seed_value: SpinBox
var room: LineEdit
var endpoint: LineEdit
var ice: LineEdit
var products: OptionButton
var structures: OptionButton
var build_button: Button
var placement_preview: MeshInstance3D
var _build_catalog := ""
var _build_rotation := 0
var start_button: Button
var _catalog := ""
var _web_test_callback
var _web_test_tick_limit := 0
var veil_overlay
var visibility_ground
var stance_choices: OptionButton
var target_hint: Label
var _target_mode := ""

func _ready() -> void:
	_build_world()
	_build_ui()
	var outline := ImmediateMesh.new()
	outline.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for corner in 7:
		var angle := float(corner) * TAU / 6.0 + PI / 6.0
		outline.surface_add_vertex(Vector3(cos(angle), 0.07, sin(angle)))
	outline.surface_end()
	placement_preview = MeshInstance3D.new()
	placement_preview.mesh = outline
	placement_preview.material_override = _material(Color("80dcac"), true)
	placement_preview.hide()
	add_child(placement_preview)
	session.status_changed.connect(func(message): status.text = message)
	session.lobby_changed.connect(_lobby_changed)
	session.match_started.connect(_started)
	status.text = ""
	if OS.has_feature("web") and JavaScriptBridge.eval("new URLSearchParams(location.search).get('selftest') === '1'"):
		var result: Dictionary = preload("res://tests/foundation_suite.gd").new().run()
		JavaScriptBridge.eval("window.atdTestResult = " + JSON.stringify(result))
		_web_test_callback = JavaScriptBridge.create_callback(_web_test_action)
		JavaScriptBridge.get_interface("window").atdTestAction = _web_test_callback

func _web_test_action(arguments: Array) -> void:
	# Explicit selftest URL only; exercises the same UI/session entry points.
	match str(arguments[0]):
		"local": _local()
		"reset": _reset()
		"host": _connect(true)
		"join": room.text = str(arguments[1]); _connect(false)
		"start": _start_network()
		"finish_test": session.transport.send_to(1, {"type": "test_done"})
		"limit": _web_test_tick_limit = maxi(0, int(str(arguments[1])))
		"config_export_project": config_editor.export_project()
		"config_export_merged": config_editor.export_merged()
		"config_load": config_editor.load_dialog()
		"config_defaults": config_editor.reset_defaults()
		"move":
			selected.clear()
			for actor in session.rollback.simulation.state.actors:
				if session.controls(int(actor.owner)) and actor.definition == "marine": selected.append(int(actor.id))
			if selected.is_empty():
				for actor in session.rollback.simulation.state.actors:
					if session.controls(int(actor.owner)) and session.rollback.simulation.content.units[actor.definition].capabilities.has("move"): selected.append(int(actor.id))
			_order({"kind": "move", "point": [0, 0, 0]})
		"lightless": faction.select(1); _local()
		"defensive":
			stance_choices.select(1)
			selected.clear()
			for actor in session.rollback.simulation.state.actors:
				if session.controls(int(actor.owner)) and actor.definition == "nest": selected.append(int(actor.id))
			_order({"kind": "veil_stance", "stance": "defensive"})
	var info := {"running": session.running, "room": session.transport.room, "players": session.roster.size(), "error": session.error, "status": status.text}
	if str(arguments[0]) == "benchmark":
		var probe = load("res://tests/movement_benchmark.gd").new()
		info.benchmark = probe.run(PackedStringArray(str(arguments[1]).split(" ", false)))
	if str(arguments[0]).begins_with("config_"):
		var content = config_editor.validate_content()
		info.config_files = config_editor.workspace.files.size()
		info.engineer_hp = int(content.data.units.engineer.hp) if content != null else -1
	if session.rollback != null:
		info.tick = int(session.rollback.simulation.state.tick)
		info.confirmed = session.rollback.confirmed_tick
		info.hashes = session.rollback.hashes
		if str(arguments[0]) == "checkpoint":
			info.snapshot = session.rollback.checkpoints.get(int(str(arguments[1])), {})
			info.frames = session.rollback.frames
	JavaScriptBridge.eval("window.atdLiveState = " + JSON.stringify(info))

func _process(dt: float) -> void:
	session.poll()
	if session.rollback == null: return
	if session.running:
		var tick := 1.0 / float(session.rollback.simulation.content.settings.tick_hz)
		accumulator = minf(accumulator + dt, tick * 4)
		while accumulator >= tick:
			if _web_test_tick_limit > 0 and int(session.rollback.simulation.state.tick) >= _web_test_tick_limit: break
			if not session.advance(): break
			accumulator -= tick
		var pan := Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_up", "ui_down"))
		if not get_viewport().gui_get_focus_owner() is LineEdit:
			pan += Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0,
				float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		camera.position += pan * dt * camera.size * 0.5
	var stamp: Array = [session.rollback.get_instance_id(), int(session.rollback.simulation.state.tick), session.rollback.rollbacks, selected.duplicate(), session.local_control,
		veil_overlay.show_veil, veil_overlay.show_links, veil_overlay.show_illumination, veil_overlay.show_perception]
	if stamp != _frame_signature:
		_sync_meshes()
		_frame_signature = stamp
	if _target_mode == "build": _preview_build(_ground_point(get_viewport().get_mouse_position()))
	refresh_time += dt
	if refresh_time >= 0.2:
		refresh_time = 0
		_refresh_hud()

func _build_world() -> void:
	RenderingServer.set_default_clear_color(VisibilityGround.COLORS[VisibilityGround.State.DARK])
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = VisibilityGround.COLORS[VisibilityGround.State.DARK]
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.light_energy = 0.7
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	camera.position = Vector3(0, 40, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	add_child(camera)
	actors_root = Node3D.new()
	add_child(actors_root)
	visibility_ground = VisibilityGround.new()
	add_child(visibility_ground)
	veil_overlay = VeilOverlay.new()
	add_child(veil_overlay)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 15
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("15212a")
	panel_style.border_color = Color("354954")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(12)
	ui_theme.set_stylebox("panel", "PanelContainer", panel_style)
	lobby = PanelContainer.new()
	var menu_theme: Theme = ui_theme.duplicate()
	lobby.theme = menu_theme
	canvas.add_child(lobby)
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.offset_left = 24; lobby.offset_top = 24
	lobby.offset_right = -24; lobby.offset_bottom = -24
	_style_menu(menu_theme)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	lobby.add_child(layout)
	menu_navigation = VBoxContainer.new()
	menu_navigation.custom_minimum_size.x = 164
	menu_navigation.add_theme_constant_override("separation", 8)
	layout.add_child(menu_navigation)
	var brand := _label(menu_navigation, "ATD", 36)
	brand.add_theme_color_override("font_color", Color("b8e6c8"))
	_label(menu_navigation, "AGAINST THE\nDARKNESS", 12)
	var nav_space := Control.new()
	nav_space.custom_minimum_size.y = 24
	menu_navigation.add_child(nav_space)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	menu_tabs = TabContainer.new()
	menu_tabs.tabs_visible = false
	menu_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(menu_tabs)
	var play := _menu_page("Play")
	_menu_heading(play, "Play", "Choose how you want to play.")
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	play.add_child(choices)
	var local_box := _menu_card(choices, "Local sandbox", "Explore freely. Control either faction or both.")
	_card_spacer(local_box)
	_primary_button(local_box, "Start local sandbox", _local)
	var online := _menu_card(choices, "Multiplayer", "Host a room or join other players.")
	_card_spacer(online)
	_button(online, "Open multiplayer", func(): menu_tabs.current_tab = MENU_MULTIPLAYER)

	var network := _menu_page("Multiplayer")
	_menu_heading(network, "Multiplayer", "Play together in a shared room.")
	var room_panel := _menu_card(network, "Room", "Leave the code blank to create a room when hosting.")
	room = LineEdit.new()
	room.placeholder_text = "Room code"
	room.custom_minimum_size.y = 40
	room_panel.add_child(room)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	room_panel.add_child(buttons)
	_primary_button(buttons, "Host room", func(): _connect(true))
	_button(buttons, "Join room", func(): _connect(false))
	_button(room_panel, "Faction & seed...", func(): menu_tabs.current_tab = MENU_SETUP)
	var lobby_box := _menu_card(network, "Lobby", "")
	network_lobby = lobby_box.get_parent()
	lobby_players = _label(lobby_box, "", 14)
	start_button = _primary_button(lobby_box, "Start network match", _start_network)
	start_button.disabled = true
	network_lobby.hide()
	var advanced := _fold(network, "Connection settings")
	var connection := _menu_card(advanced, "Network", "")
	_label(connection, "Signaling server", 14)
	endpoint = LineEdit.new()
	endpoint.text = Transport.DEFAULT_URL
	connection.add_child(endpoint)
	_label(connection, "ICE servers (JSON)", 14)
	ice = LineEdit.new()
	ice.text = '[{"urls":["stun:stun.l.google.com:19302"]}]'
	ice.tooltip_text = "Add TURN URLs, username and credential for restrictive networks."
	connection.add_child(ice)
	_button(connection, "Reconnect signaling", func(): session.transport.reconnect_signaling())
	_button(connection, "Disconnect / reset lobby", _reset)

	var setup := _menu_page("Match setup")
	_menu_heading(setup, "Match setup", "Applies to your next sandbox or hosted match.")
	var player_options := _menu_card(setup, "Player", "Choose the faction you control at the start.")
	_label(player_options, "Starting faction", 14)
	faction = OptionButton.new()
	faction.add_item("Human"); faction.add_item("Lightless")
	faction.custom_minimum_size.y = 40
	player_options.add_child(faction)
	var world_options := _menu_card(setup, "World", "Reuse a seed to start from the same world.")
	_label(world_options, "Seed", 14)
	seed_value = SpinBox.new()
	seed_value.min_value = 0; seed_value.max_value = 2147483647; seed_value.value = 42
	seed_value.custom_minimum_size.y = 40
	world_options.add_child(seed_value)

	var content_frame := _menu_frame("Content")
	editor_panel = content_frame
	var content_page := VBoxContainer.new()
	content_page.add_theme_constant_override("separation", 12)
	content_frame.add_child(content_page)
	_menu_heading(content_page, "Content", "Edit the definitions used by your next match.")
	var edit_buttons := HBoxContainer.new()
	edit_buttons.add_theme_constant_override("separation", 8)
	content_page.add_child(edit_buttons)
	_button(edit_buttons, "Validate", func():
		var content = _content()
		if content != null: status.text = "Valid content - " + content.fingerprint().left(16))
	_button(edit_buttons, "Save files", func(): config_editor.save_files())
	var file_menu := MenuButton.new()
	file_menu.text = "Project..."
	edit_buttons.add_child(file_menu)
	var popup := file_menu.get_popup()
	for title in ["Load project...", "Export project...", "Export merged...", "Restore defaults"]: popup.add_item(title)
	popup.id_pressed.connect(_project_action)
	config_editor = ConfigEditor.new()
	content_page.add_child(config_editor)
	editor = config_editor.editor
	config_editor.message_changed.connect(func(message): status.text = message)

	var help := _menu_page("How to play")
	_menu_heading(help, "How to play", "Controls and faction objectives.")
	var controls_card := _menu_card(help, "Controls", "")
	_label(controls_card, "Left click: select / Shift: add to selection\nRight click: move, attack or interact\nWASD / arrows: pan / Mouse wheel: zoom\nQ: target enemy Veil / Escape: cancel targeting", 15)
	var human_help := _menu_card(help, "Human", "")
	_label(human_help, "Select an engineer and use Place structure to build a Defense Turret. Right-click an owned blueprint to resume work; cancel it for a full refund. Right-click your damaged extraction point to repair it. Destroy the Nest, discover its nacre remains, then right-click to mine. Deliver enough nacre and choose Start extraction to begin the countdown.", 15)
	var lightless_help := _menu_card(help, "Lightless", "")
	_label(lightless_help, "Scavengers collect chyme through combat; deliver it to your Nest to spend it. Select a factory to produce units, a Mother to place structures, or a connected actor to set your global Veil stance.", 15)
	_build_menu_navigation()
	status = _label(body, "", 14)
	status.add_theme_color_override("font_color", Color("b8e6c8"))

	hud = PanelContainer.new()
	hud.theme = ui_theme
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	hud.offset_left = 16; hud.offset_top = 16
	hud.offset_right = 366; hud.offset_bottom = -16
	var hud_box := _scroll_box(hud)
	sandbox_control = OptionButton.new()
	for label in ["Control Humans", "Control Lightless", "Control both factions"]: sandbox_control.add_item(label)
	hud_box.add_child(sandbox_control)
	sandbox_control.item_selected.connect(_switch_control)
	stats = _label(hud_box, "", 16)
	var legend := GridContainer.new()
	legend.name = "VisibilityLegend"
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 14)
	hud_box.add_child(legend)
	for entry in [["Illuminated", 3], ["Perceived, unlit", 2], ["Fog (remembered)", 1], ["Unexplored", 0]]:
		var item := HBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		legend.add_child(item)
		var swatch := ColorRect.new()
		swatch.color = VisibilityGround.COLORS[entry[1]]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)
		var caption := _label(item, entry[0], 12)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var objective := _section(hud_box, "Objective")
	mission_status = _label(objective, "", 14)
	extract_button = _button(objective, "Start extraction", _start_extraction)
	selection_hint = _label(hud_box, "Select a unit or structure to see details and commands.", 14)
	selection_panel = _section(hud_box, "Selection")
	inspector = _label(selection_panel, "", 14)
	context_controls.repair = _button(selection_panel, "Repair own extraction point", func(): _order({"kind": "repair_point"}))
	context_controls.nacre = _button(selection_panel, "Deliver nacre to own point", func(): _order({"kind": "deliver_nacre"}))
	context_controls.chyme = _button(selection_panel, "Deliver chyme to nearest receiver", func(): _order({"kind": "deliver_chyme"}))
	production_panel = _section(selection_panel, "Production")
	products = OptionButton.new()
	production_panel.add_child(products)
	_button(production_panel, "Produce selected type", _train)
	construction_panel = _section(selection_panel, "Construction")
	structures = OptionButton.new()
	construction_panel.add_child(structures)
	build_button = _button(construction_panel, "Place structure", _begin_build)
	context_controls.cancel = _button(selection_panel, "Cancel construction / refund", func(): _order({"kind": "cancel_build"}))
	stance_panel = _section(selection_panel, "Global Veil stance")
	stance_choices = OptionButton.new()
	for label in ["Neutral", "Defensive", "Offensive"]: stance_choices.add_item(label)
	stance_panel.add_child(stance_choices)
	_button(stance_panel, "Set connected Veil stance", _set_veil_stance)
	context_controls.attack = _button(selection_panel, "Attack Veil [Q]", func():
		_target_mode = "attack_veil"
		target_hint.text = "Choose visible enemy Veil. Escape cancels.")
	context_controls.rally = _button(selection_panel, "Set rally point", _begin_rally)
	context_controls.stop = _button(selection_panel, "Stop selected", func(): _order({"kind": "stop"}))
	target_hint = _label(hud_box, "", 13)
	var display := _fold(hud_box, "View & overlays")
	_button(display, "Focus own base", _focus_base)
	_checkbox(display, "Veil", true, func(value): veil_overlay.show_veil = value)
	_checkbox(display, "Connections", true, func(value): veil_overlay.show_links = value)
	_checkbox(display, "Illumination", false, func(value): veil_overlay.show_illumination = value)
	_checkbox(display, "Perception", false, func(value): veil_overlay.show_perception = value)
	var session_info := _fold(hud_box, "Session details")
	diagnostics = _label(session_info, "", 13)
	event_log = _label(session_info, "", 13)
	var controls := _fold(hud_box, "Controls")
	_label(controls, "Left click: select / Shift: add\nRight click: move / attack / interact\nWASD / arrows: pan / wheel: zoom\nQ: attack Veil / Escape: cancel", 13)
	_button(hud_box, "Return to main menu", _reset)
	hud.hide()

func _project_action(id: int) -> void:
	match id:
		0: _load_preset()
		1: config_editor.export_project()
		2: _save_preset()
		3: config_editor.reset_defaults()

func _scroll_box(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box

func _style_menu(ui_theme: Theme) -> void:
	for spec in [["normal", "20323f"], ["hover", "2a4554"], ["pressed", "305347"], ["disabled", "192630"]]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(spec[1])
		style.set_corner_radius_all(6)
		style.content_margin_left = 16; style.content_margin_right = 16
		style.content_margin_top = 10; style.content_margin_bottom = 10
		ui_theme.set_stylebox(spec[0], "Button", style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("b8e6c8")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(6)
	ui_theme.set_stylebox("focus", "Button", focus)

func _build_menu_navigation() -> void:
	var group := ButtonGroup.new()
	for index in menu_tabs.get_tab_count():
		var button := _button(menu_navigation, menu_tabs.get_tab_title(index), func(): menu_tabs.current_tab = index)
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 48
		menu_buttons.append(button)
	menu_buttons[0].button_pressed = true
	menu_tabs.tab_changed.connect(_menu_changed)

func _menu_changed(index: int) -> void:
	for item in menu_buttons.size(): menu_buttons[item].set_pressed_no_signal(item == index)

func _menu_frame(title: String) -> MarginContainer:
	var page := MarginContainer.new()
	page.name = title
	for side in ["left", "right"]: page.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]: page.add_theme_constant_override("margin_" + side, 16)
	menu_tabs.add_child(page)
	return page

func _menu_page(title: String) -> VBoxContainer:
	var box := _scroll_box(_menu_frame(title))
	box.add_theme_constant_override("separation", 20)
	return box

func _menu_heading(parent: Node, title: String, subtitle: String) -> void:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	parent.add_child(header)
	_label(header, title, 36)
	var description := _label(header, subtitle, 15)
	description.add_theme_color_override("font_color", Color("9fb2bf"))

func _menu_card(parent: Node, title: String, subtitle: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2c38")
	style.border_color = Color("314957")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_label(box, title, 22)
	if not subtitle.is_empty():
		var description := _label(box, subtitle, 15)
		description.add_theme_color_override("font_color", Color("a8becb"))
	return box

func _card_spacer(parent: Node) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 28
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _primary_button(parent: Node, title: String, action: Callable) -> Button:
	var button := _button(parent, title, action)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("b8e6c8")
	style.set_corner_radius_all(6)
	style.content_margin_left = 16; style.content_margin_right = 16
	style.content_margin_top = 12; style.content_margin_bottom = 12
	button.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = Color("d0f4dc")
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = style.duplicate()
	pressed.bg_color = Color("8ec6a2")
	button.add_theme_stylebox_override("pressed", pressed)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]: button.add_theme_color_override(state, Color("152b20"))
	return button

func _section(parent: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	box.add_child(HSeparator.new())
	_label(box, title, 16)
	return box

func _fold(parent: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var toggle := Button.new()
	toggle.text = "\u25b8 " + title
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.toggle_mode = true
	box.add_child(toggle)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 6)
	box.add_child(contents)
	contents.hide()
	toggle.toggled.connect(func(open):
		contents.visible = open
		toggle.text = ("\u25be " if open else "\u25b8 ") + title)
	return contents

func _content():
	return config_editor.validate_content()

func _local() -> void:
	var content = _content()
	if content == null: return
	session.start_local(content.data, int(seed_value.value), _faction())

func _connect(host: bool) -> void:
	var servers = JSON.parse_string(ice.text)
	if not servers is Array:
		status.text = "ICE servers: expected a JSON array"; return
	var result: Error = session.connect_room(endpoint.text, host, room.text, _faction(), servers)
	faction.disabled = result == OK
	if result != OK and session.transport.error.is_empty(): status.text = "Connection failed: " + error_string(result)

func _start_network() -> void:
	var content = _content()
	if content != null: session.start_network(content.data, int(seed_value.value))

func _lobby_changed(players: Array) -> void:
	network_lobby.visible = not players.is_empty()
	var lines: Array[String] = ["Room: " + session.transport.room]
	for player in players: lines.append("%d · %s · %s" % [player.id, player.faction, player.controller])
	lobby_players.text = "\n".join(lines)
	room.text = session.transport.room
	start_button.disabled = not session.transport.hosting

func _started() -> void:
	lobby.hide(); hud.show()
	accumulator = 0
	sandbox_control.visible = not session.networked
	sandbox_control.select(0 if session.faction == "human" else 1)
	selected.clear()
	_catalog = ""
	_target_mode = ""
	_build_catalog = ""
	placement_preview.hide()
	target_hint.text = ""
	event_log.text = ""
	session.rollback.events_confirmed.connect(_confirmed_events)
	_grid(int(session.rollback.simulation.content.settings.map_radius))
	_focus_base()
	_refresh_hud()

func _focus_base() -> void:
	for actor in session.rollback.simulation.state.actors:
		if session.controls(int(actor.owner)) and actor.definition in ["hq", "nest"]:
			var point := _world(actor.position)
			camera.position = Vector3(point.x + 5, 40, point.z)
			return

func _reset() -> void:
	session.close()
	_frame_signature.clear()
	_order_signature.clear()
	selected.clear()
	for child in actors_root.get_children(): child.queue_free()
	actor_nodes.clear()
	field_nodes.clear()
	visibility_ground.clear()
	veil_overlay.clear()
	_target_mode = ""
	placement_preview.hide()
	for name in ["Grid", "Orders", "RallyMarkers", "Terrain"]:
		var node := get_node_or_null(name)
		if node != null: remove_child(node); node.queue_free()
	lobby.show(); menu_tabs.current_tab = MENU_PLAY; hud.hide()
	start_button.disabled = true
	faction.disabled = false
	lobby_players.text = ""
	network_lobby.hide()
	status.text = ""

func _save_preset() -> void:
	config_editor.export_merged()

func _load_preset() -> void:
	config_editor.load_dialog()

func _switch_control(index: int) -> void:
	session.set_local_control(["human", "lightless", "both"][index])
	selected.clear()
	_target_mode = ""
	target_hint.text = ""
	placement_preview.hide()
	_catalog = ""; _build_catalog = ""
	_sync_meshes()
	_refresh_hud()

func _control_owner() -> int:
	if session.networked or session.rollback == null: return session.own_id
	for id in selected:
		var actor = session.rollback.simulation.entity(int(id))
		if actor != null and session.controls(int(actor.owner)): return int(actor.owner)
	for player in session.rollback.simulation.state.players:
		if session.controls(int(player.id)): return int(player.id)
	return session.own_id

func _view_owners() -> Array:
	var owners: Array = []
	for player in session.rollback.simulation.state.players:
		if session.controls(int(player.id)): owners.append(int(player.id))
	return owners

func _visible_to(actor: Dictionary) -> int:
	return _visibility_at(actor.position, actor)

func _visibility_at(point: Array, actor = null) -> int:
	var simulation = session.rollback.simulation
	var value := 0
	for owner in _view_owners():
		value = maxi(value, simulation.visible_to(owner, actor, _light_snapshot if _syncing_meshes else null) if actor != null else simulation.visibility_at(owner, point, _light_snapshot if _syncing_meshes else null))
		if value == 2: return 2
	return value

func _known_field(field: Dictionary) -> bool:
	for owner in field.known_by:
		if session.controls(int(owner)): return true
	return false

func _faction() -> String:
	if session.running:
		for player in session.rollback.simulation.state.players:
			if int(player.id) == _control_owner(): return player.faction
	return "human" if faction.selected == 0 else "lightless"

func _sync_meshes() -> void:
	var simulation = session.rollback.simulation
	_syncing_meshes = true
	_light_snapshot.clear()
	for owner in _view_owners(): _light_snapshot[str(owner)] = simulation.illumination_cells(int(owner))
	var alive: Dictionary = {}
	for actor in simulation.state.actors:
		var id := int(actor.id)
		alive[id] = true
		if actor_nodes.has(id) and actor_nodes[id].get_meta("geometry") != [actor.definition, int(actor.get("rotation", 0)), actor.construction.get("definition", "")]:
			var previous: Node3D = actor_nodes[id]
			actors_root.remove_child(previous)
			previous.queue_free()
			actor_nodes.erase(id)
		if not actor_nodes.has(id): actor_nodes[id] = _actor_node(actor, simulation.content.units[actor.definition])
		var node: Node3D = actor_nodes[id]
		node.visible = _visible_to(actor) == 2
		node.position = _world(Geometry.center(simulation, actor))
		var facing := _world(actor.facing)
		node.get_node("Body").rotation.y = 0.0 if simulation.content.units[actor.definition].visual.shape == "footprint" else atan2(-facing.x, -facing.z)
		node.get_node("Selection").visible = selected.has(id)
		if node.has_node("WeaponRange"): node.get_node("WeaponRange").visible = selected.has(id) and session.controls(int(actor.owner))
		var definition: Dictionary = simulation.content.units[actor.definition]
		var label: Label3D = node.get_node("Label")
		label.visible = selected.has(id) or definition.capabilities.has("factory") or int(actor.hp) < int(definition.hp)
		label.text = "%s · P%d" % [definition.name, actor.owner]
		if selected.has(id) or int(actor.hp) < int(definition.hp): label.text += "\n%d HP" % actor.hp
		if not actor.construction.is_empty():
			@warning_ignore("integer_division")
			var progress := (int(actor.construction.total) - int(actor.construction.remaining)) * 100 / int(actor.construction.total)
			label.text += "\n%s %d%%" % ["Construction" if actor.construction.get("kind") == "blueprint" else "Growth", progress]
	for id in actor_nodes.keys():
		if not alive.has(id): actor_nodes[id].queue_free(); actor_nodes.erase(id); selected.erase(id)
	_sync_orders(simulation)
	_sync_fields(simulation)
	visibility_ground.refresh(simulation, _view_owners())
	var terrain_node := get_node_or_null("Terrain")
	if terrain_node != null:
		var signature: int = [visibility_ground.cells.keys().hash(), simulation.content.settings.get("terrain", []).hash()].hash()
		if terrain_node.get_meta("visibility", -1) != signature:
			var known: Array = []
			for cell in simulation.content.settings.get("terrain", []):
				if visibility_ground.cells.has(Hex.key(cell)): known.append(cell)
			terrain_node.visible = not known.is_empty()
			if not known.is_empty(): terrain_node.mesh = FootprintMesh.body(known, 0.7)
			terrain_node.set_meta("visibility", signature)
	veil_overlay.refresh(simulation, _control_owner(), selected, _view_owners())
	_syncing_meshes = false

func _sync_fields(simulation) -> void:
	for key in simulation.state.mission.fields:
		var field: Dictionary = simulation.state.mission.fields[key]
		if not field_nodes.has(key):
			var node := Node3D.new()
			var mesh := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.6; cylinder.bottom_radius = 0.6; cylinder.height = 0.5
			mesh.mesh = cylinder; mesh.position.y = 0.25; mesh.material_override = _material(Color("e4d3b8"))
			node.add_child(mesh)
			var label := Label3D.new()
			label.name = "Label"; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = Vector3(0, 0.8, -1); label.font_size = 32; label.pixel_size = 0.018
			label.no_depth_test = true
			node.add_child(label); actors_root.add_child(node); field_nodes[key] = node
		var node: Node3D = field_nodes[key]
		var visible_now: bool = _visibility_at(field.position) == 2
		node.visible = _known_field(field) and (not visible_now or int(field.remaining) > 0)
		node.position = _world(field.position)
		node.get_node("Label").text = "Nacre · %d" % field.remaining if visible_now else "Nest remains"
	for key in field_nodes.keys():
		if not simulation.state.mission.fields.has(key):
			var node: Node3D = field_nodes[key]
			actors_root.remove_child(node); node.queue_free(); field_nodes.erase(key)

func _confirmed_events(events: Array) -> void:
	for event in events:
		if event.type == "veil_alert":
			if not session.controls(int(event.owner)): continue
			var cell := Hex.from_point(event.point)
			event_log.text = "Veil N%d: %s at %d,%d\n%d connected recipients" % [event.network, event.reason, cell[0], cell[1], event.recipients.size()]
		elif event.type == "attack":
			var simulation = session.rollback.simulation
			var source = simulation.entity(int(event.source))
			var target = simulation.entity(int(event.target))
			if (source != null and _visible_to(source) == 2) or (target != null and _visible_to(target) == 2):
				event_log.text = "Confirmed: %s dealt %s damage" % [event.source, event.amount]
		elif event.type in ["chyme_collected", "chyme_delivered"] and session.controls(int(event.owner)):
			event_log.text = "Confirmed: %d chyme %s" % [event.amount, "delivered" if event.type == "chyme_delivered" else "collected"]
		elif event.type in ["construction_started", "construction_completed", "construction_cancelled"] and session.controls(int(event.owner)):
			event_log.text = "Confirmed: %s · %s" % [event.type.trim_prefix("construction_"), session.rollback.simulation.content.units[event.definition].name]
		elif event.type == "nest_destroyed" and session.controls(int(event.owner)):
			event_log.text = "Nest lost: +%d chyme\nProduction x%d · construction x%d" % [event.amount, event.production_rate, event.construction_rate]
		elif event.type == "passive_spawn" and session.controls(int(event.owner)):
			event_log.text = "Confirmed: %s spawned" % session.rollback.simulation.content.units[event.definition].name
		elif event.type == "match_won": event_log.text = "P%d wins · %s · %d nacre extracted" % [event.owner, event.faction, event.amount]
		elif event.type == "participant_defeated": event_log.text = "P%d defeated" % event.owner
		elif event.type in ["extraction_repaired", "nacre_mined", "nacre_deposited", "extraction_started"] and session.controls(int(event.owner)):
			event_log.text = "%s · %d" % [event.type.replace("_", " "), event.amount]

func _sync_orders(simulation) -> void:
	var mesh := ImmediateMesh.new()
	var markers: Array = []
	var lines: Array = []
	for id in selected:
		var actor = simulation.entity(int(id))
		if actor == null or not session.controls(int(actor.owner)): continue
		if Rally.capable(simulation, actor):
			var rally: Array = actor.rally_point
			markers.append(rally)
			lines.append([Geometry.center(simulation, actor), rally])
			lines.append([[int(rally[0]) - 150, 0, rally[2]], [int(rally[0]) + 150, 0, rally[2]]])
			lines.append([[rally[0], 0, int(rally[2]) - 150], [rally[0], 0, int(rally[2]) + 150]])
		if not actor.get("navigation", {}).get("path", []).is_empty():
			var start: Array = actor.position
			for waypoint in actor.navigation.path:
				if not simulation.state.revealed[str(actor.owner)].has(Hex.key(Hex.from_point(waypoint))): break
				lines.append([start, waypoint])
				start = waypoint
			continue
		if actor.order.get("kind") in ["move", "attack_veil", "build"]: lines.append([actor.position, actor.order.point])
		elif actor.order.get("kind") == "mine_nacre":
			var field: Dictionary = simulation.state.mission.fields.get(str(actor.order.target), {})
			if not field.is_empty(): lines.append([actor.position, field.position])
		elif actor.order.get("kind") in ["attack", "deliver_chyme", "repair_point", "deliver_nacre", "construct", "approach"]:
			var target = simulation.entity(int(actor.order.target))
			if target != null and _visible_to(target) == 2: lines.append([actor.position, target.position])
	var signature: Array = [lines, markers]
	if signature == _order_signature: return
	_order_signature = signature.duplicate(true)
	var old := get_node_or_null("Orders")
	if old != null: remove_child(old); old.queue_free()
	var old_markers := get_node_or_null("RallyMarkers")
	if old_markers != null: remove_child(old_markers); old_markers.queue_free()
	if not markers.is_empty():
		var flags := ImmediateMesh.new()
		flags.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for point in markers:
			var origin := _world(point) + Vector3(0, 0.16, 0)
			for offset in [Vector3(0, 0, -0.7), Vector3(0.7, 0, -0.4), Vector3(0, 0, -0.1)]: flags.surface_add_vertex(origin + offset)
		flags.surface_end()
		var marker := MeshInstance3D.new()
		marker.name = "RallyMarkers"; marker.mesh = flags
		var material := _material(Color("ffda65"), true)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.no_depth_test = true
		marker.material_override = material
		add_child(marker)
	if lines.is_empty(): return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line in lines:
		for point in line: mesh.surface_add_vertex(_world(point) + Vector3(0, 0.08, 0))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "Orders"; instance.mesh = mesh; instance.material_override = _material(Color("cfbc76"), true)
	add_child(instance)

func _actor_node(actor: Dictionary, definition: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.set_meta("definition", actor.definition)
	node.set_meta("geometry", [actor.definition, int(actor.get("rotation", 0)), actor.construction.get("definition", "")])
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	var radius := float(definition.visual.radius) * sqrt(3.0)
	node.set_meta("radius", radius)
	var height := float(definition.visual.get("height", 0.6)) * sqrt(3.0) if definition.visual.shape == "footprint" else radius * (3.0 if definition.visual.shape == "capsule" else 2.0)
	match definition.visual.shape:
		"capsule":
			var mesh := CapsuleMesh.new(); mesh.radius = radius; mesh.height = height; instance.mesh = mesh
		"footprint":
			instance.mesh = FootprintMesh.body(Geometry.cells(session.rollback.simulation, actor), height, _world(Geometry.center(session.rollback.simulation, actor)))
		"cylinder":
			var mesh := CylinderMesh.new(); mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = height; instance.mesh = mesh
	instance.position.y = 0.0 if definition.visual.shape == "footprint" else height * 0.5
	instance.material_override = _material(Color(definition.visual.color))
	if definition.visual.shape == "footprint": instance.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.add_child(instance)
	if definition.visual.shape == "footprint":
		var rim := MeshInstance3D.new()
		rim.name = "FootprintRim"
		rim.mesh = FootprintMesh.rim(Geometry.cells(session.rollback.simulation, actor), height, _world(Geometry.center(session.rollback.simulation, actor)))
		rim.material_override = _material(Color("17212c"), true)
		rim.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.add_child(rim)
	var direction_mesh := ImmediateMesh.new()
	direction_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	direction_mesh.surface_add_vertex(Vector3.ZERO)
	direction_mesh.surface_add_vertex(Vector3.FORWARD * radius * 1.6)
	direction_mesh.surface_end()
	var direction := MeshInstance3D.new()
	direction.name = "Facing"; direction.mesh = direction_mesh
	var direction_material := _material(Color.WHITE, true)
	direction_material.no_depth_test = true
	direction.material_override = direction_material
	instance.add_child(direction)
	var label := Label3D.new()
	label.name = "Label"; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, height + 0.5, -0.9 - radius)
	label.font_size = 36; label.pixel_size = 0.018; label.outline_size = 4
	label.no_depth_test = true
	node.add_child(label)
	var ring := _ring(radius * 1.25, Color("efdf86"))
	if Geometry.structure(session.rollback.simulation, actor): ring.mesh = FootprintMesh.outline(Geometry.cells(session.rollback.simulation, actor), _world(Geometry.center(session.rollback.simulation, actor)))
	ring.name = "Selection"; ring.position.y = height + 0.04 if definition.visual.shape == "footprint" else 0.05
	node.add_child(ring)
	if definition.capabilities.has("weapon"):
		var range_ring := _ring(float(definition.capabilities.weapon.range) * sqrt(3.0), Color("627c87"))
		range_ring.name = "WeaponRange"; range_ring.position.y = 0.02
		node.add_child(range_ring)
	actors_root.add_child(node)
	return node

func _refresh_hud() -> void:
	var rollback = session.rollback
	var simulation = rollback.simulation
	stats.text = "P%d - %s\n%s %d" % [_control_owner(), _faction().capitalize(), "Chyme reserve" if _faction() == "lightless" else "Sandbox credits", simulation.state.banks.get(str(_control_owner()), 0)]
	@warning_ignore("integer_division")
	var hash_tick: int = int(simulation.state.tick) / rollback.hash_interval * rollback.hash_interval
	diagnostics.text = "Tick %d - confirmed %d\nRollbacks %d - replayed ticks %d\nHash @%d %s" % [simulation.state.tick, rollback.confirmed_tick, rollback.rollbacks, rollback.replayed_ticks, hash_tick, str(rollback.hashes.get(hash_tick, "pending")).left(12)]
	if not session.networked and session.local_control == "both": stats.text += "\nControlling both factions; HUD follows selection"
	if _faction() == "lightless" and simulation.content.settings.has("nest_loss"):
		var loss: Dictionary = simulation.content.settings.nest_loss
		if simulation.state.escalations.has(str(_control_owner())):
			stats.text += "\nNest lost · production x%d / growth x%d" % [loss.production_rate, loss.construction_rate]
		else: diagnostics.text += "\nNest intact · destruction grants %d chyme" % loss.chyme_grant
	if not session.error.is_empty(): stats.text += "\nSTOPPED: " + session.error
	elif int(simulation.state.tick) - rollback.confirmed_tick > rollback.window: stats.text += "\nWaiting for peer inputs…"
	_refresh_mission_hud(simulation, rollback)
	_refresh_context(simulation)
	var actor = simulation.entity(int(selected[0])) if not selected.is_empty() else null
	var controlled := actor != null and session.controls(int(actor.owner))
	var caps: Dictionary = simulation.content.units[actor.definition].capabilities if actor != null else {}
	products.disabled = not (controlled and caps.has("factory"))
	structures.disabled = not (controlled and (caps.has("metamorphosis") or caps.has("builder")))
	build_button.disabled = structures.disabled
	if actor == null:
		inspector.text = ""
		return
	var definition: Dictionary = simulation.content.units[actor.definition]
	var detail := "%s - owner %d\nHP %d/%d - armor %d\nOrder: %s" % [definition.name, actor.owner, actor.hp, definition.hp, definition.armor, actor.order.get("kind", "idle")]
	if selected.size() > 1: detail = "%d selected - inspecting first\n" % selected.size() + detail
	if Geometry.structure(simulation, actor): detail += "\nFootprint: %d tiles - rotation %d" % [Geometry.cells(simulation, actor).size(), int(actor.get("rotation", 0))]
	else: detail += "\nCollision radius: %s tiles" % definition.get("collision_radius", 0.2)
	if Geometry.structure(simulation, actor):
		detail += "\nMovement collision: " + Geometry.collision_shape(simulation, actor)
		if Geometry.collision_shape(simulation, actor) == "circle": detail += " (radius %s)" % Geometry.definition(simulation, actor).get("collision_radius", 0.2)
	if session.controls(int(actor.owner)) and actor.get("navigation", {}).get("blocked", false): detail += "\nNo route for this body size."
	if session.controls(int(actor.owner)):
		if Rally.capable(simulation, actor): detail += "\nRally: [%d, %d] - right-click ground to set" % [actor.rally_point[0] / Simulation.SCALE, actor.rally_point[2] / Simulation.SCALE]
		if definition.capabilities.has("passive_spawner"):
			var spawn: Dictionary = definition.capabilities.passive_spawner
			var alive := Spawning.alive_count(simulation, int(actor.id))
			detail += "\nPassive %s: %d/%d alive\nNext birth: %d work · rate x%d" % [simulation.content.units[spawn.definition].name, alive, spawn.max_alive, actor.passive_remaining, Escalation.rate(simulation, actor, "production")]
			if alive >= int(spawn.max_alive): detail += "\nPassive spawning paused at cap"
			elif int(actor.passive_remaining) == 0: detail += "\nWaiting for an empty spawn tile"
		if int(actor.spawn_source) > 0: detail += "\nPassive origin: actor %d" % actor.spawn_source
		if definition.capabilities.has("mission_worker"):
			detail += "\nNacre cargo %d/%d" % [actor.nacre, definition.capabilities.mission_worker.capacity]
		if not actor.construction.is_empty():
			detail += "\nBuilding %s - %d/%d work left\nConstruction rate x%d\nCancel refunds %d %s" % [simulation.content.units[actor.construction.definition].name, actor.construction.remaining, actor.construction.total, Escalation.rate(simulation, actor, "construction"), actor.construction.cost, "credits" if definition.faction == "human" else "chyme"]
			if actor.construction.get("blocked", false): detail += "\nWaiting for tile occupants to move."
		if definition.capabilities.has("metamorphosis") or definition.capabilities.has("builder"):
			if _build_catalog != actor.definition:
				structures.clear()
				for type in definition.capabilities.get("metamorphosis", definition.capabilities.get("builder", {})).structures:
					structures.add_item("%s - %d %s" % [simulation.content.units[type].name, simulation.content.units[type].cost, "credits" if definition.faction == "human" else "chyme"])
					structures.set_item_metadata(structures.item_count - 1, type)
				_build_catalog = actor.definition
		if definition.capabilities.has("chyme_collector"):
			detail += "\nChyme cargo %d/%d" % [actor.chyme, definition.capabilities.chyme_collector.capacity]
		if definition.capabilities.has("chyme_receiver"): detail += "\nAccepts chyme deliveries"
		if definition.capabilities.has("chyme_source"):
			detail += "\nGenerates %d chyme / %d ticks" % [definition.capabilities.chyme_source.amount, definition.capabilities.chyme_source.interval_ticks]
		if definition.faction == "lightless": detail += "\nVeil link: " + ("connected" if not actor.veil_networks.is_empty() else "disconnected")
		if definition.faction == "lightless" and definition.capabilities.has("move"): detail += " · " + str(actor.veil_stance.mode)
		if not actor.veil_networks.is_empty():
			var network: Dictionary = simulation.state.veil.networks[str(actor.veil_networks[0])]
			detail += "\nGlobal Veil: %s · %d tiles" % [network.stance, network.cells.size()]
	if definition.capabilities.has("weapon"):
		detail += "\nDamage %d · range %s" % [definition.capabilities.weapon.damage, definition.capabilities.weapon.range]
	if session.controls(int(actor.owner)) and definition.capabilities.has("factory"):
		detail += "\nProduction queue: %d - rate x%d" % [actor.production.size(), Escalation.rate(simulation, actor, "production")]
		if not actor.production.is_empty():
			detail += "\nNext: %s · %d work left" % [simulation.content.units[actor.production[0].definition].name, actor.production[0].remaining]
		var key: String = actor.definition
		if key != _catalog:
			products.clear()
			for type in definition.capabilities.factory.produces:
				products.add_item("%s · %d" % [simulation.content.units[type].name, simulation.content.units[type].cost])
				products.set_item_metadata(products.item_count - 1, type)
			_catalog = key
	inspector.text = detail

func _refresh_context(simulation) -> void:
	var actor = simulation.entity(int(selected[0])) if not selected.is_empty() else null
	selection_panel.visible = actor != null
	selection_hint.visible = actor == null
	var controlled := actor != null and session.controls(int(actor.owner))
	var primary_caps: Dictionary = simulation.content.units[actor.definition].capabilities if controlled else {}
	production_panel.visible = primary_caps.has("factory")
	construction_panel.visible = primary_caps.has("metamorphosis") or primary_caps.has("builder")
	var available: Dictionary = {}
	for key in context_controls: available[key] = false
	var show_stance := false
	# Compute group availability before changing any control's visibility.
	for id in selected:
		var member = simulation.entity(int(id))
		if member == null or not session.controls(int(member.owner)): continue
		var caps: Dictionary = simulation.content.units[member.definition].capabilities
		if caps.has("mission_worker") and Mission.enabled(simulation):
			var progress: Dictionary = simulation.state.mission.humans.get(str(member.owner), {})
			if not progress.is_empty() and not progress.defeated and simulation.entity(int(progress.extraction)) != null:
				available.repair = available.repair or int(progress.repair_remaining) > 0
				available.nacre = available.nacre or int(member.nacre) > 0
		available.chyme = available.chyme or (caps.has("chyme_collector") and int(member.chyme) > 0)
		available.cancel = available.cancel or not member.construction.is_empty() or member.order.get("kind") in ["build", "construct"]
		show_stance = show_stance or not member.veil_networks.is_empty()
		available.attack = available.attack or caps.has("weapon")
		available.rally = available.rally or (member.construction.is_empty() and Rally.capable(simulation, member))
		available.stop = available.stop or caps.has("move") or caps.has("weapon")
	stance_panel.visible = show_stance
	for key in context_controls: context_controls[key].visible = available[key]

func _unhandled_input(event: InputEvent) -> void:
	if session.rollback == null or not session.running: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R and _target_mode == "build":
			_build_rotation = (_build_rotation + 1) % 6
			return
		if event.physical_keycode == KEY_Q:
			_target_mode = "attack_veil"
			target_hint.text = "Choose visible enemy Veil. Escape cancels."
		elif event.physical_keycode == KEY_ESCAPE:
			_target_mode = ""; target_hint.text = ""
			placement_preview.hide()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 10, 90)
			return
		if not _target_mode.is_empty() and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if _target_mode == "build":
				if event.button_index == MOUSE_BUTTON_RIGHT:
					_target_mode = ""; target_hint.text = ""; placement_preview.hide()
				else: _place_build(_ground_point(event.position))
				return
			var point := _ground_point(event.position)
			if point.is_empty(): return
			if _target_mode == "rally":
				if event.button_index == MOUSE_BUTTON_LEFT: _order({"kind": "rally", "point": point})
			elif _target_mode == "attack_veil": _order({"kind": "attack_veil", "point": Hex.point(Hex.from_point(point))})
			else: _order({"kind": "veil_stance", "stance": "offensive", "point": point})
			_target_mode = ""; target_hint.text = ""
			return
		var id := _pick(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.shift_pressed: selected.clear()
			if id != 0 and not selected.has(id): selected.append(id)
			_refresh_hud()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_context_order(id, _ground_point(event.position))

func _begin_rally() -> void:
	_target_mode = "rally"
	target_hint.text = "Choose a rally point. Right click/Escape cancels."

func _context_order(id: int, point: Array) -> void:
	var only_structures := true
	var spawner := false
	for selected_id in selected:
		var member = session.rollback.simulation.entity(int(selected_id))
		if member == null or not session.controls(int(member.owner)): continue
		only_structures = only_structures and Geometry.structure(session.rollback.simulation, member)
		spawner = spawner or Rally.capable(session.rollback.simulation, member)
	if only_structures and spawner and not point.is_empty():
		_order({"kind": "rally", "point": point})
		return
	var simulation = session.rollback.simulation
	var actor = simulation.entity(id)
	if actor != null and int(actor.owner) != _control_owner():
		_order({"kind": "attack", "target": id})
	elif actor != null and actor.construction.get("kind") == "blueprint":
		_order({"kind": "construct", "target": id})
	elif actor != null and simulation.content.units[actor.definition].capabilities.has("extraction_point"):
		var progress: Dictionary = simulation.state.mission.humans.get(str(_control_owner()), {})
		_order({"kind": "repair_point" if int(progress.get("repair_remaining", 0)) > 0 else "deliver_nacre", "target": id})
	elif _nacre_at(point) > 0:
		_order({"kind": "mine_nacre", "target": _nacre_at(point)})
	elif actor != null and simulation.content.units[actor.definition].capabilities.has("chyme_receiver"):
		_order({"kind": "deliver_chyme", "target": id})
	elif actor != null:
		_order({"kind": "approach", "target": id})
	elif not point.is_empty():
		_order({"kind": "move", "point": point})

func _nacre_at(point: Array) -> int:
	if point.is_empty(): return 0
	var simulation = session.rollback.simulation
	var worker := false
	for id in selected:
		var actor = simulation.entity(int(id))
		if actor != null and session.controls(int(actor.owner)) and simulation.content.units[actor.definition].capabilities.has("mission_worker"): worker = true
	if not worker: return 0
	for key in simulation.state.mission.fields:
		var field: Dictionary = simulation.state.mission.fields[key]
		if _known_field(field) and Hex.from_point(point) == Hex.from_point(field.position): return int(key)
	return 0

func _start_extraction() -> void:
	var progress: Dictionary = session.rollback.simulation.state.mission.humans.get(str(_control_owner()), {})
	if not progress.is_empty(): session.queue({"kind": "start_extraction", "actors": [int(progress.extraction)]}, _control_owner())

func _refresh_mission_hud(simulation, rollback) -> void:
	var progress: Dictionary = simulation.state.mission.humans.get(str(_control_owner()), {}) if Mission.enabled(simulation) else {}
	var ready: bool = not progress.is_empty() and simulation.state.mission.outcome.is_empty() and not progress.defeated and int(progress.countdown) < 0 and int(progress.repair_remaining) <= 0 and int(progress.deposited) >= int(simulation.content.settings.mission.threshold)
	extract_button.disabled = not ready
	extract_button.visible = ready
	if not Mission.enabled(simulation): mission_status.text = "Sandbox · objectives disabled"; return
	var outcome: Dictionary = simulation.state.mission.outcome
	if not outcome.is_empty():
		mission_status.text = "P%d wins · %d nacre extracted" % [outcome.winner, outcome.nacre] if rollback.confirmed_tick >= int(outcome.tick) else "Confirming match result…"
		return
	if progress.is_empty():
		var living := 0
		for human in simulation.state.mission.humans.values():
			if not human.defeated: living += 1
		mission_status.text = "Defeat all Humans · %d remaining" % living
		return
	if progress.defeated:
		mission_status.text = "Defeated · remaining units disabled" if rollback.confirmed_tick >= int(progress.defeated_tick) else "Confirming defeat…"
		return
	mission_status.text = "Extraction repair: %d work left\nNacre delivered: %d/%d" % [progress.repair_remaining, progress.deposited, simulation.content.settings.mission.threshold]
	if int(progress.countdown) >= 0: mission_status.text += "\nExtraction: %d ticks remaining" % progress.countdown
	elif ready: mission_status.text += "\nReady - start extraction when you choose"

func _ground_point(screen: Vector2) -> Array:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null: return []
	var r := float(point.z) / 1.5
	var q := float(point.x) / sqrt(3.0) - r * 0.5
	return [int(round(q * Simulation.SCALE)), 0, int(round(r * Simulation.SCALE))]

func _selected_mother():
	var simulation = session.rollback.simulation
	for id in selected:
		var actor = simulation.entity(int(id))
		if actor != null and session.controls(int(actor.owner)) and (simulation.content.units[actor.definition].capabilities.has("metamorphosis") or simulation.content.units[actor.definition].capabilities.has("builder")): return actor
	return null

func _begin_build() -> void:
	if structures.disabled or structures.selected < 0 or _selected_mother() == null: return
	_build_rotation = 0
	_target_mode = "build"
	target_hint.text = "Choose a revealed, empty tile. Right click/Escape cancels."

func _build_error(point: Array) -> String:
	var mother = _selected_mother()
	if mother == null or structures.disabled: return "Select your builder."
	if point.is_empty(): return "Choose a tile inside the arena."
	var simulation = session.rollback.simulation
	var type: String = structures.get_item_metadata(structures.selected)
	var error := Construction.site_error(simulation, mother, type, Hex.point(Hex.from_point(point)), true, _build_rotation)
	if not error.is_empty(): return error
	if int(simulation.state.banks[str(mother.owner)]) < int(simulation.content.units[type].cost): return "Not enough construction reserves."
	return ""

func _preview_build(point: Array) -> void:
	placement_preview.visible = not point.is_empty()
	if point.is_empty(): return
	var type: String = structures.get_item_metadata(structures.selected) if structures.selected >= 0 else ""
	if type.is_empty(): return
	var signature := [type, _build_rotation]
	if placement_preview.get_meta("footprint", []) != signature:
		placement_preview.mesh = FootprintMesh.outline(Geometry.offsets(session.rollback.simulation.content.units[type], _build_rotation))
		placement_preview.set_meta("footprint", signature)
	placement_preview.position = _world(Hex.point(Hex.from_point(point))) + Vector3(0, 0.07, 0)
	var error := _build_error(point)
	placement_preview.material_override.albedo_color = Color("80dcac") if error.is_empty() else Color("e37b79")
	target_hint.text = "Left click to place. R rotates. Right click/Escape cancels." if error.is_empty() else error

func _place_build(point: Array) -> void:
	var error := _build_error(point)
	if not error.is_empty():
		target_hint.text = error
		return
	_order({"kind": "build", "definition": structures.get_item_metadata(structures.selected), "point": Hex.point(Hex.from_point(point)), "rotation": _build_rotation})
	_target_mode = ""
	placement_preview.hide()
	target_hint.text = "Queued construction order."

func _set_veil_stance() -> void:
	var mode: String = ["neutral", "defensive", "offensive"][stance_choices.selected]
	var connected := false
	for id in selected:
		var actor = session.rollback.simulation.entity(int(id))
		if actor != null and session.controls(int(actor.owner)) and not actor.veil_networks.is_empty(): connected = true
	if not connected:
		target_hint.text = "Select your connected Lightless unit or structure."
		return
	if mode == "offensive":
		_target_mode = "offensive"
		target_hint.text = "Choose an outside target. Escape cancels."
	else:
		_order({"kind": "veil_stance", "stance": mode})
		target_hint.text = "Queued network stance: " + mode

func _order(command: Dictionary) -> void:
	var groups: Dictionary = {}
	for id in selected:
		var actor = session.rollback.simulation.entity(int(id))
		if actor == null or not session.controls(int(actor.owner)): continue
		var owner := int(actor.owner)
		if not groups.has(owner): groups[owner] = []
		groups[owner].append(int(id))
	for owner in groups:
		var entry := command.duplicate(true)
		entry.actors = groups[owner]
		session.queue(entry, int(owner))

func _train() -> void:
	if products.disabled or products.selected < 0: return
	_order({"kind": "train", "definition": products.get_item_metadata(products.selected)})

func _pick(screen: Vector2) -> int:
	var best := 0
	var nearest := INF
	for id in actor_nodes:
		var node: Node3D = actor_nodes[id]
		if not node.visible: continue
		var actor = session.rollback.simulation.entity(int(id))
		var point := _ground_point(screen)
		if Geometry.structure(session.rollback.simulation, actor):
			if not point.is_empty() and Hex.from_point(point) in Geometry.cells(session.rollback.simulation, actor): return int(id)
			continue
		var center := camera.unproject_position(node.position)
		var edge := camera.unproject_position(node.position + Vector3(float(node.get_meta("radius")), 0, 0))
		var distance := center.distance_to(screen)
		if distance <= maxf(8.0, center.distance_to(edge) + 3.0) and distance < nearest: nearest = distance; best = int(id)
	return best

func _grid(radius: int) -> void:
	var previous_terrain := get_node_or_null("Terrain")
	if previous_terrain != null: remove_child(previous_terrain); previous_terrain.queue_free()
	var old := get_node_or_null("Grid")
	if old != null: old.queue_free()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if abs(q + r) > radius: continue
			var center := _world([q * Simulation.SCALE, 0, r * Simulation.SCALE])
			for edge in 6:
				for index in [edge, edge + 1]:
					var angle := float(index) * TAU / 6.0 + PI / 6.0
					mesh.surface_add_vertex(center + Vector3(cos(angle), -0.03, sin(angle)))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "Grid"; instance.mesh = mesh; instance.material_override = _material(Color("182330"), true)
	add_child(instance)
	var terrain: Array = session.rollback.simulation.content.settings.get("terrain", [])
	if not terrain.is_empty():
		var obstacle := MeshInstance3D.new()
		obstacle.name = "Terrain"
		obstacle.visible = false
		obstacle.material_override = _material(Color("52606b"))
		obstacle.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		add_child(obstacle)

func _ring(radius: float, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for step in 33:
		var angle := float(step) * TAU / 32.0
		mesh.surface_add_vertex(Vector3(cos(angle), 0, sin(angle)) * radius)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh; instance.material_override = _material(color, true)
	return instance

func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if unshaded: material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _world(position: Array) -> Vector3:
	var q := float(position[0]) / Simulation.SCALE
	var r := float(position[2]) / Simulation.SCALE
	return Vector3(sqrt(3.0) * (q + r * 0.5), float(position[1]) / Simulation.SCALE, 1.5 * r)

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text; label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text; button.pressed.connect(action)
	button.custom_minimum_size.y = 34
	parent.add_child(button)
	return button

func _checkbox(parent: Node, text: String, value: bool, action: Callable) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = text; checkbox.button_pressed = value; checkbox.toggled.connect(action)
	parent.add_child(checkbox)

func _exit_tree() -> void:
	session.close()
