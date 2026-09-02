extends Node3D

@export var ball: RigidBody3D
@export var cup: Area3D

@onready var hole_summary_panel: Control = $UILayer/HoleSummaryPanel
@onready var summary_title_label: Label = $UILayer/HoleSummaryPanel/Panel/TitleLabel
@onready var summary_results_container: VBoxContainer = $UILayer/HoleSummaryPanel/Panel/ResultsContainer

var current_hole_index: int = 0
var current_par: int = 0
var current_strokes: int = 0

const BALL_STATE_SEND_INTERVAL: float = 1.0 / 15.0
var _send_timer: float = 0.0
var _was_moving: bool = false

func _ready() -> void:
	NetworkClient.hole_started.connect(_on_hole_started)
	NetworkClient.stroke_updated.connect(_on_stroke_updated)
	NetworkClient.hole_ended.connect(_on_hole_ended)
	cup.ball_sunk.connect(_on_ball_sunk)
	hole_summary_panel.visible = false

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
	hole_summary_panel.visible = false
	ball.reset_to(spawn)

func _on_stroke_updated(player_id: String, hole_index: int, strokes: int) -> void:
	if player_id != NetworkClient.my_player_id:
		return
	current_strokes = strokes
	# TODO: update HUD display once it exists (CL-13)

func _on_ball_sunk() -> void:
	print(ball.global_position)
	NetworkClient.send_holed(ball.global_position)

func _on_hole_ended(hole_index: int, results: Array) -> void:
	summary_title_label.text = "Hole %d Complete" % (hole_index + 1)

	for child in summary_results_container.get_children():
		child.queue_free()

	for r in results:
		var row := Label.new()
		row.text = "%s  —  %d strokes" % [r["name"], r["strokes"]]
		row.add_theme_color_override("font_color", Color(r["colour"]))
		summary_results_container.add_child(row)

	hole_summary_panel.visible = true
