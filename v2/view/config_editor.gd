extends VBoxContainer
signal message_changed(message: String)
const ConfigFiles = preload("res://authoring/config_files.gd")
const Content = preload("res://core/content.gd")
var workspace = ConfigFiles.new()
var editor: CodeEdit
var file_tree: Tree
var filter: LineEdit
var file_label: Label
var active_file := ""
var _switching := false
var _items: Dictionary = {}
var _positions: Dictionary = {}
var _upload_callback

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_label = Label.new(); add_child(file_label)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 210
	add_child(split)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 200
	split.add_child(navigation)
	filter = LineEdit.new(); filter.placeholder_text = "Find file or definition…"
	filter.text_changed.connect(func(_text): _refresh_tree())
	navigation.add_child(filter)
	var new_file := Button.new(); new_file.text = "New imported file"
	new_file.pressed.connect(_new_file_dialog); navigation.add_child(new_file)
	file_tree = Tree.new(); file_tree.hide_root = true
	file_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_tree.item_selected.connect(_file_selected)
	navigation.add_child(file_tree)
	editor = CodeEdit.new()
	editor.gutters_draw_line_numbers = true
	editor.custom_minimum_size = Vector2(300, 240)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var highlighter := CodeHighlighter.new()
	highlighter.symbol_color = editor.get_theme_color("font_color")
	highlighter.number_color = Color("9bd5b1")
	highlighter.add_color_region('"', '"', Color("e6cb86"))
	editor.syntax_highlighter = highlighter
	editor.text_changed.connect(_edited)
	split.add_child(editor)
	reset_defaults()

func reset_defaults() -> void:
	open_file("res://content/default.json")

func open_file(path: String) -> void:
	var next = ConfigFiles.new()
	next.open_file(path)
	_adopt(next)

func load_text(source: String) -> void:
	var next = ConfigFiles.new()
	next.open_text(source)
	_adopt(next)

func _adopt(next) -> void:
	if not next.files.has(next.root_path): message_changed.emit("\n".join(next.errors)); return
	workspace = next; active_file = ""; _positions.clear()
	filter.text = ""
	_show_file(workspace.root_path)
	_refresh_tree()
	message_changed.emit("Loaded %d configuration files" % workspace.files.size() if workspace.errors.is_empty() else "\n".join(workspace.errors))

func _flush() -> void:
	if active_file.is_empty(): return
	workspace.files[active_file] = editor.text
	_positions[active_file] = {"line": editor.get_caret_line(), "column": editor.get_caret_column(), "scroll": editor.scroll_vertical}

func _edited() -> void:
	if _switching or active_file.is_empty(): return
	workspace.files[active_file] = editor.text
	file_label.text = workspace.relative_path(active_file) + (" · modified" if workspace.dirty(active_file) else "")
	if _items.has(active_file): _items[active_file].set_text(0, _file_name(active_file))

func _show_file(path: String) -> void:
	_flush()
	if not workspace.files.has(path): return
	_switching = true
	active_file = path
	editor.text = workspace.files[path]
	var position: Dictionary = _positions.get(path, {})
	editor.set_caret_line(int(position.get("line", 0)))
	editor.set_caret_column(int(position.get("column", 0)))
	editor.scroll_vertical = float(position.get("scroll", 0))
	_switching = false
	_edited()

func _file_selected() -> void:
	if _switching: return
	var selected := file_tree.get_selected()
	if selected != null and selected.get_metadata(0) is String: _show_file(selected.get_metadata(0))

func _file_name(path: String) -> String:
	return ("* " if workspace.dirty(path) else "") + path.get_file() + (" (main)" if path == workspace.root_path else "") + (" [unlinked]" if not path in workspace.imported else "")

