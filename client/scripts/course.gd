extends Node3D

@export var ball: RigidBody3D
@export var cup: Area3D

var current_hole_index: int = 0
var current_par: int = 0
var current_strokes: int = 0

const BALL_STATE_SEND_INTERVAL: float = 1.0 / 15.0
var _send_timer: float = 0.0
var _was_moving: bool = false

func _ready() -> void:
	NetworkClient.hole_started.connect(_on_hole_started)
	NetworkClient.stroke_updated.connect(_on_stroke_updated)
	cup.ball_sunk.connect(_on_ball_sunk)

func _process(delta: float) -> void:
	if ball.is_moving:
		_send_timer += delta
		if _send_timer >= BALL_STATE_SEND_INTERVAL:
			_send_timer = 0.0
			NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, false)
		_was_moving = true
	elif _was_moving:
		# just stopped -- send one final update so server knows we're at rest
		NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, true)
		_was_moving = false

func _on_hole_started(hole_index: int, par: int, _timer_ms: float, spawn: Vector3) -> void:
	current_hole_index = hole_index
	current_par = par
	current_strokes = 0
	ball.reset_to(spawn)

func _on_stroke_updated(player_id: String, hole_index: int, strokes: int) -> void:
	if player_id != NetworkClient.my_player_id:
		return
	current_strokes = strokes
	# TODO: update HUD display once it exists (CL-13)

func _on_ball_sunk() -> void:
	print(ball.global_position)
	NetworkClient.send_holed(ball.global_position)
	
