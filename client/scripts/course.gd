extends Node3D

const BALL_SCENE := preload("res://scenes/Ball.tscn")
const GHOST_SCRIPT := preload("res://scripts/ghost_ball.gd")
const SYNC_HZ := 15.0
const SPECTATE_DELAY := 1.1
const BALL_RADIUS := 0.15
const TEE_SPACING := 0.55
const BALL_HIT_LAYER := 4
const KICKOFF_BEAT := 0.7
const KICKOFF_GO := 0.55
const SHIELD_MS := 5000
const SHRINK_MS := 10000
const PICKUP_RESPAWN_MS := 18000

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
var _spectate_id := ""
var _holed_ids: Dictionary = {}
var _ghost_club: GhostClub
var _stick_aim := Vector3.ZERO
var _phone_look := Vector2.ZERO
var _phone_preview := false
var _phone_swing_fired := false
var _phone_hit_ms := 0
var _tee_origin := Vector3.ZERO
var _fairway := Vector3.FORWARD
var _kickoff := false
var _want_phone_panel := false
var _bump_at: Dictionary = {}
var _prev_ball_vel := Vector3.ZERO
var _pickups: Dictionary = {}
var _pads: Array[SpeedPad] = []
var _shield_until := 0
var _shrink_until := 0
var _shield_ids: Dictionary = {}
var _shrink_ids: Dictionary = {}
var _pending_pickup := ""
var _slot_kind: Array[String] = ["", ""]
var _slot_until: Array[int] = [0, 0]
var _phone_powers_key := ""


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
	hud.phone_link_pressed.connect(_on_phone_link_pressed)
	if hud.has_signal("aim_mode_changed"):
		hud.aim_mode_changed.connect(_on_aim_mode_changed)
	hud.chat_submitted.connect(_on_chat_submitted)
	hud.spectate_follow_pressed.connect(_on_spectate_follow)
	hud.spectate_free_pressed.connect(_on_spectate_free)
	hud.spectate_prev_pressed.connect(func() -> void: _cycle_spectate(-1))
	hud.spectate_next_pressed.connect(func() -> void: _cycle_spectate(1))
	if hud.has_signal("power_used"):
		hud.power_used.connect(_on_power_used)
	if GameSession.online:
		hud.stop_timer()
		hud.reset_timer()
	ball.freeze = true
	ball.apply_color(GameSession.my_color)
	_setup_scoreboard()
	_setup_multiplayer()
	_setup_phone()
	_refresh_power_hud()


func _load_map() -> void:
	var spec: Dictionary = GameSession.get_map()
	if hud:
		hud.set_hole(int(spec.get("hole", 1)))
		hud.set_par(int(spec.get("par", 3)))
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
	_tee_origin = tee_pos
	_fairway = _tee_facing(tee_pos, hole_pos)
	_spawn_ball(_tee_world_pos(_local_player_id()))

	hud.set_hole(int(spec.hole))
	hud.set_par(int(spec.par))
	camera_rig.overview_zoom = float(spec.get("overview_zoom", 12.0))
	camera_rig.max_zoom = maxf(camera_rig.max_zoom, camera_rig.overview_zoom)
	call_deferred("_place_field_items")


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
	ball.sleeping = true
	if GameSession.online:
		_apply_ball_collisions()
		_place_field_balls()
		_run_kickoff()
		return
	ball.sleeping = false
	ball.freeze = false


func _ground_snap(tee: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		tee + Vector3(0.0, 6.0, 0.0),
		tee + Vector3(0.0, -4.0, 0.0)
	)
	var skip: Array[RID] = [ball.get_rid()]
	for ghost in _ghosts.values():
		if ghost is CollisionObject3D and is_instance_valid(ghost):
			skip.append((ghost as CollisionObject3D).get_rid())
	query.exclude = skip
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return tee + Vector3(0.0, _ball_radius() + 0.04, 0.0)
	return hit.position + Vector3(0.0, _ball_radius() + 0.02, 0.0)


func _local_player_id() -> String:
	if GameSession.online and not NetworkClient.player_id.is_empty():
		return NetworkClient.player_id
	return "local"


func _tee_facing(tee: Vector3, hole_pos: Vector3) -> Vector3:
	var toward := hole_pos - tee
	toward.y = 0.0
	if toward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return toward.normalized()


func _tee_right() -> Vector3:
	var right := Vector3.UP.cross(_fairway)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	return right.normalized()


