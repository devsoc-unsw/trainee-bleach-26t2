extends CanvasLayer

signal hit_received(power: float, stick_x: float, stick_y: float)
signal pose_received(beta: float, gamma: float, holding: bool, stick_x: float, stick_y: float, lift: float, power: float, accel: float, yaw: float, recenter: bool, look_x: float, look_y: float, zoom: float)
signal qr_ready(bytes: PackedByteArray)
signal urls_changed
signal power_used(kind: String, slot: int)
signal restart_requested
signal phone_seen

const STALE_MS := 2500
const CURSOR_HZ := 15.0
# Full-tilt travel, screens per second. Small nudges are much slower because
# of CURSOR_CURVE — that is what makes the pointer stoppable.
const CURSOR_SPEED := 0.95
const CURSOR_CURVE := 2.3
const CURSOR_DEAD := 0.12
const CURSOR_START := 0.17

var server: PhoneServer
var _cursor: Control
var _qr_http: HTTPRequest
var _qr_bytes: PackedByteArray
var _uv := Vector2(0.5, 0.5)
var _stick := Vector2.ZERO
var _last_pose_ms := 0
var _last_click_ms := 0
var _holding := false
var _cursor_moving := false
var _session_live := false
var _hover: Control
var _ghosts: Dictionary = {}
var _send_acc := 0.0
var _sent_off := true
var _typing: Control
var _type_scene: Node
var _type_key := ""


func _ready() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_ALWAYS
	server = PhoneServer.new()
	add_child(server)
	server.hit_received.connect(func(power: float, sx: float, sy: float) -> void:
		hit_received.emit(power, sx, sy)
		_try_click()
	)
	server.pose_received.connect(_on_pose)
	server.power_used.connect(func(kind: String, slot: int = -1) -> void: power_used.emit(kind, slot))
	server.restart_requested.connect(func() -> void: restart_requested.emit())
	server.client_seen.connect(_mark_seen)
	server.type_received.connect(_on_type_from_phone)
	server.urls_changed.connect(func() -> void: urls_changed.emit())
	_cursor = (load("res://scripts/wii_pointer.gd") as GDScript).new()
	add_child(_cursor)
	if not NetworkClient.cursor_received.is_connected(_on_remote_cursor):
		NetworkClient.cursor_received.connect(_on_remote_cursor)
	if not NetworkClient.lobby_state_received.is_connected(_on_lobby_for_cursors):
		NetworkClient.lobby_state_received.connect(_on_lobby_for_cursors)
	if not NetworkClient.phone_pose.is_connected(_apply_pose):
		NetworkClient.phone_pose.connect(_apply_pose)
	if not NetworkClient.phone_hit.is_connected(_on_net_hit):
		NetworkClient.phone_hit.connect(_on_net_hit)
	if not NetworkClient.phone_typed.is_connected(_on_type_from_phone):
		NetworkClient.phone_typed.connect(_on_type_from_phone)
	if not NetworkClient.phone_linked.is_connected(_on_cloud_linked):
		NetworkClient.phone_linked.connect(_on_cloud_linked)
	ensure_listening()


func _on_cloud_linked() -> void:
	_mark_seen()


func ensure_listening() -> Error:
	var err := server.ensure_listening()
	if err == OK:
		urls_changed.emit()
	return err


func last_error() -> String:
	return server.last_error()


func public_urls() -> PackedStringArray:
	return server.public_urls()


func local_url() -> String:
	return server.local_url()


func is_linked() -> bool:
	if _last_pose_ms <= 0:
		return false
	return Time.get_ticks_msec() - _last_pose_ms <= STALE_MS


func _mark_seen() -> void:
	var first := not is_linked()
	_session_live = true
	_last_pose_ms = Time.get_ticks_msec()
	if first:
		phone_seen.emit()


func mark_unlinked() -> void:
	_session_live = false
	_last_pose_ms = 0


func set_powers(left_kind: String, left_left: float, right_kind: String, right_left: float) -> void:
	if server:
		server.set_powers(left_kind, left_left, right_kind, right_left)


func set_rank(place: int, label: String = "", caption: String = "") -> void:
	if server:
		server.set_rank(place, label, caption)


func set_type(on: bool, text: String = "", hint: String = "", max_len: int = 32) -> void:
	if server:
		server.set_type(on, text, hint, max_len)
	if GameSession.online:
		NetworkClient.send_phone_type(on, text, hint, max_len)


