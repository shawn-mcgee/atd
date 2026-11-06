extends RefCounted
## Authoring buffers and deterministic import resolution; simulations receive only data.
const MAX_FILES := 128
const MAX_BYTES := 2097152
var root_path := ""
var files: Dictionary = {}
var saved: Dictionary = {}
var origins: Dictionary = {}
var data: Dictionary = {}
var errors: Array[String] = []
var imported: Array[String] = []
var virtual := false
var _bytes := 0
var _parsed: Dictionary = {}

func open_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: errors.assign([path + ": cannot read file"]); return false
	var text := file.get_as_text(); file.close()
	var document = JSON.parse_string(text)
	if document is Dictionary and document.get("format") == "atd-config-project": return open_text(text)
	root_path = path.simplify_path()
	files.clear(); saved.clear(); virtual = false
	files[root_path] = text; saved[root_path] = text
	return compile()

func open_text(text: String) -> bool:
	var document = JSON.parse_string(text)
	errors.clear()
	var buffers: Dictionary = {}
	var entry := "default.json"
	if document is Dictionary and document.get("format") == "atd-config-project":
		if document.get("version") != 1 or not document.get("files") is Dictionary or not document.get("entry") is String:
			errors.append("project: expected version 1, entry and files"); return false
		entry = document.entry
		if entry != entry.get_file() or not entry.ends_with(".json") or document.files.is_empty() or document.files.size() > MAX_FILES:
			errors.append("project: invalid entry or file count"); return false
		for relative in document.files:
			if not relative is String or not document.files[relative] is String or not _relative(relative):
				errors.append("project.files: expected relative JSON paths and text"); return false
			buffers["user://imported-config/".path_join(relative).simplify_path()] = document.files[relative]
	else: buffers["user://imported-config/default.json"] = text
	var next_root := "user://imported-config/".path_join(entry)
	if not buffers.has(next_root): errors.append("project: entry file is missing"); return false
	var size := 0
	for source in buffers.values(): size += str(source).to_utf8_buffer().size()
	if size > MAX_BYTES: errors.append("project: text exceeds 2 MB"); return false
	root_path = next_root
	files = buffers; saved.clear(); virtual = true
	return compile()

func compile() -> bool:
	errors.clear(); origins.clear(); data.clear(); imported.clear(); _parsed.clear(); _bytes = 0
	if root_path.is_empty(): errors.append("project: select a main JSON file"); return false
	_apply_file(root_path, [])
	return errors.is_empty()

func _apply_file(path: String, stack: Array) -> void:
	if stack.has(path): errors.append("%s: import cycle: %s" % [relative_path(path), " -> ".join(stack + [path])]); return
	if stack.size() >= 16: errors.append(relative_path(path) + ": imports exceed 16 levels"); return
	if not _parsed.has(path):
		if imported.size() >= MAX_FILES: errors.append("project: maximum 128 imported files"); return
		if not files.has(path):
			if virtual: errors.append(relative_path(path) + ": imported file not found"); return
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null: errors.append(relative_path(path) + ": imported file not found"); return
			files[path] = file.get_as_text(); file.close()
			saved[path] = files[path]
		_bytes += str(files[path]).to_utf8_buffer().size()
		if _bytes > MAX_BYTES: errors.append("project: imported text exceeds 2 MB"); return
		var parser := JSON.new()
		if parser.parse(files[path]) != OK:
			errors.append("%s: JSON line %d: %s" % [relative_path(path), parser.get_error_line(), parser.get_error_message()]); return
		if not parser.data is Dictionary: errors.append(relative_path(path) + ": expected an object"); return
		_parsed[path] = parser.data
		imported.append(path)
	var document: Dictionary = _parsed[path]
	var imports = document.get("imports", [])
	if not imports is Array: errors.append(relative_path(path) + ".imports: expected an array of relative JSON paths"); return
	for index in imports.size():
		var relative = imports[index]
		if not relative is String or not _relative(relative, true):
			errors.append("%s.imports[%d]: expected a relative JSON path" % [relative_path(path), index]); continue
		var target := path.get_base_dir().path_join(relative).simplify_path()
		if not target.begins_with(root_path.get_base_dir() + "/"):
			errors.append("%s.imports[%d]: path leaves the project directory" % [relative_path(path), index]); continue
		_apply_file(target, stack + [path])
	var patch: Dictionary = document.duplicate(true)
	patch.erase("imports")
	_merge(data, patch, path, "")