func _tee_world_pos(player_id: String) -> Vector3:
	if not GameSession.online:
		return _tee_origin
	var ids := GameSession.player_ids()
	var count := maxi(ids.size(), 1)
	if count <= 1:
		return _tee_origin
	var index := ids.find(player_id)
	if index < 0:
		index = GameSession.player_slot(player_id) - 1
	var shift := (float(index) - float(count - 1) * 0.5) * TEE_SPACING
	return _tee_origin + _tee_right() * shift


func _place_field_balls() -> void:
	if not GameSession.online:
		return
	for id in GameSession.player_ids():
		if id == NetworkClient.player_id:
			continue
		var pos := _ground_snap(_tee_world_pos(id))
		var ghost := _ensure_ghost(id, _color_for(id), pos, _player_name(id))
		if ghost.has_method("place_at"):
			ghost.call("place_at", pos)
		else:
			ghost.set("target", pos)
			ghost.global_position = pos
		ghost.visible = true


func _apply_ball_collisions() -> void:
	var hit := GameSession.online and GameSession.is_free_for_all()
	var shielded := _has_shield()
	if hit and not shielded:
		ball.collision_layer = 1 | BALL_HIT_LAYER
		ball.collision_mask = 1 | BALL_HIT_LAYER
	else:
		ball.collision_layer = 1
		ball.collision_mask = 1
	_watch_ball_hits(hit)
	for ghost in _ghosts.values():
		if ghost != null and is_instance_valid(ghost) and ghost.has_method("set_solid"):
			var id := str(ghost.get("player_id"))
			var solid := hit and not bool(_holed_ids.get(id, false)) and not bool(_shield_ids.get(id, false))
			ghost.call("set_solid", solid)


func _watch_ball_hits(on: bool) -> void:
	ball.max_contacts_reported = 8 if on else 0
	ball.contact_monitor = on
	if on and not ball.body_entered.is_connected(_on_ball_hit_body):
		ball.body_entered.connect(_on_ball_hit_body)
	elif not on and ball.body_entered.is_connected(_on_ball_hit_body):
		ball.body_entered.disconnect(_on_ball_hit_body)


func _physics_process(_delta: float) -> void:
	if ball != null and is_instance_valid(ball):
		if not _kickoff and GameSession.online and GameSession.is_free_for_all() and not ball.is_holed:
			_try_player_hits()
		_prev_ball_vel = ball.linear_velocity


func _on_ball_hit_body(other: Node) -> void:
	if other == null or not ("player_id" in other):
		return
	_bump_player(str(other.get("player_id")), other)


func _try_player_hits() -> void:
	for id in _ghosts.keys():
		var ghost: Node3D = _ghosts[id] as Node3D
		if ghost == null or not is_instance_valid(ghost):
			continue
		var other_r := BALL_RADIUS * (PuttBall.SHRINK_SCALE if ghost.has_method("has_shrink") and ghost.call("has_shrink") else 1.0)
		if ghost.global_position.distance_to(ball.global_position) > _ball_radius() + other_r + 0.1:
			continue
		_bump_player(str(id), ghost)


func _bump_player(id: String, other: Node) -> void:
	if _kickoff or not GameSession.online or not GameSession.is_free_for_all():
		return
	if ball == null or ball.is_holed or id.is_empty() or id == NetworkClient.player_id:
		return
	if bool(_holed_ids.get(id, false)):
		return
	var now := Time.get_ticks_msec()
	if now - int(_bump_at.get(id, 0)) < 220:
		return
	var away: Vector3 = other.global_position - ball.global_position
	away.y = 0.0
	var incoming := _prev_ball_vel
	incoming.y = 0.0
	if away.length_squared() < 0.0001:
		away = incoming
	if away.length_squared() < 0.0001:
		away = ball.linear_velocity
		away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	var normal := away.normalized()
	var approach := maxf(incoming.dot(normal), ball.linear_velocity.dot(normal))
	var carry := maxf(incoming.length(), ball.linear_velocity.length())
	if approach < 0.05 and carry < 0.35:
		return
	var speed := maxf(maxf(approach * 1.15, carry * 0.7), 4.5)
	var given := normal * minf(speed, 22.0)
	given.y = clampf(maxf(_prev_ball_vel.y, 0.0) * 0.2, 0.0, 2.5)
	_bump_at[id] = now
	if bool(_shield_ids.get(id, false)) or (other.has_method("has_shield") and other.call("has_shield")):
		if ball.has_method("nudge"):
			ball.nudge(-given)
		NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, false)
		return
	NetworkClient.send_bump(id, given)
	if other.has_method("apply_knock"):
		other.call("apply_knock", given)


