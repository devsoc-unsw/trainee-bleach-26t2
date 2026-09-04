class_name UiStyle
extends RefCounted

const CREAM := Color("F6F1E6")
const CREAM_DEEP := Color("EDE4D4")
const TEAL := Color("4CB8B0")
const TEAL_HOVER := Color("6DCCC6")
const TEAL_PRESS := Color("3A9A93")
const BROWN := Color("5A5248")
const BROWN_SOFT := Color("8A7E72")
const INK := Color("3A322C")
const WHITE := Color("FFFbf5")

const FONT_BOLD: FontFile = preload("res://ui/fonts/Montserrat-Bold.ttf")
const FONT_EXTRA: FontFile = preload("res://ui/fonts/Montserrat-ExtraBold.ttf")


static func pill(color: Color, hpad: float = 22.0, vpad: float = 14.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(999)
	style.corner_detail = 16
	style.content_margin_left = hpad
	style.content_margin_right = hpad
	style.content_margin_top = vpad
	style.content_margin_bottom = vpad
	style.shadow_color = Color(0.42, 0.33, 0.27, 0.18)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style


static func card(radius: int = 28) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(radius)
	style.corner_detail = 16
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.shadow_color = Color(0.42, 0.33, 0.27, 0.2)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)
	return style


static func ghost_pill() -> StyleBoxFlat:
	var style := pill(Color(1, 1, 1, 0.35), 18, 12)
	style.shadow_size = 0
	style.bg_color = Color("FBF7F0")
	return style


static func input_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WHITE
	style.set_corner_radius_all(16)
	style.corner_detail = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("E4DCCE")
	return style


static func apply_font(node: Control, extra: bool, size: int, color: Color) -> void:
	node.add_theme_font_override("font", FONT_EXTRA if extra else FONT_BOLD)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
