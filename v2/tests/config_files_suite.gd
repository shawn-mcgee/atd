extends RefCounted
const ConfigFiles = preload("res://authoring/config_files.gd")
const Content = preload("res://core/content.gd")
const Canonical = preload("res://core/canonical.gd")
var checks := 0
var failures: Array[String] = []

func run() -> Dictionary:
	var content = Content.new()
	_check(content.load_file("res://content/default.json"), "split preset validates")
	var original: Dictionary = content.data.duplicate(true)
	var sources := {
		"default.json": {"imports": ["base.json", "tuning.json"], "units": {"marine": {"armor": 7}}},
		"base.json": original,
		"tuning.json": {"units": {"marine": {"hp": 123}, "hq": {"capabilities": {"factory": {"produces": ["marine"]}}}}}}
	var project = _project(sources)
	_check(project.errors.is_empty() and content.load_project(project), "imports deep-merge partial definitions before schema validation")
	_check(int(content.data.units.marine.hp) == 123 and int(content.data.units.marine.armor) == 7 and content.data.units.marine.capabilities.has("move"), "imports retain unrelated fields and main file overrides last")
	_check(content.data.units.hq.capabilities.factory.produces == ["marine"], "arrays replace rather than append")
	_check(not content.data.has("imports") and project.files.size() == 3, "merged content has no local file dependencies")
	var flat = Content.new()
	_check(flat.load_text(Canonical.text(content.data)) and flat.fingerprint() == content.fingerprint(), "flat export and imported project have identical gameplay fingerprints")
	project.files[project.root_path.get_base_dir().path_join("tuning.json")] = Canonical.text({"units": {"marine": {"hp": -1}}})
	_check(not content.load_project(project) and "tuning.json: units.marine.hp" in "\n".join(content.errors), "validation identifies the source file and affected field")
	project = _project({"default.json": {"imports": ["nested/actor.json"]}, "nested/actor.json": {"imports": ["../base.json"]}, "base.json": original})
	_check(project.errors.is_empty() and content.load_project(project), "nested imports resolve relative to their own file")
	for imports in [["missing.json"], ["../outside.json"], ["res://content/default.json"], [1], "base.json"]:
		project = _project({"default.json": {"imports": imports}})
		_check(not project.errors.is_empty(), "bad import paths and missing files are rejected")
	project = _project({"default.json": {"imports": ["cycle.json"]}, "cycle.json": {"imports": ["default.json"]}})
	_check("cycle" in "\n".join(project.errors), "import cycles have a readable error")
	project = _project({"default.json": {"imports": ["broken.json"]}, "broken.json": "{"})
	_check("broken.json: JSON line" in "\n".join(project.errors), "syntax errors retain imported filename and line")
	var deep: Dictionary = {}
	for index in 18: deep["default.json" if index == 0 else "%d.json" % index] = {"imports": ["%d.json" % (index + 1)]} if index < 17 else original
	project = _project(deep)
	_check("16 levels" in "\n".join(project.errors), "excessive import depth is bounded")
	_check(not flat.load_text('{"imports":["base.json"]}'), "network/in-memory validation cannot read unresolved local imports")
	project = _project({"default.json": {"imports": ["base.json"]}, "base.json": original, "unused.json": "{"})
	_check(content.load_project(project) and project.files.has("user://imported-config/unused.json"), "unlinked drafts survive without changing the imported match")
	_check(project.add_file("custom/overrides.json") and project.compile(), "new file is created and imported by the main file")
	project.files["user://imported-config/custom/overrides.json"] = Canonical.text({"units": {"engineer": {"hp": 21}}})
	var roundtrip = ConfigFiles.new()
	_check(roundtrip.open_text(JSON.stringify(project.project())) and content.load_project(roundtrip) and int(content.data.units.engineer.hp) == 21, "portable project roundtrip retains file layout and unsaved edits")
	_check(roundtrip.files["user://imported-config/unused.json"] == "{", "project export preserves invalid unlinked drafts verbatim")
	_save_roundtrip(original)
	return {"checks": checks, "failures": failures, "hash": content.fingerprint()}

func _project(sources: Dictionary):
	var files: Dictionary = {}
	for path in sources: files[path] = sources[path] if sources[path] is String else JSON.stringify(sources[path])
	var project = ConfigFiles.new()
	project.open_text(JSON.stringify({"format": "atd-config-project", "version": 1, "entry": "default.json", "files": files}))
	return project

func _save_roundtrip(original: Dictionary) -> void:
	var directory := "user://config-authoring-tests"
	DirAccess.make_dir_recursive_absolute(directory)
	var root := directory.path_join("default.json")
	var child := directory.path_join("base.json")
	_write(root, '{"imports":["base.json"]}')
	_write(child, Canonical.text(original))
	var project = ConfigFiles.new()
	_check(project.open_file(root), "native file graph loads from disk")
	project.files[child] = Canonical.text({"version": 1, "units": {"engineer": {"hp": 20}}})
	_check(project.save_files() and not project.dirty(child), "saving source files updates clean state")
	var reread = ConfigFiles.new()
	_check(reread.open_file(root) and int(reread.data.units.engineer.hp) == 20, "saved nested files reload with exact edits")
	project.files[child] = Canonical.text({"units": {"engineer": {"hp": 22}}})
	_write(child, '{"external_edit":true}')
	_check(not project.save_files() and "changed on disk" in "\n".join(project.errors) and FileAccess.get_file_as_string(child) == '{"external_edit":true}', "IDE changes cannot be silently overwritten")
	var virtual_project = _project({"default.json": original})
	_check(virtual_project.save_as(directory.path_join("copy.json")), "imported project can be saved to a chosen native entry file")
	var content = Content.new()
	_check(content.load_file(directory.path_join("copy.json")), "saved project entry is a directly loadable preset")

func _write(path: String, source: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source); file.close()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