func pointer_live() -> bool:
	return _phone_cursor_live()


func hovered_control() -> Control:
	if _hover != null and is_instance_valid(_hover):
		return _hover
	return null


func last_qr() -> PackedByteArray:
	return _qr_bytes


func fetch_qr() -> void:
	if _qr_http == null:
		_qr_http = HTTPRequest.new()
		_qr_http.timeout = 1.5
		add_child(_qr_http)
		_qr_http.request_completed.connect(_on_http)
	_request_qr_png()


func _on_http(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	_qr_bytes = body
	qr_ready.emit(body)


func _request_qr_png() -> void:
	var urls := public_urls()
	if urls.is_empty() or _qr_http == null:
		return
	var qr_url := "%s/phone/qr?u=%s" % [NetworkClient.http_base(), urls[0].uri_encode()]
	_qr_http.cancel_request()
	_qr_http.request(qr_url)


func _process(delta: float) -> void:
	var share := _share_party_cursors()
	var phone_on := _phone_cursor_live()
	if share:
		if phone_on:
			_steer_phone(delta)
		else:
			_cursor_moving = false
			_uv = _mouse_uv()
		_paint_pointer(_cursor, NetworkClient.player_id)
		_set_cursor(true, _uv)
		if GameSession.is_loading():
			_set_hover(null)
		else:
			_set_hover(_clickable_at(get_tree().root, _screen_pos()))
	elif phone_on:
		_steer_phone(delta)
		_paint_pointer(_cursor, NetworkClient.player_id)
		_set_cursor(true, _uv)
		_set_hover(_clickable_at(get_tree().root, _screen_pos()))
	else:
		_cursor_moving = false
		_set_cursor(false)
		_set_hover(null)
	_tick_remotes(delta, share)
	_send_cursor(delta, share)
	_tick_type()


func _steer_phone(delta: float) -> void:
	if _holding:
		var drive := _cursor_drive()
		if drive.length_squared() > 0.0001:
			var step := CURSOR_SPEED * delta
			_uv.x = clampf(_uv.x + drive.x * step, 0.03, 0.97)
			_uv.y = clampf(_uv.y - drive.y * step, 0.04, 0.96)
	else:
		_cursor_moving = false


func _phone_cursor_live() -> bool:
	if _last_pose_ms == 0 or Time.get_ticks_msec() - _last_pose_ms > STALE_MS:
		return false
	if GameSession.is_loading():
		return true
	return not _in_course()


func _share_party_cursors() -> bool:
	if not GameSession.online:
		return false
	if GameSession.is_loading():
		return true
	return _on_select()


func _on_select() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return scene.scene_file_path.ends_with("map_select.tscn")


func _mouse_uv() -> Vector2:
	var rect := get_viewport().get_visible_rect()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return _uv
	var mouse := get_viewport().get_mouse_position()
	return Vector2(
		clampf((mouse.x - rect.position.x) / rect.size.x, 0.03, 0.97),
		clampf((mouse.y - rect.position.y) / rect.size.y, 0.04, 0.96)
	)


func _paint_pointer(pointer: Control, player_id: String) -> void:
	if pointer == null or not pointer.has_method("set_look"):
		return
	if not GameSession.online or player_id.is_empty():
		pointer.call("set_look", Color("3A322C"), 0)
		return
	pointer.call("set_look", GameSession.player_tint(player_id), GameSession.player_slot(player_id))


func _on_remote_cursor(player_id: String, uv: Vector2, on: bool) -> void:
	if player_id.is_empty() or player_id == NetworkClient.player_id:
		return
	var ghost: Dictionary = _ghosts.get(player_id, {})
	if ghost.is_empty():
		var pointer: Control = (load("res://scripts/wii_pointer.gd") as GDScript).new()
		add_child(pointer)
		ghost = { "node": pointer, "uv": uv, "target": uv, "on": on }
		_ghosts[player_id] = ghost
	ghost["target"] = uv
	ghost["on"] = on
	_paint_pointer(ghost["node"], player_id)


func _on_lobby_for_cursors(_lobby: Dictionary) -> void:
	_prune_ghosts()


func _prune_ghosts() -> void:
	var live: Dictionary = {}
	var people: Variant = GameSession.active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if p is Dictionary:
				live[str(p.get("id", ""))] = true
	var gone: Array = []
	for id in _ghosts.keys():
		if not live.has(id):
			gone.append(id)
	for id in gone:
		var ghost: Dictionary = _ghosts[id]
		var node: Node = ghost.get("node")
		_ghosts.erase(id)
		if node != null and is_instance_valid(node):
			node.queue_free()


func _tick_remotes(delta: float, share: bool) -> void:
	_prune_ghosts()
	var follow := 1.0 - exp(-delta * 18.0)
	for id in _ghosts.keys():
		var ghost: Dictionary = _ghosts[id]
		var node: Control = ghost.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var here: Vector2 = ghost.get("uv", ghost.get("target", Vector2(0.5, 0.5)))
		var want: Vector2 = ghost.get("target", here)
		here = here.lerp(want, follow)
		ghost["uv"] = here
		_paint_pointer(node, str(id))
		if node.has_method("set_point"):
			node.call("set_point", share and bool(ghost.get("on", false)), here)


func _send_cursor(delta: float, share: bool) -> void:
	if not GameSession.online:
		return
	_send_acc += delta
	if _send_acc < 1.0 / CURSOR_HZ:
		return
	_send_acc = 0.0
	if share:
		NetworkClient.send_cursor(_uv, true)
		_sent_off = false
	elif not _sent_off:
		NetworkClient.send_cursor(_uv, false)
		_sent_off = true


func _cursor_drive() -> Vector2:
	var mag := _stick.length()
	if _cursor_moving:
		if mag < CURSOR_DEAD:
			_cursor_moving = false
			return Vector2.ZERO
	elif mag < CURSOR_START:
		return Vector2.ZERO
	else:
		_cursor_moving = true
	var t := clampf((mag - CURSOR_DEAD) / (1.0 - CURSOR_DEAD), 0.0, 1.0)
	t = pow(t, CURSOR_CURVE)
	return _stick / mag * t


func _on_pose(beta: float, gamma: float, holding: bool, stick_x: float, stick_y: float, lift: float, power: float, accel: float = 0.0, yaw: float = 0.0, recenter: bool = false, look_x: float = 0.0, look_y: float = 0.0, zoom: float = 0.0) -> void:
	pose_received.emit(beta, gamma, holding, stick_x, stick_y, lift, power, accel, yaw, recenter, look_x, look_y, zoom)
	_apply_pose(beta, gamma, holding, stick_x, stick_y, lift, power, accel, yaw, recenter, look_x, look_y, zoom)


func _apply_pose(_beta: float, _gamma: float, holding: bool, stick_x: float, stick_y: float, _lift: float, _power: float, _accel: float = 0.0, _yaw: float = 0.0, _recenter: bool = false, _look_x: float = 0.0, _look_y: float = 0.0, _zoom: float = 0.0) -> void:
	_session_live = true
	_last_pose_ms = Time.get_ticks_msec()
	var raw := Vector2(stick_x, stick_y)
	_stick = raw if raw.length() >= 0.08 else Vector2.ZERO
	_holding = holding


func _on_net_hit(_power: float, _stick_x: float, _stick_y: float) -> void:
	_try_click()


func _try_click() -> void:
	var hit := _clickable_at(get_tree().root, _screen_pos())
	if _in_course() and not _is_text_field(hit):
		return
	var now := Time.get_ticks_msec()
	if now - _last_click_ms < 400:
		return
	_last_click_ms = now
	_click_under_cursor()


func _click_under_cursor() -> void:
	var hit := _clickable_at(get_tree().root, _screen_pos())
	if hit == null:
		_close_type()
		return
	if _is_text_field(hit):
		_open_type(hit)
		return
	_close_type()
	if hit.has_signal("hovered"):
		hit.emit_signal("hovered")
	if hit.has_signal("chosen"):
		hit.emit_signal("chosen")
		return
	if hit is BaseButton:
		(hit as BaseButton).pressed.emit()
		return
	if hit.has_signal("pressed"):
		hit.emit_signal("pressed")
		return
	if hit.has_method("set_on") and hit.get("is_on") != null:
		hit.call("set_on", not bool(hit.get("is_on")))
		if hit.has_signal("toggled"):
			hit.emit_signal("toggled", bool(hit.get("is_on")))


func _clickable_at(node: Node, pos: Vector2) -> Control:
	var kids := node.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var found := _clickable_at(kids[i], pos)
		if found:
			return found
	if not (node is Control):
		return null
	var control := node as Control
	if not control.is_visible_in_tree():
		return null
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return null
	if not control.get_global_rect().has_point(pos):
		return null
	if node.get("locked") == true:
		return null
	if node is LineEdit or node is TextEdit:
		return control
	if node is BaseButton:
		return control
	if control.has_signal("chosen") or control.has_signal("pressed") or control.has_signal("toggled"):
		return control
	return null


func _is_text_field(node: Control) -> bool:
	return node != null and is_instance_valid(node) and (node is LineEdit or node is TextEdit)


func _open_type(edit: Control) -> void:
	if not _is_text_field(edit):
		return
	_typing = edit
	_type_scene = get_tree().current_scene
	if edit.has_method("grab_focus"):
		edit.grab_focus()
	if edit is LineEdit:
		var line := edit as LineEdit
		line.caret_column = line.text.length()
	_type_key = ""
	_push_type_state()


func _close_type() -> void:
	if _typing == null and _type_key.is_empty():
		return
	if _typing != null and is_instance_valid(_typing) and _typing.has_focus():
		_typing.release_focus()
	_typing = null
	_type_scene = null
	_type_key = ""
	set_type(false)


func _tick_type() -> void:
	if _typing == null:
		return
	if not is_instance_valid(_typing) or not _typing.is_visible_in_tree():
		_close_type()
		return
	if _type_scene != null and get_tree().current_scene != _type_scene:
		_close_type()


func _push_type_state() -> void:
	var on := _is_text_field(_typing)
	var text := _field_text(_typing) if on else ""
	var hint := _field_hint(_typing) if on else ""
	var max_len := _field_max(_typing) if on else 32
	var key := "%s|%s|%s|%d" % [on, text, hint, max_len]
	if key == _type_key:
		return
	_type_key = key
	set_type(on, text, hint, max_len)


func _on_type_from_phone(text: String, done: bool, closing: bool = false) -> void:
	if not _is_text_field(_typing):
		return
	var clipped := text
	var limit := _field_max(_typing)
	if clipped.length() > limit:
		clipped = clipped.substr(0, limit)
	_set_field_text(_typing, clipped)
	_type_key = "%s|%s|%s|%d" % [true, clipped, _field_hint(_typing), limit]
	if closing:
		_close_type()
		return
	if done:
		_submit_field(_typing)
		_close_type()


func _field_text(edit: Control) -> String:
	if edit is LineEdit:
		return (edit as LineEdit).text
	if edit is TextEdit:
		return (edit as TextEdit).text
	return ""


func _field_hint(edit: Control) -> String:
	if edit is LineEdit:
		var line := edit as LineEdit
		if not line.placeholder_text.is_empty():
			return line.placeholder_text
	return "Type here"


func _field_max(edit: Control) -> int:
	if edit is LineEdit:
		var line := edit as LineEdit
		if line.max_length > 0:
			return line.max_length
	return 120


func _set_field_text(edit: Control, text: String) -> void:
	if edit is LineEdit:
		var line := edit as LineEdit
		if line.text == text:
			line.caret_column = text.length()
			return
		line.text = text
		line.caret_column = text.length()
		line.text_changed.emit(text)
		return
	if edit is TextEdit:
		var box := edit as TextEdit
		if box.text != text:
			box.text = text


func _submit_field(edit: Control) -> void:
	if edit is LineEdit:
		var line := edit as LineEdit
		line.text_submitted.emit(line.text)


func _screen_pos() -> Vector2:
	var rect := get_viewport().get_visible_rect()
	return Vector2(rect.position.x + _uv.x * rect.size.x, rect.position.y + _uv.y * rect.size.y)


func _set_hover(hit: Control) -> void:
	if hit == _hover:
		return
	if _hover != null and is_instance_valid(_hover):
		if _hover.has_signal("unhovered"):
			_hover.emit_signal("unhovered")
		if _hover.has_method("_on_hover"):
			_hover.call("_on_hover", false)
	_hover = hit
	if _hover == null:
		return
	GameSession.play_sfx("hover")
	if _hover.has_signal("hovered"):
		_hover.emit_signal("hovered")
	if _hover.has_method("_on_hover"):
		_hover.call("_on_hover", true)


func _set_cursor(on: bool, uv: Vector2 = Vector2(0.5, 0.5)) -> void:
	if _cursor and _cursor.has_method("set_point"):
		_cursor.set_point(on, uv)


func _in_course() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var path := scene.scene_file_path
	return path.ends_with("course.tscn") or path.ends_with("test_level.tscn")
