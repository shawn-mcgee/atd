extends RefCounted
## Approved Batch 9 icons, shared with atlas preparation.
static var library = preload("res://view/sprite_library.gd").new()
static func texture(key: String) -> Texture2D:
	return library.texture("ui_" + key)
