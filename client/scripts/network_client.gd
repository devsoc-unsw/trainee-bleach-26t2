extends Node

signal connection_status_changed(status: String)
signal message_received(data: Dictionary)

# TODO: add signals for game events:
#   player_joined(player: Dictionary)
#   player_left(player_id: String)
#   lobby_updated(players: Array)
#   match_started(holes: Array)
#   hole_started(hole_index: int, par: int, spawn: Vector3)
#   snapshot_received(balls: Array)
#   stroke_updated(player_id: String, strokes: int)
#   hole_ended(results: Array)
#   match_ended(placings: Array)




# Change this to your deployed server URL before exporting.
# Uses ws:// for localhost, wss:// for everything else.
const SERVER_HOST: String = "localhost:8080"

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false
var _was_connected: bool = false

func _get_server_url() -> String:
	if SERVER_HOST.begins_with("localhost") or SERVER_HOST.begins_with("127.0.0.1"):
		return "ws://" + SERVER_HOST
	else:
		return "wss://" + SERVER_HOST


func _ready() -> void:
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
				_send_test_message()

			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				var text := packet.get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(text)
				if parsed is Dictionary:
					message_received.emit(parsed as Dictionary)
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


func _send_test_message() -> void:
	var msg := JSON.stringify({ "t": "hello", "from": "godot" })
	_socket.send_text(msg)

# TODO: add send methods:
#   send_join(name: String, code: String) -> join or create room
#   send_ready()
#   send_start_match() -> host only
#   send_shot(dir: Vector2, power: float)
#   send_ball_state(pos: Vector3, vel: Vector3, at_rest: bool) -> call at 15Hz while moving
#   send_holed(pos: Vector3)
#   send_oob()
#
# TODO: add message routing in _process:
#   parse data["t"] and emit the right signal with the payload
#   e.g. "lobby_state" -> lobby_updated.emit(data["players"])
#        "hole_start"  -> hole_started.emit(data["holeIndex"], data["par"], ...)
#        "snapshot"    -> snapshot_received.emit(data["balls"])


func _emit_status(status: String) -> void:
	connection_status_changed.emit(status)