func _on_bump(_from_id: String, velocity: Vector3) -> void:
	if _kickoff or ball == null or not is_instance_valid(ball) or ball.is_holed:
		return
	if _has_shield():
		return
	if ball.has_method("nudge"):
		ball.nudge(velocity)
	NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, false)


func _run_kickoff() -> void:
	_kickoff = true
	ball.freeze = true
	hud.stop_timer()
	hud.reset_timer()
	for word in ["3", "2", "1", "GOLF!"]:
		if hud.has_method("show_kickoff"):
			hud.show_kickoff(word)
		var beat := KICKOFF_GO if word == "GOLF!" else KICKOFF_BEAT
		await get_tree().create_timer(beat).timeout
		if not is_inside_tree():
			return
	if hud.has_method("hide_kickoff"):
		hud.hide_kickoff()
	_kickoff = false
	_apply_ghost_visibility()
	ball.sleeping = false
	ball.freeze = false
	hud.start_timer()


func _find_marker(marker_name: String) -> Node3D:
	if _map == null:
		return null
	var direct := _map.get_node_or_null(marker_name)
	if direct is Node3D:
		return direct as Node3D
	return _map.find_child(marker_name, true, false) as Node3D


func _ground_at(pos: Vector3) -> Vector3:
	return _ground_snap(pos) - Vector3(0.0, _ball_radius() + 0.02, 0.0)


func _ball_radius() -> float:
	if ball != null and ball.has_method("radius"):
		return ball.radius()
	return BALL_RADIUS


func _has_shield() -> bool:
	return Time.get_ticks_msec() < _shield_until


func _has_shrink() -> bool:
	return Time.get_ticks_msec() < _shrink_until


func _place_field_items() -> void:
	_spawn_field_items(GameSession.get_map())


func _spawn_field_items(spec: Dictionary) -> void:
	var raw_pickups: Variant = spec.get("pickups", [])
	if raw_pickups is Array:
		for item in raw_pickups:
			if not item is Dictionary:
				continue
			var pickup := CoursePickup.new()
			add_child(pickup)
			var pos: Vector3 = item.get("pos", Vector3.ZERO)
			pickup.setup(str(item.get("id", "")), str(item.get("kind", "shield")), _ground_at(pos) + Vector3(0, 0.32, 0))
			pickup.collected.connect(_on_pickup_touched)
			_pickups[pickup.pickup_id] = pickup
	var raw_pads: Variant = spec.get("pads", [])
	if raw_pads is Array:
		for item in raw_pads:
			if not item is Dictionary:
				continue
			var pad := SpeedPad.new()
			add_child(pad)
			var pos: Vector3 = item.get("pos", Vector3.ZERO)
			var dir: Vector3 = item.get("dir", -_fairway)
			pad.setup(_ground_at(pos), dir, float(item.get("len", 2.6)), float(item.get("wid", 1.45)))
			pad.crossed.connect(_on_pad_crossed)
			_pads.append(pad)


func _on_pickup_touched(kind: String, pickup_id: String) -> void:
	if _kickoff or ball == null or ball.is_holed or pickup_id.is_empty():
		return
	if not _can_store_power(kind):
		return
	var pickup: CoursePickup = _pickups.get(pickup_id)
	if pickup == null or not pickup.live:
		return
	if GameSession.online:
		_pending_pickup = pickup_id
		pickup.set_live(false)
		NetworkClient.send_pickup(pickup_id, kind)
		return
	_grant_pickup(pickup_id, kind, "local")


func _on_pickup_taken(pickup_id: String, player_id: String, kind: String) -> void:
	_pending_pickup = ""
	_grant_pickup(pickup_id, kind, player_id)


func _on_pickup_error(code: String, _message: String) -> void:
	if code != "PICKUP_TAKEN":
		return
	var pickup: CoursePickup = _pickups.get(_pending_pickup)
	_pending_pickup = ""
	if pickup:
		pickup.set_live(true)


