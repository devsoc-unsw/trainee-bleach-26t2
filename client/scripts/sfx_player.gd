extends Node

const HOVER := "res://assets/sound-effects/hover sound.mp3"
const SELECT := "res://assets/sound-effects/select sound.mp3"
const HIT := "res://assets/sound-effects/ball hit.mp3"
const GOAL := "res://assets/sound-effects/goal sound.mp3"
const MAP_SELECT := "res://assets/sound-effects/map select sound.mp3"
const PICKUP := "res://assets/sound-effects/item pickup.mp3"
const POWERUP := "res://assets/sound-effects/powerup use.mp3"

var _players: Dictionary = {}
var _last: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_players["hover"] = _make(HOVER, 6.0, "UI")
	_players["select"] = _make(SELECT, 0.0, "UI")
	_players["hit"] = _make(HIT, 0.0, "SFX")
	_players["goal"] = _make(GOAL, 0.0, "SFX")
	_players["map"] = _make(MAP_SELECT, 0.0, "UI")
	_players["pickup"] = _make(PICKUP, 0.0, "SFX")
	_players["powerup"] = _make(POWERUP, 0.0, "SFX")
	get_tree().node_added.connect(_hook)


func hover() -> void:
	_play("hover", 70)


func select() -> void:
	_play("select", 90)


func hit() -> void:
	_play("hit", 0)


func goal() -> void:
	_play("goal", 0)


func map_select() -> void:
	_play("map", 0)


func pickup() -> void:
	_play("pickup", 40)


func powerup() -> void:
	_play("powerup", 40)


func _play(key: String, gap_ms: int) -> void:
	var session := get_node_or_null("/root/GameSession")
	if session != null:
		if float(session.get("master_volume")) <= 0.0:
			return
		var ui := key == "hover" or key == "select" or key == "map"
		if ui and float(session.get("ui_volume")) <= 0.0:
			return
		if not ui and float(session.get("sfx_volume")) <= 0.0:
			return
	var now := Time.get_ticks_msec()
	if gap_ms > 0 and now - int(_last.get(key, 0)) < gap_ms:
		return
	_last[key] = now
	var player: AudioStreamPlayer = _players.get(key)
	if player == null or player.stream == null:
		return
	player.play()


func _hook(node: Node) -> void:
	if not (node is Control):
		return
	if node.has_signal("hovered"):
		_bind(node, "hovered", hover)
	if node is BaseButton:
		var btn := node as BaseButton
		if not btn.mouse_entered.is_connected(_on_btn_hover):
			btn.mouse_entered.connect(_on_btn_hover.bind(btn))
		if not btn.pressed.is_connected(_on_btn_press):
			btn.pressed.connect(_on_btn_press.bind(btn))


func _bind(node: Node, signal_name: String, cb: Callable) -> void:
	if not node.is_connected(signal_name, cb):
		node.connect(signal_name, cb)


func _on_btn_hover(btn: BaseButton) -> void:
	if btn == null or not is_instance_valid(btn) or btn.disabled:
		return
	hover()


func _on_btn_press(btn: BaseButton) -> void:
	if btn == null or not is_instance_valid(btn) or btn.disabled:
		return
	select()


func _make(path: String, volume_db: float = 0.0, bus_name: String = "SFX") -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	player.volume_db = volume_db
	if ResourceLoader.exists(path):
		player.stream = load(path) as AudioStream
	add_child(player)
	return player
