extends RigidBody3D

@export var stop_velocity_threshold: float = 0.15
@export var stop_duration_required: float = 0.20
@export var min_speed: float = 2.0
@export var max_speed: float = 40.0

var is_moving: bool = false
var stop_timer: float = 0.0
var start_position: Vector3
var last_safe_position: Vector3

func _ready() -> void:
	print("Ball is ready")
	

func hit(direction: Vector3, power: float) -> void:
	if is_moving:
		print("Already moving")
		return
	
	sleeping = false
	start_position = global_position
	
	# need to determine the up and "intended" direction of the ball
	var clamped_power = clamp(power, 0.0, 1.0)
	var speed = lerp(min_speed, max_speed, clamped_power)
	
	var launch_dir = direction.normalized()
	var impulse = launch_dir * speed * mass

	apply_central_impulse(impulse)
	is_moving = true
	# print("velocity after impulse: ", linear_velocity)
	print("power: ", power, " | speed: ", speed)

func _physics_process(delta: float) -> void:
	if is_moving:
		if linear_velocity.length() < stop_velocity_threshold:
			stop_timer += delta
			if stop_timer >= stop_duration_required:
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				is_moving = false
				sleeping = true
				stop_timer = 0.0
				last_safe_position = global_position
				var distance = start_position.distance_to(global_position)
				print("Ball travelled: ", distance, " m")
		else:
			stop_timer = 0.0

func reset_to(position: Vector3) -> void:
	global_position = position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	is_moving = false
	stop_timer = 0.0
	sleeping = false
