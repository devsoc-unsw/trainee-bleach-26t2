extends Control

@onready var status_label: Label = $StatusLabel
@onready var name_entry_panel: Control = $NameEntryPanel
@onready var name_line_edit: LineEdit = $NameEntryPanel/NameLineEdit
@onready var code_line_edit: LineEdit = $NameEntryPanel/CodeLineEdit
@onready var join_button: Button = $NameEntryPanel/JoinButton

@onready var lobby_panel: Control = $LobbyPanel
@onready var room_code_label: Label = $LobbyPanel/RoomCodeLabel
@onready var mode_label: Label = $LobbyPanel/ModeLabel
@onready var mode_button_row: HBoxContainer = $LobbyPanel/ModeButtonRow
@onready var turn_button: Button = $LobbyPanel/ModeButtonRow/TurnByTurnButton
@onready var ffa_button: Button = $LobbyPanel/ModeButtonRow/FreeForAllButton
@onready var player_list_container: VBoxContainer = $LobbyPanel/PlayerListContainer
@onready var ready_button: Button = $LobbyPanel/ReadyButton
@onready var start_button: Button = $LobbyPanel/StartButton

@onready var countdown_panel: Control = $CountdownPanel

func _ready() -> void:
	NetworkClient.connection_status_changed.connect(_on_status_changed)
	NetworkClient.player_joined.connect(_on_player_joined)
	NetworkClient.lobby_updated.connect(_on_lobby_updated)
	NetworkClient.server_error.connect(_on_server_error)
	NetworkClient.match_started.connect(_on_match_started)

	join_button.pressed.connect(_on_join_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	turn_button.pressed.connect(_on_turn_mode_pressed)
	ffa_button.pressed.connect(_on_ffa_mode_pressed)
	NetworkClient.game_mode_changed.connect(_on_game_mode_changed)

	lobby_panel.visible = false
	countdown_panel.visible = false
	status_label.text = "Initialising..."

func _on_status_changed(status: String) -> void:
	status_label.text = "Status: " + status

func _on_join_pressed() -> void:
	var player_name := name_line_edit.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "Enter a name first"
		return
	var code := code_line_edit.text.strip_edges().to_upper()
	NetworkClient.send_join(player_name, code)

func _on_player_joined(player: Dictionary) -> void:
	room_code_label.text = "Room code: " + player["code"]
	name_entry_panel.visible = false
	lobby_panel.visible = true
	_render_player_list(player["players"])

func _on_lobby_updated(players: Array) -> void:
	status_label.text = "Status: Connected"
	_render_player_list(players)

func _render_player_list(players: Array) -> void:
	for child in player_list_container.get_children():
		child.queue_free()

	var am_host := false
	for p in players:
		if p["id"] == NetworkClient.my_player_id and p["isHost"]:
			am_host = true
		var row := Label.new()
		var ready_marker := "✓" if p["ready"] else "…"
		row.text = "%s  %s" % [p["name"], ready_marker]
		row.add_theme_color_override("font_color", Color(p["colour"]))
		player_list_container.add_child(row)

	start_button.visible = am_host
	_refresh_mode_ui(am_host)

	for p in players:
		if p["id"] == NetworkClient.my_player_id:
			ready_button.text = "Unready" if p["ready"] else "Ready"
			break

func _refresh_mode_ui(am_host: bool) -> void:
	var is_turn := NetworkClient.game_mode == NetworkClient.MODE_TURN_BY_TURN
	mode_label.text = "Mode: " + ("Turn by Turn" if is_turn else "Free for All")
	mode_button_row.visible = am_host
	if am_host:
		turn_button.disabled = is_turn
		ffa_button.disabled = not is_turn

func _on_game_mode_changed(_mode: String) -> void:
	var am_host := false
	if NetworkClient.players.has(NetworkClient.my_player_id):
		am_host = NetworkClient.players[NetworkClient.my_player_id]["isHost"]
	_refresh_mode_ui(am_host)

func _on_turn_mode_pressed() -> void:
	NetworkClient.send_set_mode(NetworkClient.MODE_TURN_BY_TURN)

func _on_ffa_mode_pressed() -> void:
	NetworkClient.send_set_mode(NetworkClient.MODE_FREE_FOR_ALL)

func _on_ready_pressed() -> void:
	NetworkClient.send_ready()

func _on_start_pressed() -> void:
	start_button.disabled = true
	NetworkClient.send_start_match()
	
func _on_match_started(_course_id: String, _holes: Array) -> void:
	name_entry_panel.visible = false
	lobby_panel.visible = false
	countdown_panel.visible = true

func _on_server_error(code: String, message: String) -> void:
	status_label.text = "Error: " + message
	start_button.disabled = false
