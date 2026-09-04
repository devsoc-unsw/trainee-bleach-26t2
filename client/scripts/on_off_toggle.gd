extends Control

signal toggled(is_on: bool)

const ON_TRACK := Color("4CB8B0")
const OFF_TRACK := Color("D5CEC3")
const KNOB := Color("FBF7F0")

@export var font: Font
@export var is_on: bool = true

var _knob_t: float = 1.0
var _tween: Tween
var _track_box: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = Vector2(52, 30)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	_knob_t = 1.0 if is_on else 0.0
	_track_box = StyleBoxFlat.new()
	_track_box.corner_detail = 12
	_track_box.anti_aliasing = true


func set_on(value: bool) -> void:
	if is_on == value:
		return
	is_on = value
	_animate_knob()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			is_on = not is_on
			_animate_knob()
			toggled.emit(is_on)
			accept_event()


func _animate_knob() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "_knob_t", 1.0 if is_on else 0.0, 0.12)
	_tween.parallel().tween_method(_redraw, 0.0, 1.0, 0.12)


func _redraw(_value: float) -> void:
	queue_redraw()


func _draw() -> void:
	var track := OFF_TRACK.lerp(ON_TRACK, _knob_t)
	_track_box.bg_color = track
	_track_box.set_corner_radius_all(int(size.y * 0.5))
	_track_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	var pad := 3.0
	var knob_r := (size.y - pad * 2.0) * 0.5
	var min_x := pad + knob_r
	var max_x := size.x - pad - knob_r
	var knob_x := lerpf(min_x, max_x, _knob_t)
	var knob_c := Vector2(knob_x, size.y * 0.5)
	draw_circle(knob_c + Vector2(0, 1.0), knob_r, Color(0.42, 0.325, 0.267, 0.16))
	draw_circle(knob_c, knob_r, KNOB)
	draw_circle(knob_c + Vector2(-knob_r * 0.28, -knob_r * 0.3), knob_r * 0.28, Color(1, 1, 1, 0.75))
	if _knob_t > 0.04:
		draw_circle(knob_c, lerpf(0.0, knob_r * 0.34, _knob_t), Color(ON_TRACK, _knob_t))
