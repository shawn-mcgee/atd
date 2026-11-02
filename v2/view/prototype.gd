extends Node3D
## Presentation/input only. Meshes and labels never drive gameplay.
const Content = preload("res://core/content.gd")
const Session = preload("res://net/match_session.gd")
const Simulation = preload("res://core/simulation.gd")
const Transport = preload("res://net/coordinator_transport.gd")
const Hex = preload("res://core/hex_cells.gd")
const VeilOverlay = preload("res://view/veil_overlay.gd")
var session = Session.new()
var camera: Camera3D
var actors_root: Node3D
var actor_nodes: Dictionary = {}
var selected: Array = []
var accumulator := 0.0
var refresh_time := 0.0
var lobby: Control
var editor_panel: Control
var hud: Control
var editor: TextEdit
var status: Label
var lobby_players: Label
var stats: Label
var inspector: Label
var event_log: Label
var faction: OptionButton
var seed_value: SpinBox
var room: LineEdit
var endpoint: LineEdit
var ice: LineEdit
var products: OptionButton
var start_button: Button
var _catalog := ""
var _web_test_callback
var veil_overlay
var stance_choices: OptionButton
var target_hint: Label
var _target_mode := ""

func _ready() -> void:
	_build_world()
	_build_ui()
	session.status_changed.connect(func(message): status.text = message)
	session.lobby_changed.connect(_lobby_changed)
	session.match_started.connect(_started)
	status.text = "Edit content, then start a local sandbox or host/join a WebRTC lobby."
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
		"move":
			selected.clear()
			for actor in session.rollback.simulation.state.actors:
				if int(actor.owner) == session.own_id and actor.definition == "marine": selected.append(int(actor.id))
			_order({"kind": "move", "point": [0, 0, 0]})
		"lightless": faction.select(1); _local()
		"defensive":
			stance_choices.select(1)
			selected.clear()
			for actor in session.rollback.simulation.state.actors:
				if int(actor.owner) == session.own_id and actor.definition == "nest": selected.append(int(actor.id))
			_order({"kind": "veil_stance", "stance": "defensive"})
	var info := {"running": session.running, "room": session.transport.room, "players": session.roster.size(), "error": session.error, "status": status.text}
	if session.rollback != null:
		info.tick = int(session.rollback.simulation.state.tick)
		info.confirmed = session.rollback.confirmed_tick
		info.hashes = session.rollback.hashes
	JavaScriptBridge.eval("window.atdLiveState = " + JSON.stringify(info))

func _process(dt: float) -> void:
	session.poll()
	if session.rollback == null: return
	if session.running:
		var tick := 1.0 / float(session.rollback.simulation.content.settings.tick_hz)
		accumulator = minf(accumulator + dt, tick * 4)
		while accumulator >= tick:
			if not session.advance(): break
			accumulator -= tick
		var pan := Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_up", "ui_down"))
		if not get_viewport().gui_get_focus_owner() is LineEdit:
			pan += Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0,
				float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		camera.position += pan * dt * camera.size * 0.5
	_sync_meshes()
	refresh_time += dt
	if refresh_time >= 0.2:
		refresh_time = 0
		_refresh_hud()

