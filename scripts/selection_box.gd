extends Control
var rectangle := Rect2()
var active := false
func _draw() -> void:
	if active:
		draw_rect(rectangle, Color(0.4, 0.95, 0.8, 0.1))
		draw_rect(rectangle, Color("7bf4d0"), false, 1.0)
