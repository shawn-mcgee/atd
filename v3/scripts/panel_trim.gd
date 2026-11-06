class_name PanelTrim
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var rect := Rect2(Vector2(-9, -9), size + Vector2(18, 18))
	draw_rect(rect, Color("52605a"), false, 1)
	for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var direction := Vector2(1 if p.x == rect.position.x else -1, 1 if p.y == rect.position.y else -1)
		draw_line(p, p + Vector2(direction.x * 18, 0), Color("a6a17c"), 2)
		draw_line(p, p + Vector2(0, direction.y * 9), Color("a6a17c"), 2)
		var rivet: Vector2 = p + direction * 6
		draw_circle(rivet, 1.5, Color("101b1d"))
		draw_line(rivet - Vector2(1, 0), rivet + Vector2(1, 0), Color("6b7871"), 1)
