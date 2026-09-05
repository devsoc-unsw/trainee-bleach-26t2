class_name WiiPointer
extends Control

var _on := false
var _uv := Vector2(0.5, 0.5)
var _outline := Color("3A322C")
var _number := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 90
	visible = false


func set_look(outline: Color, number: int) -> void:
	_outline = outline
	_number = maxi(0, number)
	queue_redraw()


func set_point(on: bool, uv: Vector2 = Vector2(0.5, 0.5)) -> void:
	_on = on
	_uv = uv
	visible = on
	queue_redraw()


func _draw() -> void:
	if not _on:
		return
	var area := size
	if area.x < 1.0 or area.y < 1.0:
		area = get_viewport_rect().size
	var tip := Vector2(_uv.x * area.x, _uv.y * area.y)
	var shape := _pointer_shape(tip)
	_stroke(shape, Color(0, 0, 0, 0.25), 6.0, Vector2(1.4, 1.8))
	_stroke(shape, _outline, 3.0)
	draw_colored_polygon(shape, Color.WHITE)
	if _number > 0:
		_draw_badge(tip + Vector2(22, 20))


func _pointer_shape(tip: Vector2) -> PackedVector2Array:
	# Flat 45-degree OS pointer: triangular head, notched base, short stem.
	# Hotspot is the sharp tip. Axis runs down-right.
	var d := Vector2.ONE.normalized()
	var p := Vector2(-d.y, d.x)
	var head := 22.0
	var head_w := 9.5
	var notch_at := 13.0
	var stem := 10.0
	var stem_w := 2.6
	return PackedVector2Array([
		tip,
		tip + d * head - p * head_w,
		tip + d * notch_at - p * stem_w,
		tip + d * (notch_at + stem) - p * stem_w,
		tip + d * (notch_at + stem) + p * stem_w,
		tip + d * notch_at + p * stem_w,
		tip + d * head + p * head_w,
	])


func _stroke(shape: PackedVector2Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO) -> void:
	if width <= 0.0:
		return
	for i in range(shape.size()):
		var a: Vector2 = shape[i] + offset
		var b: Vector2 = shape[(i + 1) % shape.size()] + offset
		draw_line(a, b, color, width, true)


func _draw_badge(center: Vector2) -> void:
	var radius := 9.0
	draw_circle(center + Vector2(1, 1.4), radius, Color(0, 0, 0, 0.28))
	draw_circle(center, radius, _outline)
	draw_circle(center, radius - 2.2, Color.WHITE)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var label := str(_number)
	var font_size := 11
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := center + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 1.0)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _outline)
