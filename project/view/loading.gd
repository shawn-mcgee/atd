extends Control
## Small bootstrap: keep the console responsive while scene data and the core load.
const GAME_SCENE := "res://scenes/top_down.tscn"
const ConsoleTheme = preload("res://view/rts_theme.gd")
@export var initial_seed := 0
var status: Label
var progress: ProgressBar
var retry: Button
var paths: Array[String] = []
var loaded_resources: Array[Resource] = []
var scene: PackedScene
var generation_thread: Thread
var stage := "starting"
var seed_value := 0

func _ready() -> void:
	get_window().min_size = Vector2i(1100, 720)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seed_value = initial_seed if initial_seed > 0 else randi_range(1, 2147483647)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
	build_ui()
	# Let the loading console reach the screen before requesting heavy resources.
	await get_tree().process_frame
	await get_tree().process_frame
	request_resources()

func build_ui() -> void:
	var layer := CanvasLayer.new(); layer.layer = 100; add_child(layer)
	var background := ColorRect.new(); background.color = ConsoleTheme.INK
	layer.add_child(background); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme = ConsoleTheme.make()
	var center := CenterContainer.new(); background.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new(); panel.custom_minimum_size.x = 560
	panel.add_theme_stylebox_override("panel", ConsoleTheme.box(ConsoleTheme.PANEL, ConsoleTheme.EDGE, 28)); center.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 18); panel.add_child(column)
	var title := Label.new(); title.text = "AGAINST THE DARKNESS"; title.add_theme_color_override("font_color", ConsoleTheme.GOLD)
	title.add_theme_font_size_override("font_size", 26); column.add_child(title)
	var caption := Label.new(); caption.text = "FIELD COMMAND / ESTABLISHING UPLINK"
	caption.add_theme_color_override("font_color", ConsoleTheme.MUTED); column.add_child(caption)
	progress = ProgressBar.new(); progress.custom_minimum_size.y = 12; progress.show_percentage = false; column.add_child(progress)
	status = Label.new(); status.text = "Preparing expedition…"; status.custom_minimum_size.x = 500
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(status)
	var hint := Label.new(); hint.text = "Keep the lights on. Bring everyone home."; hint.add_theme_color_override("font_color", ConsoleTheme.MUTED); column.add_child(hint)
	retry = Button.new(); retry.text = "Retry loading"; ConsoleTheme.apply_button(retry); retry.visible = false
	retry.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/loading.tscn")); column.add_child(retry)

func request_resources() -> void:
	# Compile scripts on the main thread: background script compilation can leak
	# script-default RefCounted objects in this Godot version. Textures stay async.
	scene = load(GAME_SCENE)
	if scene == null:
		fail("The mission scene could not be loaded."); return
	paths.clear()
	var atlas = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/atlas.json"))
	if not atlas is Dictionary or not atlas.has("sheets"):
		fail("The sprite catalog could not be loaded."); return
	for sheet in atlas.sheets.values(): paths.append("res://assets/sprites/" + str(sheet.file))
	for path in paths:
		if ResourceLoader.load_threaded_request(path) != OK:
			fail("Could not load mission data: " + path.get_file()); return
	stage = "resources"; status.text = "Loading terrain, units and field equipment…"

func _process(_dt: float) -> void:
	if stage == "resources":
		var total := 0.0
		var complete := true
		for path in paths:
			var amount: Array = []
			var state := ResourceLoader.load_threaded_get_status(path, amount)
			if state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				fail("Could not load mission data: " + path.get_file()); return
			total += float(amount[0]) if not amount.is_empty() else 0.0
			if state != ResourceLoader.THREAD_LOAD_LOADED: complete = false
		progress.value = total / paths.size() * 100
		if complete:
			# Retrieve requests before the regular sprite loader reads the cached files.
			for path in paths:
				loaded_resources.append(ResourceLoader.load_threaded_get(path))
			stage = "world"; progress.indeterminate = true
			status.text = "Surveying terrain and preparing the expedition…"
			generation_thread = Thread.new()
			if OS.has_feature("web") or generation_thread.start(generate_world) != OK:
				generation_thread = null
				generate_on_main.call_deferred()
	elif stage == "world" and generation_thread != null and not generation_thread.is_alive():
		var world = generation_thread.wait_to_finish(); generation_thread = null
		finish(world)

func generate_world():
	# The scene-free core is owned exclusively by this worker until joined.
	var world = load("res://engine/simulation.gd").new()
	world.initialize(seed_value)
	return world

func generate_on_main() -> void:
	# Single-threaded web exports still display the console before generation.
	await get_tree().process_frame
	finish(generate_world())

func finish(world) -> void:
	if world == null:
		fail("The expedition could not be prepared."); return
	stage = "handoff"; progress.indeterminate = false; progress.value = 100
	status.text = "Opening field command…"
	await get_tree().process_frame
	var game = scene.instantiate(); game.simulation = world; game.initial_seed = seed_value
	get_tree().root.add_child(game); get_tree().current_scene = game
	# Keep the console over the HUD until terrain and light masks have rendered.
	await get_tree().process_frame
	await get_tree().process_frame
	queue_free()

func fail(message: String) -> void:
	stage = "failed"; progress.indeterminate = false
	status.text = message; retry.visible = true

func _exit_tree() -> void:
	if generation_thread != null and generation_thread.is_started():
		var world = generation_thread.wait_to_finish()
		if world != null: world.dispose()
