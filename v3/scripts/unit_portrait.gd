class_name UnitPortrait
extends Control

var kind := ""
var serial := 0
var group_size := 0
var structure := false
var vehicle_glyph: Texture2D
const FONT := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")

func _ready() -> void:
	custom_minimum_size = Vector2(86, 112)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := Rect2(0, 0, 78, 94)
	draw_rect(r, Color("121e23"))
	for y in range(8, 90, 6): draw_line(Vector2(5, y), Vector2(73, y), Color(0.5, 0.6, 0.57, 0.035), 1)
	var tint := Color("caad76") if kind == "engineer" else Color("93b8c7")
	if kind == "":
		draw_arc(Vector2(39, 44), 20, 0, TAU, 32, Color("536663"), 1, true)
		draw_line(Vector2(20, 44), Vector2(58, 44), Color("536663"), 1, true)
		draw_line(Vector2(39, 25), Vector2(39, 63), Color("536663"), 1, true)
	elif kind in ["scout", "ranger", "excavator", "reaper", "cremator", "javelin", "radar", "rampart"]:
		vehicle_glyph = CommandSkin.icon(kind)
		draw_texture_rect(vehicle_glyph, Rect2(10, 17, 58, 58), false, tint)
	elif kind == "mother":
		draw_colored_polygon(PackedVector2Array([Vector2(20, 85), Vector2(24, 57), Vector2(43, 49), Vector2(55, 61), Vector2(59, 85)]), Color("62695c"))
		draw_line(Vector2(23, 62), Vector2(13, 84), Color("8d937e"), 7, true)
		draw_line(Vector2(55, 65), Vector2(63, 90), Color("8d937e"), 5, true)
		var skull := PackedVector2Array()
		for i in range(24): skull.append(Vector2(37, 32) + Vector2(cos(i * TAU / 24) * 25, sin(i * TAU / 24) * 28))
		draw_colored_polygon(skull, Color("a3a58c"))
		for side in [-1, 1]:
			draw_circle(Vector2(36 + side * 10, 37), 5, Color("3c443b"))
			draw_circle(Vector2(36 + side * 10, 38), 1.7, Color("c8bb8c"))
		draw_line(Vector2(27, 50), Vector2(45, 53), Color("333b32"), 5, true)
	elif kind == "father":
		for arm in range(8):
			var points := PackedVector2Array()
			for step in range(7): points.append(Vector2(22 + arm * 5 + sin(step * 0.7 + arm) * step * 0.8, 46 + step * (4.6 if arm in [2, 5] else 3.8)))
			draw_polyline(points, Color("a99aab"), 3.5 - absf(arm - 3.5) * 0.2, true)
		var mantle := PackedVector2Array()
		for i in range(24): mantle.append(Vector2(39, 31) + Vector2(cos(i * TAU / 24) * 23, sin(i * TAU / 24) * 24))
		draw_colored_polygon(mantle, Color("887789"))
		draw_arc(Vector2(39, 29), 18, PI, TAU, 16, Color("b8afa3"), 5, true)
		for side in [-1, 1]: draw_circle(Vector2(39 + side * 11, 41), 3, Color("e1a77c"))
	elif structure:
		draw_rect(Rect2(16, 70, 46, 9), Color("536965"))
		draw_colored_polygon(PackedVector2Array([Vector2(24, 68), Vector2(24, 36), Vector2(33, 27), Vector2(47, 27), Vector2(55, 36), Vector2(55, 68)]), Color("81918d"))
		draw_rect(Rect2(23, 45, 33, 5), tint)
		draw_rect(Rect2(34, 57, 12, 13), Color("22363e"))
		draw_line(Vector2(46, 29), Vector2(46, 15), Color("a5b5aa"), 2)
		draw_circle(Vector2(46, 13), 2, Color("c7a375"))
	else:
		var helmet := PackedVector2Array([Vector2(23, 21), Vector2(55, 21), Vector2(61, 31), Vector2(58, 54), Vector2(48, 62), Vector2(30, 62), Vector2(20, 54), Vector2(17, 31)])
		draw_colored_polygon(helmet, Color("81918d"))
		draw_colored_polygon(PackedVector2Array([Vector2(24, 34), Vector2(55, 34), Vector2(52, 45), Vector2(26, 45)]), Color("22363e"))
		draw_line(Vector2(26, 35), Vector2(53, 35), tint, 2, true)
		draw_rect(Rect2(32, 51, 14, 6), Color("344643"))
		draw_colored_polygon(PackedVector2Array([Vector2(10, 80), Vector2(14, 68), Vector2(27, 61), Vector2(51, 61), Vector2(65, 68), Vector2(69, 80)]), Color("536965"))
		draw_line(Vector2(17, 70), Vector2(25, 67), tint, 3, true)
	for p in [Vector2(0, 0), Vector2(78, 0), Vector2(0, 94), Vector2(78, 94)]:
		var direction := Vector2(1 if p.x == 0 else -1, 1 if p.y == 0 else -1)
		draw_line(p, p + Vector2(direction.x * 10, 0), Color("7b8b7e"), 1)
		draw_line(p, p + Vector2(0, direction.y * 10), Color("7b8b7e"), 1)
	draw_string(FONT, Vector2(0, 109), ("%s / x%d" % [kind.left(3).to_upper(), group_size]) if group_size > 1 else "%s / %02d" % [kind.left(3).to_upper() if kind != "" else "COM", serial], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)
