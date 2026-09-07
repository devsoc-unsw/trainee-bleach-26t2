class_name UiStyle
extends RefCounted

const CREAM := Color("F6F1E6")
const CREAM_DEEP := Color("EDE4D4")
const GHOST := Color("FBF7F0")
const GHOST_HOVER := Color("E6DCD0")
const GHOST_PRESS := Color("DCD1C3")
const TEAL := Color("4CB8B0")
const TEAL_HOVER := Color("6DCCC6")
const TEAL_PRESS := Color("3A9A93")
const BROWN := Color("5A5248")
const BROWN_SOFT := Color("8A7E72")
const INK := Color("3A322C")
const WHITE := Color("FFFbf5")

const FONT_BOLD: FontFile = preload("res://ui/fonts/Montserrat-Bold.ttf")
const FONT_EXTRA: FontFile = preload("res://ui/fonts/Montserrat-ExtraBold.ttf")


static func to_color(value: Variant, fallback: Color = Color("E23B3B")) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	if text.is_empty():
		return fallback
	if Color.html_is_valid(text.trim_prefix("#")):
		return Color(text)
	return fallback


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
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	style.shadow_color = Color(0.42, 0.33, 0.27, 0.2)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)
	return style


static func ghost_pill(color: Color = GHOST) -> StyleBoxFlat:
	var style := pill(Color(1, 1, 1, 0.35), 18, 12)
	style.shadow_size = 0
	style.bg_color = color
	return style


static func apply_ghost_button(btn: BaseButton) -> void:
	btn.add_theme_stylebox_override("normal", ghost_pill())
	btn.add_theme_stylebox_override("hover", ghost_pill(GHOST_HOVER))
	btn.add_theme_stylebox_override("pressed", ghost_pill(GHOST_PRESS))
	btn.add_theme_stylebox_override("hover_pressed", ghost_pill(GHOST_PRESS))
	btn.add_theme_stylebox_override("focus", ghost_pill())
	btn.add_theme_stylebox_override("disabled", ghost_pill(Color(GHOST, 0.72)))
	var color := btn.get_theme_color("font_color")
	apply_button_font(btn, color)


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


static func add_audio_sliders(parent: Node, insert_at: int = -1, compact: bool = false) -> void:
	var specs: Array = [
		["MASTER", GameSession.master_volume, "set_master_volume"],
		["MUSIC", GameSession.music_volume, "set_music_volume"],
		["SOUND EFFECTS", GameSession.sfx_volume, "set_sfx_volume"],
		["UI EFFECTS", GameSession.ui_volume, "set_ui_volume"],
	]
	var idx := insert_at
	var label_size := 11 if compact else 12
	var value_size := 12 if compact else 13
	var slider_h := 16.0 if compact else 22.0
	var track_pad := 4 if compact else 6
	for spec in specs:
		var row := HBoxContainer.new()
		var caption := Label.new()
		caption.text = str(spec[0])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_font(caption, true, label_size, INK)
		var pct := Label.new()
		var amount := float(spec[1])
		pct.text = "%d%%" % int(round(amount * 100.0))
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		apply_font(pct, true, value_size, TEAL)
		row.add_child(caption)
		row.add_child(pct)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = amount
		slider.custom_minimum_size = Vector2(0, slider_h)
		var track := StyleBoxFlat.new()
		track.bg_color = Color("E4DCCE")
		track.set_corner_radius_all(8)
		track.content_margin_top = track_pad
		track.content_margin_bottom = track_pad
		var fill := StyleBoxFlat.new()
		fill.bg_color = TEAL
		fill.set_corner_radius_all(8)
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", fill if amount > 0.001 else StyleBoxEmpty.new())
		slider.add_theme_stylebox_override("grabber_area_highlight", fill if amount > 0.001 else StyleBoxEmpty.new())
		var method := str(spec[2])
		slider.value_changed.connect(func(v: float) -> void:
			pct.text = "%d%%" % int(round(v * 100.0))
			var bar: StyleBox = fill if v > 0.001 else StyleBoxEmpty.new()
			slider.add_theme_stylebox_override("grabber_area", bar)
			slider.add_theme_stylebox_override("grabber_area_highlight", bar)
			GameSession.call(method, v)
		)
		if idx >= 0:
			parent.add_child(row)
			parent.move_child(row, idx)
			parent.add_child(slider)
			parent.move_child(slider, idx + 1)
			idx += 2
		else:
			parent.add_child(row)
			parent.add_child(slider)


static func apply_font(node: Control, extra: bool, size: int, color: Color) -> void:
	node.add_theme_font_override("font", FONT_EXTRA if extra else FONT_BOLD)
	node.add_theme_font_size_override("font_size", size)
	apply_button_font(node, color)


static func apply_button_font(node: Control, color: Color) -> void:
	node.add_theme_color_override("font_color", color)
	if not node is BaseButton:
		return
	node.add_theme_color_override("font_hover_color", color)
	node.add_theme_color_override("font_pressed_color", color)
	node.add_theme_color_override("font_focus_color", color)
	node.add_theme_color_override("font_hover_pressed_color", color)
	node.add_theme_color_override("font_disabled_color", Color(color, color.a * 0.7))
