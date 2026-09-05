extends Node3D

@export var ball: RigidBody3D
@export var cup: Area3D

@onready var camera_rig: Node3D = $CameraRig
@onready var hole_summary_panel: Control = $UILayer/HoleSummaryPanel
@onready var summary_title_label: Label = $UILayer/HoleSummaryPanel/Panel/TitleLabel
@onready var summary_subtitle_label: Label = $UILayer/HoleSummaryPanel/Panel/SubtitleLabel
@onready var summary_results_container: VBoxContainer = $UILayer/HoleSummaryPanel/Panel/ResultsContainer
@onready var spectate_panel: Control = $UILayer/SpectatePanel
@onready var spectate_label: Label = $UILayer/SpectatePanel/SpectateLabel

var _summary_tween: Tween

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
	hole_summary_panel.modulate.a = 1.0
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
	_enter_spectate()

func _on_hole_ended(hole_index: int, results: Array) -> void:
	_exit_spectate()
	_clear_ghosts()
	_show_hole_leaderboard(hole_index, results)

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
	var hint := "  (Tab to switch)" if _remaining_ghost_ids().size() > 1 else ""
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

func _show_hole_leaderboard(hole_index: int, results: Array) -> void:
	summary_title_label.text = "Hole %d Results" % (hole_index + 1)
	var is_last_hole := NetworkClient.hole_count > 0 and hole_index + 1 >= NetworkClient.hole_count
	summary_subtitle_label.text = "Final results incoming..." if is_last_hole else "Next hole starting soon"

	for child in summary_results_container.get_children():
		child.queue_free()

	var header := _make_leaderboard_row("#", "Name", "Hole", "Par", "Total", Color.WHITE, false)
	header.modulate.a = 0.7
	summary_results_container.add_child(header)

	var ranked: Array = results.duplicate()
	ranked.sort_custom(func(a, b):
		if int(a["strokes"]) == int(b["strokes"]):
			return String(a["name"]) < String(b["name"])
		return int(a["strokes"]) < int(b["strokes"])
	)

	var rows: Array[Control] = []
	var place := 1
	var prev_strokes: int = -1
	for i in ranked.size():
		var r: Dictionary = ranked[i]
		var strokes := int(r["strokes"])
		if i > 0 and strokes != prev_strokes:
			place = i + 1
		prev_strokes = strokes
		var completed: bool = r.get("completed", true)
		var row := _make_leaderboard_row(
			"#%d" % place,
			String(r["name"]),
			str(strokes),
			_rel_to_par_text(int(r.get("relToPar", 0)), completed),
			str(int(r.get("total", strokes))),
			Color(r["colour"]),
			String(r.get("playerId", "")) == NetworkClient.my_player_id
		)
		row.modulate.a = 0.0
		summary_results_container.add_child(row)
		rows.append(row)

	hole_summary_panel.visible = true
	hole_summary_panel.modulate.a = 0.0
	if _summary_tween:
		_summary_tween.kill()
	_summary_tween = create_tween()
	_summary_tween.tween_property(hole_summary_panel, "modulate:a", 1.0, 0.25)
	# reveal last place first, then work up to 1st
	for i in range(rows.size() - 1, -1, -1):
		_summary_tween.tween_property(rows[i], "modulate:a", 1.0, 0.22)

func _make_leaderboard_row(
	place_text: String,
	player_name: String,
	hole_text: String,
	par_text: String,
	total_text: String,
	colour: Color,
	is_local: bool
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var place_l := Label.new()
	place_l.text = place_text
	place_l.custom_minimum_size = Vector2(44, 0)
	row.add_child(place_l)

	var name_l := Label.new()
	name_l.text = player_name + ("  (you)" if is_local else "")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_color_override("font_color", colour)
	row.add_child(name_l)

	var hole_l := Label.new()
	hole_l.text = hole_text
	hole_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hole_l.custom_minimum_size = Vector2(48, 0)
	row.add_child(hole_l)

	var par_l := Label.new()
	par_l.text = par_text
	par_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	par_l.custom_minimum_size = Vector2(48, 0)
	row.add_child(par_l)

	var total_l := Label.new()
	total_l.text = total_text
	total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_l.custom_minimum_size = Vector2(56, 0)
	row.add_child(total_l)

	if is_local:
		row.modulate = Color(1.1, 1.1, 0.85)

	return row

func _rel_to_par_text(rel: int, completed: bool) -> String:
	if not completed:
		return "DNF"
	if rel == 0:
		return "E"
	if rel > 0:
		return "+%d" % rel
	return str(rel)

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
