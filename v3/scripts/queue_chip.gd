class_name QueueChip
extends Button

var glyph: Texture2D
var progress_label := "0%"
var progress_ratio := 0.0
const FONT := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")

func _ready() -> void:
	custom_minimum_size = Vector2(46, 44)
	var normal := StyleBoxFlat.new(); normal.bg_color = Color("172522"); normal.border_color = Color("48584d"); normal.set_border_width_all(1)
	add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat; hover.border_color = Color("c5b78d"); hover.bg_color = Color("2c3931")
	add_theme_stylebox_override("hover", hover)

func _draw() -> void:
	if glyph != null: draw_texture_rect(glyph, Rect2(12, 4, 22, 22), false)
	draw_string(FONT, Vector2(6, 39), progress_label, HORIZONTAL_ALIGNMENT_LEFT, 38, 11, Color("b6c9a7") if progress_label == "READY" else Color("d2c19a"))
	draw_line(Vector2(size.x - 8, 4), Vector2(size.x - 4, 8), Color("8d9a8b"), 1)
	draw_line(Vector2(size.x - 8, 8), Vector2(size.x - 4, 4), Color("8d9a8b"), 1)
	draw_rect(Rect2(3, size.y - 3, size.x - 6, 2), Color("33463a"))
	draw_rect(Rect2(3, size.y - 3, (size.x - 6) * clampf(progress_ratio, 0, 1), 2), Color("c6b584"))