func _grant_pickup(pickup_id: String, kind: String, player_id: String) -> void:
	var pickup: CoursePickup = _pickups.get(pickup_id)
	if pickup:
		pickup.set_live(false)
		get_tree().create_timer(PICKUP_RESPAWN_MS / 1000.0).timeout.connect(func() -> void:
			if is_instance_valid(pickup):
				pickup.set_live(true)
		)
	var mine := player_id == _local_player_id() or player_id == "local"
	if not mine:
		return
	if not _can_store_power(kind):
		return
	var slot := _first_empty_slot()
	if slot < 0:
		return
	_slot_kind[slot] = kind
	_slot_until[slot] = 0
	_refresh_power_hud()


func _can_store_power(kind: String) -> bool:
	if kind != "shield" and kind != "shrink":
		return false
	for i in 2:
		if _slot_kind[i] == kind:
			return false
	return _first_empty_slot() >= 0


func _first_empty_slot() -> int:
	for i in 2:
		if _slot_kind[i].is_empty():
			return i
	return -1


func _slot_of(kind: String, stored_only: bool = false) -> int:
	for i in 2:
		if _slot_kind[i] != kind:
			continue
		if stored_only and _slot_until[i] != 0:
			continue
		return i
	return -1


func _slot_remaining(index: int) -> float:
	if index < 0 or index >= 2 or _slot_kind[index].is_empty() or _slot_until[index] <= 0:
		return 0.0
	return maxf(float(_slot_until[index] - Time.get_ticks_msec()) / 1000.0, 0.0)


func _compact_power_slots() -> void:
	var kinds: Array[String] = []
	var untils: Array[int] = []
	for i in 2:
		if _slot_kind[i].is_empty():
			continue
		kinds.append(_slot_kind[i])
		untils.append(_slot_until[i])
	_slot_kind = ["", ""]
	_slot_until = [0, 0]
	for i in kinds.size():
		_slot_kind[i] = kinds[i]
		_slot_until[i] = untils[i]


func _refresh_local_powers() -> void:
	if ball == null or not is_instance_valid(ball):
		return
	ball.apply_powers(_has_shield(), _has_shrink())
	_apply_ball_collisions()
	_refresh_power_hud()


func _apply_ghost_powers(player_id: String) -> void:
	var ghost: Node = _ghosts.get(player_id)
	if ghost != null and is_instance_valid(ghost) and ghost.has_method("set_powers"):
		ghost.call("set_powers", bool(_shield_ids.get(player_id, false)), bool(_shrink_ids.get(player_id, false)))
	_apply_ball_collisions()


func _tick_powers() -> void:
	var changed := false
	if not _has_shield() and _shield_until != 0:
		_shield_until = 0
		_clear_expired_slot("shield")
		changed = true
	if not _has_shrink() and _shrink_until != 0:
		_shrink_until = 0
		_clear_expired_slot("shrink")
		changed = true
	if changed:
		_compact_power_slots()
		_refresh_local_powers()
	else:
		_refresh_power_hud()


func _clear_expired_slot(kind: String) -> void:
	var slot := _slot_of(kind)
	if slot < 0:
		return
	_slot_kind[slot] = ""
	_slot_until[slot] = 0


func _on_power_used(kind: String) -> void:
	if _kickoff or ball == null or ball.is_holed:
		return
	var slot := _slot_of(kind, true)
	if slot < 0:
		return
	var now := Time.get_ticks_msec()
	if kind == "shield":
		_shield_until = now + SHIELD_MS
		_slot_until[slot] = _shield_until
	elif kind == "shrink":
		_shrink_until = now + SHRINK_MS
		_slot_until[slot] = _shrink_until
	else:
		return
	_refresh_local_powers()
	if GameSession.online:
		NetworkClient.send_power_use(kind)


func _on_remote_power(player_id: String, kind: String) -> void:
	if player_id.is_empty() or player_id == _local_player_id():
		return
	if kind == "shield":
		_shield_ids[player_id] = true
		_apply_ghost_powers(player_id)
		get_tree().create_timer(SHIELD_MS / 1000.0).timeout.connect(func() -> void:
			_shield_ids.erase(player_id)
			_apply_ghost_powers(player_id)
		)
	elif kind == "shrink":
		_shrink_ids[player_id] = true
		_apply_ghost_powers(player_id)
		get_tree().create_timer(SHRINK_MS / 1000.0).timeout.connect(func() -> void:
			_shrink_ids.erase(player_id)
			_apply_ghost_powers(player_id)
		)


