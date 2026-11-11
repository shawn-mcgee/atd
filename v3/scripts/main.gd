extends Node3D

var state: WorldState
var renderer: WorldRenderer
var camera: RTSCamera
var network: NetworkSession
var active := false
var local_owner := 0
var lightless_role: OptionButton
var lightless_role_count := -1
var lightless_unit_type := "scavenger"
var womb_panel: PanelContainer
var womb_buttons: Dictionary = {}
var womb_target := 0
var lightless_launch_button: Button
var selection: Array = []
var pending_orders: Array = []
var accepted_peers: Array[String] = []
var peer_owners: Dictionary = {}
var sequences: Dictionary = {}
var sequence := 0
var match_id := ""
var snapshot_timer := 0.0
var terrain_timer := 0.0
var diagnostic_timer := 0.0
var drag_start := Vector2.ZERO
var selecting := false
var build_kind := ""
var mining_mode := false
var attack_mode := false
var interaction_mode := ""
var ui: CanvasLayer
var hud: Control
var menu: PanelContainer
var resource_label: Label
var status_label: Label
var selection_label: Label
var actions: HFlowContainer
var invitation_edit: LineEdit
var seed_edit: LineEdit
var lobby_label: Label
var start_button: Button
var build_panel: PanelContainer
var selection_box: ColorRect
var paused_button: Button
var speed_button: OptionButton
var depot_resource := "ore"
var depot_panel: PanelContainer
var depot_buttons: Dictionary = {}
var minimap_dragging := false
var wall_dragging := false
var wall_start := Vector2i.ZERO
var wall_end := Vector2i.ZERO
var queue_modifier := false
var cursor_action := ""
var action_cursors: Dictionary = {}
var tactical: TacticalOverlay
var mission_label: Label
var detail_label: Label
var selection_status: CommandSkin.StatusPanel
var selection_progress: ProgressBar
var build_hint: Label
var result_panel: PanelContainer
var result_label: Label
var result_shown := false
var action_signature := ""
var selection_hint_signature := ""
var build_buttons: Dictionary = {}
var audio: GameAudio
var resource_strip: ResourceStrip
var portrait: UnitPortrait
var queue_view: ProductionQueue
var command_panel: PanelContainer
var personnel_controls: HBoxContainer
var resource_cell := Vector2i(99999, 99999)
var group_roster: HFlowContainer
var roster_signature := ""
var control_groups: Dictionary = {}
var group_buttons: Dictionary = {}
var group_bar: HBoxContainer
var last_group_slot := -1
var last_group_time := -10000
var placement_strip: PanelContainer
var placement_text: Label
var controls_panel: PanelContainer
var menu_pages: Dictionary = {}
var menu_nav: Dictionary = {}
var selected_menu_page := "expedition"
var seed_controls: VBoxContainer
var host_room_button: Button
var join_room_button: Button
var copy_room_button: Button
var leave_room_button: Button
var menu_backdrop: TextureRect
var selected_mission := ""
var mission_choices: Dictionary = {}
var mission_deploy_button: Button

func _ready() -> void:
	state = WorldState.new(Settings.data)
	state.reset(472, 1)
	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.initialize(state, 0)
	renderer.hide()
	camera = RTSCamera.new()
	add_child(camera)
	renderer.view_camera = camera
	camera.bounds = state.radius
	_focus_anchor()
	network = NetworkSession.new()
	add_child(network)
	network.received.connect(_network_event)
	audio = GameAudio.new(); add_child(audio)
	_build_ui()
	status_label.text = "Select your Engineer to establish a base. Home returns to your Anchor."

