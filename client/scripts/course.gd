extends Node3D

const BALL_SCENE := preload("res://scenes/Ball.tscn")
const GHOST_SCRIPT := preload("res://scripts/ghost_ball.gd")
const SYNC_HZ := 15.0
const SPECTATE_DELAY := 1.1

@onready var hud = $HUD
@onready var aim_controller: Node3D = $AimController
@onready var camera_rig: CameraRig = $CameraRig
@onready var hole: Node3D = $Hole
@onready var ball: PuttBall = $Ball
@onready var out_of_bounds: Area3D = $OutOfBounds

var _map: Node3D
var _ghosts: Dictionary = {}
var _sync_acc := 0.0
var _spectating := false
var _spectate_follow := true
var _spectate_index := 0
var _holed_ids: Dictionary = {}


func _ready() -> void:
	_load_map()

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
	hud.show_players_changed.connect(_on_show_players_changed)
	hud.quit_pressed.connect(_on_quit_pressed)
	hud.courses_pressed.connect(_on_courses_pressed)
	hud.chat_submitted.connect(_on_chat_submitted)
	hud.spectate_follow_pressed.connect(_on_spectate_follow)
	hud.spectate_free_pressed.connect(_on_spectate_free)
	hud.spectate_prev_pressed.connect(func() -> void: _cycle_spectate(-1))
	hud.spectate_next_pressed.connect(func() -> void: _cycle_spectate(1))
	ball.apply_color(GameSession.my_color)
	_setup_scoreboard()
	_setup_multiplayer()


func _load_map() -> void:
	var spec: Dictionary = GameSession.get_map()
	var packed: PackedScene = load(spec.scene) as PackedScene
	if packed == null:
		push_error("Could not load map scene: %s" % spec.scene)
		return
	_map = packed.instantiate() as Node3D
	if _map == null:
		push_error("Map scene did not instantiate: %s" % spec.scene)
		return
	_map.name = "Map"
	add_child(_map)
	move_child(_map, 0)

	var tee := _find_marker("Tee")
	var hole_point := _find_marker("HolePoint")
	var tee_pos: Vector3 = Vector3(0.0, 0.2, 0.0)
	var hole_pos: Vector3 = Vector3(0.0, 0.2, -20.0)
	if tee != null:
		tee_pos = tee.global_position
	if hole_point != null:
		hole_pos = hole_point.global_position

	hole.global_position = hole_pos
	_spawn_ball(tee_pos)

	hud.set_hole(int(spec.hole))
	hud.set_par(int(spec.par))
	camera_rig.overview_zoom = float(spec.get("overview_zoom", 28.0))
	camera_rig.max_zoom = maxf(camera_rig.max_zoom, camera_rig.overview_zoom)


func _spawn_ball(tee: Vector3) -> void:
	ball.freeze = true
	ball.sleeping = true
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = tee + Vector3(0.0, 0.5, 0.0)
	ball.last_safe_position = ball.global_position
	call_deferred("_finish_spawn", tee)


func _finish_spawn(tee: Vector3) -> void:
	await get_tree().physics_frame
	var pos := _ground_snap(tee)
	ball.freeze = true
	ball.global_position = pos
	ball.last_safe_position = pos
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, ball.global_transform)
	ball.sleeping = false
	ball.freeze = false


func _ground_snap(tee: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		tee + Vector3(0.0, 6.0, 0.0),
		tee + Vector3(0.0, -4.0, 0.0)
	)
	query.exclude = [ball.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return tee + Vector3(0.0, 0.16, 0.0)
	return hit.position + Vector3(0.0, 0.13, 0.0)


func _find_marker(marker_name: String) -> Node3D:
	if _map == null:
		return null
	var direct := _map.get_node_or_null(marker_name)
	if direct is Node3D:
		return direct as Node3D
	return _map.find_child(marker_name, true, false) as Node3D


func _process(delta: float) -> void:
	if not GameSession.online:
		return
	_sync_acc += delta
	if _sync_acc < 1.0 / SYNC_HZ:
		return
	_sync_acc = 0.0
	NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, not ball.is_moving)


