extends Node3D

const BALL_SCENE := preload("res://scenes/Ball.tscn")

@onready var world: Node3D = $World
@onready var camera: Camera3D = $Camera3D
@onready var content: MarginContainer = $UI/Root/Content
@onready var list_view: Control = $UI/Root/Content/ListView
@onready var room_view: Control = $UI/Root/Content/RoomView
@onready var scroll: ScrollContainer = $UI/Root/Content/ListView/LobbyBox/Scroll
@onready var rows: VBoxContainer = $UI/Root/Content/ListView/LobbyBox/Scroll/Pad/Rows
@onready var empty_label: Label = $UI/Root/Content/ListView/LobbyBox/Empty
@onready var room_code: Label = $UI/Root/Content/RoomView/Card/Layout/Code
@onready var room_title: Label = $UI/Root/Content/RoomView/Card/Layout/LobbyName
@onready var room_meta: Label = $UI/Root/Content/RoomView/Card/Layout/Meta
@onready var create_dimmer: ColorRect = $UI/Root/CreateDimmer
@onready var join_dimmer: ColorRect = $UI/Root/JoinDimmer
@onready var name_edit: LineEdit = $UI/Root/CreateDimmer/Card/Layout/NameEdit
@onready var join_edit: LineEdit = $UI/Root/JoinDimmer/Card/Layout/CodeEdit
@onready var join_error: Label = $UI/Root/JoinDimmer/Card/Layout/Error
@onready var public_btn: Button = $UI/Root/CreateDimmer/Card/Layout/Visibility/Public
@onready var private_btn: Button = $UI/Root/CreateDimmer/Card/Layout/Visibility/Private
@onready var start_btn: Button = %Start

var _public_visibility := true
var _cam_base: Transform3D
var _t := 0.0
var _player_list: VBoxContainer
var _status: Label
var _waiting_for_room := false
var _poll := 0.0
var _rounds := 3
var _rounds_label: Label
var _create_mode := "turn_by_turn"
var _turn_btn: Button
var _ffa_btn: Button
var _room_mode_label: Label
var _room_turn_btn: Button
var _room_ffa_btn: Button


func _ready() -> void:
	_build_backdrop()
	_cam_base = MapKit.frame_menu_camera(camera)
	get_viewport().size_changed.connect(_apply_responsive)
	list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_responsive()
	_make_player_list()
	_make_status()
	_make_rounds_picker()
	_make_mode_picker()
	_make_room_mode_controls()
	create_dimmer.gui_input.connect(func(e: InputEvent) -> void: _dimmer_close(e, create_dimmer))
	join_dimmer.gui_input.connect(func(e: InputEvent) -> void: _dimmer_close(e, join_dimmer))
	join_edit.text_changed.connect(_on_join_code_typed)
	_style_scrollbar()

	NetworkClient.lobby_list_received.connect(_on_list_received)
	NetworkClient.lobby_state_received.connect(_on_state_received)
	NetworkClient.error_received.connect(_on_error_received)
	NetworkClient.connection_status_changed.connect(_on_status)
	NetworkClient.connected.connect(_on_connected)
	NetworkClient.ensure_connected()
	if NetworkClient.socket_open:
		NetworkClient.send_list()

	if not GameSession.active_lobby.is_empty():
		_show_room()
	else:
		_show_list()


func _process(delta: float) -> void:
	_t += delta
	camera.global_position = _cam_base.origin + MapKit.menu_camera_orbit(_t)
	camera.look_at(MapKit.MENU_CAM_LOOK, Vector3.UP)
	if not list_view.visible:
		return
	_poll += delta
	if _poll >= 2.0:
		_poll = 0.0
		NetworkClient.send_list()


func _on_connected() -> void:
	NetworkClient.send_list()
	_set_status("Connected")


func _on_status(status: String) -> void:
	_set_status(status)


func _on_list_received(_rooms: Array) -> void:
	if list_view.visible:
		_refresh_list(false)


