extends Node

signal connection_status_changed(status: String)
signal message_received(data: Dictionary)
signal state_changed(new_state: GameState)
signal player_joined(player: Dictionary)
signal player_left(player_id: String)
signal lobby_updated(players: Array)
signal match_started(course_id: String, holes: Array)
signal hole_started(hole_index: int, par: int, timer_ms: float, spawn: Vector3)
signal snapshot_received(tick: int, balls: Array)
signal stroke_updated(player_id: String, hole_index: int, strokes: int)
signal hole_ended(hole_index: int, results: Array)
signal match_ended(placings: Array)
signal server_error(code: String, message: String)



# Change this to your deployed server URL before exporting.
# Uses ws:// for localhost, wss:// for everything else.
const SERVER_HOST: String = "localhost:8080"

enum GameState {
	LOBBY,
	COUNTDOWN,
	HOLE_ACTIVE,
	HOLE_SUMMARY,
	MATCH_END,
}

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false
var _was_connected: bool = false
var current_state: GameState = GameState.LOBBY


func _get_server_url() -> String:
	if SERVER_HOST.begins_with("localhost") or SERVER_HOST.begins_with("127.0.0.1"):
		return "ws://" + SERVER_HOST
	else:
		return "wss://" + SERVER_HOST


func _ready() -> void:
	connection_status_changed.connect(func(status): print("[NetworkClient] ", status))
	message_received.connect(func(data): print("[NetworkClient] received: ", data))
	var url := _get_server_url()
	_emit_status("Connecting to " + url + "...")

	var err := _socket.connect_to_url(url)
	if err != OK:
		_emit_status("Connection failed (error " + str(err) + ")")
		return


func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_was_connected = true
				_emit_status("Connected")
				# _send_test_message()

			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				var text := packet.get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(text)
				if parsed is Dictionary:
					_route_message(parsed as Dictionary)
				else:
					push_warning("NetworkClient: received non-dictionary message")

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			if _was_connected:
				var code := _socket.get_close_code()
				var reason := _socket.get_close_reason()
				_emit_status("Disconnected (code " + str(code) + ": " + reason + ")")
				_connected = false
				_was_connected = false
				set_process(false)

		WebSocketPeer.STATE_CONNECTING:
			pass


#func _send_test_message() -> void:
	#var msg := JSON.stringify({ "t": "hello", "from": "godot" })
	#_socket.send_text(msg)
	
func _route_message(data: Dictionary) -> void:
	message_received.emit(data)
	match data.get("t"):
		"joined":
			player_joined.emit(data)
		"lobby_state":
			lobby_updated.emit(data["players"])
		"match_start":
			_set_state(GameState.COUNTDOWN)
			match_started.emit(data["courseId"], data["holes"])
		"hole_start":
			_set_state(GameState.HOLE_ACTIVE)
			var spawn_arr: Array = data["spawn"]
			var spawn := Vector3(spawn_arr[0], spawn_arr[1], spawn_arr[2])
			hole_started.emit(data["holeIndex"], data["par"], data["timerMs"], spawn)
		"snapshot":
			snapshot_received.emit(data["tick"], data["balls"])
		"stroke_update":
			stroke_updated.emit(data["playerId"], data["holeIndex"], data["strokes"])
		"hole_end":
			_set_state(GameState.HOLE_SUMMARY)
			hole_ended.emit(data["holeIndex"], data["results"])
		"match_end":
			_set_state(GameState.MATCH_END)
			match_ended.emit(data["placings"])
		"player_left":
			player_left.emit(data["playerId"])
		"error":
			server_error.emit(data["code"], data["message"])
		_:
			pass


func _set_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	current_state = new_state
	state_changed.emit(new_state)


func _send(msg: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(msg))


#   send_join(name: String, code: String) -> join or create room
func send_join(player_name: String, code: String = "") -> void:
	var msg:= { "t": "join", "name": player_name }
	if code != "":
		msg["code"] = code
	_send(msg)

#   send_ready()
func send_ready() -> void:
	var msg:= { "t": "ready" }
	_send(msg)

#   send_start_match() -> host only
func send_start_match() -> void:
	var msg:= { "t": "start_match" }
	_send(msg)

#   send_shot(dir: Vector2, power: float)
func send_shot(dir: Vector2, power: float) -> void:
	var msg:= { "t": "shot", "dir": [dir.x, dir.y], "power": power }
	_send(msg)

#   send_ball_state(pos: Vector3, vel: Vector3, at_rest: bool) -> call at 15Hz while moving
func send_ball_state(pos: Vector3, vel: Vector3, at_rest: bool) -> void:
	var msg:= {
		"t": "ball_state",
		"pos": [pos.x, pos.y, pos.z],
		"vel": [vel.x, vel.y, vel.z],
		"atRest": at_rest
	}
	_send(msg)

#   send_holed(pos: Vector3)
func send_holed(pos: Vector3) -> void:
	var msg:= { "t": "holed", "pos": [pos.x, pos.y, pos.z] }
	_send(msg)

#
# TODO: add message routing in _process:
#   parse data["t"] and emit the right signal with the payload
#   e.g. "lobby_state" -> lobby_updated.emit(data["players"])
#        "hole_start"  -> hole_started.emit(data["holeIndex"], data["par"], ...)
#        "snapshot"    -> snapshot_received.emit(data["balls"])


func _emit_status(status: String) -> void:
	connection_status_changed.emit(status)
