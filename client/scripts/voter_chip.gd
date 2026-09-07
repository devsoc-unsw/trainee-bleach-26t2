extends Control

const SIZE := 28.0
const RING := 2.0

var slot := 1
var tint := Color("E23B3B")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(center, radius, Color(1, 1, 1, 0.95))
	draw_circle(center, maxf(radius - RING, 1.0), tint)
	var font := UiStyle.FONT_EXTRA
	if font == null:
		return
	var label := str(maxi(slot, 1))
	var font_size := 13
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(
		center.x - text_size.x * 0.5,
		center.y + (ascent - descent) * 0.5
	)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.12, 0.1, 0.08, 0.65))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