func _setup_scoreboard() -> void:
	var people: Array = []
	if GameSession.online:
		var listed: Variant = GameSession.active_lobby.get("player_list", [])
		if listed is Array:
			people = listed
	else:
		people = [{
			"id": "local",
			"name": GameSession.player_name,
			"color": GameSession.my_color,
			"strokes": 0,
			"holed": false,
		}]
	hud.set_roster(people)
	hud.set_chat_visible(GameSession.online)


func _setup_multiplayer() -> void:
	if not GameSession.online:
		return
	ball.apply_color(GameSession.my_color)
	NetworkClient.snapshot_received.connect(_on_snapshot)
	NetworkClient.stroke_updated.connect(_on_stroke_updated)
	NetworkClient.player_holed.connect(_on_player_holed)
	NetworkClient.chat_received.connect(_on_chat_received)
	NetworkClient.lobby_state_received.connect(_on_lobby_state)
	NetworkClient.hole_ended.connect(_on_hole_ended)
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if not p is Dictionary:
				continue
			var id := str(p.get("id", ""))
			if id.is_empty() or id == NetworkClient.player_id:
				continue
			_ensure_ghost(id, Color(str(p.get("color", "#4CB8B0"))), ball.global_position, str(p.get("name", "Player")))


func _on_snapshot(balls: Array) -> void:
	for snap in balls:
		if not snap is Dictionary:
			continue
		var id := str(snap.get("id", ""))
		if id.is_empty() or id == NetworkClient.player_id:
			continue
		var pos := Vector3(float(snap.get("x", 0.0)), float(snap.get("y", 0.5)), float(snap.get("z", 0.0)))
		var ghost := _ensure_ghost(id, _color_for(id), pos, _player_name(id))
		ghost.set("target", pos)


func _color_for(id: String) -> Color:
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if p is Dictionary and str(p.get("id", "")) == id:
				return Color(str(p.get("color", "#4CB8B0")))
	return Color("4CB8B0")


func _ensure_ghost(id: String, tint: Color, pos: Vector3, player_name: String = "") -> Node3D:
	if _ghosts.has(id) and is_instance_valid(_ghosts[id]):
		return _ghosts[id]
	var ghost: Node3D = BALL_SCENE.instantiate()
	ghost.set_script(GHOST_SCRIPT)
	add_child(ghost)
	if ghost.has_method("setup"):
		if player_name.is_empty():
			player_name = _player_name(id)
		ghost.call("setup", id, tint, pos, player_name)
	ghost.visible = _ghosts_visible()
	_ghosts[id] = ghost
	return ghost


func _local_holed() -> bool:
	return bool(_holed_ids.get(NetworkClient.player_id, false)) or (ball != null and bool(ball.get("is_holed")))


func _ghosts_visible() -> bool:
	if GameSession.is_turn_by_turn() and not _local_holed() and not _spectating:
		return false
	return GameSession.show_players or _spectating


func _on_show_players_changed(enabled: bool) -> void:
	GameSession.show_players = enabled
	_apply_ghost_visibility()


func _apply_ghost_visibility() -> void:
	var show := _ghosts_visible()
	for ghost in _ghosts.values():
		if ghost is Node3D and is_instance_valid(ghost):
			ghost.visible = show


func _on_shot_taken(_direction: Vector3, _power: float) -> void:
	hud.add_stroke()
	var id := NetworkClient.player_id if GameSession.online else "local"
	hud.set_player_score(id, hud.strokes)
	if GameSession.online:
		NetworkClient.send_shot()


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
	if GameSession.online:
		NetworkClient.send_ball_state(ball.global_position, Vector3.ZERO, true)
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


func _on_courses_pressed() -> void:
	if GameSession.online:
		return
	GameSession.open_select()


func _on_quit_pressed() -> void:
	GameSession.leave_match()


func _on_chat_submitted(text: String) -> void:
	NetworkClient.send_chat(text)


func _on_chat_received(payload: Dictionary) -> void:
	hud.append_chat(payload)


func _on_stroke_updated(player_id: String, value: int) -> void:
	hud.set_player_score(player_id, value)


func _on_player_holed(player_id: String, value: int) -> void:
	hud.set_player_score(player_id, value, true)
	_holed_ids[player_id] = true
	if _spectating:
		_apply_spectate_target()


