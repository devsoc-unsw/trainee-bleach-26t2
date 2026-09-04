class_name CameraRig
extends Node3D

@export var target: Node3D
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 3.0
@export var max_zoom: float = 36.0
@export var overview_zoom: float = 28.0
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


func _ready() -> void:
	print("Camera ready")
	spring_arm.spring_length = 8.0
	_update_rotation()


func _physics_process(delta: float) -> void:
	if free_roam:
		_move_free(delta)
		return
	if target:
		global_position = target.global_position


func set_follow(node: Node3D) -> void:
	free_roam = false
	target = node
	overview = false
	spring_arm.collision_mask = 2


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
	spring_arm.collision_mask = 2
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
		spring_arm.collision_mask = 2
	_update_rotation()


func toggle_overview() -> void:
	set_overview(not overview)


func _unhandled_input(event: InputEvent) -> void:
	
	if event is InputEventMouseButton:		
		# Mouse capabilities
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if event.pressed and get_viewport().gui_get_hovered_control() != null:
					return
				dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				#print("Zooming out")
				spring_arm.spring_length = clamp(
					spring_arm.spring_length - zoom_speed,
					min_zoom,
					max_zoom
				)
			MOUSE_BUTTON_WHEEL_DOWN:
				#print("Zooming in")
				spring_arm.spring_length = clamp(
					spring_arm.spring_length + zoom_speed,
					min_zoom,
					max_zoom
				)
				#print("spring_length now: ", spring_arm.spring_length)
	
	# Trackpad capabilities
	elif event is InputEventPanGesture:
		#print("zooming")
		spring_arm.spring_length = clamp(
			spring_arm.spring_length + event.delta.y * zoom_speed,
			min_zoom,
			max_zoom
		)

	elif event is InputEventMouseMotion and dragging:
		#print("Moving camera")
		yaw -= event.relative.x * orbit_speed
		pitch = clamp(pitch - event.relative.y * orbit_speed * 57.3, min_pitch, max_pitch)
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
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		wish += fwd
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		wish -= fwd
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		wish -= right
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		wish += right
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		wish.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		wish.y -= 1.0
	if wish.length_squared() < 0.0001:
		return
	var speed := move_speed * (2.2 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position += wish.normalized() * speed * delta


func _chat_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit
