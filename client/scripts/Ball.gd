class_name PuttBall
extends RigidBody3D

signal movement_started
signal movement_stopped

const BASE_RADIUS := 0.15
const SHRINK_SCALE := 0.45
const SHIELD_GREY := Color("8E8A84")

@export var stop_velocity_threshold: float = 0.18
@export var stop_duration_required: float = 0.08
@export var min_speed: float = 2.0
@export var max_speed: float = 30.0

var is_moving: bool = false
var is_holed: bool = false
var stop_timer: float = 0.0
var start_position: Vector3
var last_safe_position: Vector3
var _look := Color("E23B3B")
var _size := 1.0

func _ready() -> void:
	print("Ball is ready")
	last_safe_position = global_position

func hit(direction: Vector3, power: float) -> void:
	if is_moving or is_holed:
		print("Already moving")
		return
	
	sleeping = false
	start_position = global_position
	
	var clamped_power := clampf(power, 0.0, 1.0)
	var speed := clamped_power * max_speed
	if speed < 0.05:
		return
	
	var launch_dir = direction.normalized()
	var impulse = launch_dir * speed * mass

	apply_central_impulse(impulse)
	is_moving = true
	movement_started.emit()
	# print("velocity after impulse: ", linear_velocity)
	print("power: ", power, " | speed: ", speed)


func nudge(velocity: Vector3) -> void:
	if is_holed:
		return
	if velocity.length_squared() < 0.01:
		return
	if velocity.length() < 3.5:
		velocity = velocity.normalized() * 3.5
	freeze = false
	sleeping = false
	if not is_moving:
		start_position = global_position
		is_moving = true
		stop_timer = 0.0
		movement_started.emit()
	linear_velocity += velocity
	if linear_velocity.length() < 3.5:
		linear_velocity = velocity.normalized() * 3.5


func _physics_process(delta: float) -> void:
	if not is_moving:
		return
	if linear_velocity.length() < stop_velocity_threshold:
		stop_timer += delta
		if stop_timer >= stop_duration_required:
			_stop_rolling()
	else:
		stop_timer = 0.0


func _stop_rolling() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	stop_timer = 0.0
	sleeping = true
	if not is_moving:
		return
	is_moving = false
	last_safe_position = global_position
	var distance := start_position.distance_to(global_position)
	print("Ball travelled: ", distance, " m")
	movement_stopped.emit()

func sink() -> void:
	is_holed = true
	is_moving = false
	stop_timer = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true

func reset_to(to: Vector3) -> void:
	freeze = true
	global_position = to
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	is_moving = false
	is_holed = false
	stop_timer = 0.0
	last_safe_position = to
	freeze = false
	sleeping = false


func radius() -> float:
	return BASE_RADIUS * _size


func set_body_scale(amount: float) -> void:
	_size = amount
	apply_visual_size(self, amount)


static func apply_visual_size(ball: Node3D, amount: float) -> void:
	for path in ["MeshInstance3D", "CollisionShape3D", "Shadow"]:
		var node := ball.get_node_or_null(path) as Node3D
		if node:
			node.scale = Vector3.ONE * amount


func apply_powers(shield: bool, shrink: bool) -> void:
	set_body_scale(SHRINK_SCALE if shrink else 1.0)
	_paint(SHIELD_GREY if shield else _look)


func apply_color(tint: Color) -> void:
	_look = tint
	_paint(tint)


func _paint(tint: Color) -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.material_override == null:
		return
	var mat := mesh.material_override.duplicate() as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("color_lit", tint.lerp(Color.WHITE, 0.12))
	mat.set_shader_parameter("color_shade", tint.darkened(0.28))
	mat.set_shader_parameter("dimple_color", tint.darkened(0.14))
	mat.set_shader_parameter("stripe_color", tint)
	mat.set_shader_parameter("stripe_width", 0.0)
	mesh.material_override = mat