func _build_world() -> void:
	RenderingServer.set_default_clear_color(Color("101820"))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101820")
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
	veil_overlay = VeilOverlay.new()
	add_child(veil_overlay)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var frame := PanelContainer.new()
	frame.position = Vector2(20, 20)
	frame.size = Vector2(430, 700)
	canvas.add_child(frame)
	lobby = frame
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)
	_label(box, "AGAINST THE DARKNESS · CORE LAB", 22)
	_label(box, "Primitive meshes · orthographic view · rollback", 14)
	faction = OptionButton.new()
	faction.add_item("Human expedition"); faction.add_item("Lightless")
	box.add_child(faction)
	seed_value = SpinBox.new()
	seed_value.min_value = 0; seed_value.max_value = 2147483647; seed_value.value = 42
	box.add_child(seed_value)
	_button(box, "Start local sandbox", _local)
	endpoint = LineEdit.new()
	endpoint.text = Transport.DEFAULT_URL
	box.add_child(endpoint)
	room = LineEdit.new()
	room.placeholder_text = "Room code (blank creates one when hosting)"
	box.add_child(room)
	ice = LineEdit.new()
	ice.text = '[{"urls":["stun:stun.l.google.com:19302"]}]'
	ice.tooltip_text = "ICE servers as JSON. Add TURN URLs, username and credential for restrictive networks."
	box.add_child(ice)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_button(buttons, "Host room", func(): _connect(true))
	_button(buttons, "Join room", func(): _connect(false))
	start_button = _button(box, "Start network match (host)", _start_network)
	start_button.disabled = true
	_button(box, "Reconnect signaling", func(): session.transport.reconnect_signaling())
	_button(box, "Disconnect / reset lobby", _reset)
	lobby_players = _label(box, "", 14)
	status = _label(box, "", 14)
	status.custom_minimum_size.x = 410
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(box, "Sandbox: move, attack, production, Veil and stances.\nMission and full faction economies follow later.", 14)
	editor_panel = PanelContainer.new()
	editor_panel.position = Vector2(470, 20)
	editor_panel.size = Vector2(790, 740)
	canvas.add_child(editor_panel)
	var edit_box := VBoxContainer.new()
	editor_panel.add_child(edit_box)
	_label(edit_box, "CONTENT DEFINITIONS · JSON", 20)
	_label(edit_box, "Compose capabilities; visual.shape selects a 3D primitive.", 14)
	var code_editor := CodeEdit.new()
	code_editor.gutters_draw_line_numbers = true
	editor = code_editor
	editor.custom_minimum_size = Vector2(770, 640)
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.text = JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string("res://content/default.json")), "  ", true)
	var highlighter := CodeHighlighter.new()
	highlighter.number_color = Color("9bd5b1")
	highlighter.add_color_region('"', '"', Color("e6cb86"))
	editor.syntax_highlighter = highlighter
	edit_box.add_child(editor)
	var edit_buttons := HBoxContainer.new()
	edit_box.add_child(edit_buttons)
	_button(edit_buttons, "Validate", func():
		var content = _content()
		if content != null: status.text = "Valid content · " + content.fingerprint().left(16))
	_button(edit_buttons, "Reset defaults", func(): editor.text = FileAccess.get_file_as_string("res://content/default.json"))
	_button(edit_buttons, "Save preset", _save_preset)
	_button(edit_buttons, "Load preset", _load_preset)
	hud = PanelContainer.new()
	hud.position = Vector2(16, 16)
	hud.custom_minimum_size = Vector2(390, 760)
	canvas.add_child(hud)
	var hud_scroll := ScrollContainer.new()
	hud_scroll.custom_minimum_size = Vector2(390, 760)
	hud_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud.add_child(hud_scroll)
	var hud_box := VBoxContainer.new()
	hud_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_scroll.add_child(hud_box)
	stats = _label(hud_box, "", 15)
	inspector = _label(hud_box, "", 14)
	products = OptionButton.new()
	hud_box.add_child(products)
	_button(hud_box, "Produce selected type", _train)
	_button(hud_box, "Stop selected", func(): _order({"kind": "stop"}))
	_button(hud_box, "Focus own base", _focus_base)
	var overlays := HBoxContainer.new()
	hud_box.add_child(overlays)
	_checkbox(overlays, "Veil", true, func(value): veil_overlay.show_veil = value)
	_checkbox(overlays, "Connection", true, func(value): veil_overlay.show_links = value)
	var senses := HBoxContainer.new()
	hud_box.add_child(senses)
	_checkbox(senses, "Light", false, func(value): veil_overlay.show_illumination = value)
	_checkbox(senses, "Perception", false, func(value): veil_overlay.show_perception = value)
	stance_choices = OptionButton.new()
	for label in ["Neutral", "Defensive", "Offensive"]: stance_choices.add_item(label)
	hud_box.add_child(stance_choices)
	_button(hud_box, "Set connected Veil stance", _set_veil_stance)
	_button(hud_box, "Attack Veil [Q]", func():
		_target_mode = "attack_veil"
		target_hint.text = "Choose visible enemy Veil. Escape cancels.")
	target_hint = _label(hud_box, "", 13)
	event_log = _label(hud_box, "", 13)
	_label(hud_box, "Left click: select · Shift: add\nRight click: move / attack\nWASD/arrows: pan · wheel: zoom", 13)
	_button(hud_box, "Return to configurator", _reset)
	hud.hide()

