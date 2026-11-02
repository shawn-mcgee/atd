extends SceneTree
## The same measurement code is callable from the Web self-test interface.
const Probe = preload("res://tests/movement_benchmark.gd")

func _initialize() -> void:
	var result := Probe.new().run(OS.get_cmdline_user_args())
	quit(0 if result.ok else 1)
