extends RefCounted
## Code-drawn console chrome; no additional generated artwork required.
const INK := Color("0c1112")
const PANEL := Color("1c2527")
const EDGE := Color("626b65")
const TEXT := Color("d2cebb")
const MUTED := Color("92998c")
const GOLD := Color("d5ad68")

static func box(fill: Color, edge: Color = EDGE, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill; style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = padding; style.content_margin_right = padding
	style.content_margin_top = padding; style.content_margin_bottom = padding
	return style

static func make() -> Theme:
	var theme := Theme.new(); theme.default_font_size = 12
	theme.set_stylebox("panel", "TooltipPanel", box(INK, GOLD, 8))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, box(INK, Color("35413f"), 2))
		theme.set_stylebox("grabber", type, box(Color("5b655c"), EDGE, 2))
		theme.set_stylebox("grabber_highlight", type, box(GOLD.darkened(0.35), GOLD, 2))
		theme.set_stylebox("grabber_pressed", type, box(GOLD.darkened(0.2), GOLD, 2))
	theme.set_stylebox("background", "ProgressBar", box(INK, Color("48574f"), 1))
	theme.set_stylebox("fill", "ProgressBar", box(Color("79aa8c"), Color("79aa8c"), 0))
	return theme

static func apply_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(Color("293333"), EDGE, 7))
	button.add_theme_stylebox_override("hover", box(Color("3a4440"), GOLD, 7))
	button.add_theme_stylebox_override("pressed", box(Color("444737"), GOLD, 7))
	button.add_theme_stylebox_override("disabled", box(Color("171e20"), Color("39423e"), 7))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), GOLD, 0))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color("f2dfac"))
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.3))
	button.add_theme_font_size_override("font_size", 12)