func _on_state_received(_lobby: Dictionary) -> void:
	_waiting_for_room = false
	_show_room()


func _on_error_received(_code: String, message: String) -> void:
	_waiting_for_room = false
	join_error.text = message
	if not join_dimmer.visible and not GameSession.active_lobby.is_empty():
		return
	if not join_dimmer.visible:
		_show_overlay(join_dimmer)


func _build_backdrop() -> void:
	MapKit.menu_backdrop(world)
	var ball: RigidBody3D = BALL_SCENE.instantiate()
	ball.freeze = true
	ball.gravity_scale = 0.0
	ball.sleeping = true
	if ball.has_node("Shadow"):
		ball.get_node("Shadow").visible = false
	camera.add_child(ball)
	ball.position = Vector3(-0.72, -0.42, -1.2)
	ball.scale = Vector3.ONE * 1.45


func _make_player_list() -> void:
	var layout: VBoxContainer = $UI/Root/Content/RoomView/Card/Layout
	var meta: Label = room_meta
	_player_list = VBoxContainer.new()
	_player_list.name = "PlayerList"
	_player_list.add_theme_constant_override("separation", 6)
	layout.add_child(_player_list)
	layout.move_child(_player_list, meta.get_index() + 1)


func _make_status() -> void:
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(_status, true, 13, Color("FBF7F0"))
	list_view.add_child(_status)
	list_view.move_child(_status, 1)
	_set_status("Connecting...")


func _set_status(text: String) -> void:
	if _status:
		_status.text = text


func _apply_responsive() -> void:
	var pad := 28 if get_viewport().get_visible_rect().size.x < 800.0 else 56
	content.add_theme_constant_override("margin_left", pad)
	content.add_theme_constant_override("margin_right", pad)
	content.add_theme_constant_override("margin_top", 36)
	content.add_theme_constant_override("margin_bottom", 72)


func _show_list() -> void:
	list_view.visible = true
	room_view.visible = false
	_hide_overlay(create_dimmer)
	_hide_overlay(join_dimmer)
	_refresh_list()
	NetworkClient.send_list()


func _show_room() -> void:
	var lobby := GameSession.active_lobby
	if lobby.is_empty():
		return
	list_view.visible = false
	room_view.visible = true
	_hide_overlay(create_dimmer)
	_hide_overlay(join_dimmer)
	room_title.text = str(lobby.get("name", "Lobby"))
	room_code.text = str(lobby.get("code", "----"))
	var vis := "PUBLIC" if lobby.get("is_public", true) else "PRIVATE"
	var mode := _mode_label(str(lobby.get("gameMode", "turn_by_turn")))
	room_meta.text = "%s  ·  %d / %d players  ·  %d rounds  ·  %s" % [
		vis,
		int(lobby.get("players", 1)),
		int(lobby.get("max_players", 4)),
		int(lobby.get("rounds", 1)),
		mode,
	]
	start_btn.visible = GameSession.hosting
	_refresh_room_mode_ui()
	_fill_players(lobby.get("player_list", []))


func _fill_players(people: Variant) -> void:
	for child in _player_list.get_children():
		child.queue_free()
	if not people is Array:
		return
	for p in people:
		if not p is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = UiStyle.to_color(p.get("color", "#E23B3B"))
		var name_label := Label.new()
		var suffix := "  (host)" if bool(p.get("host", false)) else ""
		name_label.text = "%s%s" % [str(p.get("name", "Player")), suffix]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiStyle.apply_font(name_label, true, 14, UiStyle.INK)
		row.add_child(swatch)
		row.add_child(name_label)
		_player_list.add_child(row)


func _style_scrollbar() -> void:
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 12
	var track := StyleBoxFlat.new()
	track.bg_color = Color("E7E0D4")
	track.set_corner_radius_all(8)
	track.content_margin_left = 2
	track.content_margin_right = 2
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var grab := StyleBoxFlat.new()
	grab.bg_color = UiStyle.TEAL
	grab.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab)
	bar.add_theme_stylebox_override("grabber_pressed", grab)


