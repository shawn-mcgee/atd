class_name CommandCard
extends Button

var glyph: Texture2D
var cost: Dictionary = {}
var hotkey := ""
const FONT := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
const TINTS := {"ore": Color("c8aa75"), "gas": Color("83b3ae"), "alloy": Color("a4b3bb"), "polymer": Color("b7b18a"), "crystal": Color("a4a5c9")}

func _ready() -> void:
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]: add_theme_color_override(key, Color.TRANSPARENT)
	custom_minimum_size = Vector2(108, 50)
	icon = null

func _draw() -> void:
	if toggle_mode and button_pressed:
		draw_rect(Rect2(1, 1, 4, size.y - 2), Color("c6d79a"))
	var tint := Color(0.65, 0.67, 0.59) if disabled else Color("d6d5bd")
	if glyph != null: draw_texture_rect(glyph, Rect2(9, 8, 24, 24), false, Color(0.6, 0.6, 0.6) if disabled else Color.WHITE)
	var title := text.split("\n")[0]
	draw_string(FONT, Vector2(39, 27 if hotkey != "" else 23), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 43, 12, tint)
	if hotkey != "":
		draw_rect(Rect2(size.x - 19, 3, 15, 12), Color("111d21"))
		draw_string(FONT, Vector2(size.x - 16, 13), hotkey, HORIZONTAL_ALIGNMENT_LEFT, 14, 10, Color("c9b780"))
	var x := 10.0
	for resource in cost:
		var color: Color = TINTS.get(resource, Color.WHITE)
		if disabled: color = color.darkened(0.35)
		var point := Vector2(x + 3, size.y - 10)
		if resource == "gas":
			draw_circle(point + Vector2(-2, 1), 2, color, false, 1); draw_circle(point + Vector2(2, 1), 2, color, false, 1); draw_circle(point + Vector2(0, -2), 2, color, false, 1)
		elif resource in ["alloy", "polymer"]:
			for y in [-2, 0, 2]: draw_line(point + Vector2(-3, y), point + Vector2(3, y), color, 1)
		else: draw_colored_polygon(PackedVector2Array([point + Vector2(0, -4), point + Vector2(3, 0), point + Vector2(0, 4), point + Vector2(-3, 0)]), color)
		draw_string(FONT, Vector2(x + 10, size.y - 6), str(int(cost[resource])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		x += 30