func _style(background: Color, border: Color = Color("3a4949")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box

func _label(text: String, size: int = 15, color: Color = Color("cbd0bd")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, call: Callable, parent: Node) -> Button:
	var button: Button = CommandCard.new() if parent == actions else Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 32
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _style(Color("19272b")))
	button.add_theme_stylebox_override("hover", _style(Color("2c3939"), Color("b2ab83")))
	button.add_theme_stylebox_override("pressed", _style(Color("4b5143"), Color("d7c08e")))
	button.pressed.connect(call)
	button.pressed.connect(func(): audio.cue("order"))
	parent.add_child(button)
	return button

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	menu_backdrop = TextureRect.new()
	menu_backdrop.texture = preload("res://assets/textures/expedition-backdrop.png")
	menu_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu_backdrop)
	hud = Control.new()
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")
	theme.default_font_size = 16
	theme.set_stylebox("panel", "TooltipPanel", CommandSkin.panel())
	theme.set_color("font_color", "TooltipLabel", Color("ddd8be"))
	theme.set_font_size("font_size", "TooltipLabel", 14)
	hud.theme = theme
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	tactical = TacticalOverlay.new()
	tactical.world = state; tactical.camera = camera; tactical.renderer = renderer
	hud.add_child(tactical)
	tactical.map_toggle_requested.connect(_toggle_fullscreen_map)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_top = 12
	top.offset_right = -14
	top.add_theme_stylebox_override("panel", _style(Color(0.035, 0.047, 0.05, 0.95)))
	hud.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	var brand := _label("E R E B U S", 25, Color("d1d2bc"))
	brand.add_theme_font_override("font", preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"))
	row.add_child(brand)
	resource_label = _label("")
	row.add_child(resource_label)
	resource_label.hide()
	resource_strip = ResourceStrip.new(); resource_strip.world = state
	row.add_child(resource_strip)
	paused_button = _button("Pause", _pause, row)
	speed_button = OptionButton.new()
	for value in Settings.data.match.singlePlayerSpeedOptions: speed_button.add_item("%sx" % str(value))
	speed_button.select(1)
	speed_button.item_selected.connect(func(i):
		if network.role == "solo": state.speed = float(Settings.data.match.singlePlayerSpeedOptions[i]))
	row.add_child(speed_button)
	var sound_button := _button("SOUND ON", func(): audio.toggle(), row)
	sound_button.text = "SOUND OFF" if audio.muted else "SOUND ON"
	sound_button.pressed.connect(func(): sound_button.text = "SOUND OFF" if audio.muted else "SOUND ON")
	_button("Leave", _leave, row)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 238
	bottom.offset_right = -400
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_top = -200
	bottom.offset_bottom = -12
	bottom.add_theme_stylebox_override("panel", CommandSkin.panel())
	bottom.add_child(PanelTrim.new())
	hud.add_child(bottom)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 18)
	bottom.add_child(dock)
	portrait = UnitPortrait.new(); dock.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.add_child(column)
	selection_label = _label("Select your Engineer or Marine", 18)
	selection_label.clip_text = true; selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(selection_label)
	selection_status = CommandSkin.StatusPanel.new(); column.add_child(selection_status); selection_status.hide()
	detail_label = _label("", 14, Color("94a49b"))
	detail_label.clip_text = false
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.y = 70
	column.add_child(detail_label)
	selection_progress = ProgressBar.new()
	selection_progress.custom_minimum_size.y = 4
	selection_progress.show_percentage = false
	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color = Color("142733")
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color("5abfa7")
	selection_progress.add_theme_stylebox_override("background", progress_background)
	selection_progress.add_theme_stylebox_override("fill", progress_fill)
	column.add_child(selection_progress)
	queue_view = ProductionQueue.new(); queue_view.world = state; queue_view.requested.connect(_issue); queue_view.custom_minimum_size.x = 250; queue_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; dock.add_child(queue_view)
	group_roster = HFlowContainer.new(); group_roster.custom_minimum_size.x = 220; dock.add_child(group_roster); group_roster.hide()
	command_panel = PanelContainer.new()
	command_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	command_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	command_panel.offset_left = -386; command_panel.offset_right = -14; command_panel.offset_top = -200; command_panel.offset_bottom = -12
	command_panel.add_theme_stylebox_override("panel", CommandSkin.panel()); hud.add_child(command_panel)
	command_panel.add_child(PanelTrim.new())
	var command_column := VBoxContainer.new(); command_panel.add_child(command_column)
	command_column.add_child(_label("COMMANDS", 11, Color("bcae88")))
	actions = HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 5); command_column.add_child(actions)
	personnel_controls = HBoxContainer.new(); command_column.add_child(personnel_controls)
	status_label = _label("", 13, Color("8e9e98"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	
	var mission := PanelContainer.new()
	mission.position = Vector2(14, 96)
	mission.custom_minimum_size.x = 315
	mission.add_theme_stylebox_override("panel", _style(Color(0.035, 0.047, 0.05, 0.92)))
	mission.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(mission)
	mission_label = _label("", 13, Color("9fc7c8"))
	mission_label.mouse_filter = Control.MOUSE_FILTER_PASS
	mission.add_child(mission_label)
	selection_box = ColorRect.new()
	selection_box.color = Color(0.35, 0.9, 0.75, 0.18)
	selection_box.color.a = 0
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.visible = false
	hud.add_child(selection_box)
	build_panel = PanelContainer.new()
	build_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	build_panel.offset_left = -380
	build_panel.offset_right = -14
	build_panel.offset_top = 85
	build_panel.add_theme_stylebox_override("panel", CommandSkin.panel())
	build_panel.add_child(PanelTrim.new())
	hud.add_child(build_panel)
	var build_column := VBoxContainer.new()
	build_panel.add_child(build_column)
	build_column.add_child(_label("CONSTRUCTION / %s TO CLOSE" % _binding("build"), 16, Color("d0cab0")))
	build_hint = _label("Select a type, then a revealed site.\nGreen: clear site. Red: blocked or unaffordable.", 11, Color("94a49b"))
	build_column.add_child(build_hint)
	var grid := GridContainer.new()
	grid.columns = 3
	build_column.add_child(grid)
	for kind in Settings.data.controls.buildOrder:
		var button := CommandCard.new()
		button.add_theme_font_size_override("font_size", 12)
		button.hotkey = str(Settings.data.controls.buildHotkeys[kind]); button.focus_mode = Control.FOCUS_NONE
		button.text = str(kind).capitalize(); button.glyph = CommandSkin.icon(str(kind)); button.cost = Settings.data.structures[kind].cost
		button.add_theme_stylebox_override("normal", _style(Color("19272b")))
		button.add_theme_stylebox_override("hover", _style(Color("2c3939"), Color("b2ab83")))
		button.pressed.connect(func(): _choose_build(str(kind)))
		grid.add_child(button)
		build_buttons[kind] = button
		var recipe: Dictionary = Settings.data.structures[kind]
		button.glyph = CommandSkin.icon(str(kind)); button.add_theme_constant_override("icon_max_width", 22)
		button.custom_minimum_size.x = 108
		button.tooltip_text = "%s\n%s\nPower draw: %d   Grid capacity: %d" % [str(kind).capitalize(), _cost_text(recipe.cost), int(recipe.powerDemand), int(recipe.powerCapacity)]
	build_panel.visible = false
	depot_panel = PanelContainer.new()
	depot_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	depot_panel.offset_left = -380; depot_panel.offset_right = -14; depot_panel.offset_top = 85
	depot_panel.add_theme_stylebox_override("panel", CommandSkin.panel())
	hud.add_child(depot_panel)
	var depot_column := VBoxContainer.new(); depot_panel.add_child(depot_column)
	depot_column.add_child(_label("DEPOT / CHOOSE STORAGE CAPACITY", 15))
	var resources := GridContainer.new(); resources.columns = 3; depot_column.add_child(resources)
	for resource in Settings.data.controls.depotHotkeys:
		var button := CommandCard.new(); button.text = str(resource).capitalize()
		button.hotkey = str(Settings.data.controls.depotHotkeys[resource]); button.glyph = CommandSkin.icon("depot")
		button.focus_mode = Control.FOCUS_NONE; button.pressed.connect(func(): _choose_depot_resource(str(resource)))
		resources.add_child(button); depot_buttons[resource] = button
	womb_panel = PanelContainer.new()
	womb_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	womb_panel.offset_left = -380; womb_panel.offset_right = -14; womb_panel.offset_top = 85
	womb_panel.add_theme_stylebox_override("panel", CommandSkin.panel()); hud.add_child(womb_panel)
	var womb_column := VBoxContainer.new(); womb_panel.add_child(womb_column)
	womb_column.add_child(_label("WOMB / CHOOSE UNIT TYPE", 15))
	var womb_grid := GridContainer.new(); womb_grid.columns = 3; womb_column.add_child(womb_grid)
	for kind in WorldState.LightlessControl.TYPES:
		var button := CommandCard.new(); button.text = str(kind).capitalize(); button.glyph = CommandSkin.icon(kind)
		button.hotkey = str(Settings.data.controls.wombHotkeys[kind]); button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): _choose_womb_type(kind)); womb_grid.add_child(button); womb_buttons[kind] = button
	womb_panel.hide()
	depot_panel.hide()
	_create_control_ui()
	menu = PanelContainer.new()
	menu.theme = theme
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	menu.offset_left = 48; menu.offset_right = 728
	menu.offset_top = -280; menu.offset_bottom = 280
	var menu_style := _style(Color(0.028, 0.043, 0.048, 0.94), Color("3f514e"))
	menu_style.set_corner_radius_all(5)
	menu_style.content_margin_left = 24; menu_style.content_margin_right = 24
	menu_style.content_margin_top = 28; menu_style.content_margin_bottom = 24
	menu.add_theme_stylebox_override("panel", menu_style)
	ui.add_child(menu)
	var layout := HBoxContainer.new(); layout.add_theme_constant_override("separation", 28); menu.add_child(layout)
	var navigation := VBoxContainer.new(); navigation.custom_minimum_size.x = 172; navigation.add_theme_constant_override("separation", 8); layout.add_child(navigation)
	var title := _label("EREBUS", 43, Color("d6d5bb"))
	title.add_theme_font_override("font", preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"))
	navigation.add_child(title)
	navigation.add_child(_label("EXPEDITION COMMAND", 11, Color("a69c7c")))
	var gap := Control.new(); gap.custom_minimum_size.y = 28; navigation.add_child(gap)
	var nav_group := ButtonGroup.new()
	for item in [["expedition", "Expedition", "anchor"], ["missions", "Field missions", "marine"], ["multiplayer", "Multiplayer", "scout"]]:
		var key: String = item[0]
		var button := _button(str(item[1]), func(): _show_menu_page(key), navigation)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.custom_minimum_size.y = 48
		button.icon = CommandSkin.icon(str(item[2])); button.add_theme_constant_override("icon_max_width", 22)
		button.toggle_mode = true; button.button_group = nav_group
		button.add_theme_stylebox_override("pressed", _style(Color("35413a"), Color("a99d73")))
		menu_nav[key] = button
	var nav_space := Control.new(); nav_space.size_flags_vertical = Control.SIZE_EXPAND_FILL; navigation.add_child(nav_space)
	navigation.add_child(_label("EARLY ALPHA  /  0.1", 11, Color("788a82")))
	var separator := VSeparator.new(); layout.add_child(separator)
	var content := VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation", 12); layout.add_child(content)
	for key in ["expedition", "missions", "multiplayer"]:
		var page := VBoxContainer.new(); page.size_flags_vertical = Control.SIZE_EXPAND_FILL; page.add_theme_constant_override("separation", 12); content.add_child(page); menu_pages[key] = page
	var expedition: VBoxContainer = menu_pages.expedition
	_menu_heading(expedition, "Into the dark", "Establish a foothold. Hold the light.")
	expedition.add_child(_label("A fresh expedition on a new world.\nBuild your base, recover Nacre, and extract.", 16, Color("a5b5ab")))
	var expedition_space := Control.new(); expedition_space.size_flags_vertical = Control.SIZE_EXPAND_FILL; expedition.add_child(expedition_space)
	expedition.add_child(_label("SINGLE PLAYER  /  PROCEDURAL MAP", 11, Color("9caa8e")))
	_menu_primary("Deploy expedition", func(): network.leave(); local_owner = 0; _start_game(_deployment_seed(), 1), expedition)
	lightless_launch_button = _button("Play as Lightless", func(): network.leave(); local_owner = -1; _start_game(_deployment_seed(), 1, "", 0, true), expedition)
	var missions: VBoxContainer = menu_pages.missions
	_menu_heading(missions, "Field missions", "Choose an operation. All missions are available.")
	var mission_keys: Array = Settings.data.missions.keys()
	selected_mission = str(mission_keys[0])
	var mission_group := ButtonGroup.new()
	var briefing := _label(str(Settings.data.missions[selected_mission].briefing), 14, Color("a5b5ab"))
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; briefing.custom_minimum_size.y = 44
	for key in mission_keys:
		var choice := _button(str(Settings.data.missions[key].title), func(): selected_mission = str(key); briefing.text = str(Settings.data.missions[key].briefing), missions)
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT; choice.custom_minimum_size.y = 44
		choice.icon = CommandSkin.icon({"foothold": "mine", "industry": "foundry", "extraction": "extract"}.get(key, "anchor")); choice.add_theme_constant_override("icon_max_width", 22)
		choice.toggle_mode = true; choice.button_group = mission_group; choice.button_pressed = str(key) == selected_mission
		mission_choices[key] = choice
	missions.add_child(briefing)
	var mission_space := Control.new(); mission_space.size_flags_vertical = Control.SIZE_EXPAND_FILL; missions.add_child(mission_space)
	mission_deploy_button = _menu_primary("Deploy mission", func(): _start_game(_deployment_seed(), 1, selected_mission), missions)
	var multiplayer_page: VBoxContainer = menu_pages.multiplayer
	_menu_heading(multiplayer_page, "Bring your crew", "Host a room or join an existing expedition.")
	host_room_button = _button("Create a room", _host, multiplayer_page); host_room_button.custom_minimum_size.y = 46
	multiplayer_page.add_child(_label("ROOM CODE", 11, Color("9caa8e")))
	var room_row := HBoxContainer.new(); room_row.add_theme_constant_override("separation", 8); multiplayer_page.add_child(room_row)
	invitation_edit = LineEdit.new(); invitation_edit.placeholder_text = "Enter room code"; invitation_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; invitation_edit.custom_minimum_size.y = 40; room_row.add_child(invitation_edit)
	invitation_edit.text_submitted.connect(func(_text):
		if network.role == "solo": _join())
	join_room_button = _button("Join", _join, room_row)
	copy_room_button = _button("Copy", func(): DisplayServer.clipboard_set(network.invitation), room_row); copy_room_button.tooltip_text = "Copy room code"
	lobby_label = _label("", 14, Color("a5b5ab")); lobby_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lobby_label.custom_minimum_size.y = 56; multiplayer_page.add_child(lobby_label)
	lightless_role = OptionButton.new(); lightless_role.tooltip_text = "Host assigns at most one Lightless player. CPU controls Lightless when unassigned."; multiplayer_page.add_child(lightless_role)
	var room_space := Control.new(); room_space.size_flags_vertical = Control.SIZE_EXPAND_FILL; multiplayer_page.add_child(room_space)
	start_button = _menu_primary("Launch expedition", _launch_hosted, multiplayer_page); start_button.hide()
	leave_room_button = _button("Leave room", func(): network.leave(); accepted_peers.clear(); invitation_edit.clear(); lobby_label.text = ""; _refresh_lobby_controls(), multiplayer_page)
	seed_controls = VBoxContainer.new(); content.add_child(seed_controls)
	var seed_toggle := CheckButton.new(); seed_toggle.text = "Choose map seed"; seed_toggle.focus_mode = Control.FOCUS_NONE; seed_toggle.add_theme_font_size_override("font_size", 13); seed_controls.add_child(seed_toggle)
	seed_edit = LineEdit.new(); seed_edit.placeholder_text = "Random if left blank"; seed_edit.tooltip_text = "Enter a seed to replay a map."; seed_controls.add_child(seed_edit); seed_edit.hide()
	seed_toggle.toggled.connect(func(value): seed_edit.visible = value)
	_show_menu_page("expedition")
	_refresh_lobby_controls()
	result_panel = PanelContainer.new()
	result_panel.theme = theme
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -250; result_panel.offset_right = 250
	result_panel.offset_top = -110; result_panel.offset_bottom = 110
	result_panel.add_theme_stylebox_override("panel", _style(Color("0b1a24"), Color("71b7ac")))
	ui.add_child(result_panel)
	var results := VBoxContainer.new()
	results.add_theme_constant_override("separation", 15)
	result_panel.add_child(results)
	result_label = _label("", 20, Color("b1ecdc"))
	results.add_child(result_label)
	_button("Inspect battlefield", func(): result_panel.hide(), results)
	_button("Return to expedition menu", _leave, results)
	result_panel.hide()
	hud.visible = false

func _menu_heading(parent: Control, title: String, caption: String) -> void:
	var heading := _label(title, 32, Color("dedbc3"))
	heading.add_theme_font_override("font", preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")); parent.add_child(heading)
	var subtitle := _label(caption, 14, Color("9bad9f")); subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(subtitle)

func _menu_primary(text: String, call: Callable, parent: Node) -> Button:
	var button := _button(text, call, parent); button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("1c2829")); button.add_theme_color_override("font_hover_color", Color("1c2829")); button.add_theme_color_override("font_pressed_color", Color("1c2829"))
	button.add_theme_stylebox_override("normal", _style(Color("c4b48a"), Color("c4b48a")))
	button.add_theme_stylebox_override("hover", _style(Color("e2d2a5"), Color("e2d2a5")))
	button.add_theme_stylebox_override("pressed", _style(Color("ae9c70"), Color("ae9c70")))
	return button

func _show_menu_page(key: String) -> void:
	selected_menu_page = key
	for name in menu_pages: menu_pages[name].visible = name == key; menu_nav[name].button_pressed = name == key
	if seed_controls != null: seed_controls.visible = key != "multiplayer" or network.role == "host"

func _refresh_lobby_controls() -> void:
	lightless_role.visible = network.role == "host"
	if lightless_role_count != accepted_peers.size():
		var previous := lightless_role.selected
		lightless_role.clear(); lightless_role.add_item("Lightless: CPU", -1)
		lightless_role.add_item("Lightless: Host", 0)
		for i in range(accepted_peers.size()): lightless_role.add_item("Lightless: Player %d" % (i + 2), i + 1)
		lightless_role.select(clampi(previous, 0, lightless_role.item_count - 1)); lightless_role_count = accepted_peers.size()
	host_room_button.disabled = network.role != "solo"
	join_room_button.visible = network.role != "host"; join_room_button.disabled = network.role == "guest"
	copy_room_button.visible = network.role == "host" and not network.invitation.is_empty()
	leave_room_button.visible = network.role != "solo"
	invitation_edit.editable = network.role == "solo"
	start_button.visible = network.role == "host" and not network.invitation.is_empty()
	seed_controls.visible = selected_menu_page != "multiplayer" or network.role == "host"

func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in cost: parts.append("%d %s" % [int(cost[resource]), str(resource).capitalize()])
	return " / ".join(parts)

func _focus_anchor() -> void:
	var anchor_id := int(state.players.get(local_owner, {}).get("anchor", 0))
	if state.structures.has(anchor_id):
		var p := HexGrid.world(state.structures[anchor_id].cell)
		camera.focus = Vector3(p.x, 0, p.y)
		camera._update_transform()

func _deployment_seed() -> int:
	var text := seed_edit.text.strip_edges()
	return int(randi()) if text.is_empty() else int(text)

func _start_game(map_seed: int, count: int, mission_key: String = "", lightless_slot: int = -1, solo_ai: bool = false) -> void:
	if lightless_slot < 0 and local_owner == -1: local_owner = 0
	if not mission_key.is_empty():
		network.leave(); local_owner = 0
	state.cfg = Settings.data
	state.reset(map_seed, count)
	if lightless_slot >= 0: state.command(0, {"action": "control_lightless", "slot": lightless_slot, "solo_ai": solo_ai})
	if not mission_key.is_empty(): state.command(0, {"action": "start_mission", "mission": mission_key})
	camera.bounds = state.radius
	seed_edit.tooltip_text = "Leave blank for a fresh map, or enter a seed to replay a layout.\nLast deployed seed: %d" % map_seed
	sequence = 0
	snapshot_timer = 0
	pending_orders.clear()
	selection.clear(); control_groups.clear(); last_group_slot = -1
	controls_panel.hide()
	roster_signature = ""
	resource_cell = Vector2i(99999, 99999)
	build_kind = ""; build_panel.hide(); selecting = false; interaction_mode = ""; mining_mode = false; attack_mode = false
	womb_panel.hide(); womb_target = 0
	depot_panel.hide(); minimap_dragging = false; queue_modifier = false
	wall_dragging = false; renderer.show_wall_line([])
	result_shown = false; result_panel.hide(); paused_button.text = "Pause"
	paused_button.visible = network.role == "solo"
	speed_button.visible = network.role == "solo"
	speed_button.select(1)
	tactical.owner_id = local_owner; tactical.reset()
	resource_strip.owner_id = local_owner
	audio.start()
	renderer.initialize(state, local_owner)
	renderer.show()
	_focus_anchor()
	if local_owner == -1: selection = [state.players[-1].anchor]
	active = true
	menu.visible = false
	menu_backdrop.hide()
	hud.visible = true
	camera.enabled = true
	_refresh_actions()

func _host() -> void:
	network.leave()
	accepted_peers.clear()
	peer_owners.clear()
	sequences.clear()
	var error := network.start("host")
	if error != "": lobby_label.text = error; return
	invitation_edit.text = network.invitation
	lobby_label.text = "Creating room..."
	start_button.visible = false
	_refresh_lobby_controls()

func _join() -> void:
	var error := network.start("guest", invitation_edit.text.strip_edges())
	if error != "": lobby_label.text = error; return
	lobby_label.text = "Connecting..."
	start_button.visible = false
	_refresh_lobby_controls()

func _launch_hosted() -> void:
	if network.role != "host" or network.self_id.is_empty(): return
	var role_slot := lightless_role.selected - 1
	if role_slot >= 0 and accepted_peers.is_empty(): lobby_label.text = "Lightless needs a Commonwealth opponent. Join another player or use Play as Lightless for solo AI."; return
	local_owner = -1 if role_slot == 0 else 0
	match_id = "%s-%s" % [network.invitation, str(Time.get_ticks_msec())]
	_start_game(_deployment_seed(), accepted_peers.size() + 1, "", role_slot)
	for index in range(accepted_peers.size()):
		var peer := accepted_peers[index]
		peer_owners[peer] = -1 if role_slot == index + 1 else index + 1
		network.send(peer, {"kind": "start", "seed": state.seed_value, "count": accepted_peers.size() + 1, "lightless_slot": role_slot, "owner": peer_owners[peer], "match": match_id, "hash": Settings.gameplay_hash})

func _network_event(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if type == "room_ready":
		invitation_edit.text = network.invitation
		if network.role == "host":
			lobby_label.text = "Share this room code with your crew.\n1 / 5 players connected."
			start_button.show()
		else: lobby_label.text = "Room found. Connecting to host..."
	elif type == "connection_failed":
		lobby_label.text = str(event.message); start_button.hide()
	elif type == "error":
		lobby_label.text = str(event.message)
		status_label.text = str(event.message)
	elif type == "peer_join" and network.role == "guest" and str(event.peer) == network.host_id:
		network.send(network.host_id, {"kind": "hello", "hash": Settings.gameplay_hash, "protocol": int(Settings.network.gameProtocolVersion)})
	elif type == "host_lost":
		state.ended = true
		state.result = "Host disconnected. Match ended; no recovery."
		lobby_label.text = state.result
		status_label.text = state.result
	elif type == "peer_leave" and network.role == "host":
		var peer := str(event.peer)
		accepted_peers.erase(peer)
		if active and peer_owners.has(peer): state.eliminate(int(peer_owners[peer]))
		peer_owners.erase(peer)
	elif type == "packet":
		var peer := str(event.peer)
		var packet: Dictionary = event.message
		var kind := str(packet.get("kind", ""))
		if kind == "hello" and network.role == "host":
			if active or packet.get("hash", "") != Settings.gameplay_hash or int(packet.get("protocol", -1)) != int(Settings.network.gameProtocolVersion) or accepted_peers.size() >= 4:
				network.send(peer, {"kind": "rejected", "message": "Room full, started, or incompatible build/settings"})
			elif not peer in accepted_peers:
				accepted_peers.append(peer)
				network.send(peer, {"kind": "welcome"})
				lobby_label.text = "%d / 5 players connected" % (accepted_peers.size() + 1)
		elif peer == network.host_id and network.role == "guest":
			if kind == "welcome": lobby_label.text = "Connected. Waiting for host to launch."
			elif kind == "rejected": lobby_label.text = str(packet.message); network.leave()
			elif kind == "start":
				if packet.hash != Settings.gameplay_hash: return
				local_owner = int(packet.owner)
				match_id = str(packet.match)
				_start_game(int(packet.seed), int(packet.count), "", int(packet.get("lightless_slot", -1)))
			elif kind == "state" and active and packet.get("match", "") == match_id:
				state.apply_snapshot(packet.data, local_owner)
		elif kind == "order" and network.role == "host" and peer_owners.has(peer) and packet.get("match", "") == match_id:
			var number := int(packet.get("sequence", 0))
			if number > int(sequences.get(peer, 0)) and packet.get("order") is Dictionary:
				sequences[peer] = number
				pending_orders.append({"owner": int(peer_owners[peer]), "order": packet.order})
	elif type == "test":
		if event.command == "solo": local_owner = 0; _start_game(472, 1)
		elif event.command == "lightless": local_owner = -1; _start_game(472, 1, "", 0, true)
		elif event.command == "lightless_slot" and network.role == "host" and not active:
			var slot := int(event.value)
			if slot >= -1 and slot <= accepted_peers.size(): lightless_role.select(slot + 1)
		elif event.command == "host": _host()
		elif event.command == "join": invitation_edit.text = str(event.value); _join()
		elif event.command == "launch": _launch_hosted()
		elif event.command == "leave": _leave()
		elif event.command == "order":
			var order = JSON.parse_string(str(event.value))
			if order is Dictionary: _issue(order)

	_refresh_lobby_controls()

func _issue(order: Dictionary) -> void:
	if not active: return
	if local_owner == -1 and order.get("action", "") == "build":
		order.unit_type = lightless_unit_type
		if order.kind in ["gland", "chyme_gland"]: order.action = "gland"; order.target = selection[0] if not selection.is_empty() else 0
	if order.get("action", "") == "depot_type" and Settings.data.controls.depotHotkeys.has(str(order.get("resource", ""))): depot_resource = str(order.resource)
	if not order.has("queued") and str(order.get("action", "")) in ["move", "attack", "mine", "repair", "deposit", "work", "equip", "board", "load_cargo", "excavate", "patrol", "escort", "unload"]: order.queued = queue_modifier or Input.is_physical_key_pressed(KEY_SHIFT)
	audio.cue("order")
	if not order.has("ids"): order.ids = selection.duplicate()
	if order.get("ids", []).size() > 128: return
	if network.role == "guest":
		sequence += 1
		network.send(network.host_id, {"kind": "order", "match": match_id, "sequence": sequence, "order": order})
	else: pending_orders.append({"owner": local_owner, "order": order})

func _physics_process(delta: float) -> void:
	if not active: return
	if network.role != "guest":
		for pending in pending_orders:
			status_label.text = state.command(int(pending.owner), pending.order)
			for fragment in ["not enough", "cannot", "invalid", "requires", "unavailable", "must", "select", "full", "unfinished"]:
				if status_label.text.to_lower().contains(fragment): audio.cue("error"); break
		pending_orders.clear()
		_refresh_action_signature()
		state.step(delta * state.speed)
		snapshot_timer += delta
		if network.role == "host" and snapshot_timer >= 0.1:
			snapshot_timer = 0
			for peer in peer_owners: network.send(peer, {"kind": "state", "match": match_id, "data": state.snapshot(int(peer_owners[peer]))})
	terrain_timer += delta
	if terrain_timer >= 0.2:
		terrain_timer = 0
		renderer.refresh_tiles()
		_update_hud()

func _process(delta: float) -> void:
	_update_cursor()
	renderer.selection = selection
	tactical.selected = selection
	tactical.hovered = _pick(get_viewport().get_mouse_position()) if active and get_viewport().gui_get_hovered_control() == null else 0
	if active: renderer.refresh_entities()
	if active: audio.update(state, local_owner, delta)
	camera.enabled = active and not tactical.map_expanded
	camera.pointer_captured = minimap_dragging or wall_dragging or tactical.minimap_rect().has_point(get_viewport().get_mouse_position()) or (get_viewport().gui_get_hovered_control() != null and camera.edge_direction(get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size) == Vector2.ZERO)
	camera.letter_pan_blocked = build_panel.visible or depot_panel.visible or womb_panel.visible
	camera.keyboard_pan_blocked = controls_panel.visible or tactical.map_expanded
	group_bar.visible = not build_panel.visible and not depot_panel.visible and not womb_panel.visible
	placement_strip.visible = build_kind != ""
	if selecting:
		var rect := Rect2(drag_start, Vector2.ZERO).expand(get_viewport().get_mouse_position())
		selection_box.position = rect.position
		selection_box.size = rect.size
		selection_box.visible = rect.size.length() > 8
		tactical.drag_selection = rect
	else: tactical.drag_selection = Rect2()
	if build_kind != "":
		var p := camera.ground(get_viewport().get_mouse_position())
		var cell := HexGrid.cell(Vector2(p.x, p.z))
		if wall_dragging: wall_end = _wall_cell(get_viewport().get_mouse_position())
		tactical.placement_kind = build_kind; tactical.placement_cell = cell
		var issue := state.placement_issue(local_owner, build_kind, cell)
		renderer.show_preview(cell, true, build_kind, issue == "")
		placement_text.text = "PLACING %s  /  %s\n%s  /  SHIFT: queue + repeat   ESC: cancel" % [(depot_resource + " depot" if build_kind == "depot" else lightless_unit_type + " womb" if build_kind == "womb" else build_kind).to_upper(), _cost_text(Settings.data.structures[build_kind].cost), "CLEAR SITE" if issue == "" else issue]
		placement_text.modulate = Color("abcdb8") if issue == "" else Color("e0a18b")
		build_hint.text = "%s · %s\n%s" % [build_kind.capitalize(), _cost_text(Settings.data.structures[build_kind].cost), "Clear site · click to place" if issue == "" else issue]
	else: renderer.show_preview(Vector2i.ZERO, false); tactical.placement_kind = ""
	if wall_dragging:
		var plan := state.wall_line_plan(local_owner, wall_start, wall_end)
		renderer.show_preview(Vector2i.ZERO, false); renderer.show_wall_line(plan.sites)
		placement_text.text = "WALL LINE / %d CLEAR / %s\nRELEASE: place   SHIFT: append + repeat   ESC / RIGHT CLICK: cancel" % [plan.count, _cost_text(plan.cost)]
	elif build_kind == "wall":
		renderer.show_wall_line([])
		placement_text.text += "  /  DRAG: wall line"
	else: renderer.show_wall_line([])
	diagnostic_timer += delta
	if diagnostic_timer >= 0.25 and network.diagnostics_enabled:
		diagnostic_timer = 0
		var own: Array = []
		for u in state.units.values():
			if u.owner == local_owner:
				var screen := camera.unproject_position(Vector3(u.pos.x, 0.4, u.pos.y))
				own.append({"id": u.id, "kind": u.kind, "x": u.pos.x, "z": u.pos.y, "screen": [screen.x, screen.y], "job": u.job.kind, "cargo": u.cargo, "stance": u.stance, "queued": u.get("orders", []).size()})
		var fields: Array = []
		for cell in state.visible.get(local_owner, {}):
			if state.tiles[cell].resource != "" and not state.tiles[cell].cliff:
				var p := HexGrid.world(cell)
				var screen := camera.unproject_position(Vector3(p.x, 0, p.y))
				fields.append({"q": cell.x, "r": cell.y, "kind": state.tiles[cell].resource, "screen": [screen.x, screen.y]})
		var structures: Array = []
		for s in state.observed_structures(local_owner):
			if s.owner != local_owner: continue
			var p := state.entity_position(s)
			var screen := camera.unproject_position(Vector3(p.x, 0.4, p.y))
			structures.append({"id": s.id, "kind": s.kind, "built": s.built, "x": p.x, "z": p.y, "screen": [screen.x, screen.y]})
		var buttons: Dictionary = {}
		for kind in build_buttons:
			var point: Vector2 = build_buttons[kind].get_global_rect().get_center()
			buttons[kind] = [point.x, point.y]
		var sites: Array = []
		if build_kind != "":
			for cell in state.known.get(local_owner, {}):
				if state.placement_issue(local_owner, build_kind, cell) != "" or state.tiles[cell].resource != "": continue
				var p := HexGrid.world(cell)
				var screen := camera.unproject_position(Vector3(p.x, 0, p.y))
				if screen.x > 340 and screen.x < 900 and screen.y > 220 and screen.y < 590: sites.append({"q": cell.x, "r": cell.y, "screen": [screen.x, screen.y]})
		var commands: Array = []
		for button in actions.get_children():
			if button is Button:
				var point: Vector2 = button.get_global_rect().get_center()
				commands.append({"text": button.text, "disabled": button.disabled, "screen": [point.x, point.y]})
		var queue_cards: Array = []
		for card in queue_view.cards:
			var point: Vector2 = card.button.get_global_rect().get_center()
			queue_cards.append({"key": card.key, "index": card.index, "screen": [point.x, point.y]})
		network.diagnostics({"ready": true, "active": active, "role": network.role, "invitation": network.invitation, "peers": accepted_peers.size(), "owner": local_owner, "tick": state.tick, "ended": state.ended, "result": state.result, "units": own, "structures": structures, "fields": fields, "resources": state.players.get(local_owner, {}).get("resources", {}), "paused": state.paused, "camera": {"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y], "edge": [camera.edge_pan.x, camera.edge_pan.y], "distance": camera.distance, "x": camera.focus.x, "z": camera.focus.z, "yaw": camera.yaw}, "selected": selection, "commands": commands, "queue_cards": queue_cards, "controls": {"fullscreenMap": tactical.map_expanded, "mapToggle": [tactical.map_toggle.get_global_rect().get_center().x, tactical.map_toggle.get_global_rect().get_center().y], "mapClose": [tactical.expanded_view.close_button.get_global_rect().get_center().x, tactical.expanded_view.close_button.get_global_rect().get_center().y], "timeControls": [paused_button.visible, speed_button.visible], "buildMenu": build_panel.visible, "attack": attack_mode, "interaction": interaction_mode, "groups": control_groups, "ghost": ghost_model_visible()}, "feedback": {"cursor": renderer.feedback_cursor, "events": state.feedback_for(local_owner).map(func(event): return event.kind), "traces": renderer.visual_shots.size(), "particles": renderer.particles.size(), "labels": tactical.damage_numbers.size()}, "activity_card": {"visible": selection_status.visible, "cargo": selection_status.cargo_contents, "activities": selection_status.activities, "screen": [selection_status.get_global_rect().get_center().x, selection_status.get_global_rect().get_center().y]}, "inspection": detail_label.text, "build_kind": build_kind, "build_buttons": buttons, "build_sites": sites, "menu_navigation": menu_navigation_for_diagnostics(), "mission": mission_label.text, "mission_id": state.mission.get("id", ""), "mission_menu": {"nav": [menu_nav.missions.get_global_rect().get_center().x, menu_nav.missions.get_global_rect().get_center().y], "selected": selected_mission, "deploy": [mission_deploy_button.get_global_rect().get_center().x, mission_deploy_button.get_global_rect().get_center().y], "choices": mission_keys_for_diagnostics()}, "status": status_label.text})

func menu_navigation_for_diagnostics() -> Dictionary:
	var buttons: Dictionary = {}
	for key in menu_nav:
		var point: Vector2 = menu_nav[key].get_global_rect().get_center(); buttons[key] = [point.x, point.y]
	return buttons

func mission_keys_for_diagnostics() -> Dictionary:
	var choices: Dictionary = {}
	for key in mission_choices:
		var point: Vector2 = mission_choices[key].get_global_rect().get_center()
		choices[key] = [point.x, point.y]
	return choices

func _pause() -> void:
	if network.role == "solo": state.paused = not state.paused; paused_button.text = "Resume" if state.paused else "Pause"

func _leave() -> void:
	tactical.set_map_expanded(false)
	network.leave()
	audio.stop()
	active = false
	renderer.hide()
	local_owner = 0
	menu.visible = true
	menu_backdrop.show()
	hud.visible = false
	start_button.visible = false
	result_panel.hide(); build_panel.hide(); build_kind = ""
	lobby_label.text = ""
	_refresh_lobby_controls()

func _update_hud() -> void:
	if not state.players.has(local_owner): return
	var inventory: Dictionary = state.resources(local_owner)
	var parts: Array[String] = []
	for r in ["ore", "gas", "alloy", "polymer", "crystal", "nacre"]: parts.append("%s %d/%d" % [r.capitalize(), int(inventory.get(r, 0)), state.capacity(local_owner, r)])
	resource_label.text = "   ".join(parts)
	var elapsed := state.time_seconds
	var goal := "01 / FIND AND DESTROY THE MEDUSA\nExplore beyond the light. Protect your Anchor."
	if state.medusa_dead: goal = "02 / RECOVER NACRE\nDeliver %d Nacre to your Anchor: %d / %d" % [int(state.cfg.match.extractionMinimumNacre), int(inventory.get("nacre", 0)), int(state.cfg.match.extractionMinimumNacre)]
	if int(inventory.get("nacre", 0)) >= int(state.cfg.match.extractionMinimumNacre): goal = "03 / READY TO EXTRACT\nSelect your Anchor and begin extraction."
	if state.players[local_owner].extracting: goal = "04 / HOLD THE ANCHOR · %ds\nExtraction in progress. The Anchor must survive." % ceili(float(state.players[local_owner].remaining))
	if not state.mission.is_empty():
		var definition: Dictionary = state.cfg.missions[state.mission.id]
		if state.mission.id != "extraction":
			var objectives: Array[String] = []
			for check in WorldState.Missions.requirements(state): objectives.append(("[OK] " if check.done else "[  ] ") + str(check.text))
			goal = "\n".join(objectives)
			goal += "\n\n" + ("Select a worker; M then click Ore.\nB opens construction; Depot expands storage.\nBuild Floodlight inside the Anchor grid." if state.mission.id == "foothold" else "Build Foundry inside the Anchor grid.\nM then click Foundry to haul Alloy.\nArmory: queue a Marine kit and Operator.")
		else:
			goal += "\n\nNest: map center. Bring your Marines.\nM on remains sends workers to recover Nacre."
		goal = str(definition.title).to_upper() + "\n\n" + goal
	if local_owner == -1: goal = "LIGHTLESS / DESTROY THE COMMONWEALTH ANCHORS\nSelect Medusa to spawn or set network stance. Mothers grow organs. Fathers recruit units. Chyme is earned through damage and delivery."
	mission_label.tooltip_text = goal
	var compact_goal := goal.split("\n")[0]
	if not state.mission.is_empty():
		var sections := goal.split("\n\n")
		compact_goal = sections[0] + "\n" + sections[1] if sections.size() > 1 else goal
	mission_label.text = "%02d:%02d%s\n\n%s" % [int(elapsed) / 60, int(elapsed) % 60, "  PAUSED" if state.paused else "", compact_goal]

	if state.ended: status_label.text = state.result
	elif state.players[local_owner].extracting: status_label.text = "EXTRACTION  %.1fs  |  Hold the Anchor" % float(state.players[local_owner].remaining)
	var valid: Array = []
	for id in selection:
		if not _observed_entity(int(id)).is_empty():
			var candidate := _observed_entity(int(id))
			if candidate.owner == local_owner and int(candidate.get("vehicle", 0)) != 0:
				var vehicle_id := int(candidate.vehicle)
				if not vehicle_id in valid: valid.append(vehicle_id)
			elif candidate.has("cell") or WorldState.TargetRules.identifiable(state, candidate, local_owner):
				if not id in valid: valid.append(id)
	if valid != selection: selection = valid; _refresh_actions()
	var inspected_kind := str(_observed_entity(int(selection[0])).get("kind", "")) if not selection.is_empty() else ""
	var remembered_selection: bool = selection.size() == 1 and _observed_entity(int(selection[0])).get("remembered", false)
	var hint_signature := JSON.stringify(selection) + "/" + inspected_kind + "/" + str(remembered_selection)
	if hint_signature != selection_hint_signature:
		selection_hint_signature = hint_signature
		if not state.ended and not state.players[local_owner].extracting: status_label.text = ("Last seen: scout to update." if remembered_selection else "") if state.players[local_owner].alive else "Eliminated. You can inspect remaining assets but cannot issue orders."
	if state.ended and not result_shown:
		result_shown = true
		result_label.text = "%s\n\nNacre delivered: %d" % [state.result, int(inventory.get("nacre", 0))]
		result_panel.show()
	portrait.kind = ""; portrait.serial = 0; portrait.group_size = 0
	selection_progress.hide(); selection_status.hide(); detail_label.show()
	queue_view.target_id = 0
	if selection.size() == 1:
		var inspected := _observed_entity(int(selection[0]))
		portrait.kind = str(inspected.kind); portrait.serial = int(inspected.id); portrait.structure = inspected.has("cell")
		selection_label.text = "%s / %02d" % [str(inspected.kind).to_upper(), int(inspected.id)]
		detail_label.text = CommandSkin.description(state, inspected)
		if inspected.get("remembered", false): selection_label.text += " / LAST SEEN"
		else:
			selection_status.refresh(state, [inspected], local_owner); selection_status.tooltip_text = detail_label.text + "\n\n" + _selection_hint(inspected_kind)
			selection_status.show(); detail_label.hide()
		queue_view.target_id = int(inspected.id) if inspected.has("cell") and inspected.owner == local_owner else 0
	else:
		selection_label.text = "%d units selected" % selection.size() if not selection.is_empty() else "Select a unit or structure"
		detail_label.text = ""
	if selection.is_empty() and state.known.get(local_owner, {}).has(resource_cell) and state.tiles.has(resource_cell):
		var deposit: Dictionary = state.tiles[resource_cell]
		selection_label.text = "%s DEPOSIT" % str(deposit.resource).to_upper()
		detail_label.text = "Remaining: %s" % ("UNLIMITED" if deposit.resource == "nacre" else str(deposit.amount))
		if deposit.resource == "nacre": detail_label.text += "  /  Anchor delivery"
	group_roster.visible = selection.size() > 1
	if selection.size() > 1:
		var types: Dictionary = {}; var health := 0.0; var maximum := 0.0; var cargo := 0
		for id in selection:
			var unit := _observed_entity(int(id))
			if unit.is_empty(): continue
			var definition: Dictionary = Settings.data.units[unit.kind] if unit.has("pos") else Settings.data.structures[unit.kind]
			types[unit.kind] = int(types.get(unit.kind, 0)) + 1; health += float(unit.hp); maximum += float(definition.health)
			if unit.has("cargo"): cargo += state.cargo_amount(unit)
		selection_status.refresh(state, selection.map(func(id): return _observed_entity(int(id))), local_owner); selection_status.show(); detail_label.hide()
		detail_label.text = "TOTAL HEALTH %d / %d\nCARGO %d · %d SPECIALIZATIONS\nClick a role to select that subgroup." % [ceili(health), ceili(maximum), cargo, types.size()]
		if types.size() == 1:
			portrait.kind = str(types.keys()[0]); portrait.group_size = selection.size(); portrait.structure = _observed_entity(int(selection[0])).has("cell")
		if _observed_entity(int(selection[0])).has("cell"): detail_label.text += "\nProduction controls act on the primary structure."
		selection_status.tooltip_text = detail_label.text
		var group_signature := JSON.stringify([selection, types])
		if roster_signature != group_signature:
			roster_signature = group_signature
			for child in group_roster.get_children(): group_roster.remove_child(child); child.queue_free()
			for kind in types:
				var button := _button("%s ×%d" % [str(kind).capitalize(), types[kind]], func():
					selection = selection.filter(func(id): return _observed_entity(int(id)).get("kind", "") == kind); _selection_feedback(), group_roster)
				button.icon = CommandSkin.icon(kind); button.expand_icon = true; button.add_theme_constant_override("icon_max_width", 20)
				button.add_theme_font_size_override("font_size", 12); button.custom_minimum_size = Vector2(104, 40)
	_refresh_action_signature()
	queue_view.refresh()
	_refresh_group_bar()
	for button in actions.get_children():
		if button.has_meta("cost"):
			button.disabled = not bool(button.get_meta("available")) or not CommandSkin.affordable(state, local_owner, button.get_meta("cost"))
	if womb_panel.visible and womb_target != 0: _refresh_womb_choices()
	status_label.visible = not status_label.text.is_empty()
	portrait.queue_redraw()

func _command(title: String, icon: String, order: Dictionary, cost: Dictionary = {}, available: bool = true, reason: String = "") -> CommandCard:
	var button := _button(title, func(): _issue(order), actions) as CommandCard
	button.glyph = CommandSkin.icon(icon); button.cost = cost
	button.add_theme_font_size_override("font_size", 12); button.custom_minimum_size = Vector2(108, 50)
	button.disabled = not available or not CommandSkin.affordable(state, local_owner, cost)
	button.set_meta("cost", cost); button.set_meta("available", available)
	var production_kind := str(order.get("kind", "")) if str(order.get("action", "")) in ["kit", "vehicle"] else "operator" if order.get("action", "") == "operator" else ""
	if Settings.data.controls.productionHotkeys.has(production_kind): button.hotkey = str(Settings.data.controls.productionHotkeys[production_kind])
	button.tooltip_text = title + "\n" + _cost_text(cost) + "\n" + (reason if reason != "" else "Paid immediately. Unstarted queued orders can be canceled for a refund." if not cost.is_empty() else "Select to issue this command.")
	return button

func _lightless_actions(e: Dictionary) -> void:
	if e.has("pos") and not WorldState.LightlessControl.directly_controllable(e):
		var guidance := _label("AUTONOMOUS\nGuide through the Medusa or a Father.", 12, Color("a5b5ab"))
		guidance.tooltip_text = "Father %d controls this recruit." % int(e.father_id) if int(e.get("father_id", 0)) != 0 else "This unit follows its network stance. Recruit it with a Father to guide a group."
		actions.add_child(guidance); return
	if e.kind == "womb" and (e.built or not e.started):
		_target_button("Change type", "womb", func(): _open_womb_types(e.id), "Change Womb type. Removing old capacity must support its current population. Clear this Womb's spawn queue first; Glands keep their original type.")
	if e.has("cell") and not e.built:
		if not e.started: _command("Cancel blueprint", "stop", {"action": "cancel_build", "target": e.id}, {}, true, "Refunds Chyme before Mother transformation. Gestation cannot be canceled.")
		return
	if e.kind in ["medusa", "father"]:
		for stance in ["attack", "defend", "gather", "probe"]:
			var current := str(e.get("network_stance", "")) if e.kind == "medusa" else str(e.get("group_stance", ""))
			var button := _command(str(stance).capitalize(), "aggressive", {"action": "medusa_stance" if e.kind == "medusa" else "father_stance", "stance": stance, "target": e.id}, {}, true, "Medusa: all units standing on Gloom, globally. Father: recruited units override that stance.")
			button.toggle_mode = true; button.set_pressed_no_signal(current == stance)
	if e.kind in ["medusa", "womb"]:
		for kind in WorldState.LightlessControl.TYPES:
			if not WorldState.LightlessColony.unlocked(state, e, kind): continue
			var spawn_button := _command(str(kind).capitalize(), kind, {"action": "spawn", "target": e.id, "kind": kind}, Settings.data.units[kind].manualSpawnCost, e.spawn_queue.size() < int(state.cfg.lightless.manualQueueLimit), "Population %d / %d. Paid Chyme immediately. Orders wait at the type cap. Click a queue chip to cancel." % [state._population(kind), WorldState.LightlessColony.cap(state, kind)])
			spawn_button.badge = "%d/%d" % [state._population(kind), WorldState.LightlessColony.cap(state, kind)]
	if e.kind == "mother":
		_target_button("Grow Womb", "build", func(): _choose_build("womb"), "Choose a revealed site. The Mother travels, transforms, then the Womb gestates.")
		_target_button("Grow Stoma", "build", func(): _choose_build("stoma"), "Choose a revealed site for a Chyme drop-off. Consumes its Mother when gestation starts.")
	if e.kind == "womb":
		_target_button("Armor Gland", "upgrade", func(): _choose_build("gland"), "Choose an adjacent unoccupied Gloom tile. Respects colony armor caps and Womb slots.")
		_target_button("Chyme Gland", "build", func(): _choose_build("chyme_gland"), "Choose an adjacent unoccupied Gloom tile to generate Chyme.")
	if e.kind == "father":
		_target_button("Recruit unit", "escort", func(): _target_interaction("recruit"), "Choose a Lightless unit anywhere on Gloom, or within local range off Gloom. Transfers are atomic; roster capacity applies.")
		_command("Release recruits", "stop", {"action": "release"}, {}, true, "Releases this Father's recruits to their current network stance.")
	if e.has("pos"):
		_command("Stop [X]", "stop", {"action": "stop"}, {}, true, "Stop orders for this unrecruited Mother or Father. Combat units act autonomously.")

func _refresh_actions() -> void:
	if womb_target != 0 and not selection.has(womb_target): womb_panel.hide(); womb_target = 0
	for parent in [actions, personnel_controls]:
		for child in parent.get_children(): parent.remove_child(child); child.queue_free()
	if selection.is_empty(): return
	if state.ended or not state.players[local_owner].alive: return
	var e := _observed_entity(int(selection[0]))
	if e.has("pos"):
		for id in selection:
			var candidate := _observed_entity(int(id))
			if candidate.get("kind", "") == "engineer": e = candidate; break
	if e.is_empty() or e.owner != local_owner: return
	if local_owner == -1: _lightless_actions(e); return
	if e.has("pos"):
		if Settings.data.units[e.kind].weapon != null or e.kind == "scout":
			for stance in ["neutral", "defensive", "aggressive"]:
				var button := _command(str(stance).capitalize(), stance, {"action": "stance", "stance": stance}, {}, true, "Neutral: manual attacks only. Defensive: defend your intended position. Aggressive: pursue enemies.")
				button.hotkey = str(Settings.data.controls.stanceHotkeys[stance]); button.toggle_mode = true
				button.set_meta("stance", stance); button.set_pressed_no_signal(e.stance == stance)
				button.pressed.connect(func(): button.set_pressed_no_signal(true))
				if e.stance == stance:
					for style in ["normal", "hover", "pressed", "hover_pressed"]: button.add_theme_stylebox_override(style, _style(Color("394739"), Color("b7bd8d")))
		if e.kind in ["operator", "engineer", "marine", "flamer", "lancer"]:
			var board := _button("Board [%s]" % _binding("board"), func(): _target_interaction("board"), actions) as CommandCard
			board.glyph = CommandSkin.icon("ranger"); board.custom_minimum_size = Vector2(108, 50)
			board.tooltip_text = "Choose a friendly vehicle or empty enemy vehicle. The first unit aboard becomes its driver."
		if e.kind in ["operator", "engineer"]:
			var load_button := _button("Load [%s]" % _binding("loadCargo"), func(): _target_interaction("load_cargo"), actions) as CommandCard
			load_button.glyph = CommandSkin.icon("depot"); load_button.custom_minimum_size = Vector2(108, 50)
			load_button.tooltip_text = "Choose a friendly Ranger or Excavator. Transfer personal cargo; retain overflow if full."
			var mine := _button("Mine [%s]" % _binding("mine"), func(): interaction_mode = ""; mining_mode = true; attack_mode = false; build_kind = ""; build_panel.hide(); status_label.text = "Choose a revealed resource patch or production facility", actions) as CommandCard; mine.glyph = CommandSkin.icon("mine"); mine.add_theme_constant_override("icon_max_width", 22); mine.custom_minimum_size = Vector2(108, 50); mine.add_theme_font_size_override("font_size", 12)
		if e.kind == "engineer":
			var repair := _button("Repair [%s]" % _binding("repair"), func(): _target_interaction("repair"), actions) as CommandCard
			repair.glyph = CommandSkin.icon("engineer"); repair.custom_minimum_size = Vector2(108, 50)
			repair.tooltip_text = "Choose a damaged friendly vehicle or completed structure. Repairs consume Ore."
			var build := _button("Build [%s]" % _binding("build"), _toggle_build, actions) as CommandCard; build.glyph = CommandSkin.icon("build"); build.add_theme_constant_override("icon_max_width", 22); build.custom_minimum_size = Vector2(108, 50); build.add_theme_font_size_override("font_size", 12)
		if Settings.data.units[e.kind].has("buriedWeapon"):
			_command("Emerge" if e.get("buried", false) else "Burrow", "build", {"action": "burrow"}, {}, e.get("transition", "") == "", "Transitions cannot be interrupted. Buried Threshers cannot move.")
		if Settings.data.units[e.kind].has("driverSeats"):
			var crew_ids := WorldState.ComplexCommands.selection(state, local_owner, selection)
			if crew_ids.any(func(id): return state.units[id].kind in ["operator", "engineer"]):
				_target_button("Mine [%s]" % _binding("mine"), "mine", func(): interaction_mode = ""; mining_mode = true; attack_mode = false, "Choose a revealed resource patch or production facility for the entire group.")
			if crew_ids.any(func(id): return state.units[id].kind == "engineer"):
				_target_button("Repair [%s]" % _binding("repair"), "repair", func(): _target_interaction("repair"), "Engineers repair while the group provides protection.")
			_command("Unload [%s]" % _binding("unload"), "unload", {"action": "unload"}, {}, int(e.driver) != 0 or not e.passengers.is_empty(), "Unload passengers first. Press again to unload the driver. Lighting and operation require a driver.")
		if Settings.data.units[e.kind].weapon != null or e.kind == "scout":
			_target_button("Attack [%s]" % _binding("attack"), "aggressive", _begin_attack, "Choose an explicit eligible target; this is not attack-move.")
		_target_button("Patrol [%s]" % _binding("patrol"), "patrol", func(): _target_interaction("patrol"), "Choose a destination to patrol between it and the current position. Combat follows stance.")
		_target_button("Escort [%s]" % _binding("escort"), "escort", func(): _target_interaction("escort"), "Choose a friendly unit or structure. Defensive positions follow the escort target.")
		_command("Stop [%s]" % _binding("stop"), "stop", {"action": "stop"}, {}, true, "Stop current orders. Carried resources are retained.")
		return
	if e.kind == "depot" and not e.started or e.kind == "depot" and e.built:
		for resource in Settings.data.controls.depotHotkeys:
			var button := _command(str(resource).capitalize(), "depot", {"action": "depot_type", "target": e.id, "resource": resource}, {}, float(e.configuration_remaining) <= 0 and e.depot_type != resource, "Change capacity type. Every Depot still accepts all ordinary resources.")
			button.hotkey = str(Settings.data.controls.depotHotkeys[resource]); button.set_meta("depot_resource", resource)
			button.toggle_mode = true; button.set_pressed_no_signal(e.depot_type == resource)
	if not e.built:
		_command("Cancel site", "cancel", {"action": "cancel_build", "target": e.id}, {}, true, "Full refund before construction starts. No refund after work starts."); return
	var toggle := CheckButton.new(); toggle.text = "+ Operator [%s] · ALL" % _binding("togglePersonnel"); toggle.button_pressed = state.players[local_owner].request_personnel
	toggle.tooltip_text = "Global setting: include a separately paid Operator with future kits and vehicles at every facility. Existing queues are unchanged."
	toggle.toggled.connect(func(value): _issue({"action": "global_personnel", "enabled": value})); personnel_controls.add_child(toggle)
	if e.kind in ["anchor", "cradle", "armory", "factory"]:
		if e.kind in ["armory", "factory"]:
			var source := OptionButton.new()
			source.add_item("Select source", 0)
			for building in state.observed_structures(local_owner):
				if building.owner != local_owner or not building.built or not building.kind in ["anchor", "cradle"]: continue
				source.add_item("%s #%d" % [str(building.kind).capitalize(), int(building.id)], int(building.id))
				if int(building.id) == int(e.personnel_source): source.select(source.item_count - 1)
			source.item_selected.connect(func(index): _issue({"action": "personnel_settings", "target": e.id, "source": source.get_item_id(index)})); source.tooltip_text = "Personnel source for automatic Operator requests"; personnel_controls.add_child(source)
		if e.kind in ["anchor", "cradle"]: _command("Operator", "operator", {"action": "operator", "target": e.id}, Settings.data.personnel.operatorCost, e.operators.size() < int(Settings.data.personnel.operatorQueueLimit))
		var types := ["engineer"] if e.kind in ["anchor", "cradle"] else ["marine", "flamer", "lancer"] if e.kind == "armory" else []
		for kind in types:
			var cost: Dictionary = Settings.data.personnel.kits[kind].cost.duplicate()
			if e.request_personnel:
				for r in Settings.data.personnel.operatorCost: cost[r] = int(cost.get(r, 0)) + int(Settings.data.personnel.operatorCost[r])
			_command(str(kind).capitalize(), kind, {"action": "kit", "kind": kind, "target": e.id}, cost, e.kits.size() < 5, "Kit assembly: %ss. Finished kits count toward the five-kit limit. Assign an Operator to collect a finished kit." % Settings.data.personnel.kits[kind].seconds)
	if e.kind == "factory":
		for kind in ["scout", "ranger", "excavator", "reaper", "cremator", "javelin"]:
			var cost: Dictionary = Settings.data.units[kind].cost.duplicate()
			if e.request_personnel:
				for r in Settings.data.personnel.operatorCost: cost[r] = int(cost.get(r, 0)) + int(Settings.data.personnel.operatorCost[r])
			_command(str(kind).capitalize(), kind, {"action": "vehicle", "kind": kind, "target": e.id}, cost, e.vehicles.size() < int(Settings.data.personnel.vehicleQueueLimit), "Assembly: %ss. Requires a driver to operate. Requested Operators board their assigned vehicle automatically." % Settings.data.units[kind].productionSeconds)
	if e.kind == "fabricator":
		for kind in Settings.data.upgrades.fabricatorArmor.types:
			var queued := false
			for facility in state.observed_structures(local_owner):
				if facility.owner == local_owner:
					for item in facility.upgrades:
						if item.kind == kind: queued = true
			_command(str(kind).capitalize() + " armor", "upgrade", {"action": "upgrade", "kind": kind, "target": e.id}, Settings.data.upgrades.fabricatorArmor.costPerType, not state.players[local_owner].upgrades.has(kind) and not queued, "Already queued. Assign Engineers to work the Fabricator." if queued else "Permanent +1 armor to this specialization. Engineers must work the Fabricator to complete it.")
	if e.kind == "anchor": _command("Extract", "extract", {"action": "extract", "target": e.id}, {}, int(state.resources(local_owner).get("nacre", 0)) >= int(state.cfg.match.extractionMinimumNacre), "Requires %d delivered Nacre. Hold the Anchor for %ds." % [state.cfg.match.extractionMinimumNacre, state.cfg.match.extractionSeconds])
	if e.kind == "relay": _command("Switch off" if e.enabled else "Switch on", "power", {"action": "toggle", "target": e.id}, {}, true, "Relays consume no power. Switching off disconnects their electrical footprint and any downstream grid that depends on this link.")
	elif int(Settings.data.structures[e.kind].powerDemand) > 0: _command("Power off" if e.enabled else "Power on", "power", {"action": "toggle", "target": e.id}, {}, true, "Disable this structure to reduce grid demand.")
	if e.kind == "gate":
		_command("Close" if e.open else "Open", "gate", {"action": "gate", "target": e.id})
		_command("Unlock" if e.locked else "Lock", "gate", {"action": "gate_lock", "target": e.id}, {}, true, "Locked gates ignore automatic opening and closing. Manual controls still work.")

func _observed_entity(id: int) -> Dictionary:
	return state.observed_entity(id, local_owner)

func _pick(screen: Vector2) -> int:
	var model := renderer.pick_model(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if model != 0: return model
	var best := 0
	var distance := 28.0
	for e in state.units.values() + state.observed_structures(local_owner):
		if not renderer.bodies.has(e.id) or not renderer.bodies[e.id].visible: continue
		var p := state.entity_position(e)
		if camera.is_position_behind(Vector3(p.x, 0.4, p.y)): continue
		var projected := camera.unproject_position(Vector3(p.x, 0.4, p.y))
		var d := projected.distance_to(screen)
		if d < distance: best = e.id; distance = d
	return best

func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if _minimap_input(event): get_viewport().set_input_as_handled(); return
	if tactical.map_expanded: return
	if _text_entry_focused(): return
	if controls_panel.visible:
		if event is InputEventKey and event.pressed and _key_is(event, "cancel"): controls_panel.hide()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_key(event): get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton: return
	var p := camera.ground(event.position)
	var cell := HexGrid.cell(Vector2(p.x, p.z))
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if build_kind != "":
				if build_kind == "wall":
					wall_start = _wall_cell(event.position); wall_end = wall_start; wall_dragging = true; selecting = false
					return
				var issue := state.placement_issue(local_owner, build_kind, cell)
				if issue != "": status_label.text = issue; return
				_issue({"action": "build", "kind": build_kind, "q": cell.x, "r": cell.y, "depot_type": depot_resource, "queued": event.shift_pressed})
				if not event.shift_pressed: _cancel_modes()
				return
			if mining_mode or attack_mode or interaction_mode != "":
				_dispatch_context(event.position, cell, p, -1, event.shift_pressed)
				return
			if event.double_click:
				_select_same_type(_pick(event.position), event.shift_pressed); selecting = false; return
			drag_start = event.position
			selecting = true
		elif selecting:
			selecting = false
			selection_box.visible = false
			if not Input.is_physical_key_pressed(KEY_SHIFT): selection.clear()
			if drag_start.distance_to(event.position) < float(Settings.data.controls.dragThresholdPixels):
				var id := _pick(event.position)
				if id:
					if event.shift_pressed and id in selection: selection.erase(id)
					elif not id in selection: selection.append(id)
				resource_cell = cell if id == 0 and state.known.get(local_owner, {}).has(cell) and state.tiles.has(cell) and state.tiles[cell].resource != "" and not state.tiles[cell].cliff else Vector2i(99999, 99999)
			else:
				var rect := Rect2(drag_start, Vector2.ZERO).expand(event.position)
				for u in state.units.values():
					if u.owner == local_owner and u.vehicle == 0 and rect.has_point(camera.unproject_position(Vector3(u.pos.x, 0.4, u.pos.y))):
						if not u.id in selection: selection.append(u.id)
			selection = selection.slice(0, int(Settings.data.controls.selectionLimit))
			_selection_feedback()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if build_kind != "" or depot_panel.visible or mining_mode or attack_mode or interaction_mode != "":
			_cancel_modes(); status_label.text = "Targeting canceled"; return
		_dispatch_context(event.position, cell, p, -1, event.shift_pressed)

func _input(event: InputEvent) -> void:
	if active and tactical.map_expanded and event is InputEventKey and event.pressed and _key_is(event, "cancel"):
		_toggle_fullscreen_map(); get_viewport().set_input_as_handled(); return
	if active and wall_dragging:
		if event is InputEventMouseMotion:
			wall_end = _wall_cell(event.position); get_viewport().set_input_as_handled(); return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_modes(); get_viewport().set_input_as_handled(); return
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				_finish_wall_line(event.position, event.shift_pressed); get_viewport().set_input_as_handled(); return
	if active and _minimap_input(event): get_viewport().set_input_as_handled()

func _wall_cell(screen: Vector2) -> Vector2i:
	var ground := camera.ground(screen)
	var point := Vector2(ground.x, ground.z)
	var cell := HexGrid.cell(point)
	while HexGrid.distance(cell) >= state.radius:
		point *= float(state.radius - 1) / float(HexGrid.distance(cell) + 1)
		cell = HexGrid.cell(point)
	return cell

func _finish_wall_line(screen: Vector2, queued: bool) -> void:
	wall_end = _wall_cell(screen)
	_issue({"action": "build_line", "q": wall_start.x, "r": wall_start.y, "end_q": wall_end.x, "end_r": wall_end.y, "queued": queued})
	wall_dragging = false; renderer.show_wall_line([])
	if not queued: _cancel_modes()

func _toggle_fullscreen_map() -> void:
	minimap_dragging = false; selecting = false
	_cancel_modes(); controls_panel.hide()
	tactical.set_map_expanded(not tactical.map_expanded)
	camera.drag = false

func _pan_minimap(screen: Vector2) -> void:
	var rect := tactical.minimap_rect().grow(-12)
	var clamped := screen.clamp(rect.position, rect.end)
	var position := tactical.minimap_world(clamped)
	var distance := HexGrid.distance(HexGrid.cell(position))
	if distance > state.radius: position *= float(state.radius) / distance
	camera.focus = Vector3(position.x, 0, position.y); camera._update_transform()

func _minimap_pick(screen: Vector2) -> int:
	var result := 0; var best := 7.0
	for e in state.units.values() + state.observed_structures(local_owner):
		if e.has("pos") and (int(e.get("vehicle", 0)) != 0 or not WorldState.TargetRules.identifiable(state, e, local_owner)): continue
		var distance: float = tactical.map_point(state.entity_position(e)).distance_to(screen)
		if distance < best: result = int(e.id); best = distance
	return result

func _minimap_input(event: InputEvent) -> bool:
	if not active or controls_panel.visible: minimap_dragging = false; return false
	if event is InputEventMouseMotion and minimap_dragging:
		_pan_minimap(event.position); return true
	if not event is InputEventMouseButton: return false
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and minimap_dragging:
		minimap_dragging = false; return true
	if tactical.map_toggle.visible and tactical.map_toggle.get_global_rect().has_point(event.position): return false
	if not event.pressed or not tactical.minimap_rect().has_point(event.position): return false
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: return false
	if event.button_index == MOUSE_BUTTON_LEFT and not (attack_mode or mining_mode or interaction_mode != ""):
		minimap_dragging = true; selecting = false; _pan_minimap(event.position); return true
	var point := tactical.minimap_world(event.position)
	_dispatch_context(event.position, HexGrid.cell(point), Vector3(point.x, 0, point.y), _minimap_pick(event.position), event.shift_pressed)
	return true

func _dispatch_context(screen: Vector2, cell: Vector2i, point: Vector3, target: int, queued: bool) -> void:
	var modes := [interaction_mode, attack_mode, mining_mode]
	queue_modifier = queued
	_context_order(screen, cell, point, target)
	queue_modifier = false
	interaction_mode = str(modes[0]) if queued else ""
	attack_mode = bool(modes[1]) if queued else false
	mining_mode = bool(modes[2]) if queued else false

func _context_order(screen: Vector2, cell: Vector2i, point: Vector3, target_override: int = -1) -> void:
	if selection.is_empty(): status_label.text = "Select units before issuing an order"; return
	tactical.mark(Vector2(point.x, point.z), Color("ef8a92") if attack_mode else Color("85e4cd"))
	var target := _pick(screen) if target_override < 0 else target_override
	var observed := _observed_entity(target)
	if mining_mode:
		if observed.has("cell") and observed.owner == local_owner and observed.kind in ["extractor", "foundry", "refinery", "synthesizer"]:
			_issue({"action": "mine", "q": observed.cell.x, "r": observed.cell.y, "facility": target})
		elif state.known.get(local_owner, {}).has(cell) and state.tiles.has(cell) and state.tiles[cell].resource != "": _issue({"action": "mine", "q": cell.x, "r": cell.y})
		else: status_label.text = "Choose a revealed resource patch or production facility"; audio.cue("error")
		return
	if observed.get("remembered", false) and interaction_mode != "patrol":
		if attack_mode or interaction_mode != "":
			status_label.text = "Rediscover this structure before targeting it"; audio.cue("error")
		else:
			var last_position := state.entity_position(observed)
			_issue({"action": "move", "x": last_position.x, "z": last_position.y})
		interaction_mode = ""; return
	if interaction_mode != "":
		if interaction_mode == "patrol": _issue({"action": "patrol", "x": point.x, "z": point.z})
		else: _issue({"action": interaction_mode, "target": target})
		interaction_mode = ""; return
	if target:
		var e := _observed_entity(target)
		if not attack_mode and e.has("pos") and Settings.data.units[e.kind].has("driverSeats"):
			var can_enter := false
			var cargo_workers := false
			for id in selection:
				var unit := _observed_entity(int(id))
				if unit.has("pos") and state.can_board(unit, target): can_enter = true
				if unit.get("kind", "") in ["operator", "engineer"] and state.cargo_amount(unit) > 0: cargo_workers = true
			if cargo_workers and e.owner == local_owner and int(Settings.data.units[e.kind].cargoCapacity) > 0:
				_issue({"action": "load_cargo", "target": target}); return
			if can_enter: _issue({"action": "board", "target": target}); return
		if attack_mode or e.owner != local_owner: _issue({"action": "attack", "target": target}); return
		if e.has("cell") and e.kind == "fabricator" and e.built: _issue({"action": "work", "target": target}); return
		if e.has("cell") and not e.built: _issue({"action": "work", "target": target}); return
		var has_cargo := false
		var has_engineer := false
		for id in WorldState.ComplexCommands.selection(state, local_owner, selection):
			var unit := _observed_entity(int(id))
			if unit.has("cargo") and state.cargo_amount(unit) > 0: has_cargo = true
			if unit.get("kind", "") == "engineer": has_engineer = true
		if e.has("cell") and e.kind in ["anchor", "depot"] and has_cargo: _issue({"action": "deposit", "target": target}); return
		var max_hp := float(Settings.data.structures[e.kind].health) if e.has("cell") else float(Settings.data.units[e.kind].health)
		if has_engineer and e.hp < max_hp and (e.has("cell") or not Settings.data.units[e.kind].get("biological", true)):
			_issue({"action": "repair", "target": target}); return
		if e.has("cell") and e.kind in ["extractor", "foundry", "refinery", "synthesizer"]:
			_issue({"action": "mine", "q": e.cell.x, "r": e.cell.y, "facility": target}); return
		if e.has("cell") and e.kind in ["anchor", "cradle", "armory"]:
			_issue({"action": "equip", "target": target}); return
	if state.detected.get(local_owner, {}).has(cell):
		for id in selection:
			if state.structures.has(int(id)) and Settings.data.structures[state.structures[int(id)].kind].has("weapon"):
				_issue({"action": "attack_tile", "q": cell.x, "r": cell.y}); return
	if state.tiles.has(cell) and state.tiles[cell].cliff and state.known.get(local_owner, {}).has(cell):
		for id in selection:
			if _observed_entity(int(id)).get("kind", "") == "excavator":
				_issue({"action": "excavate", "q": cell.x, "r": cell.y}); return
	if state.tiles.has(cell) and state.tiles[cell].resource != "" and state.known.get(local_owner, {}).has(cell):
		_issue({"action": "mine", "q": cell.x, "r": cell.y})
	else: _issue({"action": "move", "x": point.x, "z": point.z})

func _target_interaction(kind: String) -> void:
	build_kind = ""; mining_mode = false; attack_mode = false; build_panel.hide()
	interaction_mode = kind
	status_label.text = "Choose a patrol destination" if kind == "patrol" else "Choose a friendly unit or structure to escort" if kind == "escort" else "Choose a vehicle to board" if kind == "board" else "Choose a damaged friendly vehicle or structure" if kind == "repair" else "Choose a friendly cargo vehicle"

func _selection_hint(kind: String) -> String:
	match kind:
		"radar": return "Amber markers show unidentified enemy tiles. Select a turret and right click a contact."
		"rampart": return "Shield coverage adds armor to friendly structures while powered. Bonuses do not stack."
		"sentry", "torch", "lance": return "Right click an eligible enemy or radar contact to override automatic targeting."
		"relay": return "Coverage and dashed lines show grid links. Switch off disconnects this Relay and dependent grids; switching on reconnects them. Relays consume no power."
		"factory": return "Queue a vehicle; enable + Operator to request its driver from the selected personnel source."
		"gate": return "Unlocked gates open for friendly routes. Manual opening and locking are separate controls."
		"scout", "ranger", "excavator", "reaper", "cremator", "javelin": return "Vehicles require a driver. Unload releases passengers first, then the driver."
		"engineer": return "Idle: build or repair nearby structures. %s: build; drag to place a wall line. Use Repair to fix vehicles." % _binding("build")
		"operator": return "Right click to gather or collect a kit. Choose Board vehicle or Load cargo for vehicle work."
		"depot": return "All Depots accept ordinary resources. Capacity type affects storage limits; Nacre goes to the Anchor."
		"": return "Select a unit or structure. Right click to issue a context order."
		_: return "Right click for context orders. %s: attack target. %s: stop. %s: patrol. %s: escort." % [_binding("attack"), _binding("stop"), _binding("patrol"), _binding("escort")]

func _binding(action: String) -> String:
	return str(Settings.data.controls.commands[action])

func _matches_key(event: InputEventKey, binding: String) -> bool:
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code != OS.find_keycode_from_string(binding): return false
	camera.suppressed_pan_keys[code] = true
	return true

func _selection_shortcut(event: InputEventKey) -> bool:
	if selection.is_empty() or state.ended or not state.players[local_owner].alive: return false
	var e := _observed_entity(int(selection[0]))
	if e.is_empty() or e.owner != local_owner: return false
	if local_owner == -1:
		if not WorldState.LightlessControl.directly_controllable(e): return false
		if _key_is(event, "stop"): _issue({"action": "stop"}); return true
		return false
	if e.has("cell") and _key_is(event, "togglePersonnel"):
		_issue({"action": "global_personnel", "enabled": not bool(state.players[local_owner].request_personnel)}); return true
	if e.has("pos"):
		for stance in Settings.data.controls.stanceHotkeys:
			if _matches_key(event, str(Settings.data.controls.stanceHotkeys[stance])):
				_issue({"action": "stance", "stance": stance}); return true
	for button in actions.get_children():
		if button is CommandCard and button.hotkey != "" and _matches_key(event, button.hotkey):
			if not button.disabled: button.pressed.emit()
			else: status_label.text = "Command unavailable: " + button.text; audio.cue("error")
			return true
	return false

func _cursor_mode() -> String:
	if not active or controls_panel.visible: return ""
	if minimap_dragging: return "pan"
	if build_kind != "": return "build"
	if attack_mode: return "attack"
	if mining_mode: return "mine"
	return interaction_mode

func _update_cursor() -> void:
	var mode := _cursor_mode()
	if get_viewport().gui_get_hovered_control() != null and not tactical.minimap_rect().has_point(get_viewport().get_mouse_position()): mode = ""
	if mode == cursor_action: return
	cursor_action = mode
	if mode == "": Input.set_custom_mouse_cursor(null); return
	if not action_cursors.has(mode):
		var paths := {"attack": '<circle cx="22" cy="22" r="7"/><path d="M22 12v5m0 10v5M12 22h5m10 0h5"/>', "mine": '<path d="M15 17q8-7 15 1M23 16l-7 15"/>', "repair": '<path d="M29 14l-4 5-4-4 4-4q-10-2-8 8l-6 8 4 4 8-8q10 2 6-9z"/>', "patrol": '<path d="M13 19h17l-5-5m5 12H13l5 5"/>', "escort": '<circle cx="25" cy="18" r="4"/><circle cx="17" cy="27" r="4"/>', "board": '<path d="M22 13h9v18h-9m-10-9h15l-4-4m4 4-4 4"/>', "load_cargo": '<path d="M16 20h14v11H16zm7-9v12m-4-4 4 4 4-4"/>', "build": '<path d="M15 30l11-15m-8-1 9 7 4-5-9-7z"/>', "pan": '<path d="M22 12v20M12 22h20m-14-6 4-4 4 4m-8 12 4 4 4-4"/>'}
		var glyph: String = paths.get(mode, paths.attack)
		var color := "#ed9473" if mode == "attack" else "#e8c78a"
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36"><path d="M3 3v22l6-6 5 9 4-2-5-9h9z" fill="#e3e7d5" stroke="#071014" stroke-width="2"/><g fill="none" stroke="#071014" stroke-width="5" stroke-linejoin="round">%s</g><g fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round">%s</g></svg>' % [glyph, color, glyph]
		var icon_image := Image.new(); icon_image.load_svg_from_string(svg)
		action_cursors[mode] = ImageTexture.create_from_image(icon_image)
	Input.set_custom_mouse_cursor(action_cursors[mode], Input.CURSOR_ARROW, Vector2(3, 3))

func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)

func _key_is(event: InputEventKey, action: String) -> bool:
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	return code == OS.find_keycode_from_string(_binding(action))

func _text_entry_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _cancel_modes() -> void:
	wall_dragging = false; renderer.show_wall_line([])
	build_kind = ""; mining_mode = false; attack_mode = false; interaction_mode = ""; build_panel.hide(); placement_strip.hide()
	depot_panel.hide(); womb_panel.hide(); womb_target = 0

func _toggle_build() -> void:
	var eligible := false
	for id in selection:
		var unit := _observed_entity(int(id))
		if unit.get("kind", "") == "engineer" and unit.owner == local_owner and int(unit.get("vehicle", 0)) == 0: eligible = true
	if not eligible: status_label.text = "Select an Engineer to build"; audio.cue("error"); return
	var opening := not build_panel.visible
	_cancel_modes(); build_panel.visible = opening
	status_label.text = "Choose a structure by its letter. Arrow keys, edge scroll and middle drag still pan." if opening else "Construction catalogue closed"

func _choose_build(kind: String) -> void:
	_cancel_modes()
	if kind == "womb":
		build_kind = "womb"; _open_womb_types(); return
	if kind == "depot":
		build_kind = "depot"; depot_panel.show()
		group_bar.hide()
		status_label.text = "Place %s Depot now, or choose O Ore / G Gas / A Alloy / P Polymer / C Crystal." % depot_resource.capitalize(); return
	build_kind = kind
	status_label.text = "Place %s. WASD pans; Shift repeats placement; Esc cancels." % kind.capitalize()
	audio.cue("order")

func _open_womb_types(target: int = 0) -> void:
	if target != 0: _cancel_modes()
	womb_target = target; womb_panel.show(); group_bar.hide()
	_refresh_womb_choices()
	status_label.text = "Choose the Womb's new type; population and capacity rules apply." if target != 0 else "Place %s Womb now, or optionally choose a type. Esc cancels." % lightless_unit_type.capitalize()

func _refresh_womb_choices() -> void:
	var site := _observed_entity(womb_target)
	for kind in womb_buttons:
		var issue := WorldState.LightlessColony.reconfigure_issue(state, site, kind) if womb_target != 0 else ""
		womb_buttons[kind].disabled = not issue.is_empty()
		womb_buttons[kind].tooltip_text = issue if not issue.is_empty() else "Choose %s Womb. Current population %d / %d." % [str(kind).capitalize(), state._population(kind), WorldState.LightlessColony.cap(state, kind)]

func _choose_womb_type(kind: String) -> void:
	if not kind in WorldState.LightlessControl.TYPES: return
	var target := womb_target
	_cancel_modes(); lightless_unit_type = kind
	if target != 0: _issue({"action": "womb_type", "target": target, "unit_type": kind})
	else:
		build_kind = "womb"; status_label.text = "Place %s Womb. Shift repeats placement." % kind.capitalize()

func _choose_depot_resource(resource: String) -> void:
	if not Settings.data.controls.depotHotkeys.has(resource): return
	_cancel_modes(); depot_resource = resource; build_kind = "depot"
	status_label.text = "Place %s Depot. Shift queues construction and repeats placement." % resource.capitalize()

func _begin_attack() -> void:
	if local_owner == -1: status_label.text = "Lightless combat units are autonomous; guide them through a Father or the Medusa."; return
	var eligible := false
	for id in selection:
		var unit := _observed_entity(int(id))
		if unit.is_empty() or unit.owner != local_owner: continue
		if (unit.has("pos") and (Settings.data.units[unit.kind].weapon != null or unit.kind == "scout")) or (unit.has("cell") and Settings.data.structures[unit.kind].has("weapon")): eligible = true
	if not eligible: status_label.text = "Select an armed unit or turret"; audio.cue("error"); return
	_cancel_modes(); attack_mode = true; status_label.text = "Choose an eligible target to attack"

func _handle_key(event: InputEventKey) -> bool:
	if _key_is(event, "cancel"):
		if build_panel.visible or depot_panel.visible or womb_panel.visible or build_kind != "" or mining_mode or attack_mode or interaction_mode != "": _cancel_modes()
		else: selection.clear(); _refresh_actions()
		return true
	if womb_panel.visible:
		for kind in Settings.data.controls.wombHotkeys:
			if _matches_key(event, str(Settings.data.controls.wombHotkeys[kind])): _choose_womb_type(kind); return true
		return false
	if _key_is(event, "build"): _toggle_build(); return true
	if depot_panel.visible or build_kind == "depot":
		for resource in Settings.data.controls.depotHotkeys:
			if _matches_key(event, str(Settings.data.controls.depotHotkeys[resource])): _choose_depot_resource(str(resource)); return true
		if depot_panel.visible: return false
	if build_panel.visible:
		var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		for kind in Settings.data.controls.buildHotkeys:
			if code == OS.find_keycode_from_string(str(Settings.data.controls.buildHotkeys[kind])):
				camera.suppressed_pan_keys[code] = true; _choose_build(kind); return true
		return false
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var slot := int(code) - KEY_0
	if slot >= 1 and slot <= int(Settings.data.controls.controlGroupCount):
		if event.ctrl_pressed or event.shift_pressed: _assign_group(slot, event.ctrl_pressed and event.shift_pressed)
		else: _recall_group(slot)
		return true
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	if _selection_shortcut(event): return true
	if _key_is(event, "pause"): _pause(); return true
	if _key_is(event, "focusAnchor"): _focus_anchor(); return true
	if _key_is(event, "focusSelection"): _focus_selection(); return true
	if _key_is(event, "attack"): _begin_attack(); return true
	if _key_is(event, "stop"): _cancel_modes(); _issue({"action": "stop"}); return true
	if _key_is(event, "unload"): _issue({"action": "unload"}); return true
	for action in ["patrol", "escort", "board", "repair"]:
		if _key_is(event, action): _target_interaction(action); return true
	if _key_is(event, "loadCargo"): _target_interaction("load_cargo"); return true
	if _key_is(event, "mine"):
		for id in selection:
			if _observed_entity(int(id)).get("kind", "") in ["operator", "engineer"]:
				_cancel_modes(); mining_mode = true; status_label.text = "Choose a revealed resource patch or production facility"; return true
		status_label.text = "Select an Operator or Engineer to gather"; audio.cue("error"); return true
	return false

func _select_same_type(id: int, additive: bool) -> void:
	var exemplar := _observed_entity(id)
	if exemplar.is_empty(): return
	if not additive: selection.clear()
	var viewport := get_viewport().get_visible_rect()
	for candidate in state.units.values() + state.observed_structures(local_owner):
		if candidate.owner != local_owner or candidate.kind != exemplar.kind or not renderer.bodies.has(candidate.id) or not renderer.bodies[candidate.id].visible: continue
		var position := state.entity_position(candidate)
		var world_point := Vector3(position.x, 0.4, position.y)
		if camera.is_position_behind(world_point) or not viewport.has_point(camera.unproject_position(world_point)): continue
		if not candidate.id in selection: selection.append(candidate.id)
	if exemplar.owner != local_owner: selection = [id]
	selection = selection.slice(0, int(Settings.data.controls.selectionLimit)); _selection_feedback()

func _selection_feedback() -> void:
	_refresh_actions(); tactical.selection_pulse = float(Settings.data.controls.selectionPulseSeconds); audio.cue("select")

func _focus_selection() -> void:
	var center := Vector2.ZERO
	var count := 0
	for id in selection:
		var entity_data := _observed_entity(int(id))
		if entity_data.is_empty(): continue
		center += state.entity_position(entity_data); count += 1
	if count > 0: camera.focus = Vector3(center.x / count, 0, center.y / count); camera._update_transform()

func _assign_group(slot: int, merge: bool = false) -> void:
	var members: Array = control_groups.get(slot, []).filter(func(id): return not _observed_entity(int(id)).is_empty() and _observed_entity(int(id)).owner == local_owner) if merge else []
	for id in selection:
		if _observed_entity(int(id)).get("owner", -1) == local_owner and not id in members: members.append(id)
	if members.is_empty(): return
	control_groups[slot] = members.slice(0, int(Settings.data.controls.selectionLimit))
	_refresh_group_bar(); status_label.text = "Group %d assigned: %d assets" % [slot, control_groups[slot].size()]; audio.cue("order")

func _recall_group(slot: int) -> void:
	var members: Array = control_groups.get(slot, []).filter(func(id): return not _observed_entity(int(id)).is_empty() and _observed_entity(int(id)).owner == local_owner)
	if members.is_empty(): status_label.text = "Group %d is empty. Ctrl+%d or Shift+%d assigns the selection." % [slot, slot, slot]; return
	control_groups[slot] = members
	_cancel_modes(); selection = members; _selection_feedback(); _update_hud()
	var now := Time.get_ticks_msec()
	if last_group_slot == slot and now - last_group_time <= float(Settings.data.controls.groupDoubleTapSeconds) * 1000: _focus_selection()
	last_group_slot = slot; last_group_time = now
	status_label.text = "Group %d: %d selected. Double tap to focus." % [slot, selection.size()]

func _refresh_group_bar() -> void:
	for slot in group_buttons:
		var members: Array = control_groups.get(slot, []).filter(func(id): return not _observed_entity(int(id)).is_empty() and _observed_entity(int(id)).owner == local_owner)
		var button: Button = group_buttons[slot]
		button.text = "%d/%s" % [slot, "99+" if members.size() > 99 else str(members.size())] if not members.is_empty() else str(slot)
		button.modulate = Color.WHITE if not members.is_empty() else Color("6e7d78")
		button.set_pressed_no_signal(not members.is_empty() and members.size() == selection.size() and members.all(func(id): return id in selection))
		button.tooltip_text = "Group %d: %d assets\n%d: recall / double tap: focus\nCtrl+%d or Shift+%d: assign\nCtrl+Shift+%d: add selection" % [slot, members.size(), slot, slot, slot, slot]

func _create_control_ui() -> void:
	group_bar = HBoxContainer.new(); group_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	group_bar.offset_left = -375; group_bar.offset_right = -14; group_bar.offset_top = 81; group_bar.offset_bottom = 108
	hud.add_child(group_bar)
	group_bar.add_child(_label("GROUPS", 10, Color("bcae88")))
	for slot in range(1, int(Settings.data.controls.controlGroupCount) + 1):
		var button := _button(str(slot), func():
			if Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_CTRL): _assign_group(slot)
			else: _recall_group(slot), group_bar)
		_tight_group_button(button); button.toggle_mode = true
		button.custom_minimum_size = Vector2(27, 26); button.add_theme_font_size_override("font_size", 10); group_buttons[slot] = button
	var help_button := _button("?", func(): controls_panel.visible = not controls_panel.visible, group_bar)
	_tight_group_button(help_button); help_button.tooltip_text = "Controls and shortcuts"
	placement_strip = PanelContainer.new(); placement_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	placement_strip.offset_left = -235; placement_strip.offset_right = 235; placement_strip.offset_top = 82; placement_strip.offset_bottom = 130
	placement_strip.add_theme_stylebox_override("panel", CommandSkin.panel()); hud.add_child(placement_strip)
	placement_text = _label("", 12); placement_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; placement_strip.add_child(placement_text); placement_strip.hide()
	controls_panel = PanelContainer.new(); controls_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	controls_panel.offset_left = -310; controls_panel.offset_right = 310; controls_panel.offset_top = -205; controls_panel.offset_bottom = 205
	controls_panel.add_theme_stylebox_override("panel", CommandSkin.panel()); hud.add_child(controls_panel)
	var column := VBoxContainer.new(); controls_panel.add_child(column)
	column.add_child(_label("FIELD CONTROLS", 22, Color("cfbd8f")))
	var help: Array[String] = [
		"WASD / arrows: pan   Middle drag: pan   Wheel: zoom",
		"Left click / drag: select   Shift: add/remove selection",
		"Double click: matching owned units/structures in view",
		"Minimap: left-drag camera; right-click context order",
		"Shift + order: append plan; ordinary order: replace; X: stop",
		"%s: attack   %s: mine   %s: patrol   %s: escort" % [_binding("attack"), _binding("mine"), _binding("patrol"), _binding("escort")],
		"%s: board   %s: cargo   %s: repair   %s: unload" % [_binding("board"), _binding("loadCargo"), _binding("repair"), _binding("unload")],
		"Stance: %s neutral / %s defensive / %s aggressive" % [Settings.data.controls.stanceHotkeys.neutral, Settings.data.controls.stanceHotkeys.defensive, Settings.data.controls.stanceHotkeys.aggressive],
		"Structures: %s toggles global Operator requests" % _binding("togglePersonnel"),
		"Production and kit keys are shown on their command cards.",
		"%s: build catalogue; choose its displayed letter" % _binding("build"),
		"Depot: B, D arms the remembered type (initially Ore).",
		"Place immediately or choose its resource button/key.",
		"Shift repeats and queues construction; Escape cancels.",
		"1-9: recall group; double-tap: focus",
		"Ctrl/Shift + number: assign; Ctrl+Shift + number: add",
		"%s: focus selection   %s: Anchor   %s: pause" % [_binding("focusSelection"), _binding("focusAnchor"), _binding("pause")]
	]
	var text := _label("\n".join(help), 14)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(text)
	_button("Close", func(): controls_panel.hide(), column); controls_panel.hide()

func _target_button(title: String, glyph: String, action: Callable, explanation: String) -> CommandCard:
	var button := _button(title, action, actions) as CommandCard
	button.glyph = CommandSkin.icon(glyph); button.tooltip_text = explanation
	return button

func _tight_group_button(button: Button) -> void:
	for key in ["normal", "hover", "pressed"]:
		var style := _style(Color("253337") if key == "normal" else Color("46524b"))
		style.set_content_margin_all(3); button.add_theme_stylebox_override(key, style)
	button.custom_minimum_size = Vector2(27, 26)

func ghost_model_visible() -> bool:
	return renderer.ghost_model != null and renderer.ghost_model.visible

func _refresh_action_signature() -> void:
	# Include every selected role so kit transformations and crew changes update a
	# mixed group's commands. Exclude ordinary income/HP to keep open menus stable.
	var parts: Array = [state.ended, state.players[local_owner].alive, state.players[local_owner].get("request_personnel", true), int(state.resources(local_owner).get("nacre", 0)) >= int(state.cfg.match.extractionMinimumNacre), state.players[local_owner].upgrades]
	for id in selection:
		var e := _observed_entity(int(id))
		parts.append([id, e.get("kind", ""), e.get("stance", ""), e.get("network_stance", ""), e.get("group_stance", ""), e.get("father_id", 0), e.get("enabled", true), e.get("open", false), e.get("locked", false), e.get("built", true), e.get("driver", 0), e.get("passengers", []).size(), e.get("buried", false), e.get("transition", ""), e.get("request_personnel", false), e.get("personnel_source", 0), e.get("kits", []).size(), e.get("operators", []).size(), e.get("vehicles", []).size(), e.get("upgrades", []).map(func(item): return item.kind), e.get("configuration_remaining", 0) > 0, e.get("depot_type", ""), e.get("unit_type", "")])
	if local_owner == -1: parts.append([state.units.size(), state.structures.values().map(func(site): return [site.id, site.built, site.get("unit_type", ""), float(site.get("configuration_remaining", 0)) > 0])])
	var signature := JSON.stringify(parts)
	if signature != action_signature: action_signature = signature; _refresh_actions()