func _refresh_list(animate := true) -> void:
	for child in rows.get_children():
		child.queue_free()
	var public := GameSession.public_lobbies()
	var empty := public.is_empty()
	empty_label.visible = empty
	if empty and not NetworkClient.socket_open:
		empty_label.text = "Connecting to server..."
	else:
		empty_label.text = "No lobbies available"
	scroll.visible = true
	scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_SHOW_NEVER if empty else ScrollContainer.SCROLL_MODE_AUTO
	)
	for i in public.size():
		var row := _make_row(public[i])
		rows.add_child(row)
		if animate:
			row.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(row, "modulate:a", 1.0, 0.22).set_delay(i * 0.05)


func _make_row(lobby: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color("FBF7F0")
	shell.set_corner_radius_all(14)
	shell.content_margin_left = 16
	shell.content_margin_right = 16
	shell.content_margin_top = 10
	shell.content_margin_bottom = 10
	shell.border_width_left = 2
	shell.border_width_top = 2
	shell.border_width_right = 2
	shell.border_width_bottom = 2
	shell.border_color = Color("E4DCCE")
	card.add_theme_stylebox_override("panel", shell)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = str(lobby.name)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiStyle.apply_font(title, true, 16, UiStyle.INK)
	var sub := Label.new()
	sub.text = "%s  ·  CODE %s" % [str(lobby.get("host", "Host")), lobby.code]
	UiStyle.apply_font(sub, true, 12, UiStyle.TEAL)
	info.add_child(title)
	info.add_child(sub)
	row.add_child(info)

	var count := Label.new()
	count.text = "%d / %d" % [int(lobby.players), int(lobby.max_players)]
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.apply_font(count, true, 15, UiStyle.BROWN)
	row.add_child(count)

	var join := Button.new()
	join.set_script(load("res://scripts/fancy_button.gd"))
	join.text = "JOIN"
	join.custom_minimum_size = Vector2(96, 40)
	join.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(join, true, 14, Color.WHITE)
	join.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 14, 8))
	join.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 14, 8))
	join.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 14, 8))
	var code := str(lobby.code)
	join.pressed.connect(func() -> void: _try_join(code))
	row.add_child(join)
	return card


func _on_back_pressed() -> void:
	if room_view.visible:
		GameSession.leave_lobby()
		_show_list()
		return
	GameSession.open_title()


func _on_create_pressed() -> void:
	name_edit.text = "%s's Lobby" % GameSession.player_name
	_public_visibility = true
	_sync_visibility_buttons()
	_show_overlay(create_dimmer)


func _on_join_code_pressed() -> void:
	join_edit.text = ""
	join_error.text = ""
	_show_overlay(join_dimmer)
	join_edit.grab_focus()