func _merge(into: Dictionary, patch: Dictionary, source: String, prefix: String) -> void:
	for key in patch:
		var field := prefix + str(key)
		origins[field] = source
		if patch[key] is Dictionary:
			if not into.get(key) is Dictionary: into[key] = {}
			_merge(into[key], patch[key], source, field + ".")
		else: into[key] = patch[key].duplicate(true) if patch[key] is Array else patch[key]

func error_file(message: String) -> String:
	var field := message.split(": ", true, 1)[0]
	while not field.is_empty():
		if origins.has(field): return str(origins[field])
		var dot := field.rfind(".")
		field = field.substr(0, dot) if dot >= 0 else ""
	return root_path

func relative_path(path: String) -> String:
	return path.trim_prefix(root_path.get_base_dir() + "/")

func dirty(path: String) -> bool:
	return not saved.has(path) or files[path] != saved[path]

func add_file(relative: String) -> bool:
	errors.clear()
	if not _relative(relative): errors.append("new file: use a relative JSON path inside the project"); return false
	var path := root_path.get_base_dir().path_join(relative).simplify_path()
	if files.has(path) or (not virtual and FileAccess.file_exists(path)): errors.append("new file: path already exists"); return false
	if files.size() >= MAX_FILES: errors.append("project: maximum 128 files"); return false
	var document = JSON.parse_string(files[root_path])
	if not document is Dictionary or not document.get("imports", []) is Array:
		errors.append("new file: fix the main file's JSON/imports first"); return false
	var imports: Array = document.get("imports", []).duplicate()
	imports.append(relative)
	document.imports = imports
	files[root_path] = JSON.stringify(document, "  ", false) + "\n"
	files[path] = "{}\n"
	return true

func project() -> Dictionary:
	var buffers: Dictionary = {}
	var paths: Array = files.keys(); paths.sort()
	for path in paths: buffers[relative_path(path)] = files[path]
	return {"format": "atd-config-project", "version": 1, "entry": root_path.get_file(), "files": buffers}

func save_files() -> bool:
	errors.clear()
	if virtual: errors.append("project: choose a destination for these imported files"); return false
	var paths: Array = files.keys()
	paths.sort_custom(func(a, b): return a != root_path if a == root_path or b == root_path else a < b)
	# Check all conflicts before writing any file, including edits made in the IDE.
	for path in paths:
		if not dirty(path): continue
		if FileAccess.file_exists(path) and (not saved.has(path) or FileAccess.get_file_as_string(path) != saved[path]):
			errors.append(relative_path(path) + ": changed on disk; reload or export before saving")
	if not errors.is_empty(): return false
	for path in paths:
		if not dirty(path): continue
		var result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if result != OK: errors.append(relative_path(path) + ": cannot create directory"); continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: errors.append(relative_path(path) + ": cannot write file"); continue
		file.store_string(files[path]); file.close()
		saved[path] = files[path]
	return errors.is_empty()

func save_as(path: String) -> bool:
	var next = get_script().new()
	next.root_path = path.simplify_path()
	for old in files:
		var target: String = next.root_path if old == root_path else next.root_path.get_base_dir().path_join(relative_path(old))
		next.files[target] = files[old]
		if FileAccess.file_exists(target) and (old == root_path or FileAccess.get_file_as_string(target) == files[old]): next.saved[target] = FileAccess.get_file_as_string(target)
	if not next.save_files(): errors.assign(next.errors); return false
	root_path = next.root_path; files = next.files; saved = next.saved; virtual = false
	return true

static func _relative(path: String, parents: bool = false) -> bool:
	return not path.is_empty() and not path.is_absolute_path() and not ":" in path and not "\\" in path and path.ends_with(".json") and (parents or not ".." in path.split("/"))
