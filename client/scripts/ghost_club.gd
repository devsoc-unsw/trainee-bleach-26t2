class_name GhostClub
extends Node3D

const SHAFT_LEN := 0.74
const BALL_RADIUS := 0.15
const HEAD_CLEARANCE := 0.04
const HAND := Vector3(0.36, 1.00, 0.14)
const HEAD_TARGET := Vector3(0.05, 0.06, 0.025)
const MAX_SWING := 1.83
const UP_SPEED := 2.6
const DOWN_SPEED := 3.2

var _hinge: Node3D
var _head: Node3D
var _swing := 0.0
var _open := 0.0
var _target_swing := 0.0
var _target_open := 0.0
var _aim := Vector3.FORWARD
var _fade := 0.0
var _mats: Array[StandardMaterial3D] = []
var _address_beta := 75.0
var _holding := false
var _calibrated := false
var _raw_beta := 75.0
var _raw_gamma := 0.0
var _raw_lift := 0.0
var _beta_f := 75.0
var _gamma_f := 0.0
var _lift_f := 0.0
var _lift_boost := 0.0
var _ball: Node3D


func _ready() -> void:
	_hinge = Node3D.new()
	_hinge.position = HAND
	add_child(_hinge)
	_build_club(_hinge)
	visible = false


func set_pose(beta: float, gamma: float, holding: bool, _stick_x: float = 0.0, _stick_y: float = 0.0, lift: float = 0.0) -> void:
	_holding = holding
	_raw_beta = beta
	_raw_gamma = gamma
	_raw_lift = lift
	if not holding:
		_calibrated = false
		_target_swing = 0.0
		_target_open = 0.0
		_lift_boost = 0.0
		return
	if not _calibrated:
		_address_beta = beta
		_beta_f = beta
		_gamma_f = gamma
		_calibrated = true


func follow(ball: Node3D, aim: Vector3) -> void:
	if ball == null:
		return
	_ball = ball
	_aim = aim
	if _aim.length_squared() < 0.0001:
		_aim = Vector3.FORWARD
	else:
		_aim = _aim.normalized()
	global_position = ball.global_position


func _process(delta: float) -> void:
	var want := 1.0 if _holding else 0.0
	var fade_speed := 12.0 if _holding else 14.0
	_fade = lerpf(_fade, want, 1.0 - exp(-delta * fade_speed))
	visible = _fade > 0.02
	if not visible:
		return
	_smooth_pose(delta)
	var right := Vector3.UP.cross(_aim)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := _aim.cross(right).normalized()
	global_transform.basis = Basis(right, up, -_aim)
	_apply_hinge()
	_keep_head_clear()
	var alpha := 0.58 * _fade
	for i in _mats.size():
		var mat := _mats[i]
		var c := mat.albedo_color
		c.a = alpha * (0.9 if i == 0 else 1.0)
		mat.albedo_color = c


func _smooth_pose(delta: float) -> void:
	_beta_f = lerpf(_beta_f, _raw_beta, 1.0 - exp(-delta * 7.0))
	_gamma_f = lerpf(_gamma_f, _raw_gamma, 1.0 - exp(-delta * 6.0))
	_lift_f = lerpf(_lift_f, _raw_lift, 1.0 - exp(-delta * 4.5))
	if _holding:
		var tilt := clampf(_address_beta - _beta_f, 0.0, 100.0)
		if tilt < 7.0:
			tilt = tilt * tilt / 7.0
		if _lift_f > 1.2:
			_lift_boost = maxf(_lift_boost, clampf((_lift_f - 1.2) * 1.15, 0.0, 20.0))
		else:
			var decay := 14.0 if _lift_f < -1.4 else 6.0
			_lift_boost = move_toward(_lift_boost, 0.0, decay * delta)
		_target_swing = deg_to_rad(clampf(tilt + _lift_boost, 0.0, 105.0))
		_target_open = deg_to_rad(clampf(_gamma_f * 0.18, -12.0, 12.0))
	var rising := _target_swing >= _swing
	var next := lerpf(_swing, _target_swing, 1.0 - exp(-delta * (6.0 if rising else 7.5)))
	var max_step := (UP_SPEED if rising else DOWN_SPEED) * delta
	_swing = clampf(_swing + clampf(next - _swing, -max_step, max_step), 0.0, MAX_SWING)
	_open = lerpf(_open, _target_open, 1.0 - exp(-delta * 7.0))


