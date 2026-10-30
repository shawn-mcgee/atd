extends PanelContainer
## Beveled steel edges and inset screw heads, kept away from panel content.
func _draw() -> void:
	var edge := size - Vector2.ONE * 2
	draw_line(Vector2(2, 2), Vector2(edge.x, 2), Color("7b8276"), 1)
	draw_line(Vector2(2, 2), Vector2(2, edge.y), Color("66746a"), 1)
	draw_line(Vector2(2, edge.y), edge, Color("080d0e"), 2)
	draw_line(Vector2(edge.x, 2), edge, Color("080d0e"), 2)
	for point in [Vector2(5, 5), Vector2(size.x - 6, 5), Vector2(5, size.y - 6), size - Vector2.ONE * 6]:
		draw_circle(point, 2, Color("0b1112"))
		draw_line(point - Vector2(1, 0), point + Vector2(1, 0), Color("7b8276"), 1)
