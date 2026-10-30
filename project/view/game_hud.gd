extends RefCounted
## Global resources stay at the top; selection, grid, orders and construction share one dock.
const Rules = preload("res://engine/expedition_rules.gd")
const MATERIAL = preload("res://assets/ui/material.svg")
const METHANE = preload("res://assets/ui/methane.svg")
const POWER = preload("res://assets/ui/power.svg")
var game: Node2D
var material_value: Label
var methane_value: Label
var grid_panel: HBoxContainer
var grid_value: Label
var order_tab: Button
var build_tab: Button
var order_grid: GridContainer
var build_scroll: ScrollContainer
var active_tab := "orders"
var selection_grid: Dictionary = {}
var help_overlay: ColorRect
var help_footer: Label
var ready := false

func icon(parent: Node, texture: Texture2D, pixels: int = 20) -> TextureRect:
	var node := TextureRect.new(); node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(pixels, pixels); node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node); return node

func row(parent: Node, separation: int = 8) -> HBoxContainer:
	var node := HBoxContainer.new(); node.add_theme_constant_override("separation", separation); parent.add_child(node); return node

func purchase(button: Button, kind: String, shortcut: String) -> void:
	var cost := Rules.cost(kind)
	button.text = ""
	button.tooltip_text = "%s\n%d materials%s%s" % [Rules.title(kind), cost.minerals, " / %d methane" % cost.gas if cost.gas > 0 else "", "\nShortcut: " + shortcut if not shortcut.is_empty() else ""]
	if not button.has_meta("purchase_name"):
		button.text = ""; button.custom_minimum_size = Vector2(112, 44)
		var content := VBoxContainer.new(); content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); content.offset_left = 9; content.offset_right = -9; content.offset_top = 4; content.offset_bottom = -4
		content.add_theme_constant_override("separation", 0); button.add_child(content)
		var heading := row(content, 4); heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title: Label = game.label(heading, Rules.title(kind), 13); title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var key: Label = game.label(heading, "", 12, game.AMBER); key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.set_meta("key_label", key)
		var costs := row(content, 4); costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon(costs, MATERIAL, 13); game.label(costs, str(cost.minerals), 11)
		if cost.gas > 0: icon(costs, METHANE, 13); game.label(costs, str(cost.gas), 11)
		button.set_meta("purchase_name", title)
	button.set_meta("shortcut", shortcut)
	var key_label: Label = button.get_meta("key_label")
	key_label.text = "[" + shortcut + "]" if not shortcut.is_empty() else "Click"
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.custom_minimum_size.y = 44

func command(parent: Node, key: String, title: String, shortcut: String, callback: Callable) -> void:
	var item: Button = game.button(parent, title, callback)
	item.custom_minimum_size = Vector2(100, 32)
	item.tooltip_text = title + (" [" + shortcut + "]" if not shortcut.is_empty() else "")
	item.set_meta("short_title", title)
	item.set_meta("shortcut", shortcut)
	game.context_buttons[key] = item

