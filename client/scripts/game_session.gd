extends Node

const COURSE_SCENE := "res://scenes/course.tscn"
const SELECT_SCENE := "res://scenes/map_select.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
const LOBBY_SCENE := "res://scenes/lobby_browser.tscn"

var map_id: String = "main_walk"
var player_name: String = "Player"
var master_volume: float = 0.8
var lobbies: Array[Dictionary] = []
var active_lobby: Dictionary = {}
var hosting := false
var online := false
var my_color := Color("E23B3B")
var last_error := ""
var show_players := true
var game_mode := "turn_by_turn"
var vote_deadline_ms := 0.0
var vote_counts: Dictionary = {}
var my_vote := ""

signal vote_updated

const MAPS := {
	"rainbow_stairs": {
		"id": "rainbow_stairs",
		"title": "Rainbow Stairs",
		"blurb": "Putt up the rainbow stairs onto the Quad.",
		"par": 4,
		"hole": 1,
		"accent": Color("E23B3B"),
		"scene": "res://scenes/maps/rainbow_stairs.tscn",
		"overview_zoom": 36.0,
		"preview": "res://assets/previews/rainbow_stairs.png",
		"preview_from": Vector3(14.0, 12.0, 8.0),
		"preview_look": Vector3(0.5, 1.2, -18.0),
	},
	"main_walk": {
		"id": "main_walk",
		"title": "Anzac to Law",
		"blurb": "From the light rail, down University Mall to the Law Library.",
		"par": 5,
		"hole": 2,
		"accent": Color("4CB8B0"),
		"scene": "res://scenes/maps/main_walk.tscn",
		"overview_zoom": 48.0,
		"preview": "res://assets/previews/main_walk.png",
		"preview_from": Vector3(18.0, 16.0, 8.0),
		"preview_look": Vector3(0.0, 0.6, -28.0),
	},
	"village_green": {
		"id": "village_green",
		"title": "Village Green",
		"blurb": "Around the soccer field and bouldering wall.",
		"par": 3,
		"hole": 3,
		"accent": Color("5BBF5B"),
		"scene": "res://scenes/maps/village_green.tscn",
		"overview_zoom": 40.0,
		"preview": "res://assets/previews/village_green.png",
		"preview_from": Vector3(16.0, 13.0, 8.0),
		"preview_look": Vector3(0.0, 0.6, -20.0),
	},
}

const ORDER: Array[String] = ["rainbow_stairs", "main_walk", "village_green"]

var _loading := false
var _veil: ColorRect
var _spinner: LoadSpinner


func _ready() -> void:
	set_master_volume(master_volume)
	_build_loader()
	NetworkClient.lobby_list_received.connect(_on_lobby_list)
	NetworkClient.lobby_state_received.connect(_on_lobby_state)
	NetworkClient.match_started.connect(_on_match_started)
	NetworkClient.match_over.connect(_on_match_over)
	NetworkClient.vote_state_received.connect(_on_vote_state)
	NetworkClient.error_received.connect(_on_net_error)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))


func open_title() -> void:
	if online and not active_lobby.is_empty():
		NetworkClient.send_leave()
	active_lobby = {}
	hosting = false
	online = false
	game_mode = "turn_by_turn"
	vote_deadline_ms = 0.0
	vote_counts = {}
	my_vote = ""
	get_tree().change_scene_to_file(TITLE_SCENE)


func open_lobbies() -> void:
	online = true
	NetworkClient.ensure_connected()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func public_lobbies() -> Array[Dictionary]:
	return lobbies


func create_lobby(lobby_name: String, is_public: bool, rounds: int = 1, mode: String = "turn_by_turn") -> void:
	last_error = ""
	game_mode = mode
	NetworkClient.ensure_connected()
	NetworkClient.send_create(lobby_name, is_public, player_name, rounds, mode)


func is_turn_by_turn() -> bool:
	return game_mode == "turn_by_turn"


func set_game_mode(mode: String) -> void:
	NetworkClient.send_set_mode(mode)


func join_lobby(raw_code: String) -> String:
	var code := raw_code.strip_edges().to_upper()
	if code.length() != 4:
		return "Enter a 4-letter code"
	last_error = ""
	NetworkClient.ensure_connected()
	NetworkClient.send_join(code, player_name)
	return ""


func leave_lobby() -> void:
	NetworkClient.send_leave()
	active_lobby = {}
	hosting = false
	game_mode = "turn_by_turn"
	vote_deadline_ms = 0.0
	vote_counts = {}
	my_vote = ""


func leave_match() -> void:
	if online:
		leave_lobby()
		open_lobbies()
		return
	open_title()


func refresh_lobbies() -> void:
	NetworkClient.send_list()


func _on_lobby_list(rooms: Array) -> void:
	lobbies.clear()
	for room in rooms:
		if room is Dictionary:
			lobbies.append(_room_from_net(room))


func _on_lobby_state(lobby: Dictionary) -> void:
	active_lobby = _room_from_net(lobby)
	hosting = str(lobby.get("hostId", "")) == NetworkClient.player_id
	game_mode = str(active_lobby.get("gameMode", game_mode))
	var mine := _my_player()
	if not mine.is_empty():
		my_color = Color(str(mine.get("color", "#E23B3B")))


func _on_net_error(_code: String, message: String) -> void:
	last_error = message


func _my_player() -> Dictionary:
	for p in active_lobby.get("player_list", []):
		if p is Dictionary and str(p.get("id", "")) == NetworkClient.player_id:
			return p
	return {}


func _room_from_net(raw: Dictionary) -> Dictionary:
	var people: Array = []
	var count := 1
	var players_raw: Variant = raw.get("players", raw.get("player_list", []))
	if players_raw is Array:
		people = players_raw
		count = people.size()
	else:
		count = int(players_raw)
		var listed: Variant = raw.get("player_list", [])
		if listed is Array:
			people = listed
	var host_name := str(raw.get("host", "Host"))
	for p in people:
		if p is Dictionary and bool(p.get("host", false)):
			host_name = str(p.get("name", host_name))
	return {
		"code": str(raw.get("code", "")),
		"name": str(raw.get("name", "Lobby")),
		"is_public": bool(raw.get("isPublic", raw.get("is_public", true))),
		"players": count,
		"max_players": int(raw.get("maxPlayers", raw.get("max_players", 4))),
		"host": host_name,
		"hostId": str(raw.get("hostId", "")),
		"mapId": str(raw.get("mapId", "")),
		"rounds": int(raw.get("rounds", 1)),
		"roundIndex": int(raw.get("roundIndex", 0)),
		"gameMode": str(raw.get("gameMode", "turn_by_turn")),
		"player_list": people,
	}


func get_map(id: String = "") -> Dictionary:
	var key := id if not id.is_empty() else map_id
	if MAPS.has(key):
		return MAPS[key]
	return MAPS["main_walk"]


func play_map(id: String) -> void:
	if online:
		NetworkClient.send_vote(id)
		return
	map_id = id
	_play_with_fade(COURSE_SCENE)


func begin_course_vote() -> void:
	NetworkClient.send_select()


func quick_start_match() -> void:
	if hosting:
		NetworkClient.send_quick_start()


func vote_seconds_left() -> float:
	if vote_deadline_ms <= 0.0:
		return 0.0
	return maxf(0.0, vote_deadline_ms / 1000.0 - Time.get_unix_time_from_system())


func _on_vote_state(deadline: float, votes: Dictionary, counts: Dictionary) -> void:
	vote_deadline_ms = deadline
	vote_counts = counts
	my_vote = str(votes.get(NetworkClient.player_id, ""))
	vote_updated.emit()
	if not online or _loading:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != SELECT_SCENE:
		get_tree().change_scene_to_file(SELECT_SCENE)


func _on_match_started(id: String) -> void:
	if not online:
		return
	map_id = id
	vote_deadline_ms = 0.0
	vote_counts = {}
	my_vote = ""
	_play_with_fade(COURSE_SCENE)


func _on_match_over(placings: Array = []) -> void:
	if not online:
		return
	vote_deadline_ms = 0.0
	var scene := get_tree().current_scene
	if scene and scene.has_method("present_match_results"):
		scene.call("present_match_results", placings)
		return
	return_to_lobby()


func open_select() -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)


func return_to_lobby() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _build_loader() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_veil = ColorRect.new()
	_veil.color = Color.BLACK
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	_veil.visible = false
	layer.add_child(_veil)

	_spinner = LoadSpinner.new()
	_spinner.anchor_left = 1.0
	_spinner.anchor_top = 1.0
	_spinner.anchor_right = 1.0
	_spinner.anchor_bottom = 1.0
	_spinner.offset_left = -56.0
	_spinner.offset_top = -56.0
	_spinner.offset_right = -20.0
	_spinner.offset_bottom = -20.0
	_spinner.modulate.a = 0.0
	_spinner.visible = false
	_spinner.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_spinner)


func _play_with_fade(path: String) -> void:
	if _loading:
		return
	_loading = true
	_request_scene(path)
	var map_scene := str(get_map().get("scene", ""))
	if not map_scene.is_empty():
		_request_scene(map_scene)
	await _fade_to_black()
	if not map_scene.is_empty():
		await _await_scene(map_scene)
	var packed := await _await_scene(path)
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_from_black()
	_loading = false


func _request_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var err := ResourceLoader.load_threaded_request(path, "", false)
	if err != OK and err != ERR_BUSY:
		push_warning("Could not thread-load %s (%s)" % [path, error_string(err)])


func _await_scene(path: String) -> PackedScene:
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as PackedScene
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
		await get_tree().process_frame
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


func _fade_to_black() -> void:
	_veil.visible = true
	_spinner.visible = true
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.modulate.a = 0.0
	_spinner.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_veil, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_spinner, "modulate:a", 1.0, 0.22).set_delay(0.12)
	await tw.finished


func _fade_from_black() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_spinner, "modulate:a", 0.0, 0.18)
	tw.tween_property(_veil, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	_veil.visible = false
	_spinner.visible = false
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
