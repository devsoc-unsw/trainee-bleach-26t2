class_name CameraRig
extends Node3D

@export var target: Node3D
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 3.0
@export var max_zoom: float = 36.0
@export var overview_zoom: float = 12.0
@export var min_pitch: float = -85.0
@export var max_pitch: float = -10.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var yaw: float = 0.0
var pitch: float = -30.0
var dragging: bool = false
var overview: bool = false
var free_roam: bool = false
var move_speed: float = 14.0
var _phone_drive := Vector2.ZERO
var input_locked := false


func _ready() -> void:
	print("Camera ready")
	spring_arm.spring_length = 8.0
	spring_arm.collision_mask = 0
	_update_rotation()
	set_process(true)


func _process(_delta: float) -> void:
	_update_xray()


func _exit_tree() -> void:
	_set_xray(Vector3.ZERO, Vector3.ZERO, 0.0)


func set_input_locked(on: bool) -> void:
	if input_locked == on:
		return
	input_locked = on
	_phone_drive = Vector2.ZERO
	if on:
		dragging = false


func _physics_process(delta: float) -> void:
	if free_roam:
		if not input_locked:
			_move_free(delta)
		return
	if target:
		global_position = target.global_position


func set_follow(node: Node3D) -> void:
	free_roam = false
	_phone_drive = Vector2.ZERO
	target = node
	overview = false
	spring_arm.collision_mask = 0


func set_free_roam(from: Vector3) -> void:
	free_roam = true
	target = null
	overview = false
	global_position = from
	spring_arm.collision_mask = 0
	max_zoom = maxf(max_zoom, 64.0)

func reset_view() -> void:
	if free_roam:
		return
	overview = false
	yaw = 0.0
	pitch = -30.0
	spring_arm.spring_length = 8.0
	spring_arm.collision_mask = 0
	_update_rotation()


func set_overview(enabled: bool = true) -> void:
	if free_roam:
		return
	overview = enabled
	if overview:
		yaw = 0.0
		pitch = -82.0
		spring_arm.spring_length = overview_zoom
		spring_arm.collision_mask = 0
	else:
		pitch = -30.0
		spring_arm.spring_length = 8.0
		spring_arm.collision_mask = 0
	_update_rotation()


func toggle_overview() -> void:
	set_overview(not overview)


func nudge_zoom(inward: bool) -> void:
	apply_zoom_rate(-1.0 if inward else 1.0, 0.22)


func apply_zoom_rate(dir: float, delta: float) -> void:
	if spring_arm == null or absf(dir) < 0.08:
		return
	spring_arm.spring_length = clampf(spring_arm.spring_length + dir * zoom_speed * 10.0 * delta, min_zoom, max_zoom)
	if overview:
		overview_zoom = spring_arm.spring_length


func _input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		match mouse.button_index:
			MOUSE_BUTTON_RIGHT:
				if mouse.pressed:
					if _blocks_look():
						return
					dragging = true
				else:
					dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				if _blocks_look():
					return
				spring_arm.spring_length = clampf(spring_arm.spring_length - zoom_speed, min_zoom, max_zoom)
			MOUSE_BUTTON_WHEEL_DOWN:
				if _blocks_look():
					return
				spring_arm.spring_length = clampf(spring_arm.spring_length + zoom_speed, min_zoom, max_zoom)
	elif event is InputEventPanGesture:
		if _blocks_look():
			return
		spring_arm.spring_length = clampf(spring_arm.spring_length + event.delta.y * zoom_speed, min_zoom, max_zoom)
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * orbit_speed
		pitch = clampf(pitch - motion.relative.y * orbit_speed * 57.3, min_pitch, max_pitch)
		_update_rotation()
		get_viewport().set_input_as_handled()


func _blocks_look() -> bool:
	var hit := get_viewport().gui_get_hovered_control()
	if hit == null or not is_instance_valid(hit):
		return false
	var node: Node = hit
	while node != null:
		if node is BaseButton or node is Range or node is LineEdit or node is TextEdit:
			return true
		node = node.get_parent()
	return false


func set_phone_drive(stick_x: float, stick_y: float) -> void:
	if input_locked:
		_phone_drive = Vector2.ZERO
		return
	var stick := Vector2(stick_x, stick_y)
	_phone_drive = stick if stick.length() >= 0.08 else Vector2.ZERO


func orbit_look(look_x: float, look_y: float, delta: float) -> void:
	if input_locked:
		return
	if absf(look_x) < 0.06 and absf(look_y) < 0.06:
		return
	yaw -= look_x * 1.7 * delta
	pitch = clampf(pitch + look_y * 70.0 * delta, min_pitch, max_pitch)
	_update_rotation()


func _update_rotation() -> void:
	rotation = Vector3(deg_to_rad(pitch), yaw, 0)


func _move_free(delta: float) -> void:
	if _chat_focused():
		return
	var cam := camera
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	fwd.y = 0.0
	right.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
	if right.length_squared() > 0.0001:
		right = right.normalized()
	var wish := Vector3.ZERO
	_look_free(delta)
	if Input.is_physical_key_pressed(KEY_W):
		wish += fwd
	if Input.is_physical_key_pressed(KEY_S):
		wish -= fwd
	if Input.is_physical_key_pressed(KEY_A):
		wish -= right
	if Input.is_physical_key_pressed(KEY_D):
		wish += right
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		wish.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		wish.y -= 1.0
	if _phone_drive.length_squared() > 0.0001:
		wish += fwd * _phone_drive.y + right * _phone_drive.x
	if wish.length_squared() < 0.0001:
		return
	var speed := move_speed * (2.2 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position += wish.normalized() * speed * delta


func _look_free(delta: float) -> void:
	var yaw_step := 1.7 * delta
	var pitch_step := 70.0 * delta
	var turned := false
	if Input.is_physical_key_pressed(KEY_LEFT):
		yaw += yaw_step
		turned = true
	if Input.is_physical_key_pressed(KEY_RIGHT):
		yaw -= yaw_step
		turned = true
	if Input.is_physical_key_pressed(KEY_UP):
		pitch = clampf(pitch + pitch_step, min_pitch, max_pitch)
		turned = true
	if Input.is_physical_key_pressed(KEY_DOWN):
		pitch = clampf(pitch - pitch_step, min_pitch, max_pitch)
		turned = true
	if turned:
		_update_rotation()


func _chat_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _update_xray() -> void:
	if camera == null or target == null or not is_instance_valid(target) or overview or free_roam:
		_set_xray(Vector3.ZERO, Vector3.ZERO, 0.0)
		return
	if not is_inside_tree():
		return
	var ball_at := target.global_position + Vector3(0.0, 0.16, 0.0)
	var cam_at := camera.global_position
	var span := cam_at.distance_to(ball_at)
	var radius := clampf(1.15 + span * 0.06, 1.15, 2.2)
	_set_xray(ball_at, cam_at, radius)


func _set_xray(ball_at: Vector3, cam_at: Vector3, radius: float) -> void:
	MapKit.set_xray(ball_at, cam_at, radius)