func _refresh_tree() -> void:
	if file_tree == null: return
	_switching = true
	file_tree.clear(); _items.clear()
	var root := file_tree.create_item()
	var folders := {"": root}
	var paths: Array = workspace.files.keys(); paths.sort()
	paths.erase(workspace.root_path); paths.push_front(workspace.root_path)
	var query := filter.text.strip_edges().to_lower()
	for path in paths:
		if not workspace.files.has(path): continue
		var relative: String = workspace.relative_path(path)
		if not query.is_empty() and not query in relative.to_lower() and not query in str(workspace.files[path]).to_lower(): continue
		var directory := ""
		var parent: TreeItem = root
		var parts := relative.split("/")
		for index in parts.size() - 1:
			directory += parts[index] + "/"
			if not folders.has(directory):
				var folder := file_tree.create_item(parent)
				folder.set_text(0, parts[index]); folder.set_selectable(0, false)
				folders[directory] = folder
			parent = folders[directory]
		var item := file_tree.create_item(parent)
		item.set_text(0, _file_name(path)); item.set_metadata(0, path); item.set_tooltip_text(0, relative)
		_items[path] = item
		if path == active_file: item.select(0)
	_switching = false

func validate_content():
	_flush()
	var content = Content.new()
	var valid: bool = content.load_project(workspace)
	_refresh_tree()
	if not valid:
		message_changed.emit("\n".join(content.errors.slice(0, 8)))
		return null
	message_changed.emit("Valid content · %d files · %s" % [workspace.imported.size(), content.fingerprint().left(16)])
	return content

func _new_file_dialog() -> void:
	var dialog := ConfirmationDialog.new(); dialog.title = "New imported JSON file"
	var path := LineEdit.new(); path.placeholder_text = "human/units/new_unit.json"; path.custom_minimum_size.x = 400
	dialog.add_child(path); add_child(dialog)
	dialog.confirmed.connect(func():
		new_file(path.text.strip_edges())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(); path.grab_focus()

func new_file(relative: String) -> bool:
	_flush()
	if not workspace.add_file(relative): message_changed.emit("\n".join(workspace.errors)); return false
	workspace.compile()
	# The main buffer was changed by add_file; do not flush its old editor text over it.
	active_file = ""
	_show_file(workspace.root_path.get_base_dir().path_join(relative).simplify_path())
	_refresh_tree()
	return true

func save_files() -> void:
	_flush()
	if OS.has_feature("web"): export_project(); return
	if workspace.virtual:
		var dialog := _dialog(FileDialog.FILE_MODE_SAVE_FILE, workspace.root_path.get_file())
		dialog.file_selected.connect(func(path):
			if workspace.save_as(path): active_file = ""; _show_file(workspace.root_path); _refresh_tree(); message_changed.emit("Saved project files")
			else: message_changed.emit("\n".join(workspace.errors))
			dialog.queue_free())
		return
	if workspace.save_files(): _edited(); _refresh_tree(); message_changed.emit("Saved project files")
	else: message_changed.emit("\n".join(workspace.errors))

func export_project() -> void:
	_flush()
	_export(JSON.stringify(workspace.project(), "  ", false), "atd-project.json")

func export_merged() -> void:
	var content = validate_content()
	if content != null: _export(JSON.stringify(content.data, "  ", true), "atd-content.json")

func _export(source: String, filename: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(source.to_utf8_buffer(), filename, "application/json")
		return
	var dialog := _dialog(FileDialog.FILE_MODE_SAVE_FILE, filename)
	dialog.file_selected.connect(func(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: message_changed.emit("Cannot write " + path)
		else: file.store_string(source); message_changed.emit("Exported " + path)
		dialog.queue_free())

func load_dialog() -> void:
	if OS.has_feature("web"):
		if _upload_callback == null:
			_upload_callback = JavaScriptBridge.create_callback(func(arguments): load_text(str(arguments[0])))
			JavaScriptBridge.get_interface("window").atdConfigUpload = _upload_callback
		JavaScriptBridge.eval("""(() => {
const input = document.createElement('input'); input.type = 'file'; input.accept = '.json,application/json';
input.onchange = async () => { if (input.files.length) window.atdConfigUpload(await input.files[0].text()); };
input.click();
})()""")
		return
	var dialog := _dialog(FileDialog.FILE_MODE_OPEN_FILE)
	dialog.file_selected.connect(func(path): open_file(path); dialog.queue_free())

func _dialog(mode: int, filename: String = "") -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.json ; Configuration JSON"])
	dialog.current_file = filename
	add_child(dialog); dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(800, 600))
	return dialog
