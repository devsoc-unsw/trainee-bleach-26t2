extends Control

const CREAM := Color("F6F1E6")
const SHADOW := Color(0.42, 0.325, 0.267, 0.2)
const MARGIN := 16.0
const BAR_TOP := 8.0
const BAR_HEIGHT := 64.0

var _pill: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_pill = StyleBoxFlat.new()
	_pill.bg_color = CREAM
	_pill.set_corner_radius_all(int(BAR_HEIGHT * 0.5))
	_pill.corner_detail = 16
	_pill.anti_aliasing = true
	_pill.shadow_color = SHADOW
	_pill.shadow_size = 10
	_pill.shadow_offset = Vector2(0, 3)


func bar_rect() -> Rect2:
	return Rect2(MARGIN, BAR_TOP, size.x - MARGIN * 2.0, BAR_HEIGHT)


func _draw() -> void:
	if _pill == null:
		return
	_pill.draw(get_canvas_item(), bar_rect())
