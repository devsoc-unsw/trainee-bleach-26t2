extends Button

var _hover := false
var _tween: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_center_pivot)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(_on_press.bind(true))
	button_up.connect(_on_press.bind(false))
	_center_pivot()


func _center_pivot() -> void:
	pivot_offset = size * 0.5


func _on_hover(inside: bool) -> void:
	_hover = inside
	_animate(1.055 if inside else 1.0, 0.16)


func _on_press(down: bool) -> void:
	_animate(0.96 if down else (1.055 if _hover else 1.0), 0.08)


func _animate(to_scale: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", Vector2.ONE * to_scale, duration)