func setup(world: Node2D) -> void:
	game = world
	var layer := CanvasLayer.new(); game.add_child(layer)
	game.ui = Control.new(); game.ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); game.ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; layer.add_child(game.ui)
	game.world_bars = preload("res://view/world_status_bars.gd").new(); game.ui.add_child(game.world_bars); game.world_bars.setup(game)
	game.selection_box = game.SelectionBox.new(); game.selection_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); game.selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; game.ui.add_child(game.selection_box)
	var header: PanelContainer = game.panel(game.ui); header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 18; header.offset_right = -18; header.offset_top = 14; header.offset_bottom = 72
	var top := row(header, 22)
	var identity := VBoxContainer.new(); identity.add_theme_constant_override("separation", 1); top.add_child(identity)
	game.label(identity, "AGAINST THE DARKNESS", 16)
	game.objective_label = game.label(identity, "", 12, Color("8fa8b4"))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(spacer)
	game.sensors = game.label(top, "", 12, game.AMBER); game.sensors.visible = false
	var resources := row(top, 18)
	var material := row(resources, 6); material.custom_minimum_size.x = 125; icon(material, MATERIAL); material_value = game.label(material, "", 17); material_value.mouse_filter = Control.MOUSE_FILTER_PASS
	var methane := row(resources, 6); methane.custom_minimum_size.x = 125; icon(methane, METHANE); methane_value = game.label(methane, "", 17); methane_value.mouse_filter = Control.MOUSE_FILTER_PASS
	game.stats = material_value # Compatibility for callers that check UI initialization.
	game.pause_button = game.button(top, "Pause [Space]", game.toggle_pause); game.pause_button.tooltip_text = "Pause / resume [Space]"
	var help: Button = game.button(top, "Help [F1]", toggle_help); help.tooltip_text = "Controls and mission details [F1]"
	# One stable bottom dock; minimap occupies the space immediately to its right.
	game.command_panel = game.panel(game.ui); game.command_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var dock := row(game.command_panel, 20)
	var selection := VBoxContainer.new(); selection.custom_minimum_size.x = 220; selection.add_theme_constant_override("separation", 8); dock.add_child(selection)
	game.command_title = game.label(selection, "No selection", 17, game.MINT)
	game.details = game.label(selection, "", 13); game.details.custom_minimum_size.x = 220; game.details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid_panel = row(selection, 8); icon(grid_panel, POWER, 20); grid_value = game.label(grid_panel, "", 12, Color("8cc7ff")); grid_value.mouse_filter = Control.MOUSE_FILTER_PASS
	var commands := VBoxContainer.new(); commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL; commands.add_theme_constant_override("separation", 6); dock.add_child(commands)
	game.command_content = commands
	var tabs := row(commands, 6)
	order_tab = game.button(tabs, "Commands", func(): show_tab("orders")); order_tab.toggle_mode = true
	build_tab = game.button(tabs, "Build", func(): show_tab("build")); build_tab.toggle_mode = true
	build_tab.tooltip_text = "1-0 select the first ten structures; click other cards\nT rotates / Shift queues / Right-click cancels"
	game.command_scroll = ScrollContainer.new(); game.command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; game.command_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; commands.add_child(game.command_scroll)
	order_grid = GridContainer.new(); order_grid.columns = 5; order_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_grid.add_theme_constant_override("h_separation", 6); order_grid.add_theme_constant_override("v_separation", 6); game.command_scroll.add_child(order_grid)
	command(order_grid, "board", "Board", "B", game.board_squad)
	command(order_grid, "unload", "Unload", "U", game.unload)
	command(order_grid, "expedition", "Explore", "E", func(): game.choose_expedition(false))
	command(order_grid, "mining", "Mine", "M", func(): game.choose_expedition(true))
	command(order_grid, "attack", "Attack move", "Q", func(): game.choose_tactical("attack_move"))
	command(order_grid, "defend", "Defend", "V", func(): game.choose_tactical("defend"))
	command(order_grid, "patrol", "Patrol", "P", func(): game.choose_tactical("patrol"))
	command(order_grid, "drill_order", "Drill", "C", func(): game.choose_tactical("drill"))
	command(order_grid, "repair", "Repair", "R", game.choose_repair)
	command(order_grid, "load", "Collect cargo", "L", game.load_nearest)
	command(order_grid, "stock", "Deposit", "J", game.stock_depot)
	command(order_grid, "home", "Return HQ", "H", game.return_home)
	command(order_grid, "escort", "Escort", "G", game.escort)
	command(order_grid, "recharge", "Auto recharge", "N", game.toggle_auto_recharge); game.context_buttons.recharge.toggle_mode = true
	command(order_grid, "reload_turret", "Reload", "R", game.reload_selected_turrets)
	command(order_grid, "auto_reload", "Auto reload", "Z", game.toggle_turret_reload); game.context_buttons.auto_reload.toggle_mode = true
	command(order_grid, "repeater", "Grid relay", "Y", game.toggle_repeater)
	command(order_grid, "gate", "Open gate", "O", game.toggle_gate)
	command(order_grid, "gate_lock", "Lock gate", "K", game.toggle_gate_lock)
	command(order_grid, "stop", "Stop", "X", game.stop_selected)
	command(order_grid, "destroy", "Destroy", "Delete", game.destroy_selected)
	for kind in Rules.UNITS:
		var key: String = kind
		command(order_grid, key, Rules.title(key), "", func(): game.train_unit(key))
		purchase(game.context_buttons[key], key, "")
	command(order_grid, "cancel_train", "Cancel last", "", game.cancel_training)
	build_scroll = ScrollContainer.new(); build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; build_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; commands.add_child(build_scroll)
	game.construction_panel = PanelContainer.new(); build_scroll.add_child(game.construction_panel); game.construction_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.construction_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var builds := VBoxContainer.new(); builds.add_theme_constant_override("separation", 4); game.construction_panel.add_child(builds)
	game.power_preview_label = game.label(builds, "", 12, game.MINT); game.power_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; game.power_preview_label.visible = false
	var options := GridContainer.new(); options.columns = 4; options.size_flags_horizontal = Control.SIZE_EXPAND_FILL; options.add_theme_constant_override("h_separation", 6); options.add_theme_constant_override("v_separation", 6); builds.add_child(options)
	for i in range(game.BUILD_KINDS.size()):
		var kind: String = game.BUILD_KINDS[i]
		var item: Button = game.button(options, "", func(): game.choose_build(kind)); game.build_buttons[kind] = item
		purchase(item, kind, str((i + 1) % 10) if i < 10 else "")
	game.message = game.label(game.ui, "", 13, game.AMBER); game.message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	game.message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; game.message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	make_briefing(); make_help()
	ready = true; fit(); after_context()

