class_name ResourceStrip
extends Control

var world: WorldState
var owner_id := 0
const FONT := preload("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")
const BOLD := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
const TYPES := ["ore", "gas", "alloy", "polymer", "crystal", "nacre"]
const TINTS := [Color("c8aa75"), Color("83b3ae"), Color("a4b3bb"), Color("b7b18a"), Color("a4a5c9"), Color("dec0af")]

func _ready() -> void:
	custom_minimum_size = Vector2(540, 42)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void: queue_redraw()

func _draw() -> void:
	if world == null or not world.players.has(owner_id): return
	if owner_id == -1:
		draw_string(BOLD, Vector2(12, 29), "CHYME  %d" % int(world.lightless_chyme), HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("dec0af"))
		draw_string(FONT, Vector2(190, 27), "LIGHTLESS  /  Damage, deliver, grow", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("a5b5ab"))
		return
	var width := size.x / 6
	for i in range(6):
		var x := i * width
		var resource: String = TYPES[i]
		var count := int(world.resources(owner_id).get(resource, 0))
		var capacity := world.capacity(owner_id, resource)
		var tint: Color = TINTS[i]
		var p := Vector2(x + 8, 17)
		if i in [0, 4, 5]:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 0), p + Vector2(0, 7), p + Vector2(-6, 0)]), tint.darkened(0.25))
			draw_line(p + Vector2(0, -6), p + Vector2(0, 6), tint, 1, true)
		elif i == 1:
			for j in range(3): draw_circle(p + Vector2((j - 1) * 4, abs(j - 1) * 5 - 2), 3, tint, false, 1, true)
		else:
			for j in range(3): draw_line(p + Vector2(-6, j * 4 - 4), p + Vector2(6, j * 4 - 4), tint, 2, true)
		draw_string(FONT, Vector2(x + 23, 12), resource.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint.darkened(0.15))
		draw_string(BOLD, Vector2(x + 23, 32), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("e0e0ce"))
		var count_width := BOLD.get_string_size(str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(FONT, Vector2(x + 28 + count_width, 31), "/ %d" % capacity, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("73827f"))
		draw_rect(Rect2(x + 23, 37, width - 35, 2), Color("283436"))
		draw_rect(Rect2(x + 23, 37, (width - 35) * clampf(float(count) / maxf(1, capacity), 0, 1), 2), tint.darkened(0.3))