func _content():
	var content = Content.new()
	if not content.load_text(editor.text):
		status.text = "\n".join(content.errors.slice(0, 8))
		return null
	return content

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
	var lines: Array[String] = ["Room: " + session.transport.room]
	for player in players: lines.append("%d · %s · %s" % [player.id, player.faction, player.controller])
	lobby_players.text = "\n".join(lines)
	room.text = session.transport.room
	start_button.disabled = not session.transport.hosting

func _started() -> void:
	lobby.hide(); editor_panel.hide(); hud.show()
	accumulator = 0
	selected.clear()
	_catalog = ""
	_target_mode = ""
	target_hint.text = ""
	event_log.text = ""
	session.rollback.events_confirmed.connect(_confirmed_events)
	_grid(int(session.rollback.simulation.content.settings.map_radius))
	_focus_base()

func _focus_base() -> void:
	for actor in session.rollback.simulation.state.actors:
		if int(actor.owner) == session.own_id and actor.definition in ["hq", "nest"]:
			var point := _world(actor.position)
			camera.position = Vector3(point.x + 5, 40, point.z)
			return

func _reset() -> void:
	session.close()
	selected.clear()
	for child in actors_root.get_children(): child.queue_free()
	actor_nodes.clear()
	veil_overlay.clear()
	_target_mode = ""
	for name in ["Grid", "Orders"]:
		var node := get_node_or_null(name)
		if node != null: remove_child(node); node.queue_free()
	lobby.show(); editor_panel.show(); hud.hide()
	start_button.disabled = true
	faction.disabled = false
	lobby_players.text = ""
	status.text = "Ready for a new session."

