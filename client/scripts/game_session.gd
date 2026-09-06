extends Node

const COURSE_SCENE := "res://scenes/course.tscn"
const SELECT_SCENE := "res://scenes/map_select.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
const LOBBY_SCENE := "res://scenes/lobby_browser.tscn"

const BALL_COLORS: Array[String] = [
	"#E23B3B",
	"#4CB8B0",
	"#F2D04B",
	"#7B5BBF",
	"#E67E22",
	"#27AE60",
	"#2980B9",
	"#E84393",
]

const AUDIO_CFG := "user://audio.cfg"

var map_id: String = "main_walk"
var player_name: String = "Player"
var master_volume: float = 0.8
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var ui_volume: float = 1.0
var lobbies: Array[Dictionary] = []
var active_lobby: Dictionary = {}
var hosting := false
var online := false
var my_color := Color("E23B3B")
var last_error := ""
var aim_with_phone := false
var prefer_mouse := false
var game_mode := "turn_by_turn"
var vote_deadline_ms := 0.0
var vote_counts: Dictionary = {}
var vote_picks: Dictionary = {}
var my_vote := ""
var hole_ends_at_ms := 0.0

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
		"overview_zoom": 16.0,
		"preview": "res://assets/previews/rainbow_stairs.png",
		"preview_from": Vector3(14.0, 12.0, 8.0),
		"preview_look": Vector3(0.5, 1.2, -18.0),
		"pickups": [
			{"id": "rainbow_shield", "kind": "shield", "pos": Vector3(2.4, 0.2, -5.2)},
			{"id": "rainbow_shrink", "kind": "shrink", "pos": Vector3(-2.6, 0.9, -16.5)},
			{"id": "rainbow_gust", "kind": "gust", "pos": Vector3(-3.6, 0.7, -20.8)},
		],
		"pads": [
			{"pos": Vector3(0.0, 0.55, -11.5), "dir": Vector3(0.04, 0.0, -1.0), "len": 2.8, "wid": 1.5},
			{"pos": Vector3(0.6, 1.4, -27.5), "dir": Vector3(0.15, 0.0, -1.0), "len": 2.4, "wid": 1.4},
		],
	},
	"main_walk": {
		"id": "main_walk",
		"title": "Anzac to Law",
		"blurb": "From the light rail, down University Mall to the Law Library.",
		"par": 5,
		"hole": 2,
		"accent": Color("4CB8B0"),
		"scene": "res://scenes/maps/main_walk.tscn",
		"overview_zoom": 18.0,
		"preview": "res://assets/previews/main_walk.png",
		"preview_from": Vector3(18.0, 16.0, 8.0),
		"preview_look": Vector3(0.0, 0.6, -28.0),
		"pickups": [
			{"id": "mall_shield", "kind": "shield", "pos": Vector3(3.6, 0.2, -14.0)},
			{"id": "mall_shrink", "kind": "shrink", "pos": Vector3(-3.4, 0.2, -32.0)},
			{"id": "mall_gust", "kind": "gust", "pos": Vector3(-3.8, 0.2, -10.5)},
		],
		"pads": [
			{"pos": Vector3(0.0, 0.2, -22.0), "dir": Vector3(0.0, 0.0, -1.0), "len": 3.0, "wid": 1.6},
			{"pos": Vector3(0.9, 0.2, -48.0), "dir": Vector3(0.12, 0.0, -1.0), "len": 2.6, "wid": 1.45},
		],
	},
	"village_green": {
		"id": "village_green",
		"title": "Village Green",
		"blurb": "Past the bouldering wall and soccer pitch to the hall lawn.",
		"par": 4,
		"hole": 3,
		"accent": Color("5BBF5B"),
		"scene": "res://scenes/maps/village_green.tscn",
		"overview_zoom": 24.0,
		"preview": "res://assets/previews/village_green.png",
		"preview_from": Vector3(18.0, 16.0, 10.0),
		"preview_look": Vector3(0.4, 0.6, -32.0),
		"pickups": [
			{"id": "green_shield", "kind": "shield", "pos": Vector3(2.6, 0.2, -8.4)},
			{"id": "green_shrink", "kind": "shrink", "pos": Vector3(-2.4, 0.2, -16.2)},
			{"id": "green_gust", "kind": "gust", "pos": Vector3(2.2, 0.2, -46.4)},
		],
		"pads": [
			{"pos": Vector3(0.3, 0.2, -18.8), "dir": Vector3(0.0, 0.0, -1.0), "len": 2.7, "wid": 1.5},
			{"pos": Vector3(0.5, 0.2, -48.2), "dir": Vector3(0.08, 0.0, -1.0), "len": 2.5, "wid": 1.4},
		],
	},
}

const ORDER: Array[String] = ["rainbow_stairs", "main_walk", "village_green"]

var _loading := false
var _prewarmed := false
var _maps_warming := false
var _warm_vp: SubViewport
var _map_holds: Dictionary = {}
var _warming: Dictionary = {}
var _veil: ColorRect
var _spinner: LoadSpinner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_web_performance()
	_load_audio()
	_ensure_audio_buses()
	apply_audio_volumes()
	_build_loader()
	apply_mouse_cursor()
	call_deferred("prewarm_ui")
	NetworkClient.lobby_list_received.connect(_on_lobby_list)
	NetworkClient.lobby_state_received.connect(_on_lobby_state)
	NetworkClient.match_started.connect(_on_match_started)
	NetworkClient.match_over.connect(_on_match_over)
	NetworkClient.vote_state_received.connect(_on_vote_state)
	NetworkClient.error_received.connect(_on_net_error)


func _apply_web_performance() -> void:
	if not OS.has_feature("web"):
		return
	# Browser builds pay for every GPU pixel and uncapped frames.
	Engine.max_fps = 60
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.72
	vp.physics_object_picking = false


func apply_mouse_cursor() -> void:
	var script := load("res://scripts/wii_pointer.gd") as GDScript
	if script == null:
		return
	var helper: Object = script.new()
	if helper.has_method("install_mouse_cursor"):
		helper.call("install_mouse_cursor", my_color)
	helper.free()


func play_sfx(kind: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method(kind):
		sfx.call(kind)


func play_music(kind: String) -> void:
	var music := get_node_or_null("/root/Music")
	if music != null and music.has_method(kind):
		music.call(kind)


func fade_music(seconds: float = 0.35) -> void:
	var music := get_node_or_null("/root/Music")
	if music != null:
		music.call("fade_out", seconds)


func set_master_volume(value: float) -> void:
	master_volume = _set_bus_volume("Master", value)
	_save_audio()


func set_music_volume(value: float) -> void:
	music_volume = _set_bus_volume("Music", value)
	_save_audio()


func set_sfx_volume(value: float) -> void:
	sfx_volume = _set_bus_volume("SFX", value)
	_save_audio()


func set_ui_volume(value: float) -> void:
	ui_volume = _set_bus_volume("UI", value)
	_save_audio()


func apply_audio_volumes() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("UI", ui_volume)


func _set_bus_volume(bus_name: String, value: float) -> float:
	var amount := clampf(value, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return amount
	AudioServer.set_bus_mute(bus, amount <= 0.001)
	if amount > 0.001:
		AudioServer.set_bus_volume_db(bus, linear_to_db(amount))
	return amount


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _load_audio() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUDIO_CFG) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui", ui_volume)), 0.0, 1.0)


func _save_audio() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.save(AUDIO_CFG)


func open_title() -> void:
	if online and not active_lobby.is_empty():
		NetworkClient.send_leave()
	active_lobby = {}
	hosting = false
	online = false
	game_mode = "turn_by_turn"
	vote_deadline_ms = 0.0
	vote_counts = {}
	vote_picks = {}
	my_vote = ""
	hole_ends_at_ms = 0.0
	fade_music(0.35)
	get_tree().change_scene_to_file(TITLE_SCENE)


func open_lobbies() -> void:
	online = true
	NetworkClient.ensure_connected()
	_play_with_fade(LOBBY_SCENE)


func public_lobbies() -> Array[Dictionary]:
	return lobbies


func create_lobby(lobby_name: String, is_public: bool, rounds: int = 1, mode: String = "turn_by_turn") -> void:
	last_error = ""
	game_mode = mode
	NetworkClient.ensure_connected()
	NetworkClient.send_create(lobby_name, is_public, player_name, rounds, mode)


func is_turn_by_turn() -> bool:
	return game_mode == "turn_by_turn"


func is_free_for_all() -> bool:
	return game_mode == "free_for_all"


func player_count() -> int:
	return maxi(player_ids().size(), 1)


func player_ids() -> Array[String]:
	var ids: Array[String] = []
	var seen: Dictionary = {}
	var people: Variant = active_lobby.get("player_list", [])
	if people is Array:
		var ranked: Array = []
		for p in people:
			if p is Dictionary and not str(p.get("id", "")).is_empty():
				ranked.append(p)
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("joinedAt", 0)) < int(b.get("joinedAt", 0))
		)
		for p in ranked:
			var id := str(p.get("id", ""))
			if seen.has(id):
				continue
			seen[id] = true
			ids.append(id)
	if ids.is_empty() and not NetworkClient.player_id.is_empty():
		ids.append(NetworkClient.player_id)
	return ids


func set_game_mode(mode: String) -> void:
	NetworkClient.send_set_mode(mode)


func color_hex(value: Variant) -> String:
	return str(value).strip_edges().trim_prefix("#").to_upper()


func is_color_taken(hex: String) -> bool:
	var key := color_hex(hex)
	if key.is_empty():
		return false
	var people: Variant = active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if not p is Dictionary:
				continue
			if str(p.get("id", "")) == NetworkClient.player_id:
				continue
			if color_hex(p.get("color", "")) == key:
				return true
	return false


func set_profile(new_name: String = "", color: String = "") -> void:
	if not new_name.is_empty():
		player_name = new_name
	if not color.is_empty() and is_color_taken(color):
		last_error = "That colour is already taken"
		return
	NetworkClient.send_set_profile(new_name, color)


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
	vote_picks = {}
	my_vote = ""
	hole_ends_at_ms = 0.0


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
		var next_name := str(mine.get("name", "")).strip_edges()
		if not next_name.is_empty():
			player_name = next_name
		var next_color := UiStyle.to_color(mine.get("color", "#E23B3B"))
		if next_color != my_color:
			my_color = next_color
			apply_mouse_cursor()


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
	play_sfx("map_select")
	_play_with_fade(COURSE_SCENE)


func begin_course_vote() -> void:
	NetworkClient.send_select()


func quick_start_match() -> void:
	if hosting:
		NetworkClient.send_quick_start()


func is_loading() -> bool:
	return _loading


func player_slot(player_id: String) -> int:
	var people: Variant = active_lobby.get("player_list", [])
	if not people is Array:
		return 1
	var ranked: Array = []
	for p in people:
		if p is Dictionary and not str(p.get("id", "")).is_empty():
			ranked.append(p)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("joinedAt", 0)) < int(b.get("joinedAt", 0))
	)
	for i in ranked.size():
		if str(ranked[i].get("id", "")) == player_id:
			return i + 1
	return ranked.size() + 1


func player_tint(player_id: String) -> Color:
	if player_id == NetworkClient.player_id:
		return my_color
	var people: Variant = active_lobby.get("player_list", [])
	if people is Array:
		for p in people:
			if p is Dictionary and str(p.get("id", "")) == player_id:
				return UiStyle.to_color(p.get("color", "#E23B3B"))
	return UiStyle.INK