func make_briefing() -> void:
	game.overlay = ColorRect.new(); game.overlay.color = Color(0, 0.012, 0.02, 0.89); game.overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); game.ui.add_child(game.overlay)
	var card: PanelContainer = game.panel(game.overlay); card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -300; card.offset_right = 300; card.offset_top = -275; card.offset_bottom = 275
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 14); card.add_child(content)
	game.label(content, "EXPEDITION BRIEF / PLANET NADIR", 12, game.MINT)
	game.overlay_title = game.label(content, "", 29)
	game.overlay_text = game.label(content, "", 16); game.overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; game.overlay_text.custom_minimum_size = Vector2(560, 350); game.overlay_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.overlay_button = game.button(content, "Begin expedition [Enter]", func():
		if game.ended: game.get_tree().reload_current_scene()
		else: game.begin_run())

func make_help() -> void:
	help_overlay = ColorRect.new(); help_overlay.color = Color(0, 0.01, 0.02, 0.8); help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); game.ui.add_child(help_overlay)
	var card: PanelContainer = game.panel(help_overlay); card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -280; card.offset_right = 280; card.offset_top = -240; card.offset_bottom = 240
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 12); card.add_child(content)
	game.label(content, "Controls", 22, game.MINT)
	game.label(content, "Click / drag to select - right-click to order\nShift adds selections, orders and patrol points\nWASD / arrows pan - wheel zoom - F home\nMiddle drag pans - Alt + middle drag rotates\nE explore - M mine\nQ attack move - V defend - P patrol\nB board - U unload - G escort\nR repair / reload - N auto recharge\nZ auto reload - Y relay power\nX stop - Delete destroy - Space pause\nBuild: 1-0 select, T rotates, Shift queues\nEscape cancels targeting - F1 closes help", 14)
	help_footer = game.label(content, "", 12, Color("8fa8b4"))
	var buttons := row(content, 10)
	game.button(buttons, "Close", toggle_help)
	game.button(buttons, "Restart mission", func(): game.get_tree().reload_current_scene())
	help_overlay.visible = false

func toggle_help() -> void:
	help_overlay.visible = not help_overlay.visible
	if help_overlay.visible: help_overlay.move_to_front(); help_footer.text = "Mission %02d:%02d / Seed %d" % [int(game.elapsed) / 60, int(game.elapsed) % 60, game.scenario_seed]

func show_tab(tab: String) -> void:
	active_tab = tab if tab != "build" or not game.selected_engineers().is_empty() else "orders"
	after_context()