func _save_preset() -> void:
	if _content() == null: return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(editor.text.to_utf8_buffer(), "atd-content.json", "application/json")
	else:
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.filters = PackedStringArray(["*.json ; Content preset"])
		dialog.current_file = "atd-content.json"
		add_child(dialog)
		dialog.file_selected.connect(func(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_string(editor.text)
			dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered(Vector2i(800, 600))

func _load_preset() -> void:
	if OS.has_feature("web"):
		status.text = "Paste a JSON preset into the editor, then Validate."; return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; Content preset"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		editor.text = FileAccess.get_file_as_string(path)
		_content()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(800, 600))

func _faction() -> String:
	return "human" if faction.selected == 0 else "lightless"

func _sync_meshes() -> void:
	var simulation = session.rollback.simulation
	var alive: Dictionary = {}
	for actor in simulation.state.actors:
		var id := int(actor.id)
		alive[id] = true
		if not actor_nodes.has(id): actor_nodes[id] = _actor_node(actor, simulation.content.units[actor.definition])
		var node: Node3D = actor_nodes[id]
		node.visible = simulation.visible_to(session.own_id, actor) == 2
		node.position = _world(actor.position)
		node.get_node("Selection").visible = selected.has(id)
		if node.has_node("WeaponRange"): node.get_node("WeaponRange").visible = selected.has(id) and int(actor.owner) == session.own_id
		var definition: Dictionary = simulation.content.units[actor.definition]
		var label: Label3D = node.get_node("Label")
		label.visible = selected.has(id) or definition.capabilities.has("factory") or int(actor.hp) < int(definition.hp)
		label.text = "%s · P%d" % [definition.name, actor.owner]
		if selected.has(id) or int(actor.hp) < int(definition.hp): label.text += "\n%d HP" % actor.hp
	for id in actor_nodes.keys():
		if not alive.has(id): actor_nodes[id].queue_free(); actor_nodes.erase(id); selected.erase(id)
	_sync_orders(simulation)
	veil_overlay.refresh(simulation, session.own_id, selected)

func _confirmed_events(events: Array) -> void:
	for event in events:
		if event.type == "veil_alert":
			if int(event.owner) != session.own_id: continue
			var cell := Hex.from_point(event.point)
			event_log.text = "Veil N%d: %s at %d,%d\n%d connected recipients" % [event.network, event.reason, cell[0], cell[1], event.recipients.size()]
		elif event.type == "attack":
			var simulation = session.rollback.simulation
			var source = simulation.entity(int(event.source))
			var target = simulation.entity(int(event.target))
			if (source != null and simulation.visible_to(session.own_id, source) == 2) or (target != null and simulation.visible_to(session.own_id, target) == 2):
				event_log.text = "Confirmed: %s dealt %s damage" % [event.source, event.amount]

func _sync_orders(simulation) -> void:
	var old := get_node_or_null("Orders")
	if old != null: remove_child(old); old.queue_free()
	var mesh := ImmediateMesh.new()
	var lines: Array = []
	for id in selected:
		var actor = simulation.entity(int(id))
		if actor == null or int(actor.owner) != session.own_id: continue
		if actor.order.get("kind") in ["move", "attack_veil"]: lines.append([actor.position, actor.order.point])
		elif actor.order.get("kind") == "attack":
			var target = simulation.entity(int(actor.order.target))
			if target != null and simulation.visible_to(session.own_id, target) == 2: lines.append([actor.position, target.position])
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
	var instance := MeshInstance3D.new()
	var size := 1.3 if definition.capabilities.has("factory") else 0.65
	match definition.visual.shape:
		"box":
			var mesh := BoxMesh.new(); mesh.size = Vector3(size, size, size); instance.mesh = mesh
		"sphere":
			var mesh := SphereMesh.new(); mesh.radius = size * 0.5; mesh.height = size; instance.mesh = mesh
		"capsule":
			var mesh := CapsuleMesh.new(); mesh.radius = size * 0.35; mesh.height = size; instance.mesh = mesh
		"prism":
			var mesh := PrismMesh.new(); mesh.size = Vector3(size, size, size); instance.mesh = mesh
		_:
			var mesh := CylinderMesh.new(); mesh.top_radius = size * 0.5; mesh.bottom_radius = size * 0.5; mesh.height = size; instance.mesh = mesh
	instance.position.y = size * 0.5
	instance.material_override = _material(Color(definition.visual.color))
	node.add_child(instance)
	var label := Label3D.new()
	label.name = "Label"; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, size + 0.5, -0.9 - size * 0.5)
	label.font_size = 36; label.pixel_size = 0.018; label.outline_size = 4
	label.no_depth_test = true
	node.add_child(label)
	var ring := _ring(size * 0.8, Color("efdf86"))
	ring.name = "Selection"; ring.position.y = 0.05
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
	stats.text = "P%d · %s\nTick %d · confirmed %d\nRollbacks %d · replayed ticks %d\nBank %d · hash %s" % [session.own_id, _faction(), simulation.state.tick,
		rollback.confirmed_tick, rollback.rollbacks, rollback.replayed_ticks, simulation.state.banks.get(str(session.own_id), 0), simulation.state_hash().left(12)]
	if not session.error.is_empty(): stats.text += "\nSTOPPED: " + session.error
	elif int(simulation.state.tick) - rollback.confirmed_tick > rollback.window: stats.text += "\nWaiting for peer inputs…"
	var actor = simulation.entity(int(selected[0])) if not selected.is_empty() else null
	products.disabled = true
	if actor == null:
		inspector.text = "Select a unit or factory."
		return
	var definition: Dictionary = simulation.content.units[actor.definition]
	inspector.text = "%s · owner %d\nHP %d/%d · armor %d\nOrder: %s\nProduction queue: %d" % [definition.name, actor.owner, actor.hp, definition.hp, definition.armor, actor.order.get("kind", "idle"), actor.production.size()]
	if int(actor.owner) == session.own_id:
		inspector.text += "\nVeil link: " + ("connected" if not actor.veil_networks.is_empty() else "disconnected")
		if definition.capabilities.has("move"): inspector.text += " · " + str(actor.veil_stance.mode)
		if not actor.veil_networks.is_empty():
			var network: Dictionary = simulation.state.veil.networks[str(actor.veil_networks[0])]
			inspector.text += "\nGlobal Veil: %s · %d tiles" % [network.stance, network.cells.size()]
	if definition.capabilities.has("weapon"):
		inspector.text += "\nDamage %d · range %s" % [definition.capabilities.weapon.damage, definition.capabilities.weapon.range]
	if int(actor.owner) == session.own_id and definition.capabilities.has("factory"):
		var key: String = actor.definition
		if key != _catalog:
			products.clear()
			for type in definition.capabilities.factory.produces:
				products.add_item("%s · %d" % [simulation.content.units[type].name, simulation.content.units[type].cost])
				products.set_item_metadata(products.item_count - 1, type)
			_catalog = key
		products.disabled = false