func _on_lobby_state(_lobby: Dictionary) -> void:
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		hud.set_roster(people)
		var live: Dictionary = {}
		for p in people:
			if p is Dictionary:
				live[str(p.get("id", ""))] = true
		var gone: Array = []
		for id in _ghosts.keys():
			if not live.has(id):
				gone.append(id)
		for id in gone:
			var ghost = _ghosts[id]
			_ghosts.erase(id)
			if ghost is Node and is_instance_valid(ghost):
				ghost.queue_free()


func _on_ball_sunk() -> void:
	hud.stop_timer()
	hud.set_ball_state(BallStatusIndicator.State.HOLED)
	var id := NetworkClient.player_id if GameSession.online else "local"
	hud.set_player_score(id, hud.strokes, true)
	_holed_ids[id] = true
	if GameSession.online:
		NetworkClient.send_holed()
		_apply_ghost_visibility()


func _on_sunk_finished() -> void:
	if GameSession.online:
		await get_tree().create_timer(SPECTATE_DELAY).timeout
		if not is_inside_tree() or not GameSession.online:
			return
		_enter_spectate()
		return
	if hole.has_method("show_results"):
		hole.show_results(hud.hole, hud.par, hud.strokes, hud.timer_value.text)


func _unhandled_input(event: InputEvent) -> void:
	if not _spectating:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			_cycle_spectate(1)
			get_viewport().set_input_as_handled()


func _enter_spectate() -> void:
	_spectating = true
	if hole.has_node("WinMenu"):
		hole.get_node("WinMenu").visible = false
	hud.show_spectate(true)
	_spectate_follow = true
	_spectate_index = 0
	_apply_ghost_visibility()
	_apply_spectate_target()


func _on_spectate_follow() -> void:
	_spectate_follow = true
	_apply_spectate_target()


func _on_spectate_free() -> void:
	_spectate_follow = false
	_apply_spectate_target()


func _cycle_spectate(step: int) -> void:
	var ids := _watchable_ids()
	if ids.is_empty():
		_spectate_follow = false
		_apply_spectate_target()
		return
	_spectate_follow = true
	_spectate_index = posmod(_spectate_index + step, ids.size())
	_apply_spectate_target()


func _watchable_ids() -> Array[String]:
	var ids: Array[String] = []
	var seen: Dictionary = {}
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if not p is Dictionary:
				continue
			var id := str(p.get("id", ""))
			if id.is_empty() or id == NetworkClient.player_id:
				continue
			if bool(p.get("holed", false)) or _holed_ids.get(id, false):
				continue
			ids.append(id)
			seen[id] = true
	for id in _ghosts.keys():
		var sid := str(id)
		if seen.has(sid) or sid == NetworkClient.player_id:
			continue
		if _holed_ids.get(sid, false):
			continue
		ids.append(sid)
	return ids


func _player_name(id: String) -> String:
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if p is Dictionary and str(p.get("id", "")) == id:
				return str(p.get("name", "Player"))
	return "Player"


func _apply_spectate_target() -> void:
	var ids := _watchable_ids()
	hud.set_spectate_mode(_spectate_follow and not ids.is_empty())
	if not _spectate_follow or ids.is_empty():
		_spectate_follow = false
		camera_rig.set_free_roam(camera_rig.global_position)
		hud.set_spectate_target_name("FREE ROAM")
		return
	_spectate_index = clampi(_spectate_index, 0, ids.size() - 1)
	var id := ids[_spectate_index]
	var ghost: Node3D = _ghosts.get(id) as Node3D
	if ghost == null or not is_instance_valid(ghost):
		ghost = _ensure_ghost(id, _color_for(id), camera_rig.global_position, _player_name(id))
	camera_rig.set_follow(ghost)
	ghost.visible = true
	hud.set_spectate_target_name(_player_name(id))


func _on_hole_ended(hole_index: int, last_hole: bool, results: Array) -> void:
	hud.show_spectate(false)
	hud.show_round_results(hole_index, last_hole, results, int(GameSession.get_map().get("par", 3)))


func present_match_results(placings: Array) -> void:
	hud.show_match_results(placings)
	await get_tree().create_timer(8.0).timeout
	if is_inside_tree():
		GameSession.return_to_lobby()


func _on_oob() -> void:
	hud.set_ball_state(BallStatusIndicator.State.OOB)
	if GameSession.online:
		NetworkClient.send_oob()
