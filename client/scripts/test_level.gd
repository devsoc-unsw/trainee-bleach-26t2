extends Node3D

@onready var hud = $HUD
@onready var aim_controller: Node3D = $AimController
@onready var camera_rig: CameraRig = $CameraRig
@onready var hole: Node3D = $Hole
@onready var ball: PuttBall = $Ball
@onready var out_of_bounds: Area3D = $OutOfBounds


func _ready() -> void:
	hud.set_hole(1)
	hud.set_par(3)
	hud.set_strokes(0)
	hud.set_ball_state(BallStatusIndicator.State.READY)
	if hud.has_method("set_ball_preview"):
		hud.set_ball_preview(ball)

	if aim_controller.has_signal("shot_taken"):
		aim_controller.shot_taken.connect(_on_shot_taken)
	if aim_controller.has_signal("aiming_changed"):
		aim_controller.aiming_changed.connect(_on_aiming_changed)
	if aim_controller.has_signal("aim_updated"):
		aim_controller.aim_updated.connect(_on_aim_updated)

	if ball.has_signal("movement_started"):
		ball.movement_started.connect(_on_ball_movement_started)
	if ball.has_signal("movement_stopped"):
		ball.movement_stopped.connect(_on_ball_movement_stopped)

	hud.camera_pressed.connect(_on_camera_pressed)
	hud.look_pressed.connect(_on_look_pressed)
	hole.ball_sunk.connect(_on_ball_sunk)
	if hole.has_signal("sunk_finished"):
		hole.sunk_finished.connect(_on_sunk_finished)
	out_of_bounds.oob_triggered.connect(_on_oob)


func _on_shot_taken(_direction: Vector3, _power: float) -> void:
	hud.add_stroke()


func _on_aiming_changed(is_aiming: bool) -> void:
	if is_aiming:
		hud.set_ball_state(BallStatusIndicator.State.AIMING)
	elif ball.is_holed:
		hud.set_ball_state(BallStatusIndicator.State.HOLED)
	elif ball.is_moving:
		hud.set_ball_state(BallStatusIndicator.State.ROLLING)
	else:
		hud.set_ball_state(BallStatusIndicator.State.READY)


func _on_aim_updated(direction: Vector3, power: float) -> void:
	hud.set_aim_preview(direction, power)


func _on_ball_movement_started() -> void:
	hud.set_ball_state(BallStatusIndicator.State.ROLLING)


func _on_ball_movement_stopped() -> void:
	if ball.is_holed:
		hud.set_ball_state(BallStatusIndicator.State.HOLED)
		return
	hud.set_ball_state(BallStatusIndicator.State.READY)


func _on_camera_pressed() -> void:
	if camera_rig.has_method("reset_view"):
		camera_rig.reset_view()


func _on_look_pressed() -> void:
	if camera_rig.has_method("set_overview"):
		camera_rig.set_overview(true)


func _on_ball_sunk() -> void:
	hud.stop_timer()
	hud.set_ball_state(BallStatusIndicator.State.HOLED)


func _on_sunk_finished() -> void:
	if hole.has_method("show_results"):
		hole.show_results(hud.hole, hud.par, hud.strokes, hud.timer_value.text)


func _on_oob() -> void:
	hud.set_ball_state(BallStatusIndicator.State.OOB)
