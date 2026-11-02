extends SceneTree
var frames := 0
var view

func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	view = load("res://scenes/prototype.tscn").instantiate()
	root.add_child(view)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 8 and "--arena" in OS.get_cmdline_user_args(): view._local()
	if frames == 30:
		RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)
	return false

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var path := "res://test-results/arena.png" if "--arena" in OS.get_cmdline_user_args() else "res://test-results/configurator.png"
	root.get_texture().get_image().save_png(path)
	quit()