func after_context() -> void:
	if not ready: return
	var builders: bool = not game.selected_engineers().is_empty()
	if not builders: active_tab = "orders"
	build_tab.visible = builders; build_tab.button_pressed = active_tab == "build"; order_tab.button_pressed = active_tab == "orders"
	game.command_scroll.visible = active_tab == "orders"; build_scroll.visible = active_tab == "build"
	game.construction_panel.visible = builders and active_tab == "build"
	game.command_panel.visible = not game.selected.is_empty() or not game.selected_resource.is_empty()
	for key in game.context_buttons:
		var item: Button = game.context_buttons[key]
		if Rules.UNITS.has(key):
			var factory: SimStructure = game.selected_factory()
			if factory != null and Rules.PRODUCTION[factory.kind].has(key): purchase(item, key, str(Rules.PRODUCTION[factory.kind].find(key) + 1))
			continue
		item.text = item.get_meta("short_title", item.text)
	var vehicle: SimUnit = game.selected_jeep()
	if vehicle != null: game.context_buttons.unload.text = "Unload passengers" if not vehicle.passengers.is_empty() else "Unload driver"
	var gate: SimStructure = game.selected_gate()
	if gate != null:
		game.context_buttons.gate.text = "Close gate" if gate.gate_open else "Open gate"
		game.context_buttons.gate_lock.text = "Unlock gate" if gate.gate_locked else "Lock gate"
		if gate.gate_open and not gate.powered: game.context_buttons.gate.text = "Manual close"
	for key in game.context_buttons:
		if Rules.UNITS.has(key): continue
		var item: Button = game.context_buttons[key]
		var shortcut: String = item.get_meta("shortcut", "")
		if not shortcut.is_empty():
			item.text += " [" + shortcut + "]"
			item.tooltip_text = item.text
	var turrets: Array = game.selected_turrets()
	if not turrets.is_empty(): game.context_buttons.auto_reload.button_pressed = turrets.all(func(turret): return turret.auto_reload)
	var vehicles: Array = game.selected_vehicles()
	if not vehicles.is_empty():
		game.context_buttons.recharge.button_pressed = vehicles.all(func(unit): return unit.auto_recharge)
		game.context_buttons.recharge.tooltip_text = "Automatically recharge within a powered grid [N]\n" + ("Enabled" if game.context_buttons.recharge.button_pressed else "Off or mixed selection")
	fit()

func fit() -> void:
	if not ready: return
	game.command_panel.offset_left = 18; game.command_panel.offset_right = -286; game.command_panel.offset_top = -288 if active_tab == "build" else -238; game.command_panel.offset_bottom = -18
	order_grid.columns = 4 if game.get_viewport().get_visible_rect().size.x >= 1250 else 3
	game.message.offset_left = 22; game.message.offset_right = game.get_viewport().get_visible_rect().size.x - 300; game.message.offset_top = game.command_panel.offset_top - 38; game.message.offset_bottom = game.command_panel.offset_top - 6
	if game.minimap != null: game.minimap.fit()

func update() -> void:
	material_value.text = "%d / %d" % [game.economy.minerals, game.economy.mineral_capacity]; material_value.tooltip_text = "Materials: %d / %d storage" % [game.economy.minerals, game.economy.mineral_capacity]
	methane_value.text = "%.0f / %d" % [game.economy.gas, game.economy.gas_capacity]; methane_value.tooltip_text = "Methane: %.1f / %d storage" % [game.economy.gas, game.economy.gas_capacity]
	game.objective_label.text = "Scout for extraction and the hive" if not game.mission.beacon_discovered and not game.mission.hive_discovered else "Repair extraction" if not game.mission.beacon.complete else "Find and secure the Hive Core" if not game.mission.stolen else "Extract: %.0f / %.0fs" % [game.mission.extraction, game.mission.EXTRACTION_TIME]
	game.objective_label.tooltip_text = game.mission.describe()
	game.sensors.visible = game.sensor_activity > 0 and (game.units.any(func(unit): return unit.kind == "scout" and unit.has_driver()) or game.structures.any(func(b): return b.kind == "scanner" and b.powered))
	game.sensors.text = "Movement detected"
	game.message.visible = game.notice_time > 0 and not game.message.text.is_empty()
	game.pause_button.text = "Resume [Space]" if game.paused else "Pause [Space]"
	after_context(); summarize_selection()