func _apply_hinge() -> void:
	var down := (HEAD_TARGET - HAND).normalized().rotated(Vector3.RIGHT, -_swing)
	down = down.rotated(Vector3.UP, _open)
	var y_axis := -down
	var hint := Vector3.RIGHT.rotated(Vector3.UP, _open)
	var z_axis := hint.cross(y_axis)
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.FORWARD.cross(y_axis)
	z_axis = z_axis.normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	_hinge.position = HAND
	_hinge.basis = Basis(x_axis, y_axis, z_axis)


func _keep_head_clear() -> void:
	if _head == null:
		return
	var min_y := _floor_y() + HEAD_CLEARANCE
	var buried := min_y - _head.global_position.y
	if buried <= 0.0:
		return
	if _swing > 0.02:
		_swing = maxf(_swing - buried * 1.8, 0.0)
		_target_swing = minf(_target_swing, _swing)
		_apply_hinge()
		buried = min_y - _head.global_position.y
		if buried <= 0.0:
			return
	global_position.y += buried


func _floor_y() -> float:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(origin, global_position + Vector3.DOWN * 0.7)
	query.collision_mask = 1
	if _ball != null and is_instance_valid(_ball):
		query.exclude = [_ball.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return float(hit.position.y)
	return global_position.y - BALL_RADIUS


func _build_club(parent: Node3D) -> void:
	var shaft_mat := _mat(Color(0.78, 0.92, 0.9, 0.42))
	var grip_mat := _mat(Color(0.32, 0.28, 0.24, 0.5))
	var head_mat := _mat(Color(0.45, 0.78, 0.74, 0.55))
	_mats = [shaft_mat, grip_mat, head_mat]

	var grip := MeshInstance3D.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.034
	grip_mesh.bottom_radius = 0.040
	grip_mesh.height = 0.24
	grip_mesh.radial_segments = 12
	grip.mesh = grip_mesh
	grip.material_override = grip_mat
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grip.position = Vector3(0.0, -0.12, 0.0)
	parent.add_child(grip)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.013
	shaft_mesh.bottom_radius = 0.018
	shaft_mesh.height = SHAFT_LEN
	shaft_mesh.radial_segments = 10
	shaft.mesh = shaft_mesh
	shaft.material_override = shaft_mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(0.0, -0.24 - SHAFT_LEN * 0.5, 0.0)
	parent.add_child(shaft)

	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.016
	neck_mesh.bottom_radius = 0.022
	neck_mesh.height = 0.08
	neck_mesh.radial_segments = 8
	neck.mesh = neck_mesh
	neck.material_override = shaft_mat
	neck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	neck.position = Vector3(0.0, -0.24 - SHAFT_LEN - 0.02, 0.04)
	neck.rotation_degrees = Vector3(22.0, 0.0, 0.0)
	parent.add_child(neck)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.10, 0.068, 0.42)
	head.mesh = head_mesh
	head.material_override = head_mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.position = Vector3(0.0, -0.24 - SHAFT_LEN - 0.06, 0.10)
	parent.add_child(head)

	var face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.016, 0.058, 0.38)
	face.mesh = face_mesh
	face.material_override = _mat(Color(0.95, 0.97, 0.94, 0.5))
	_mats.append(face.material_override as StandardMaterial3D)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.position = Vector3(0.0, -0.24 - SHAFT_LEN - 0.06, 0.31)
	parent.add_child(face)

	_head = Node3D.new()
	_head.position = Vector3(0.0, -0.24 - SHAFT_LEN - 0.10, 0.10)
	parent.add_child(_head)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat
