extends Node3D

@export var ball: RigidBody3D
@export var cup: Area3D

@onready var camera_rig: Node3D = $CameraRig
@onready var hole_summary_panel: Control = $UILayer/HoleSummaryPanel
@onready var summary_title_label: Label = $UILayer/HoleSummaryPanel/Panel/TitleLabel
@onready var summary_results_container: VBoxContainer = $UILayer/HoleSummaryPanel/Panel/ResultsContainer
@onready var spectate_panel: Control = $UILayer/SpectatePanel
@onready var spectate_label: Label = $UILayer/SpectatePanel/SpectateLabel

var current_hole_index: int = 0
var current_par: int = 0
var current_strokes: int = 0

const BALL_STATE_SEND_INTERVAL: float = 1.0 / 15.0
var _send_timer: float = 0.0
var _was_moving: bool = false

var _ghosts: Dictionary = {}
var _spectating: bool = false
var _spectate_id: String = ""

func _ready() -> void:
	NetworkClient.hole_started.connect(_on_hole_started)
	NetworkClient.stroke_updated.connect(_on_stroke_updated)
	NetworkClient.hole_ended.connect(_on_hole_ended)
	NetworkClient.snapshot_received.connect(_on_snapshot_received)
	NetworkClient.player_left.connect(_on_player_left)
	cup.ball_sunk.connect(_on_ball_sunk)
	hole_summary_panel.visible = false
	spectate_panel.visible = false
	_tint_local_ball()

func _process(delta: float) -> void:
	if NetworkClient.local_holed:
		return
	if ball.is_moving:
		_send_timer += delta
		if _send_timer >= BALL_STATE_SEND_INTERVAL:
			_send_timer = 0.0
			NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, false)
		_was_moving = true
	elif _was_moving:
		NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, true)
		_was_moving = false

func _unhandled_input(event: InputEvent) -> void:
	if not _spectating:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			_cycle_spectate_target()
			get_viewport().set_input_as_handled()

func _on_hole_started(hole_index: int, par: int, _timer_ms: float, spawn: Vector3) -> void:
	current_hole_index = hole_index
	current_par = par
	current_strokes = 0
	_was_moving = false
	_send_timer = 0.0
	hole_summary_panel.visible = false
	_exit_spectate()
	_clear_ghosts()
	_tint_local_ball()
	ball.reset_to(spawn)

func _on_stroke_updated(player_id: String, hole_index: int, strokes: int) -> void:
	if player_id != NetworkClient.my_player_id:
		return
	current_strokes = strokes
	# TODO: update HUD display once it exists (CL-13)

func _on_ball_sunk() -> void:
	NetworkClient.local_holed = true
	NetworkClient.send_holed(ball.global_position)
	if not NetworkClient.is_ffa():
		_enter_spectate()

func _on_hole_ended(hole_index: int, results: Array) -> void:
	_exit_spectate()
	_clear_ghosts()
	summary_title_label.text = "Hole %d Complete" % (hole_index + 1)

	for child in summary_results_container.get_children():
		child.queue_free()

	for r in results:
		var row := Label.new()
		row.text = "%s  —  %d strokes" % [r["name"], r["strokes"]]
		row.add_theme_color_override("font_color", Color(r["colour"]))
		summary_results_container.add_child(row)

	hole_summary_panel.visible = true

func _on_snapshot_received(_tick: int, balls: Array) -> void:
	if not _should_show_ghosts():
		_clear_ghosts()
		return

	var seen: Dictionary = {}
	for ball_data in balls:
		var id: String = ball_data["id"]
		if id == NetworkClient.my_player_id:
			continue
		var is_holed: bool = ball_data["holed"]
		if not NetworkClient.is_ffa() and is_holed:
			_remove_ghost(id)
			continue
		seen[id] = true
		_upsert_ghost(id, ball_data)

	for id in _ghosts.keys():
		if not seen.has(id):
			_remove_ghost(id)

	if _spectating:
		_refresh_spectate_target()

func _on_player_left(player_id: String) -> void:
	_remove_ghost(player_id)
	if _spectating:
		_refresh_spectate_target()

func _should_show_ghosts() -> bool:
	if NetworkClient.is_ffa():
		return true
	return NetworkClient.local_holed

func _upsert_ghost(id: String, ball_data: Dictionary) -> void:
	var pos_arr: Array = ball_data["pos"]
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var ghost: GhostBall = _ghosts.get(id)
	if ghost == null:
		ghost = GhostBall.new()
		ghost.setup(id, _player_name(id), _player_colour(id))
		add_child(ghost)
		_ghosts[id] = ghost
	ghost.apply_state(pos, ball_data["holed"])

func _remove_ghost(id: String) -> void:
	if not _ghosts.has(id):
		return
	var ghost: GhostBall = _ghosts[id]
	_ghosts.erase(id)
	if is_instance_valid(ghost):
		ghost.queue_free()
	if _spectate_id == id:
		_spectate_id = ""

func _clear_ghosts() -> void:
	for id in _ghosts.keys():
		var ghost: GhostBall = _ghosts[id]
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()
	_spectate_id = ""

func _enter_spectate() -> void:
	_spectating = true
	spectate_panel.visible = true
	spectate_label.text = "Spectating — waiting for other players"
	_refresh_spectate_target()

func _exit_spectate() -> void:
	_spectating = false
	_spectate_id = ""
	spectate_panel.visible = false
	if camera_rig:
		camera_rig.target = ball

func _refresh_spectate_target() -> void:
	if not _spectating:
		return
	var remaining := _remaining_ghost_ids()
	if remaining.is_empty():
		spectate_label.text = "Spectating — waiting for other players"
		if camera_rig:
			camera_rig.target = ball
		return
	if _spectate_id == "" or not remaining.has(_spectate_id):
		_spectate_id = remaining[0]
	_apply_spectate_target()

func _cycle_spectate_target() -> void:
	var remaining := _remaining_ghost_ids()
	if remaining.size() <= 1:
		return
	var idx := remaining.find(_spectate_id)
	_spectate_id = remaining[(idx + 1) % remaining.size()]
	_apply_spectate_target()

func _apply_spectate_target() -> void:
	if not _ghosts.has(_spectate_id):
		return
	var ghost: GhostBall = _ghosts[_spectate_id]
	if camera_rig:
		camera_rig.target = ghost
	var hint := "  (Tab to switch)" if _ghosts.size() > 1 else ""
	spectate_label.text = "Spectating %s — right-drag to look%s" % [ghost.display_name, hint]

func _remaining_ghost_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _ghosts.keys():
		var ghost: GhostBall = _ghosts[id]
		if is_instance_valid(ghost) and not ghost.holed:
			ids.append(id)
	ids.sort()
	return ids

func _player_name(id: String) -> String:
	if NetworkClient.players.has(id):
		return NetworkClient.players[id]["name"]
	return "Player"

func _player_colour(id: String) -> Color:
	if NetworkClient.players.has(id):
		return Color(NetworkClient.players[id]["colour"])
	return Color.WHITE

func _tint_local_ball() -> void:
	if ball == null:
		return
	var colour := Color.WHITE
	if NetworkClient.players.has(NetworkClient.my_player_id):
		colour = Color(NetworkClient.players[NetworkClient.my_player_id]["colour"])
	var mesh := ball.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mesh.material_override = mat