func summarize_selection() -> void:
	selection_grid = {}; grid_panel.visible = false
	if game.selected.size() == 1 and SimEntity.valid(game.selected[0]):
		var actor: SimEntity = game.selected[0]
		var enemy: bool = actor is SimPredator
		game.command_title.text = "Lightless " + Rules.PREDATORS[actor.kind].name if enemy else Rules.title(actor.kind)
		var maximum: float = actor.max_hp if enemy else Rules.UNITS[actor.kind].hp if actor is SimUnit else Rules.STRUCTURES[actor.kind].hp
		var lines: Array[String] = ["Health  %d / %d" % [maxi(0, int(actor.hp)), int(maximum)]]
		if actor is SimUnit:
			var order: String = game.tactical_groups.describe(actor)
			if order.is_empty(): order = game.complex_commands.describe(actor)
			lines.append(order.capitalize())
			var queued: int = actor.order_queue.size() + game.tactical_groups.queued_count(actor)
			if queued > 0: lines.append("Queued  %d" % queued)
			if actor.is_vehicle():
				lines.append("Battery  %.0f%%%s" % [actor.battery, "  charging" if actor.charging else ""])
				lines.append("Crew  %d / %d" % [actor.occupied_seats(), actor.seat_capacity()] if actor.has_driver() else "Driver required")
			if actor.cargo_total() > 0: lines.append("Cargo  %d MAT / %d CH4" % [actor.cargo, actor.gas_cargo])
		elif actor is SimStructure:
			if actor.waiting_for_clearance: lines.append("Waiting for clear space")
			elif not actor.complete: lines.append("Building  %d%%" % (actor.progress * 100))
			elif not actor.enabled: lines.append("Disabled")
			elif game.Power.is_electrical(actor.kind) and not actor.powered: lines.append("No power")
			if Rules.TURRETS.has(actor.kind) and Rules.TURRETS[actor.kind].magazine > 0:
				lines.append("Reloading  %.1fs" % actor.reload_remaining if actor.reload_remaining > 0 else "Ammo  %d / %d" % [actor.ammo, Rules.TURRETS[actor.kind].magazine])
			if not actor.queue.is_empty(): lines.append("Producing %s  %d%%\nQueued  %d" % [Rules.title(actor.queue[0]), actor.production_progress / float(Rules.UNITS[actor.queue[0]].time) * 100, actor.queue.size()])
		game.details.text = "\n".join(lines)
		selection_grid = game.power.grid_for(actor, game.structures)
		grid_panel.visible = not selection_grid.is_empty()
		if grid_panel.visible:
			grid_value.text = "Grid %d    %d / %d used\n%d spare%s" % [selection_grid.id + 1, selection_grid.used, selection_grid.capacity, maxi(0, selection_grid.capacity - selection_grid.used), " / %d needed" % selection_grid.demand if selection_grid.demand > selection_grid.used else ""]
			grid_value.tooltip_text = "This grid only\nInstalled capacity: %d\nDemand: %d\nMethane: %.2f/s" % [selection_grid.installed_capacity, selection_grid.demand, selection_grid.fuel_rate]
		elif actor is SimStructure and game.Power.is_electrical(actor.kind): game.details.text += "\nNo grid connection"
	elif game.selected.size() > 1:
		game.command_title.text = "%d selected" % game.selected.size()
		var counts: Dictionary = {}
		for actor in game.selected:
			var title: String = Rules.title(actor.kind) if not actor is SimPredator else "Lightless " + actor.kind
			counts[title] = int(counts.get(title, 0)) + 1
		var lines: Array[String] = []
		for title in counts: lines.append("%s  %d" % [title, counts[title]])
		game.details.text = "\n".join(lines)
	elif not game.selected_resource.is_empty():
		var resource: Dictionary = game.selected_resource
		game.command_title.text = "Materials patch" if resource.kind == "minerals" else "Methane patch"
		game.details.text = "Patch  %d\nField  %d" % [resource.remaining, game.resource_fields.field_remaining(game, resource)]
	else: game.command_title.text = "No selection"; game.details.text = ""
