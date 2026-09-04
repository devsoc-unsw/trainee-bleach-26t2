extends Node3D

signal shot_taken(direction: Vector3, power: float)
signal aiming_changed(is_aiming: bool)
signal aim_updated(direction: Vector3, power: float)

@export var ball: PuttBall
@export var camera_rig: CameraRig
@export var max_drag_px: float = 320.0
@export var arrow_min_length: float = 0.425
@export var arrow_max_length: float = 5.0
@export var arrow_width: float = 0.055
@export var arrow_head_width: float = 0.14
@export var arrow_head_length: float = 0.22
@export var max_deviation_degrees: float = 3.0
@export var preview_deadzone_px: float = 6.0
@export var cancel_radius_px: float = 28.0

var aiming: bool = false
var drag_start_screen: Vector2
var _has_pulled_out: bool = false
var camera: Camera3D
var trajectory_mesh: MeshInstance3D
var immediate_mesh: ImmediateMesh
var _line_mat: StandardMaterial3D

const LINE_STEPS := 10


func _ready() -> void:
	camera = camera_rig.camera

	immediate_mesh = ImmediateMesh.new()
	trajectory_mesh = MeshInstance3D.new()
	trajectory_mesh.mesh = immediate_mesh
	add_child(trajectory_mesh)

	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.albedo_color = Color.WHITE
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mat.no_depth_test = true
	trajectory_mesh.material_override = _line_mat


func _pointer_on_hud() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _can_aim() -> bool:
	if ball == null:
		return false
	if ball.is_moving:
		return false
	if ball.freeze:
		return false
	if ball.get("is_holed"):
		return false
	return true


func _set_aiming(value: bool) -> void:
	if aiming == value:
		return
	aiming = value
	if not aiming:
		immediate_mesh.clear_surfaces()
	aiming_changed.emit(aiming)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				if _pointer_on_hud() or not _can_aim():
					return
				_set_aiming(true)
				drag_start_screen = mouse.position
				_has_pulled_out = false
			else:
				if aiming:
					_release_shot(mouse.position)
					_set_aiming(false)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			if aiming:
				_set_aiming(false)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if aiming:
			_set_aiming(false)


func _process(_delta: float) -> void:
	if aiming and _can_aim():
		_update_trajectory_preview(get_viewport().get_mouse_position())
	elif aiming and not _can_aim():
		_set_aiming(false)


func _compute_shot(end_screen: Vector2) -> Dictionary:
	var drag_screen := end_screen - drag_start_screen
	var drag_px := drag_screen.length()
	var power := clampf(drag_px / max_drag_px, 0.0, 1.0)

	var cam_right: Vector3 = camera.global_transform.basis.x
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	cam_right.y = 0.0
	cam_fwd.y = 0.0
	cam_right = cam_right.normalized()
	cam_fwd = cam_fwd.normalized()

	var world_drag := cam_right * drag_screen.x + cam_fwd * (-drag_screen.y)
	var direction := -world_drag.normalized() if drag_px > 1.0 else Vector3.FORWARD

	return {"direction": direction, "power": power, "drag_px": drag_px}


func _is_cancelled(end_screen: Vector2, shot: Dictionary) -> bool:
	var drag_px := float(shot.drag_px)
	if drag_px > cancel_radius_px:
		_has_pulled_out = true
	if drag_px < preview_deadzone_px:
		return true
	return _has_pulled_out and _cursor_near_ball(end_screen)


func _cursor_near_ball(end_screen: Vector2) -> bool:
	if camera == null or camera.is_position_behind(ball.global_position):
		return false
	var ball_screen := camera.unproject_position(ball.global_position)
	return ball_screen.distance_to(end_screen) <= cancel_radius_px


func _apply_yaw_deviation(direction: Vector3, max_degrees: float) -> Vector3:
	var random_degrees := randf_range(-max_degrees, max_degrees)
	return direction.rotated(Vector3.UP, deg_to_rad(random_degrees))


func _update_trajectory_preview(mouse_pos: Vector2) -> void:
	var shot := _compute_shot(mouse_pos)
	immediate_mesh.clear_surfaces()

	if _is_cancelled(mouse_pos, shot):
		aim_updated.emit(shot.direction, 0.0)
		return

	var launch_dir: Vector3 = shot.direction.normalized()
	var power: float = shot.power
	var arrow_length := lerpf(arrow_min_length, arrow_max_length, power)
	_draw_aim_arrow(ball.global_position, launch_dir, arrow_length, _power_color(power))
	aim_updated.emit(launch_dir, power)


func _draw_aim_arrow(start: Vector3, dir: Vector3, length: float, tip_color: Color) -> void:
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var head_len := minf(arrow_head_length, length * 0.45)
	var shaft_len := maxf(length - head_len, 0.0)
	var half_w := arrow_width * 0.5
	var head_half_w := arrow_head_width * 0.5
	start += Vector3.UP * 0.02

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(LINE_STEPS):
		var t0 := float(i) / float(LINE_STEPS)
		var t1 := float(i + 1) / float(LINE_STEPS)
		var p0 := start + dir * (shaft_len * t0)
		var p1 := start + dir * (shaft_len * t1)
		var c0 := Color.WHITE.lerp(tip_color, t0 * (shaft_len / length))
		var c1 := Color.WHITE.lerp(tip_color, t1 * (shaft_len / length))
		_add_arrow_quad(
			p0 - right * half_w, p0 + right * half_w,
			p1 + right * half_w, p1 - right * half_w,
			c0, c1
		)

	var head_base := start + dir * shaft_len
	var tip := start + dir * length
	var base_color := Color.WHITE.lerp(tip_color, shaft_len / length)
	immediate_mesh.surface_set_color(base_color)
	immediate_mesh.surface_add_vertex(head_base - right * head_half_w)
	immediate_mesh.surface_set_color(base_color)
	immediate_mesh.surface_add_vertex(head_base + right * head_half_w)
	immediate_mesh.surface_set_color(tip_color)
	immediate_mesh.surface_add_vertex(tip)
	immediate_mesh.surface_end()


func _add_arrow_quad(
	bottom_left: Vector3,
	bottom_right: Vector3,
	top_right: Vector3,
	top_left: Vector3,
	c0: Color,
	c1: Color
) -> void:
	immediate_mesh.surface_set_color(c0)
	immediate_mesh.surface_add_vertex(bottom_left)
	immediate_mesh.surface_set_color(c0)
	immediate_mesh.surface_add_vertex(bottom_right)
	immediate_mesh.surface_set_color(c1)
	immediate_mesh.surface_add_vertex(top_right)
	immediate_mesh.surface_set_color(c0)
	immediate_mesh.surface_add_vertex(bottom_left)
	immediate_mesh.surface_set_color(c1)
	immediate_mesh.surface_add_vertex(top_right)
	immediate_mesh.surface_set_color(c1)
	immediate_mesh.surface_add_vertex(top_left)


func _power_color(power: float) -> Color:
	if power < 0.45:
		return Color("9CE8E0").lerp(Color("F2D04B"), power / 0.45)
	return Color("F2D04B").lerp(Color("E23B3B"), (power - 0.45) / 0.55)


func _release_shot(end_screen: Vector2) -> void:
	if not _can_aim():
		return

	var shot := _compute_shot(end_screen)
	if _is_cancelled(end_screen, shot):
		return

	var deviation_degrees: float = shot.power * shot.power * max_deviation_degrees
	var direction := _apply_yaw_deviation(shot.direction, deviation_degrees)
	ball.hit(direction, shot.power)
	if ball.is_moving:
		shot_taken.emit(direction, shot.power)
