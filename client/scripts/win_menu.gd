extends CanvasLayer

signal replay_pressed

@onready var title_label: Label = $Dimmer/Card/Layout/Title
@onready var subtitle_label: Label = $Dimmer/Card/Layout/Subtitle
@onready var strokes_value: Label = $Dimmer/Card/Layout/Stats/StrokesRow/Value
@onready var par_value: Label = $Dimmer/Card/Layout/Stats/ParRow/Value
@onready var time_value: Label = $Dimmer/Card/Layout/Stats/TimeRow/Value


func _ready() -> void:
	visible = false
	layer = 20


func present(hole: int, par: int, strokes: int, time_text: String) -> void:
	title_label.text = _title_for(strokes, par)
	subtitle_label.text = "HOLE %d COMPLETE" % hole
	strokes_value.text = str(strokes)
	par_value.text = str(par)
	time_value.text = time_text
	var replay := get_node_or_null("Dimmer/Card/Layout/ReplayButton") as Button
	var courses := get_node_or_null("Dimmer/Card/Layout/CoursesButton") as Button
	if replay:
		replay.visible = not GameSession.online
	if courses:
		courses.visible = not GameSession.online
	visible = true


func _title_for(strokes: int, par: int) -> String:
	if strokes <= 1:
		return "HOLE IN ONE!"
	var diff := strokes - par
	match diff:
		-2:
			return "EAGLE!"
		-1:
			return "BIRDIE!"
		0:
			return "PAR!"
		1:
			return "BOGEY"
		_:
			if diff < -2:
				return "AMAZING!"
			return "HOLE COMPLETE"


func _on_replay_pressed() -> void:
	replay_pressed.emit()
	get_tree().reload_current_scene()


func _on_courses_pressed() -> void:
	if GameSession.online:
		return
	GameSession.open_select()