func _make_rounds_picker() -> void:
	var layout: VBoxContainer = $UI/Root/CreateDimmer/Card/Layout
	var vis: Control = $UI/Root/CreateDimmer/Card/Layout/Visibility
	var card: PanelContainer = $UI/Root/CreateDimmer/Card
	card.offset_top = -310.0
	card.offset_bottom = 310.0
	var caption := Label.new()
	caption.text = "ROUNDS"
	UiStyle.apply_font(caption, true, 13, UiStyle.INK)
	layout.add_child(caption)
	layout.move_child(caption, vis.get_index() + 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	layout.add_child(row)
	layout.move_child(row, caption.get_index() + 1)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(48, 44)
	minus.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(minus, true, 20, Color.WHITE)
	minus.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 10, 8))
	minus.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 10, 8))
	minus.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 10, 8))
	minus.add_theme_stylebox_override("hover_pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 10, 8))
	minus.add_theme_stylebox_override("focus", UiStyle.pill(UiStyle.TEAL, 10, 8))
	minus.add_theme_color_override("font_pressed_color", Color.WHITE)
	minus.pressed.connect(func() -> void: _set_rounds(_rounds - 1))
	row.add_child(minus)
	_rounds_label = Label.new()
	_rounds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(_rounds_label, true, 16, UiStyle.TEAL)
	row.add_child(_rounds_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(48, 44)
	plus.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(plus, true, 20, Color.WHITE)
	plus.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 10, 8))
	plus.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 10, 8))
	plus.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 10, 8))
	plus.add_theme_stylebox_override("hover_pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 10, 8))
	plus.add_theme_stylebox_override("focus", UiStyle.pill(UiStyle.TEAL, 10, 8))
	plus.add_theme_color_override("font_pressed_color", Color.WHITE)
	plus.pressed.connect(func() -> void: _set_rounds(_rounds + 1))
	row.add_child(plus)
	_set_rounds(_rounds)


func _set_rounds(value: int) -> void:
	_rounds = clampi(value, 1, 9)
	if _rounds_label:
		_rounds_label.text = "%d round%s" % [_rounds, "" if _rounds == 1 else "s"]


func _mode_label(mode: String) -> String:
	return "Free for All" if mode == "free_for_all" else "Turn by Turn"


func _make_mode_picker() -> void:
	var layout: VBoxContainer = $UI/Root/CreateDimmer/Card/Layout
	var caption := Label.new()
	caption.text = "MODE"
	UiStyle.apply_font(caption, true, 13, UiStyle.INK)
	layout.add_child(caption)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	layout.add_child(row)
	_turn_btn = Button.new()
	_turn_btn.text = "Turn by Turn"
	_turn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_btn.custom_minimum_size = Vector2(0, 44)
	_turn_btn.focus_mode = Control.FOCUS_NONE
	_turn_btn.pressed.connect(func() -> void: _set_create_mode("turn_by_turn"))
	row.add_child(_turn_btn)
	_ffa_btn = Button.new()
	_ffa_btn.text = "Free for All"
	_ffa_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ffa_btn.custom_minimum_size = Vector2(0, 44)
	_ffa_btn.focus_mode = Control.FOCUS_NONE
	_ffa_btn.pressed.connect(func() -> void: _set_create_mode("free_for_all"))
	row.add_child(_ffa_btn)
	var confirm: Control = $UI/Root/CreateDimmer/Card/Layout/Confirm
	layout.move_child(caption, confirm.get_index())
	layout.move_child(row, confirm.get_index())
	_set_create_mode(_create_mode)


func _set_create_mode(mode: String) -> void:
	_create_mode = mode
	if _turn_btn:
		_style_choice(_turn_btn, mode == "turn_by_turn")
	if _ffa_btn:
		_style_choice(_ffa_btn, mode == "free_for_all")


func _make_room_mode_controls() -> void:
	var layout: VBoxContainer = $UI/Root/Content/RoomView/Card/Layout
	_room_mode_label = Label.new()
	_room_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(_room_mode_label, true, 14, UiStyle.TEAL)
	layout.add_child(_room_mode_label)
	var row := HBoxContainer.new()
	row.name = "ModeRow"
	row.add_theme_constant_override("separation", 10)
	layout.add_child(row)
	_room_turn_btn = Button.new()
	_room_turn_btn.text = "Turn by Turn"
	_room_turn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_turn_btn.custom_minimum_size = Vector2(0, 40)
	_room_turn_btn.focus_mode = Control.FOCUS_NONE
	_room_turn_btn.pressed.connect(func() -> void: GameSession.set_game_mode("turn_by_turn"))
	row.add_child(_room_turn_btn)
	_room_ffa_btn = Button.new()
	_room_ffa_btn.text = "Free for All"
	_room_ffa_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_ffa_btn.custom_minimum_size = Vector2(0, 40)
	_room_ffa_btn.focus_mode = Control.FOCUS_NONE
	_room_ffa_btn.pressed.connect(func() -> void: GameSession.set_game_mode("free_for_all"))
	row.add_child(_room_ffa_btn)
	layout.move_child(_room_mode_label, start_btn.get_index())
	layout.move_child(row, start_btn.get_index())


func _refresh_room_mode_ui() -> void:
	var mode := str(GameSession.active_lobby.get("gameMode", GameSession.game_mode))
	if _room_mode_label:
		_room_mode_label.text = "Mode: %s" % _mode_label(mode)
	if _room_turn_btn:
		_room_turn_btn.get_parent().visible = GameSession.hosting
		_style_choice(_room_turn_btn, mode == "turn_by_turn")
		_room_turn_btn.disabled = mode == "turn_by_turn"
	if _room_ffa_btn:
		_style_choice(_room_ffa_btn, mode == "free_for_all")
		_room_ffa_btn.disabled = mode == "free_for_all"


func _on_confirm_create() -> void:
	var lobby_name := name_edit.text.strip_edges()
	if lobby_name.is_empty():
		lobby_name = "Putt Party"
	_waiting_for_room = true
	GameSession.create_lobby(lobby_name, _public_visibility, _rounds, _create_mode)


func _on_confirm_join(_text: String = "") -> void:
	_try_join(join_edit.text)


func _on_join_code_typed(value: String) -> void:
	var caret := join_edit.caret_column
	var cleaned := value.to_upper()
	if cleaned != value:
		join_edit.text = cleaned
		join_edit.caret_column = caret
	join_error.text = ""


func _try_join(code: String) -> void:
	var err := GameSession.join_lobby(code)
	if err.is_empty():
		_waiting_for_room = true
		join_error.text = "Joining..."
	else:
		join_error.text = err
		if not join_dimmer.visible:
			_show_overlay(join_dimmer)
			join_edit.text = code.to_upper()


func _on_create_back_pressed() -> void:
	_hide_overlay(create_dimmer)


func _on_join_back_pressed() -> void:
	_hide_overlay(join_dimmer)


func _on_start_pressed() -> void:
	if not GameSession.hosting:
		return
	GameSession.begin_course_vote()


func _on_leave_pressed() -> void:
	GameSession.leave_lobby()
	_show_list()


func _on_public_pressed() -> void:
	_public_visibility = true
	_sync_visibility_buttons()


func _on_private_pressed() -> void:
	_public_visibility = false
	_sync_visibility_buttons()


func _sync_visibility_buttons() -> void:
	_style_choice(public_btn, _public_visibility)
	_style_choice(private_btn, not _public_visibility)


func _style_choice(btn: Button, on: bool) -> void:
	var color := UiStyle.TEAL if on else Color("E7E0D4")
	var font := Color.WHITE if on else UiStyle.BROWN
	btn.add_theme_stylebox_override("normal", UiStyle.pill(color, 18, 10))
	btn.add_theme_stylebox_override("hover", UiStyle.pill(color.lightened(0.08), 18, 10))
	btn.add_theme_stylebox_override("pressed", UiStyle.pill(color.darkened(0.08), 18, 10))
	btn.add_theme_stylebox_override("hover_pressed", UiStyle.pill(color.darkened(0.08), 18, 10))
	btn.add_theme_stylebox_override("focus", UiStyle.pill(color, 18, 10))
	btn.add_theme_color_override("font_color", font)
	btn.add_theme_color_override("font_hover_color", font)
	btn.add_theme_color_override("font_pressed_color", font)
	btn.add_theme_color_override("font_hover_pressed_color", font)


func _show_overlay(dimmer: ColorRect) -> void:
	dimmer.visible = true
	dimmer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(dimmer, "modulate:a", 1.0, 0.2)


func _hide_overlay(dimmer: ColorRect) -> void:
	if not dimmer.visible:
		return
	var tw := create_tween()
	tw.tween_property(dimmer, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void: dimmer.visible = false)


func _dimmer_close(event: InputEvent, dimmer: ColorRect) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_hide_overlay(dimmer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if create_dimmer.visible:
			_hide_overlay(create_dimmer)
		elif join_dimmer.visible:
			_hide_overlay(join_dimmer)
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
