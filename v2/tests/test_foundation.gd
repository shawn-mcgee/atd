extends SceneTree
const Suite = preload("res://tests/foundation_suite.gd")

func _initialize() -> void:
	var result: Dictionary = Suite.new().run()
	print("ATD_RESULT " + JSON.stringify(result))
	quit(0 if result.ok else 1)
