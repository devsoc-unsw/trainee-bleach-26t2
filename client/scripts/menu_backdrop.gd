extends Control

const GRASS_LIT := Color(0.27, 0.45, 0.28)
const GRASS_SHADE := Color(0.16, 0.32, 0.2)
const SKY_TOP := Color("5EABE8")
const SKY_HORIZON := Color("F8D7A4")
const SUN := Color("FFE7A8")

var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		return

	var sky := PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)])
	draw_polygon(sky, PackedColorArray([SKY_TOP, SKY_TOP, SKY_HORIZON, SKY_HORIZON]))

	var sun_r := minf(s.x, s.y) * 0.13
	var sun_p := Vector2(s.x * 0.82, s.y * 0.18 + sin(_t * 0.6) * 6.0)
	draw_circle(sun_p, sun_r * 1.35, Color(SUN, 0.22))
	draw_circle(sun_p, sun_r, SUN)

	_draw_cloud(Vector2(s.x * 0.14 + sin(_t * 0.15) * 30.0, s.y * 0.16), 1.0)
	_draw_cloud(Vector2(s.x * 0.48 + cos(_t * 0.11) * 40.0, s.y * 0.1), 0.72)
	_draw_cloud(Vector2(s.x * 0.72 + sin(_t * 0.09 + 1.2) * 24.0, s.y * 0.22), 0.85)

	_draw_checks(s)
	draw_rect(Rect2(0, 0, s.x, s.y), Color(0.18, 0.12, 0.08, 0.05))


func _draw_cloud(origin: Vector2, scale: float) -> void:
	var cream := Color("F7F1E6", 0.88)
	var r := 28.0 * scale
	draw_circle(origin, r * 1.15, cream)
	draw_circle(origin + Vector2(r * 1.1, r * 0.12), r * 0.95, cream)
	draw_circle(origin + Vector2(-r * 0.95, r * 0.18), r * 0.8, cream)
	draw_circle(origin + Vector2(r * 0.2, -r * 0.45), r * 0.7, cream)


func _hill_y(x: float, s: Vector2) -> float:
	return s.y * 0.56 + sin(x * 0.012 + _t * 0.35) * 18.0 + cos(x * 0.007) * 12.0


func _draw_checks(s: Vector2) -> void:
	var cell := 32.0
	var shift := fmod(_t * 9.0, cell * 2.0)
	var y := s.y * 0.48
	while y < s.y + cell:
		var x := -cell - shift
		var col := 0
		while x < s.x + cell:
			if y + cell * 0.5 >= _hill_y(x + cell * 0.5, s):
				var lit := (col + int(floor(y / cell))) % 2 == 0
				draw_rect(Rect2(x, y, cell + 1.0, cell + 1.0), GRASS_LIT if lit else GRASS_SHADE)
			x += cell
			col += 1
		y += cell
