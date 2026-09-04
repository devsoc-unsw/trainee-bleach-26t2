extends Control

var map_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func setup(id: String) -> void:
	map_id = id
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color("6BB3E8"))
	draw_rect(Rect2(0.0, s.y * 0.38, s.x, s.y * 0.62), Color("5A9A4A"))
	match map_id:
		"rainbow_stairs":
			_rainbow(s)
		"main_walk":
			_mall(s)
		_:
			_village(s)


func _rainbow(s: Vector2) -> void:
	draw_rect(Rect2(0.0, s.y * 0.52, s.x, s.y * 0.48), Color("6BB04A"))
	var ramp := [
		Color("E23B3B"), Color("F28C28"), Color("F2D04B"),
		Color("5BBF5B"), Color("4CB8B0"), Color("4A7FD4"), Color("7B5BBF"),
	]
	for i in ramp.size():
		var y := s.y * (0.28 + float(i) * 0.06)
		var step := Rect2(s.x * (0.14 + float(i) * 0.018), y, s.x * 0.52, s.y * 0.034)
		draw_rect(step, ramp[i])
		draw_rect(Rect2(step.position.x, step.position.y + step.size.y, step.size.x, s.y * 0.018), ramp[i].darkened(0.18))
	draw_rect(Rect2(s.x * 0.08, s.y * 0.12, s.x * 0.84, s.y * 0.28), Color("C4A07A"))
	draw_rect(Rect2(s.x * 0.22, s.y * 0.18, s.x * 0.28, s.y * 0.16), Color("7EC8E0"))


func _mall(s: Vector2) -> void:
	draw_rect(Rect2(0.0, s.y * 0.46, s.x, s.y * 0.54), Color("C8C4BA"))
	draw_rect(Rect2(0.0, s.y * 0.46, s.x * 0.22, s.y * 0.54), Color("5A9A4A"))
	draw_rect(Rect2(s.x * 0.78, s.y * 0.46, s.x * 0.22, s.y * 0.54), Color("5A9A4A"))
	draw_rect(Rect2(s.x * 0.08, s.y * 0.1, s.x * 0.34, s.y * 0.4), Color("8A5A44"))
	draw_rect(Rect2(s.x * 0.58, s.y * 0.16, s.x * 0.32, s.y * 0.34), Color("E8DCC8"))
	draw_rect(Rect2(s.x * 0.64, s.y * 0.22, s.x * 0.2, s.y * 0.16), Color("7EC8E0"))


func _village(s: Vector2) -> void:
	draw_rect(Rect2(s.x * 0.12, s.y * 0.48, s.x * 0.52, s.y * 0.28), Color("4A8A4A"))
	draw_rect(Rect2(s.x * 0.14, s.y * 0.6, s.x * 0.48, 3.0), Color("F4F1EA"))
	draw_rect(Rect2(s.x * 0.14, s.y * 0.48, 3.0, s.y * 0.28), Color("F4F1EA"))
	draw_rect(Rect2(s.x * 0.68, s.y * 0.22, s.x * 0.2, s.y * 0.5), Color("9AA0A6"))
	draw_rect(Rect2(s.x * 0.08, s.y * 0.18, s.x * 0.28, s.y * 0.22), Color("8A5A44"))