func _unhandled_input(event: InputEvent) -> void:
	if session.rollback == null or not session.running: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			_target_mode = "attack_veil"
			target_hint.text = "Choose visible enemy Veil. Escape cancels."
		elif event.physical_keycode == KEY_ESCAPE:
			_target_mode = ""; target_hint.text = ""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 10, 90)
			return
		if not _target_mode.is_empty() and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var point := _ground_point(event.position)
			if point.is_empty(): return
			if _target_mode == "attack_veil": _order({"kind": "attack_veil", "point": Hex.point(Hex.from_point(point))})
			else: _order({"kind": "veil_stance", "stance": "offensive", "point": point})
			_target_mode = ""; target_hint.text = ""
			return
		var id := _pick(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.shift_pressed: selected.clear()
			if id != 0 and not selected.has(id): selected.append(id)
			_refresh_hud()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var actor = session.rollback.simulation.entity(id)
			if actor != null and int(actor.owner) != session.own_id: _order({"kind": "attack", "target": id})
			else:
				var point := _ground_point(event.position)
				if not point.is_empty(): _order({"kind": "move", "point": point})

func _ground_point(screen: Vector2) -> Array:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null: return []
	var r := float(point.z) / 1.5
	var q := float(point.x) / sqrt(3.0) - r * 0.5
	return [int(round(q * Simulation.SCALE)), 0, int(round(r * Simulation.SCALE))]

func _set_veil_stance() -> void:
	var mode: String = ["neutral", "defensive", "offensive"][stance_choices.selected]
	var connected := false
	for id in selected:
		var actor = session.rollback.simulation.entity(int(id))
		if actor != null and int(actor.owner) == session.own_id and not actor.veil_networks.is_empty(): connected = true
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
	command.actors = selected.duplicate()
	session.rollback.queue(command)

func _train() -> void:
	if products.disabled or products.selected < 0: return
	_order({"kind": "train", "definition": products.get_item_metadata(products.selected)})

func _pick(screen: Vector2) -> int:
	var best := 0
	var nearest := 28.0
	for id in actor_nodes:
		var node: Node3D = actor_nodes[id]
		if not node.visible: continue
		var distance := camera.unproject_position(node.position).distance_to(screen)
		if distance < nearest: nearest = distance; best = int(id)
	return best

func _grid(radius: int) -> void:
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
	instance.name = "Grid"; instance.mesh = mesh; instance.material_override = _material(Color("263642"), true)
	add_child(instance)

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
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text; button.pressed.connect(action)
	parent.add_child(button)
	return button

func _checkbox(parent: Node, text: String, value: bool, action: Callable) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = text; checkbox.button_pressed = value; checkbox.toggled.connect(action)
	parent.add_child(checkbox)

func _exit_tree() -> void:
	session.close()
