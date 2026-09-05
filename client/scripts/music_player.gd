extends Node

const PLAZA := "res://assets/music/Plaza.mp3"
const SAFE_HAVEN := "res://assets/music/Safe Haven.mp3"
const BLISS := "res://assets/music/Bliss Boutique.mp3"

const CUE_TITLE := "plaza"
const CUE_MENUS := "menu"
const CUE_PLAY := "play"

const SCENE_FADE := 0.45
const LOOP_FADE := 2.0
const SILENT_DB := -60.0
const FULL_DB := 0.0

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _cue := ""
var _path := ""
var _switching := false
var _tween: Tween
var _streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_a = _make_player("MusicA")
	_b = _make_player("MusicB")
	_active = _a


func play_title() -> void:
	play(CUE_TITLE)


func play_menus() -> void:
	play(CUE_MENUS)


func play_game() -> void:
	play(CUE_PLAY)


func play_for_scene(scene_path: String) -> void:
	if scene_path == "res://scenes/title.tscn":
		play_title()
	elif scene_path == "res://scenes/course.tscn":
		play_game()
	elif scene_path == "res://scenes/map_select.tscn" or scene_path == "res://scenes/lobby_browser.tscn":
		play_menus()


func play(cue: String) -> void:
	var next := _path_for(cue)
	if next.is_empty():
		return
	_cue = cue
	_switch(next, SCENE_FADE)


func fade_out(seconds: float = SCENE_FADE) -> void:
	_cue = ""
	_path = ""
	_switching = true
	_kill_tween()
	var outgoing := _active
	if outgoing == null or not outgoing.playing:
		_switching = false
		return
	var fade := maxf(seconds, 0.05)
	_tween = create_tween()
	_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		if outgoing != null:
			outgoing.stop()
			outgoing.volume_db = SILENT_DB
		if _active == outgoing:
			_switching = false
	)


func _process(_delta: float) -> void:
	if _switching or _active == null or not _active.playing or _active.stream == null:
		return
	var length := _active.stream.get_length()
	if length <= 0.25:
		return
	var fade := _loop_fade(length)
	var pos := _active.get_playback_position()
	if pos > fade and length - pos <= fade:
		_switch(_path, fade)


func _switch(path: String, fade: float) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_switching = true
	_path = path
	_kill_tween()
	var incoming := _b if _active == _a else _a
	incoming.stop()
	incoming.stream = _load_stream(path)
	incoming.volume_db = SILENT_DB
	incoming.play(0.0)
	var fade_in := maxf(fade, 0.05)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(incoming, "volume_db", FULL_DB, fade_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _active.playing and _active != incoming:
		_tween.tween_property(_active, "volume_db", SILENT_DB, fade_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func() -> void:
		if _active != incoming:
			_active.stop()
			_active.volume_db = SILENT_DB
		_active = incoming
		_switching = false
	)


func _path_for(cue: String) -> String:
	match cue:
		CUE_TITLE:
			return PLAZA
		CUE_MENUS:
			return SAFE_HAVEN
		CUE_PLAY:
			return BLISS
		_:
			return ""


func _load_stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var src := load(path) as AudioStream
	if src == null:
		return null
	var stream := src.duplicate() as AudioStream
	if stream == null:
		stream = src
	if stream.has_method("set_loop"):
		stream.call("set_loop", false)
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_streams[path] = stream
	return stream


func _loop_fade(length: float) -> float:
	return clampf(LOOP_FADE, 0.35, length * 0.22)


func _make_player(node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = "Music"
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