func _refresh_power_hud() -> void:
	var left_kind := _slot_kind[0]
	var right_kind := _slot_kind[1]
	var left_left := _slot_remaining(0)
	var right_left := _slot_remaining(1)
	if hud != null and hud.has_method("set_powerups"):
		hud.set_powerups(left_kind, left_left, right_kind, right_left)
	_push_phone_powers(left_kind, left_left, right_kind, right_left)


func _push_phone_powers(left_kind: String, left_left: float, right_kind: String, right_left: float) -> void:
	var phone := _phone()
	if phone.has_method("set_powers"):
		phone.call("set_powers", left_kind, left_left, right_kind, right_left)
	var key := "%s|%.1f|%s|%.1f" % [left_kind, left_left, right_kind, right_left]
	if key == _phone_powers_key:
		return
	_phone_powers_key = key
	if GameSession.online:
		NetworkClient.send_phone_powers(left_kind, left_left, right_kind, right_left)


func _on_pad_crossed(pad: SpeedPad, body: Node) -> void:
	if pad == null or body != ball or _kickoff or ball.is_holed:
		return
	if not pad.can_boost():
		return
	pad.mark_used()
	var dir := pad.boost_dir
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = _fairway
	dir = dir.normalized()
	var along := ball.linear_velocity.dot(dir)
	var side := ball.linear_velocity - dir * along
	var boosted := dir * maxf(along, 1.2) + dir * pad.strength + side * 0.35
	boosted.y = maxf(ball.linear_velocity.y, 0.4)
	if ball.freeze:
		ball.freeze = false
	if ball.has_method("nudge"):
		ball.nudge(boosted - ball.linear_velocity)
	else:
		ball.linear_velocity = boosted
	if GameSession.online:
		NetworkClient.send_ball_state(ball.global_position, ball.linear_velocity, false)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_apply_phone_look(delta)
	_update_ghost_club()
	_tick_powers()
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


func _phone() -> Node:
	return get_node("/root/PhoneLink")


func _setup_phone() -> void:
	var phone := _phone()
	if not phone.hit_received.is_connected(_on_phone_hit):
		phone.hit_received.connect(_on_phone_hit)
	if not phone.pose_received.is_connected(_on_phone_pose):
		phone.pose_received.connect(_on_phone_pose)
	if not phone.qr_ready.is_connected(_on_phone_qr_png):
		phone.qr_ready.connect(_on_phone_qr_png)
	if not NetworkClient.phone_ready.is_connected(_on_phone_ready):
		NetworkClient.phone_ready.connect(_on_phone_ready)
	if not NetworkClient.phone_linked.is_connected(_on_phone_linked):
		NetworkClient.phone_linked.connect(_on_phone_linked)
	if not NetworkClient.phone_gone.is_connected(_on_phone_gone):
		NetworkClient.phone_gone.connect(_on_phone_gone)
	if not NetworkClient.phone_hit.is_connected(_on_phone_hit):
		NetworkClient.phone_hit.connect(_on_phone_hit)
	if not NetworkClient.phone_pose.is_connected(_on_phone_pose):
		NetworkClient.phone_pose.connect(_on_phone_pose)
	if phone.has_signal("power_used") and not phone.power_used.is_connected(_on_power_used):
		phone.power_used.connect(_on_power_used)
	if not NetworkClient.phone_power.is_connected(_on_power_used):
		NetworkClient.phone_power.connect(_on_power_used)
	if not NetworkClient.error_received.is_connected(_on_phone_error):
		NetworkClient.error_received.connect(_on_phone_error)
	if phone.is_linked():
		GameSession.aim_with_phone = true
		if hud.has_method("_refresh_aim_mode_buttons"):
			hud._refresh_aim_mode_buttons()


func _exit_tree() -> void:
	_teardown_phone()


