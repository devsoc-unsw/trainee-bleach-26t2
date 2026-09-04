class_name BallStatusIndicator
extends Control

enum State { READY, AIMING, ROLLING, HOLED, OOB }

const WELL_RIM := Color("1F4F4B")
const WELL_RING := Color("2F6F69")
const LABEL_COLOR := Color("5A5248")
const LABEL_SHADOW := Color(1, 1, 1, 0.35)
const OOB_TINT := Color(0.89, 0.23, 0.23, 0.35)

@export var font: Font
@export var view_height: float = 0.72
@export var view_size: float = 0.5

var state: State = State.READY
var _time: float = 0.0
var _oob_until: float = -1.0
var _ball: Node3D
var _viewport: SubViewport
var _camera: Camera3D
var _view: TextureRect
var _mask: ShaderMaterial


func _ready() -> void:
	custom_minimum_size = Vector2(136, 50)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_setup_viewport()
	resized.connect(_layout_view)
	_layout_view()


func set_ball(ball: Node3D) -> void:
	_ball = ball
	if _viewport == null or ball == null or not is_instance_valid(ball):
		return
	var host := ball.get_parent()
	if host and _viewport.get_parent() != host:
		_viewport.reparent(host, false)
	_viewport.own_world_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _camera:
		_camera.top_level = true
		_camera.current = true
	_follow_ball()


func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if state == State.OOB:
		_oob_until = _time + 0.9
	queue_redraw()


func set_aim(_direction: Vector2, _power: float) -> void:
	if state == State.ROLLING or state == State.HOLED or state == State.OOB:
		return
	if state != State.AIMING:
		state = State.AIMING
	queue_redraw()


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BallPreview"
	_viewport.size = Vector2i(128, 128)
	_viewport.transparent_bg = false
	_viewport.disable_3d = false
	_viewport.own_world_3d = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = view_size
	_camera.near = 0.05
	_camera.far = 20.0
	_camera.current = true
	_camera.top_level = true
	_viewport.add_child(_camera)

	_mask = ShaderMaterial.new()
	_mask.shader = load("res://shaders/circle_mask.gdshader")

	_view = TextureRect.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.material = _mask
	add_child(_view)
	_view.texture = _viewport.get_texture()
	_view.flip_v = false


func _layout_view() -> void:
	if _view == null:
		return
	var well := _well_rect()
	_view.position = well.position
	_view.size = well.size


func _well_rect() -> Rect2:
	var radius := 20.0
	var center := Vector2(22.0, size.y * 0.5)
	return Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))


func _process(delta: float) -> void:
	_time += delta
	if state == State.OOB and _oob_until >= 0.0 and _time >= _oob_until:
		_oob_until = -1.0
		set_state(State.READY)
	_follow_ball()
	queue_redraw()


func _follow_ball() -> void:
	if _camera == null or _ball == null or not is_instance_valid(_ball):
		return
	var target: Vector3 = _ball.global_position
	_camera.global_position = target + Vector3(0.0, view_height, 0.0)
	_camera.look_at(target, Vector3.FORWARD)


func _draw() -> void:
	var well := _well_rect()
	var center := well.get_center()
	var radius := well.size.x * 0.5
	draw_circle(center + Vector2(0, 1.6), radius + 1.4, Color(0, 0, 0, 0.2))
	draw_arc(center, radius + 1.2, 0.0, TAU, 40, WELL_RIM, 3.2, true)
	draw_arc(center, radius + 0.2, 0.0, TAU, 40, WELL_RING, 2.0, true)
	if state == State.OOB:
		draw_circle(center, radius - 1.0, OOB_TINT)
	_draw_state_label()


func _draw_state_label() -> void:
	var use_font := font if font else get_theme_default_font()
	if use_font == null:
		return
	var text := _state_text()
	var font_size := 14
	var ascent := use_font.get_ascent(font_size)
	var descent := use_font.get_descent(font_size)
	var well := _well_rect()
	var pos := Vector2(
		well.position.x + well.size.x + 8.0,
		size.y * 0.5 + (ascent - descent) * 0.5
	)
	draw_string(use_font, pos + Vector2(0, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW)
	draw_string(use_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _state_text() -> String:
	match state:
		State.AIMING:
			return "AIMING"
		State.ROLLING:
			return "ROLLING"
		State.HOLED:
			return "HOLED"
		State.OOB:
			return "OOB"
		_:
			return "READY"
