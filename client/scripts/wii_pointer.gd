class_name WiiPointer
extends Control

var _on := false
var _uv := Vector2(0.5, 0.5)
var _fill := Color("FF4D6A")
var _outline := Color.WHITE
var _number := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 90
	visible = false


func set_look(outline: Color, number: int) -> void:
	_fill = vivid(outline)
	_outline = Color.WHITE
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
	var shape := pointer_shape(tip, 1.85)
	_stroke(shape, Color(0, 0, 0, 0.28), 10.0, Vector2(2.0, 2.6))
	_stroke(shape, _outline, 5.5)
	draw_colored_polygon(shape, _fill)
	if _number > 0:
		_draw_badge(tip + Vector2(36, 32))


static func vivid(tint: Color) -> Color:
	var out := tint
	if out.s < 0.08:
		out = Color("FF4D6A")
	out.s = minf(out.s * 1.4 + 0.18, 1.0)
	out.v = minf(maxf(out.v, 0.84) * 1.12, 1.0)
	return out


static func pointer_shape(tip: Vector2, amount := 1.0) -> PackedVector2Array:
	var d := Vector2.ONE.normalized()
	var p := Vector2(-d.y, d.x)
	var head := 22.0 * amount
	var head_w := 9.5 * amount
	var notch_at := 13.0 * amount
	var stem := 12.0 * amount
	var stem_w := 2.8 * amount
	return PackedVector2Array([
		tip,
		tip + d * head - p * head_w,
		tip + d * notch_at - p * stem_w,
		tip + d * (notch_at + stem) - p * stem_w,
		tip + d * (notch_at + stem) + p * stem_w,
		tip + d * notch_at + p * stem_w,
		tip + d * head + p * head_w,
	])


static func install_mouse_cursor(tint: Color) -> void:
	var fill := vivid(tint)
	var img := _cursor_image(fill)
	var tex := ImageTexture.create_from_image(img)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(3, 3))
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_POINTING_HAND, Vector2(3, 3))
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_MOVE, Vector2(3, 3))
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_DRAG, Vector2(3, 3))


static func _cursor_image(fill: Color) -> Image:
	var px := 96
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var shape := pointer_shape(Vector2(4, 4), 2.35)
	_fill_poly(img, _grow_poly(shape, 3.2), Color(0, 0, 0, 0.35))
	_fill_poly(img, _grow_poly(shape, 1.6), Color.WHITE)
	_fill_poly(img, shape, fill)
	return img


static func _grow_poly(shape: PackedVector2Array, amount: float) -> PackedVector2Array:
	var mid := Vector2.ZERO
	for p in shape:
		mid += p
	mid /= float(shape.size())
	var out := PackedVector2Array()
	for p in shape:
		var dir := p - mid
		if dir.length_squared() < 0.0001:
			out.append(p)
		else:
			out.append(p + dir.normalized() * amount)
	return out


static func _fill_poly(img: Image, shape: PackedVector2Array, color: Color) -> void:
	if shape.size() < 3:
		return
	var min_x := 0
	var min_y := 0
	var max_x := img.get_width() - 1
	var max_y := img.get_height() - 1
	var box_min := Vector2(max_x, max_y)
	var box_max := Vector2.ZERO
	for p in shape:
		box_min.x = minf(box_min.x, p.x)
		box_min.y = minf(box_min.y, p.y)
		box_max.x = maxf(box_max.x, p.x)
		box_max.y = maxf(box_max.y, p.y)
	var x0 := clampi(int(floor(box_min.x)), min_x, max_x)
	var y0 := clampi(int(floor(box_min.y)), min_y, max_y)
	var x1 := clampi(int(ceil(box_max.x)), min_x, max_x)
	var y1 := clampi(int(ceil(box_max.y)), min_y, max_y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _point_in_poly(Vector2(x + 0.5, y + 0.5), shape):
				img.set_pixel(x, y, color)


static func _point_in_poly(point: Vector2, shape: PackedVector2Array) -> bool:
	var inside := false
	var j := shape.size() - 1
	for i in shape.size():
		var a: Vector2 = shape[i]
		var b: Vector2 = shape[j]
		var hit := ((a.y > point.y) != (b.y > point.y)) and (
			point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y + 0.0001) + a.x
		)
		if hit:
			inside = not inside
		j = i
	return inside


func _stroke(shape: PackedVector2Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO) -> void:
	if width <= 0.0:
		return
	for i in range(shape.size()):
		var a: Vector2 = shape[i] + offset
		var b: Vector2 = shape[(i + 1) % shape.size()] + offset
		draw_line(a, b, color, width, true)


func _draw_badge(center: Vector2) -> void:
	var radius := 16.0
	draw_circle(center + Vector2(1.6, 2.2), radius, Color(0, 0, 0, 0.3))
	draw_circle(center, radius, _outline)
	draw_circle(center, radius - 3.2, _fill)
	var font := UiStyle.FONT_EXTRA
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return
	var label := str(_number)
	var font_size := 16
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(
		center.x - text_size.x * 0.5,
		center.y + (ascent - descent) * 0.5
	)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