func _teardown_phone() -> void:
	var phone := _phone()
	if phone.hit_received.is_connected(_on_phone_hit):
		phone.hit_received.disconnect(_on_phone_hit)
	if phone.pose_received.is_connected(_on_phone_pose):
		phone.pose_received.disconnect(_on_phone_pose)
	if phone.qr_ready.is_connected(_on_phone_qr_png):
		phone.qr_ready.disconnect(_on_phone_qr_png)
	if NetworkClient.phone_ready.is_connected(_on_phone_ready):
		NetworkClient.phone_ready.disconnect(_on_phone_ready)
	if NetworkClient.phone_linked.is_connected(_on_phone_linked):
		NetworkClient.phone_linked.disconnect(_on_phone_linked)
	if NetworkClient.phone_gone.is_connected(_on_phone_gone):
		NetworkClient.phone_gone.disconnect(_on_phone_gone)
	if NetworkClient.phone_hit.is_connected(_on_phone_hit):
		NetworkClient.phone_hit.disconnect(_on_phone_hit)
	if NetworkClient.phone_pose.is_connected(_on_phone_pose):
		NetworkClient.phone_pose.disconnect(_on_phone_pose)
	if phone.has_signal("power_used") and phone.power_used.is_connected(_on_power_used):
		phone.power_used.disconnect(_on_power_used)
	if NetworkClient.phone_power.is_connected(_on_power_used):
		NetworkClient.phone_power.disconnect(_on_power_used)
	if NetworkClient.error_received.is_connected(_on_phone_error):
		NetworkClient.error_received.disconnect(_on_phone_error)
	if NetworkClient.bump_received.is_connected(_on_bump):
		NetworkClient.bump_received.disconnect(_on_bump)
	if NetworkClient.pickup_taken.is_connected(_on_pickup_taken):
		NetworkClient.pickup_taken.disconnect(_on_pickup_taken)
	if NetworkClient.error_received.is_connected(_on_pickup_error):
		NetworkClient.error_received.disconnect(_on_pickup_error)
	if NetworkClient.power_used.is_connected(_on_remote_power):
		NetworkClient.power_used.disconnect(_on_remote_power)


func _on_phone_link_pressed() -> void:
	_want_phone_panel = true
	hud.show_phone_panel(true)
	if _ghost_club == null:
		_ghost_club = GhostClub.new()
		add_child(_ghost_club)
	var phone := _phone()
	var err: Error = phone.ensure_listening()
	if err == OK:
		hud.set_phone_urls(phone.public_urls(), phone.local_url())
		var qr: PackedByteArray = phone.last_qr()
		if not qr.is_empty():
			hud.set_phone_qr_png(qr)
		if phone.is_linked():
			hud.set_phone_status("Still linked. Keep the same phone page open.")
			GameSession.aim_with_phone = true
		else:
			hud.set_phone_status("Same Wi-Fi. Scan the code, or type the address. Use the https one for swing sensors.")
		phone.fetch_qr()
	else:
		hud.set_phone_status("Phone port blocked (%s)." % phone.last_error())
	if GameSession.online:
		NetworkClient.ensure_connected()
		NetworkClient.send_phone_open()
		if err != OK:
			hud.set_phone_status("Scan YOUR code. Each player gets their own phone, and their own ball.")


func _on_phone_qr_png(bytes: PackedByteArray) -> void:
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
	if not _want_phone_panel:
		return
	var phone := _phone()
	hud.set_phone_qr_png(bytes)
	hud.set_phone_urls(phone.public_urls(), phone.local_url())


func _on_phone_ready(code: String, urls: PackedStringArray, qr: String) -> void:
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
	if not _want_phone_panel:
		return
	# Online pairing is per-player. Don't hide those unique codes behind the
	# local phone page, or every guest would swing the host's ball.
	if not GameSession.online and _phone().server != null and _phone().server.is_listening():
		return
	hud.set_phone_info(code, false, qr)
	hud.set_phone_urls(urls)
	hud.show_phone_panel(true)


func _on_phone_linked() -> void:
	_phone_powers_key = ""
	_refresh_power_hud()
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
	if not GameSession.online and _phone().server != null and _phone().server.is_listening():
		return
	GameSession.aim_with_phone = true
	hud.set_phone_info(_phone_code_text(), true)


func _on_phone_gone() -> void:
	_phone_look = Vector2.ZERO
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
	if not GameSession.online and _phone().server != null and _phone().server.is_listening():
		return
	hud.set_phone_info(_phone_code_text(), false)


func _on_aim_mode_changed(_use_phone: bool) -> void:
	_clear_phone_aim()


func _clear_phone_aim() -> void:
	_phone_preview = false
	_stick_aim = Vector3.ZERO
	_phone_look = Vector2.ZERO
	_reset_phone_swing()
	if aim_controller.has_method("clear_aim"):
		aim_controller.clear_aim()
	if _ghost_club:
		_ghost_club.set_pose(75.0, 0.0, false)


func _reset_phone_swing() -> void:
	_phone_swing_fired = false


