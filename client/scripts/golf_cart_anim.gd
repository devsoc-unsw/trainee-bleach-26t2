extends Control

const SKY := Color("C5E4F2")
const GROUND := Color("2F7A6E")
const MOUNTAIN := Color("A8D4A3")
const SNOW := Color("F4F6F0")
const TREE := Color("6FA86C")
const CART := Color("F4D35E")
const ROOF := Color("E89B3A")
const WINDOW := Color("A9D4EA")

const LOOP := 1100.0

var _t := 0.0
var _body_box: StyleBoxFlat
var _roof_box: StyleBoxFlat
var _pane_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_box = StyleBoxFlat.new()
	_body_box.bg_color = CART
	_roof_box = StyleBoxFlat.new()
	_roof_box.bg_color = ROOF
	_pane_box = StyleBoxFlat.new()
	_pane_box.bg_color = WINDOW
	set_process(true)
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return
	var ground_h := s.y * 0.22
	var ground_y := s.y - ground_h
	draw_rect(Rect2(Vector2.ZERO, s), SKY)
	_draw_mountains(ground_y, _t * 36.0, s.x)
	_draw_trees(ground_y, _t * 62.0, s.x)
	draw_rect(Rect2(0.0, ground_y, s.x, ground_h), GROUND)
	_draw_cart(Vector2(s.x * 0.22, ground_y + sin(_t * 9.0) * 1.1), minf(s.x, s.y) / 720.0)


func _draw_mountains(ground_y: float, scroll: float, view_w: float) -> void:
	# Discrete peaks, wrapped by period so nothing snaps at the seam.
	var peaks := [
		[40.0, 240.0, 160.0],
		[220.0, 280.0, 210.0],
		[380.0, 420.0, 300.0],
		[560.0, 250.0, 170.0],
		[900.0, 260.0, 180.0],
	]
	for peak in peaks:
		for x in _wrap_xs(peak[0], scroll, view_w, peak[1] * 0.5 + 8.0):
			_mountain(x, ground_y, peak[1], peak[2])


func _draw_trees(ground_y: float, scroll: float, view_w: float) -> void:
	for base in [120.0, 640.0, 980.0]:
		for x in _wrap_xs(base, scroll, view_w, 48.0):
			_pine(x, ground_y, 52.0 if base < 200.0 else 44.0)


func _wrap_xs(anchor: float, scroll: float, view_w: float, half_w: float) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var x := fposmod(anchor - scroll, LOOP)
	var i := -1
	while i <= 2:
		var px := x + float(i) * LOOP
		if px + half_w >= -4.0 and px - half_w <= view_w + 4.0:
			xs.append(px)
		i += 1
	return xs


func _mountain(cx: float, ground_y: float, width: float, height: float) -> void:
	var peak := Vector2(cx, ground_y - height)
	var left := Vector2(cx - width * 0.5, ground_y + 2.0)
	var right := Vector2(cx + width * 0.5, ground_y + 2.0)
	draw_colored_polygon(PackedVector2Array([left, peak, right]), MOUNTAIN)
	var cap := height * 0.2
	var t := cap / height
	var snow_l := left.lerp(peak, 1.0 - t)
	var snow_r := right.lerp(peak, 1.0 - t)
	var jag := (snow_r.x - snow_l.x) * 0.22
	draw_colored_polygon(
		PackedVector2Array([
			snow_l,
			Vector2(lerpf(snow_l.x, peak.x, 0.35), snow_l.y + cap * 0.28),
			Vector2(peak.x - jag * 0.15, peak.y + cap * 0.12),
			peak,
			Vector2(peak.x + jag * 0.2, peak.y + cap * 0.18),
			Vector2(lerpf(peak.x, snow_r.x, 0.55), snow_r.y + cap * 0.22),
			snow_r,
		]),
		SNOW
	)


func _pine(cx: float, ground_y: float, height: float) -> void:
	var w := height * 0.7
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(cx - w * 0.5, ground_y + 2.0),
			Vector2(cx, ground_y - height),
			Vector2(cx + w * 0.5, ground_y + 2.0),
		]),
		TREE
	)


func _draw_cart(origin: Vector2, sc: float) -> void:
	sc = clampf(sc, 0.78, 1.4)
	var r := int(round(10.0 * sc))
	_body_box.set_corner_radius_all(r)
	draw_style_box(_body_box, Rect2(origin + Vector2(-48.0, -30.0) * sc, Vector2(98.0, 30.0) * sc))
	_roof_box.corner_radius_top_left = int(round(8.0 * sc))
	_roof_box.corner_radius_top_right = int(round(8.0 * sc))
	draw_style_box(_roof_box, Rect2(origin + Vector2(-14.0, -46.0) * sc, Vector2(58.0, 18.0) * sc))
	_pane_box.set_corner_radius_all(int(round(3.0 * sc)))
	draw_style_box(_pane_box, Rect2(origin + Vector2(-6.0, -42.0) * sc, Vector2(20.0, 12.0) * sc))
	draw_circle(origin + Vector2(-26.0, 6.0) * sc, 9.0 * sc, GROUND)
	draw_circle(origin + Vector2(30.0, 6.0) * sc, 9.0 * sc, GROUND)
