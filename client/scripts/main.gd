extends Control

@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	NetworkClient.connection_status_changed.connect(_on_status_changed)
	NetworkClient.message_received.connect(_on_message_received)
	status_label.text = "Initialising..."


func _on_status_changed(status: String) -> void:
	status_label.text = "Status: " + status
	if status == "Connected":
		NetworkClient.send_join("some name")
		NetworkClient.send_ready()
		NetworkClient.send_start_match()


func _on_message_received(data: Dictionary) -> void:
	var reply_text := JSON.stringify(data)
	status_label.text = status_label.text + "\n\nServer echoed:\n" + reply_text


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()

# TODO: replace this scene with actual game scenes:
#   scenes/lobby.tscn       - name entry, room code, player list, start button
#   scenes/course.tscn      - 3D hole with ball, camera, aiming arrow
#   scenes/scoreboard.tscn  - live scores, hole summary, final results
#
# TODO: scripts to create:
#   scripts/ball.gd          - RigidBody3D, shot input, power-scaled inaccuracy (done)
#   scripts/camera.gd        - orbit camera with SpringArm3D, free-look (done)
#   scripts/ghost_ball.gd    - non-colliding visual for other players, interpolated
#   scripts/shot_input.gd    - pull-back drag, power calc, arrow preview with jitter (done)
#   scripts/hole_manager.gd  - loads hole scenes, handles OOB/water/cup areas
#   scripts/hud.gd           - stroke counter, timer, toasts