func voters_for_map(course_id: String) -> Array:
	var out: Array = []
	for player_id in vote_picks.keys():
		if str(vote_picks[player_id]) != course_id:
			continue
		var id := str(player_id)
		out.append({
			"id": id,
			"slot": player_slot(id),
			"color": player_tint(id),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot", 0)) < int(b.get("slot", 0))
	)
	return out


func vote_seconds_left() -> float:
	if vote_deadline_ms <= 0.0:
		return 0.0
	return maxf(0.0, vote_deadline_ms / 1000.0 - Time.get_unix_time_from_system())


func _on_vote_state(deadline: float, votes: Dictionary, counts: Dictionary) -> void:
	vote_deadline_ms = deadline
	vote_counts = counts
	vote_picks = votes.duplicate()
	my_vote = str(votes.get(NetworkClient.player_id, ""))
	vote_updated.emit()
	if not online or _loading:
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("leave_to_map_select"):
		if scene.has_method("is_ready_for_map_select") and not bool(scene.call("is_ready_for_map_select")):
			return
		scene.call("leave_to_map_select")
		return
	if scene == null or scene.scene_file_path != SELECT_SCENE:
		_play_with_fade(SELECT_SCENE)


func _on_match_started(id: String, hole_ends_at: float = 0.0) -> void:
	if not online:
		return
	map_id = id
	hole_ends_at_ms = hole_ends_at
	vote_deadline_ms = 0.0
	vote_counts = {}
	vote_picks = {}
	my_vote = ""
	play_sfx("map_select")
	_play_with_fade(COURSE_SCENE)


func _on_match_over(placings: Array = []) -> void:
	if not online:
		return
	vote_deadline_ms = 0.0
	hole_ends_at_ms = 0.0
	var scene := get_tree().current_scene
	if scene and scene.has_method("present_match_results"):
		scene.call("present_match_results", placings)
		return
	return_to_lobby()


func prewarm_ui() -> void:
	if _prewarmed:
		return
	_prewarmed = true
	MapKit.warm()
	await get_tree().process_frame
	await get_tree().process_frame
	_request_scene(SELECT_SCENE)
	_request_scene(LOBBY_SCENE)


func prewarm_course_assets() -> void:
	_request_scene(COURSE_SCENE)
	_request_scene("res://assets/music/Bliss Boutique.mp3")
	for id in ORDER:
		var spec: Dictionary = MAPS[id]
		var scene_path := str(spec.get("scene", ""))
		if not scene_path.is_empty():
			_request_scene(scene_path)


func prewarm_maps() -> void:
	if _maps_warming:
		return
	_maps_warming = true
	prewarm_course_assets()
	for id in ORDER:
		await get_tree().process_frame
		await warm_map_instance(id)
	_maps_warming = false


func warm_map_instance(id: String) -> void:
	if id.is_empty() or not MAPS.has(id):
		return
	if _map_holds.has(id) and is_instance_valid(_map_holds[id]):
		return
	if bool(_warming.get(id, false)):
		while bool(_warming.get(id, false)):
			await get_tree().process_frame
		return
	_warming[id] = true
	var path := str(MAPS[id].get("scene", ""))
	_request_scene(path)
	var packed := await _await_scene(path)
	if packed == null:
		_warming[id] = false
		return
	var hold := _ensure_warm_vp()
	var inst := packed.instantiate() as Node3D
	if inst == null:
		_warming[id] = false
		return
	inst.set_meta("defer_rebuild", true)
	inst.visible = false
	hold.add_child(inst)
	await get_tree().process_frame
	if inst.has_method("warm_rebuild"):
		await inst.warm_rebuild()
	elif inst.has_method("_rebuild_visuals"):
		inst.call("_rebuild_visuals")
	await get_tree().process_frame
	_map_holds[id] = inst
	_warming[id] = false


func take_map_instance(id: String) -> Node3D:
	var inst := _map_holds.get(id) as Node3D
	_map_holds.erase(id)
	if inst == null or not is_instance_valid(inst):
		return null
	var parent := inst.get_parent()
	if parent != null:
		parent.remove_child(inst)
	inst.visible = true
	inst.process_mode = Node.PROCESS_MODE_INHERIT
	return inst


func _ensure_warm_vp() -> SubViewport:
	if _warm_vp != null and is_instance_valid(_warm_vp):
		return _warm_vp
	_warm_vp = SubViewport.new()
	_warm_vp.own_world_3d = true
	_warm_vp.size = Vector2i(8, 8)
	_warm_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_warm_vp)
	return _warm_vp


func open_select() -> void:
	_play_with_fade(SELECT_SCENE)


func open_select_faded() -> void:
	_play_with_fade(SELECT_SCENE)


func return_to_lobby() -> void:
	fade_music(0.35)
	get_tree().change_scene_to_file(LOBBY_SCENE)


func return_to_lobby_faded() -> void:
	_play_with_fade(LOBBY_SCENE)


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
	fade_music(0.4)
	_request_scene(path)
	var map_scene := ""
	if path == COURSE_SCENE:
		map_scene = str(get_map().get("scene", ""))
		if not map_scene.is_empty():
			_request_scene(map_scene)
	await _fade_to_black()
	if path == COURSE_SCENE:
		await warm_map_instance(map_id)
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
	if path == LOBBY_SCENE or path == SELECT_SCENE:
		prewarm_maps()
	elif path == COURSE_SCENE:
		warm_map_instance(map_id)


func _request_scene(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	if ResourceLoader.has_cached(path):
		return
	var err := ResourceLoader.load_threaded_request(path, "", true)
	if err != OK and err != ERR_BUSY:
		push_warning("Could not thread-load %s (%s)" % [path, error_string(err)])


func _await_scene(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if ResourceLoader.has_cached(path):
		return ResourceLoader.load(path) as PackedScene
	_request_scene(path)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as PackedScene
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			return null
		if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			if ResourceLoader.has_cached(path):
				return ResourceLoader.load(path) as PackedScene
			_request_scene(path)
		await get_tree().process_frame
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
