extends Area3D

signal ball_sunk

@export var max_sink_speed: float = 5.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# only the ball can enter, not camera
func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D:
		return
	if not body.has_method("hit"):
		return

	var speed = body.linear_velocity.length()
	if speed <= max_sink_speed:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true
		print("Ball in hole")
		ball_sunk.emit()
	else:
		print("Ball entered cup too fast")