func _on_phone_hit(power: float, stick_x: float = 0.0, stick_y: float = 0.0) -> void:
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
	if _kickoff or _spectating or not GameSession.aim_with_phone:
		return
	if ball != null and ball.is_holed:
		_hide_ghost_club()
		return
	if ball != null and ball.freeze:
		return
	_phone_swing_fired = true
	_phone_preview = false
	_phone_hit_ms = Time.get_ticks_msec()
	if _ghost_club:
		_ghost_club.set_pose(75.0, 0.0, false)
	if aim_controller.has_method("swing_from_phone"):
		aim_controller.swing_from_phone(power, stick_x, stick_y)
	if aim_controller.has_method("clear_aim"):
		aim_controller.clear_aim()


func _on_phone_pose(beta: float, gamma: float, holding: bool, stick_x: float = 0.0, stick_y: float = 0.0, lift: float = 0.0, power: float = -1.0, _accel: float = 0.0, _yaw: float = 0.0, _recenter: bool = false, look_x: float = 0.0, look_y: float = 0.0) -> void:
	_phone_look = Vector2(look_x, look_y)
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
	if aim_controller == null or not is_instance_valid(aim_controller):
		return
	if camera_rig == null or not is_instance_valid(camera_rig):
		return
	if not GameSession.aim_with_phone or _spectating or (ball != null and ball.is_holed):
		_hide_ghost_club()
		return
	if _ghost_club == null:
		_ghost_club = GhostClub.new()
		add_child(_ghost_club)
	var stick := Vector2(stick_x, stick_y)
	var aiming := stick.length() > 0.04
	if aiming:
		_stick_aim = _world_from_stick(stick_x, stick_y)
	_ghost_club.set_pose(beta, gamma, holding or aiming, stick_x, stick_y, lift)
	_update_ghost_club()
	if _phone_swing_fired:
		if aim_controller.has_method("clear_aim"):
			aim_controller.clear_aim()
		if _ghost_club:
			_ghost_club.set_pose(75.0, 0.0, false)
		var settled: bool = ball != null and not ball.is_moving
		if not holding and settled and Time.get_ticks_msec() - _phone_hit_ms > 600:
			_reset_phone_swing()
		return
	if not aim_controller.has_method("preview_from_phone"):
		return
	if aiming:
		_phone_preview = true
		var pulled := power if power >= 0.0 else stick.length()
		aim_controller.preview_from_phone(stick_x, stick_y, pulled)
	elif _phone_preview:
		_phone_preview = false
		aim_controller.preview_from_phone(0.0, 0.0, 0.0)


func _apply_phone_look(delta: float) -> void:
	if not GameSession.aim_with_phone:
		return
	if camera_rig == null or not is_instance_valid(camera_rig):
		return
	if camera_rig.has_method("orbit_look"):
		camera_rig.orbit_look(_phone_look.x, _phone_look.y, delta)


func _world_from_stick(stick_x: float, stick_y: float) -> Vector3:
	var cam: Camera3D = camera_rig.camera if camera_rig else null
	if cam == null:
		return Vector3.FORWARD
	var cam_right: Vector3 = cam.global_transform.basis.x
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	cam_right.y = 0.0
	cam_fwd.y = 0.0
	if cam_right.length_squared() > 0.0001:
		cam_right = cam_right.normalized()
	if cam_fwd.length_squared() > 0.0001:
		cam_fwd = cam_fwd.normalized()
	else:
		cam_fwd = Vector3.FORWARD
	var world := cam_right * stick_x + cam_fwd * stick_y
	if world.length_squared() < 0.0001:
		return cam_fwd
	return world.normalized()


func _update_ghost_club() -> void:
	if _ghost_club == null:
		return
	if _kickoff or _spectating or (ball != null and ball.is_holed):
		_ghost_club.stow()
		return
	_ghost_club.follow(ball, _phone_aim())


func _hide_ghost_club() -> void:
	if _ghost_club:
		_ghost_club.stow()


func _phone_aim() -> Vector3:
	if _stick_aim.length_squared() > 0.0001:
		return _stick_aim
	var cam: Camera3D = camera_rig.camera if camera_rig else null
	if cam == null:
		return Vector3.FORWARD
	var aim: Vector3 = -cam.global_transform.basis.z
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		return Vector3.FORWARD
	return aim.normalized()


