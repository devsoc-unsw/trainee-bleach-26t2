extends Node

@onready var current_screen: Node = null

const LOBBY_SCENE := preload("res://scenes/lobby.tscn")
const COURSE_SCENE := preload("res://scenes/course.tscn")

func _ready() -> void:
	NetworkClient.state_changed.connect(_on_state_changed)
	_swap_screen(LOBBY_SCENE)


func _on_state_changed(new_state: NetworkClient.GameState) -> void:
	match new_state:
		NetworkClient.GameState.LOBBY, NetworkClient.GameState.COUNTDOWN:
			if not (current_screen and current_screen.scene_file_path == LOBBY_SCENE.resource_path):
				_swap_screen(LOBBY_SCENE)
		NetworkClient.GameState.HOLE_ACTIVE, NetworkClient.GameState.HOLE_SUMMARY:
			if not (current_screen and current_screen.scene_file_path == COURSE_SCENE.resource_path):
				_swap_screen(COURSE_SCENE)
			pass
		NetworkClient.GameState.MATCH_END:
			pass # TODO: swap to scoreboard.tscn

func _swap_screen(scene: PackedScene) -> void:
	if current_screen:
		current_screen.queue_free()
	current_screen = scene.instantiate()
	add_child(current_screen)


# TODO: replace this scene with actual game scenes:
#   scenes/lobby.tscn       - name entry, room code, player list, start button
#   scenes/course.tscn      - 3D hole with ball, camera, aiming arrow
#   scenes/scoreboard.tscn  - live scores, hole summary, final results
#
# TODO: scripts to create:
#   scripts/ball.gd          - RigidBody3D, shot input, power-scaled inaccuracy (done)
#   scripts/camera.gd        - orbit camera with SpringArm3D, free-look (done)
#   scripts/shot_input.gd    - pull-back drag, power calc, arrow preview with jitter (done)
#   scripts/ghost_ball.gd    - non-colliding visual for other players, interpolated
#   scripts/hole_manager.gd  - loads hole scenes, handles OOB/water/cup areas
#   scripts/hud.gd           - stroke counter, timer, toasts
