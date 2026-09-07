extends Button

const HOVER_SCALE := 1.22

var _tween: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_center_pivot)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	_center_pivot()


func _center_pivot() -> void:
	pivot_offset = size * 0.5


func _on_hover(inside: bool) -> void:
	if disabled:
		inside = false
	_animate(HOVER_SCALE if inside else 1.0)


func _animate(to_scale: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "scale", Vector2.ONE * to_scale, 0.14)
