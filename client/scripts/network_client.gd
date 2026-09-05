extends Node

signal connection_status_changed(status: String)
signal connected
signal lobby_list_received(rooms: Array)
signal lobby_state_received(lobby: Dictionary)
signal match_started(map_id: String)
signal vote_state_received(deadline: float, votes: Dictionary, counts: Dictionary)
signal snapshot_received(balls: Array)
signal stroke_updated(player_id: String, strokes: int)
signal player_holed(player_id: String, strokes: int)
signal match_over(placings: Array)
signal hole_ended(hole_index: int, last_hole: bool, results: Array)
signal chat_received(payload: Dictionary)
signal error_received(code: String, message: String)

var player_id := ""
var socket_open := false

var _socket := WebSocketPeer.new()
var _want_connect := false
var _was_connected := false
var _reconnect_in := 0.0
var _pending: Array[Dictionary] = []


func _ready() -> void:
	set_process(true)


func ensure_connected() -> void:
	_want_connect = true
	if socket_open:
		return
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING or state == WebSocketPeer.STATE_OPEN:
		return
	_connect_now()


func disconnect_from_server() -> void:
	_want_connect = false
	socket_open = false
	_was_connected = false
	_pending.clear()
	_socket.close()
	player_id = ""


func _connect_now() -> void:
	var state := _socket.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED and state != WebSocketPeer.STATE_CLOSING:
		return
	if state == WebSocketPeer.STATE_CLOSING:
		_socket = WebSocketPeer.new()
	var url := _server_url()
	_emit_status("Connecting to %s..." % url)
	var err := _socket.connect_to_url(url)
	if err != OK:
		_emit_status("Connection failed")
		_reconnect_in = 2.0


func _server_url() -> String:
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("window.location.host"))
		var https := str(JavaScriptBridge.eval("window.location.protocol")).begins_with("https")
		if host.is_empty() or host == "null":
			host = "127.0.0.1:8080"
		return ("wss://" if https else "ws://") + host
	var override := OS.get_environment("PUTT_SERVER")
	if not override.is_empty():
		return override
	return "ws://127.0.0.1:8080"


func _process(delta: float) -> void:
	if _reconnect_in > 0.0 and _want_connect and not socket_open:
		_reconnect_in -= delta
		if _reconnect_in <= 0.0:
			_socket = WebSocketPeer.new()
			_connect_now()
	if not _want_connect and not socket_open:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not socket_open:
				socket_open = true
				_was_connected = true
				_emit_status("Connected")
				connected.emit()
			while _socket.get_available_packet_count() > 0:
				_handle_packet(_socket.get_packet())
			_flush_pending()
		WebSocketPeer.STATE_CLOSED:
			if _was_connected or socket_open:
				_emit_status("Disconnected")
			socket_open = false
			_was_connected = false
			if _want_connect and _reconnect_in <= 0.0:
				_reconnect_in = 2.0


func _handle_packet(packet: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var kind := str(data.get("t", ""))
	match kind:
		"welcome":
			player_id = str(data.get("playerId", player_id))
		"lobby_list":
			lobby_list_received.emit(data.get("rooms", []))
		"lobby_state":
			lobby_state_received.emit(data)
		"match_start":
			match_started.emit(str(data.get("mapId", "rainbow_stairs")))
		"vote_state":
			vote_state_received.emit(
				float(data.get("deadline", 0.0)),
				data.get("votes", {}) if data.get("votes", {}) is Dictionary else {},
				data.get("counts", {}) if data.get("counts", {}) is Dictionary else {}
			)
		"snapshot":
			snapshot_received.emit(data.get("balls", []))
		"stroke_update":
			stroke_updated.emit(str(data.get("playerId", "")), int(data.get("strokes", 0)))
		"player_holed":
			player_holed.emit(str(data.get("playerId", "")), int(data.get("strokes", 0)))
		"hole_end":
			hole_ended.emit(
				int(data.get("holeIndex", 0)),
				bool(data.get("lastHole", false)),
				data.get("results", []) if data.get("results", []) is Array else []
			)
		"match_over":
			var raw: Variant = data.get("placings", [])
			match_over.emit(raw if raw is Array else [])
		"chat":
			chat_received.emit(data)
		"error":
			error_received.emit(str(data.get("code", "")), str(data.get("message", "Something went wrong")))
		_:
			pass


func send_list() -> void:
	_send({ "t": "list" })


func send_create(lobby_name: String, is_public: bool, player_name: String, rounds: int = 1, game_mode: String = "turn_by_turn") -> void:
	_send({
		"t": "create",
		"name": lobby_name,
		"isPublic": is_public,
		"playerName": player_name,
		"rounds": rounds,
		"gameMode": game_mode,
	})


func send_set_mode(mode: String) -> void:
	_send({ "t": "set_mode", "mode": mode })


func send_set_profile(player_name: String = "", color: String = "") -> void:
	var msg := { "t": "set_profile" }
	if not player_name.is_empty():
		msg["name"] = player_name
	if not color.is_empty():
		msg["color"] = color
	_send(msg)


func send_join(code: String, player_name: String) -> void:
	_send({ "t": "join", "code": code, "playerName": player_name })


func send_leave() -> void:
	_send({ "t": "leave" })


func send_chat(text: String) -> void:
	_send({ "t": "chat", "text": text })


func send_select() -> void:
	_send({ "t": "select" })


func send_vote(map_id: String) -> void:
	_send({ "t": "vote", "mapId": map_id })


func send_quick_start() -> void:
	_send({ "t": "quick_start" })


func send_shot() -> void:
	_send({ "t": "shot" })


func send_ball_state(pos: Vector3, vel: Vector3, at_rest: bool) -> void:
	_send({
		"t": "ball_state",
		"x": pos.x, "y": pos.y, "z": pos.z,
		"vx": vel.x, "vy": vel.y, "vz": vel.z,
		"atRest": at_rest,
	})


func send_holed() -> void:
	_send({ "t": "holed" })


func send_oob() -> void:
	_send({ "t": "oob" })


func _send(payload: Dictionary) -> void:
	if not socket_open:
		_pending.append(payload)
		ensure_connected()
		return
	_socket.send_text(JSON.stringify(payload))


func _flush_pending() -> void:
	if not socket_open or _pending.is_empty():
		return
	var queued := _pending.duplicate()
	_pending.clear()
	for payload in queued:
		_socket.send_text(JSON.stringify(payload))


func _emit_status(status: String) -> void:
	connection_status_changed.emit(status)
