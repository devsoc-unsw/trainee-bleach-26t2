class_name PowerSlot
extends Control

signal pressed

var kind := "shield"
var charged := false
var remaining := 0.0

const DOTS := 22
const EMPTY := Color("8A7E72")
const SHIELD := Color("8E8A84")
const SHIELD_LINE := Color("5A5248")
const TINY := Color("F2D04B")
const TINY_LINE := Color("C9A22A")
const FILL := Color("F6F1E6")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_state(is_charged: bool, seconds: float) -> void:
	set_slot(kind if is_charged or seconds > 0.001 else "", seconds)


func set_slot(next_kind: String, seconds: float) -> void:
	var charged_now := not next_kind.is_empty()
	var next := maxf(seconds, 0.0)
	if kind == next_kind and charged == charged_now and is_equal_approx(next, remaining):
		return
	kind = next_kind
	charged = charged_now
	remaining = next
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if charged and remaining <= 0.001 else Control.CURSOR_ARROW
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and charged and remaining <= 0.001:
			pressed.emit()
			accept_event()


func _max_time() -> float:
	return 5.0 if kind == "shield" else 10.0


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3.5
	if remaining > 0.001:
		_draw_held(center, radius)
		_draw_sigil(center)
	elif charged:
		_draw_ready(center, radius)
		_draw_sigil(center)
	else:
		_draw_dotted(center, radius)


func _draw_dotted(center: Vector2, radius: float) -> void:
	for i in DOTS:
		var angle := TAU * float(i) / float(DOTS) - PI * 0.5
		draw_circle(center + Vector2(cos(angle), sin(angle)) * radius, 1.65, EMPTY)


func _draw_ready(center: Vector2, radius: float) -> void:
	draw_circle(center, radius - 0.5, FILL)
	var accent := SHIELD_LINE if kind == "shield" else TINY_LINE
	draw_arc(center, radius, 0.0, TAU, 36, accent, 2.6, true)


func _draw_held(center: Vector2, radius: float) -> void:
	draw_circle(center, radius - 0.5, FILL)
	var accent := SHIELD_LINE if kind == "shield" else TINY_LINE
	var sweep := clampf(remaining / _max_time(), 0.0, 1.0)
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * sweep, 36, accent, 2.6, true)


func _draw_sigil(center: Vector2) -> void:
	if kind == "shield":
		_draw_shield(center)
	else:
		_draw_tiny(center)


func _draw_shield(center: Vector2) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -13),
		center + Vector2(11, -7),
		center + Vector2(10, 3),
		center + Vector2(0, 14),
		center + Vector2(-10, 3),
		center + Vector2(-11, -7),
	])
	draw_colored_polygon(pts, SHIELD)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, SHIELD_LINE, 1.8, true)
	draw_line(center + Vector2(0, -8), center + Vector2(0, 8), Color("F6F1E6"), 1.4, true)


func _draw_tiny(center: Vector2) -> void:
	draw_arc(center, 12.0, 0.0, TAU, 28, TINY_LINE, 2.1, true)
	draw_circle(center, 5.6, TINY)
	draw_circle(center + Vector2(-1.6, -1.6), 1.5, Color("FFF4C2"))