func _on_phone_error(code: String, _message: String) -> void:
	if code != "PHONE_FAILED":
		return
	if _phone().server != null and _phone().server.is_listening():
		return
	hud.set_phone_info(_phone_code_text(), false)


func _phone_code_text() -> String:
	if hud._phone_code:
		return hud._phone_code.text
	return ""


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
	if not NetworkClient.bump_received.is_connected(_on_bump):
		NetworkClient.bump_received.connect(_on_bump)
	if not NetworkClient.pickup_taken.is_connected(_on_pickup_taken):
		NetworkClient.pickup_taken.connect(_on_pickup_taken)
	if not NetworkClient.error_received.is_connected(_on_pickup_error):
		NetworkClient.error_received.connect(_on_pickup_error)
	if not NetworkClient.power_used.is_connected(_on_remote_power):
		NetworkClient.power_used.connect(_on_remote_power)
	_apply_ball_collisions()
	_place_field_balls()


func _on_snapshot(balls: Array) -> void:
	if _kickoff:
		return
	for snap in balls:
		if not snap is Dictionary:
			continue
		var id := str(snap.get("id", ""))
		if id.is_empty() or id == NetworkClient.player_id:
			continue
		var pos := Vector3(float(snap.get("x", 0.0)), float(snap.get("y", 0.5)), float(snap.get("z", 0.0)))
		var ghost := _ensure_ghost(id, _color_for(id), pos, _player_name(id))
		if ghost.has_method("take_network_pos"):
			ghost.call("take_network_pos", pos)
		else:
			ghost.set("target", pos)
	if _spectating and _spectate_follow:
		_apply_spectate_target()


func _color_for(id: String) -> Color:
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if p is Dictionary and str(p.get("id", "")) == id:
				return UiStyle.to_color(p.get("color", "#4CB8B0"), UiStyle.TEAL)
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
	if ghost.has_method("set_solid"):
		ghost.call("set_solid", GameSession.is_free_for_all() and not bool(_holed_ids.get(id, false)) and not bool(_shield_ids.get(id, false)))
	if ghost.has_method("set_powers"):
		ghost.call("set_powers", bool(_shield_ids.get(id, false)), bool(_shrink_ids.get(id, false)))
	ghost.visible = true if _kickoff else _ghosts_visible()
	_ghosts[id] = ghost
	return ghost


func _local_holed() -> bool:
	return bool(_holed_ids.get(NetworkClient.player_id, false)) or (ball != null and bool(ball.get("is_holed")))


func _ghosts_visible() -> bool:
	if _kickoff:
		return true
	if GameSession.is_turn_by_turn() and not _local_holed() and not _spectating:
		return false
	return GameSession.show_players or _spectating


func _on_show_players_changed(enabled: bool) -> void:
	GameSession.show_players = enabled
	_apply_ghost_visibility()


func _apply_ghost_visibility() -> void:
	var shown := _ghosts_visible()
	for ghost in _ghosts.values():
		if ghost is Node3D and is_instance_valid(ghost):
			ghost.visible = shown


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
	if not is_inside_tree() or hud == null or not is_instance_valid(hud):
		return
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
	var ghost: Node = _ghosts.get(player_id)
	if ghost != null and is_instance_valid(ghost) and ghost.has_method("set_solid"):
		ghost.call("set_solid", false)
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
	ball.collision_layer = 1
	ball.collision_mask = 1
	_hide_ghost_club()
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
	_hide_ghost_club()
	if hole.has_node("WinMenu"):
		hole.get_node("WinMenu").visible = false
	hud.show_spectate(true)
	_spectate_follow = true
	_spectate_index = 0
	_spectate_id = ""
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
	var add := func(id: String) -> void:
		if id.is_empty() or seen.has(id):
			return
		if id == NetworkClient.player_id or bool(_holed_ids.get(id, false)):
			return
		seen[id] = true
		ids.append(id)
	for id in GameSession.player_ids():
		add.call(id)
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if not p is Dictionary:
				continue
			var id := str(p.get("id", ""))
			if bool(p.get("holed", false)):
				_holed_ids[id] = true
				continue
			add.call(id)
	for id in _ghosts.keys():
		add.call(str(id))
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
		ghost = _ensure_ghost(id, _color_for(id), _tee_world_pos(id), _player_name(id))
	var switched := id != _spectate_id
	_spectate_id = id
	camera_rig.set_follow(ghost)
	if switched and camera_rig.has_method("reset_view"):
		camera_rig.reset_view()
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
