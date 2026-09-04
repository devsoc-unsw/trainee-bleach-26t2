extends CanvasLayer

signal camera_pressed
signal look_pressed
signal settings_pressed
signal ability_pressed
signal quit_pressed
signal courses_pressed
signal chat_submitted(text: String)
signal spectate_follow_pressed
signal spectate_free_pressed
signal spectate_prev_pressed
signal spectate_next_pressed
signal show_players_changed(enabled: bool)
signal scorecard_toggled(expanded: bool)

@export var hole: int = 1
@export var par: int = 3
@export var strokes: int = 0
@export var timer_running: bool = true

var elapsed: float = 0.0
var scorecard_expanded: bool = true

@onready var hole_value: Label = $Root/TopBar/Stats/HoleGroup/Value
@onready var par_value: Label = $Root/TopBar/Stats/ParGroup/Value
@onready var stroke_value: Label = $Root/TopBar/Stats/StrokeGroup/Value
@onready var timer_value: Label = $Root/TopBar/Stats/TimerGroup/Value
@onready var scorecard: PanelContainer = $Root/Scorecard
@onready var scorecard_header: PanelContainer = $Root/Scorecard/Layout/Header
@onready var scorecard_body: Control = $Root/Scorecard/Layout/Body
@onready var chevron_button: Button = $Root/Scorecard/Layout/Header/HeaderRow/ChevronButton
@onready var players_toggle: Control = $Root/Scorecard/Layout/Body/BodyRow/PlayersToggle
@onready var show_players_row: Control = $Root/Scorecard/Layout/Body/BodyRow
@onready var ball_status: Control = $Root/TopBar/LeftButtons/BallStatus
@onready var camera_button: Button = $Root/TopBar/LeftButtons/CameraButton
@onready var look_button: Button = $Root/TopBar/LeftButtons/LookButton

var _style_card_open: StyleBox
var _style_card_closed: StyleBoxEmpty
var _style_header_open: StyleBox
var _style_header_closed: StyleBox
var _roster: Array[Dictionary] = []
var _players_box: VBoxContainer
var _chat_card: PanelContainer
var _chat_log: VBoxContainer
var _chat_scroll: ScrollContainer
var _chat_input: LineEdit
var _pause_dimmer: ColorRect
var _courses_btn: Button
var _spectate_bar: PanelContainer
var _spectate_name: Label
var _follow_btn: Button
var _free_btn: Button
var _cycle_row: HBoxContainer


func _ready() -> void:
	chevron_button.pivot_offset = chevron_button.size * 0.5
	_style_card_open = scorecard.get_theme_stylebox("panel").duplicate()
	_style_card_closed = StyleBoxEmpty.new()
	_style_header_open = scorecard_header.get_theme_stylebox("panel").duplicate()
	_style_header_closed = _style_header_open.duplicate()
	if _style_header_closed is StyleBoxFlat:
		var header_closed := _style_header_closed as StyleBoxFlat
		header_closed.corner_radius_bottom_left = header_closed.corner_radius_top_left
		header_closed.corner_radius_bottom_right = header_closed.corner_radius_top_right
		header_closed.shadow_color = Color(0.42, 0.33, 0.27, 0.18)
		header_closed.shadow_size = 10
		header_closed.shadow_offset = Vector2(0, 2)
	_build_left_dock()
	_build_pause_menu()
	_build_spectate_bar()
	_refresh_stats()
	_apply_scorecard_state()
	_setup_view_buttons()
	if players_toggle.has_signal("toggled"):
		players_toggle.toggled.connect(_on_show_players_toggled)
	if players_toggle.has_method("set_on"):
		players_toggle.call("set_on", GameSession.show_players)
	set_chat_visible(GameSession.online)
	show_players_row.visible = GameSession.online


func _process(delta: float) -> void:
	if not timer_running:
		return
	elapsed += delta
	_refresh_timer()


func set_hole(value: int) -> void:
	hole = value
	_refresh_stats()


func set_par(value: int) -> void:
	par = value
	_refresh_stats()
	_refresh_roster()


func set_strokes(value: int) -> void:
	strokes = maxi(value, 0)
	_refresh_stats()


func add_stroke() -> void:
	set_strokes(strokes + 1)


func set_elapsed(seconds: float) -> void:
	elapsed = maxf(seconds, 0.0)
	_refresh_timer()


func start_timer() -> void:
	timer_running = true


func stop_timer() -> void:
	timer_running = false


func reset_timer() -> void:
	elapsed = 0.0
	_refresh_timer()


func set_ball_state(state: int) -> void:
	if ball_status and ball_status.has_method("set_state"):
		ball_status.set_state(state)


func set_ball_preview(ball: Node3D) -> void:
	if ball_status and ball_status.has_method("set_ball"):
		ball_status.set_ball(ball)


func set_aim_preview(world_dir: Vector3, power: float) -> void:
	if ball_status == null or not ball_status.has_method("set_aim"):
		return
	ball_status.set_aim(_world_dir_to_hud(world_dir), power)


func set_chat_visible(on: bool) -> void:
	if _chat_card:
		_chat_card.visible = on


func set_roster(people: Array) -> void:
	_roster.clear()
	for p in people:
		if not p is Dictionary:
			continue
		var id := str(p.get("id", ""))
		if id.is_empty():
			continue
		_roster.append({
			"id": id,
			"name": str(p.get("name", "Player")),
			"color": Color(str(p.get("color", "#E23B3B"))),
			"strokes": int(p.get("strokes", 0)),
			"holed": bool(p.get("holed", false)),
		})
	_refresh_roster()


func set_player_score(player_id: String, value: int, holed: Variant = null) -> void:
	for row in _roster:
		if str(row.get("id", "")) != player_id:
			continue
		row["strokes"] = value
		if holed != null:
			row["holed"] = bool(holed)
		_refresh_roster()
		return


func append_chat(payload: Dictionary) -> void:
	if _chat_log == null:
		return
	var kind := str(payload.get("kind", "say"))
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind == "system":
		line.text = str(payload.get("text", ""))
		UiStyle.apply_font(line, false, 13, UiStyle.BROWN_SOFT)
	else:
		line.text = "%s: %s" % [str(payload.get("name", "Player")), str(payload.get("text", ""))]
		var tint := Color(str(payload.get("color", "#3A322C")))
		UiStyle.apply_font(line, false, 13, tint.darkened(0.12))
	_chat_log.add_child(line)
	while _chat_log.get_child_count() > 40:
		_chat_log.get_child(0).queue_free()
	call_deferred("_scroll_chat")


func _scroll_chat() -> void:
	if _chat_scroll == null:
		return
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _world_dir_to_hud(world_dir: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.UP
	var right := cam.global_transform.basis.x
	var fwd := -cam.global_transform.basis.z
	right.y = 0.0
	fwd.y = 0.0
	if right.length_squared() < 0.0001 or fwd.length_squared() < 0.0001:
		return Vector2.UP
	right = right.normalized()
	fwd = fwd.normalized()
	var flat := Vector3(world_dir.x, 0.0, world_dir.z)
	if flat.length_squared() < 0.0001:
		return Vector2.UP
	flat = flat.normalized()
	var hud_dir := Vector2(flat.dot(right), -flat.dot(fwd))
	if hud_dir.length_squared() < 0.0001:
		return Vector2.UP
	return hud_dir.normalized()


func _refresh_stats() -> void:
	if not is_node_ready():
		return
	hole_value.text = str(hole)
	par_value.text = str(par)
	stroke_value.text = str(strokes)
	_refresh_timer()


func _refresh_timer() -> void:
	if timer_value == null:
		return
	var total := int(elapsed)
	var minutes := int(total / 60.0)
	var seconds := total % 60
	timer_value.text = "%d:%02d" % [minutes, seconds]


func _refresh_roster() -> void:
	if _players_box == null:
		return
	for child in _players_box.get_children():
		child.queue_free()
	if _roster.is_empty():
		_add_roster_row(GameSession.player_name, GameSession.my_color, strokes, false, true)
		return
	for row in _roster:
		var id := str(row.get("id", ""))
		var mine := id == NetworkClient.player_id or id == "local"
		_add_roster_row(
			str(row.get("name", "Player")),
			row.get("color", UiStyle.TEAL),
			int(row.get("strokes", 0)),
			bool(row.get("holed", false)),
			mine
		)


func _add_roster_row(player_name: String, color: Variant, player_strokes: int, holed: bool, mine: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.color = color if color is Color else Color(str(color))
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := Label.new()
	var caption := player_name if not mine else "%s (you)" % player_name
	if holed:
		caption = "%s  in" % caption
	name_label.text = caption
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiStyle.apply_font(name_label, true, 14, UiStyle.INK)
	var stroke_label := Label.new()
	stroke_label.text = str(player_strokes)
	stroke_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stroke_label.custom_minimum_size = Vector2(28, 0)
	UiStyle.apply_font(stroke_label, true, 15, UiStyle.TEAL)
	var par_label := Label.new()
	par_label.text = _to_par_text(player_strokes, holed)
	par_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	par_label.custom_minimum_size = Vector2(36, 0)
	UiStyle.apply_font(par_label, true, 14, Color("C45A3A") if par_label.text.begins_with("+") else UiStyle.TEAL)
	if par_label.text == "E" or par_label.text == "-":
		par_label.add_theme_color_override("font_color", UiStyle.BROWN)
	row.add_child(swatch)
	row.add_child(name_label)
	row.add_child(stroke_label)
	row.add_child(par_label)
	_players_box.add_child(row)


func _to_par_text(player_strokes: int, _holed: bool) -> String:
	if player_strokes <= 0:
		return "-"
	var diff := player_strokes - par
	if diff == 0:
		return "E"
	if diff > 0:
		return "+%d" % diff
	return str(diff)


func _make_roster_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = "PLAYER"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.apply_font(name_label, true, 11, UiStyle.BROWN_SOFT)
	var stroke_label := Label.new()
	stroke_label.text = "STK"
	stroke_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stroke_label.custom_minimum_size = Vector2(28, 0)
	UiStyle.apply_font(stroke_label, true, 11, UiStyle.BROWN_SOFT)
	var par_label := Label.new()
	par_label.text = "PAR"
	par_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	par_label.custom_minimum_size = Vector2(36, 0)
	UiStyle.apply_font(par_label, true, 11, UiStyle.BROWN_SOFT)
	row.add_child(Control.new())
	row.get_child(0).custom_minimum_size = Vector2(10, 0)
	row.add_child(name_label)
	row.add_child(stroke_label)
	row.add_child(par_label)
	return row


func _build_left_dock() -> void:
	var dock := VBoxContainer.new()
	dock.name = "LeftDock"
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = 24.0
	dock.offset_top = -520.0
	dock.offset_right = 344.0
	dock.offset_bottom = -24.0
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.add_theme_constant_override("separation", 10)
	dock.alignment = BoxContainer.ALIGNMENT_END
	var root: Control = $Root
	root.add_child(dock)
	root.move_child(dock, scorecard.get_index())
	_chat_card = _make_chat_card()
	dock.add_child(_chat_card)
	var score_parent := scorecard.get_parent()
	score_parent.remove_child(scorecard)
	dock.add_child(scorecard)
	scorecard.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scorecard.anchor_right = 0.0
	scorecard.anchor_bottom = 0.0
	scorecard.offset_left = 0.0
	scorecard.offset_top = 0.0
	scorecard.offset_right = 0.0
	scorecard.offset_bottom = 0.0
	scorecard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scorecard.custom_minimum_size = Vector2(300, 0)

	var body_row := show_players_row
	var body := scorecard_body
	body.remove_child(body_row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	col.add_child(_make_roster_header())
	col.add_child(_players_box)
	col.add_child(body_row)
	body.add_child(col)


func _make_chat_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Chat"
	card.custom_minimum_size = Vector2(0, 168)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style_card_open)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	card.add_child(layout)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _style_header_open)
	var title := Label.new()
	title.text = "CHAT"
	UiStyle.apply_font(title, true, 18, Color("F6F1E6"))
	header.add_child(title)
	layout.add_child(header)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 12)
	body.add_theme_constant_override("margin_top", 8)
	body.add_theme_constant_override("margin_right", 12)
	body.add_theme_constant_override("margin_bottom", 10)
	layout.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	body.add_child(col)

	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.custom_minimum_size = Vector2(0, 88)
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_chat_scroll)
	_chat_log = VBoxContainer.new()
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_constant_override("separation", 4)
	_chat_scroll.add_child(_chat_log)

	var composer := HBoxContainer.new()
	composer.add_theme_constant_override("separation", 8)
	col.add_child(composer)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Say something..."
	_chat_input.max_length = 120
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.add_theme_stylebox_override("normal", UiStyle.input_box())
	UiStyle.apply_font(_chat_input, false, 14, UiStyle.INK)
	_chat_input.text_submitted.connect(_on_chat_submit)
	composer.add_child(_chat_input)
	var send := Button.new()
	send.text = "SEND"
	send.focus_mode = Control.FOCUS_NONE
	send.custom_minimum_size = Vector2(72, 36)
	UiStyle.apply_font(send, true, 13, Color.WHITE)
	send.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 12, 8))
	send.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 12, 8))
	send.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 12, 8))
	send.pressed.connect(func() -> void: _on_chat_submit(_chat_input.text))
	composer.add_child(send)
	return card


func _build_pause_menu() -> void:
	_pause_dimmer = ColorRect.new()
	_pause_dimmer.visible = false
	_pause_dimmer.color = Color(0.08, 0.1, 0.09, 0.55)
	_pause_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_dimmer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
				_set_pause_open(false)
	)
	$Root.add_child(_pause_dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_dimmer.add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.card(24))
	card.custom_minimum_size = Vector2(280, 0)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
	)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(title, true, 22, UiStyle.INK)
	col.add_child(title)

	var quit := Button.new()
	quit.text = "QUIT GAME"
	quit.custom_minimum_size = Vector2(0, 46)
	quit.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(quit, true, 16, Color.WHITE)
	quit.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 18, 12))
	quit.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 18, 12))
	quit.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 18, 12))
	quit.pressed.connect(func() -> void:
		_set_pause_open(false)
		quit_pressed.emit()
	)
	col.add_child(quit)

	_courses_btn = Button.new()
	_courses_btn.text = "COURSES"
	_courses_btn.custom_minimum_size = Vector2(0, 46)
	_courses_btn.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(_courses_btn, true, 16, UiStyle.BROWN)
	_courses_btn.add_theme_stylebox_override("normal", UiStyle.ghost_pill())
	_courses_btn.add_theme_stylebox_override("hover", UiStyle.ghost_pill())
	_courses_btn.add_theme_stylebox_override("pressed", UiStyle.ghost_pill())
	_courses_btn.visible = not GameSession.online
	_courses_btn.pressed.connect(func() -> void:
		_set_pause_open(false)
		courses_pressed.emit()
	)
	col.add_child(_courses_btn)

	var resume := Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(0, 46)
	resume.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(resume, true, 16, UiStyle.BROWN)
	resume.add_theme_stylebox_override("normal", UiStyle.ghost_pill())
	resume.add_theme_stylebox_override("hover", UiStyle.ghost_pill())
	resume.add_theme_stylebox_override("pressed", UiStyle.ghost_pill())
	resume.pressed.connect(func() -> void: _set_pause_open(false))
	col.add_child(resume)


func _set_pause_open(on: bool) -> void:
	_pause_dimmer.visible = on
	if _courses_btn:
		_courses_btn.visible = not GameSession.online


func show_spectate(on: bool) -> void:
	if _spectate_bar:
		_spectate_bar.visible = on


func set_spectate_mode(follow: bool) -> void:
	if _follow_btn:
		_follow_btn.modulate = Color.WHITE if follow else Color(1, 1, 1, 0.55)
	if _free_btn:
		_free_btn.modulate = Color.WHITE if not follow else Color(1, 1, 1, 0.55)
	if _cycle_row:
		_cycle_row.visible = follow


func set_spectate_target_name(player_name: String) -> void:
	if _spectate_name:
		_spectate_name.text = player_name if not player_name.is_empty() else "FREE ROAM"


func _build_spectate_bar() -> void:
	_spectate_bar = PanelContainer.new()
	_spectate_bar.visible = false
	_spectate_bar.anchor_left = 0.5
	_spectate_bar.anchor_right = 0.5
	_spectate_bar.anchor_top = 1.0
	_spectate_bar.anchor_bottom = 1.0
	_spectate_bar.offset_left = -210.0
	_spectate_bar.offset_right = 210.0
	_spectate_bar.offset_top = -176.0
	_spectate_bar.offset_bottom = -80.0
	_spectate_bar.add_theme_stylebox_override("panel", UiStyle.card(18))
	$Root.add_child(_spectate_bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_spectate_bar.add_child(col)
	_spectate_name = Label.new()
	_spectate_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_name.text = "SPECTATING"
	UiStyle.apply_font(_spectate_name, true, 16, UiStyle.INK)
	col.add_child(_spectate_name)
	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 8)
	col.add_child(modes)
	_follow_btn = _spectate_mode_button("FOLLOW")
	_free_btn = _spectate_mode_button("FREE ROAM")
	_follow_btn.pressed.connect(func() -> void: spectate_follow_pressed.emit())
	_free_btn.pressed.connect(func() -> void: spectate_free_pressed.emit())
	modes.add_child(_follow_btn)
	modes.add_child(_free_btn)
	_cycle_row = HBoxContainer.new()
	_cycle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cycle_row.add_theme_constant_override("separation", 8)
	col.add_child(_cycle_row)
	var prev := _spectate_mode_button("<")
	var nxt := _spectate_mode_button(">")
	prev.custom_minimum_size = Vector2(44, 36)
	nxt.custom_minimum_size = Vector2(44, 36)
	prev.pressed.connect(func() -> void: spectate_prev_pressed.emit())
	nxt.pressed.connect(func() -> void: spectate_next_pressed.emit())
	_cycle_row.add_child(prev)
	_cycle_row.add_child(nxt)


func _spectate_mode_button(caption: String) -> Button:
	var btn := Button.new()
	btn.text = caption
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(110, 36)
	UiStyle.apply_font(btn, true, 13, Color.WHITE)
	btn.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 12, 8))
	btn.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 12, 8))
	btn.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 12, 8))
	return btn


func _on_chat_submit(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return
	_chat_input.text = ""
	chat_submitted.emit(cleaned)


func _setup_view_buttons() -> void:
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for button in [camera_button, look_button]:
		button.toggle_mode = true
		button.button_group = group
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	camera_button.pressed.connect(_on_camera_clicked)
	look_button.pressed.connect(_on_look_clicked)
	_select_follow_view(true)


func _select_follow_view(follow: bool) -> void:
	camera_button.set_pressed_no_signal(follow)
	look_button.set_pressed_no_signal(not follow)


func _on_camera_clicked() -> void:
	camera_pressed.emit()


func _on_look_clicked() -> void:
	look_pressed.emit()


func _on_settings_pressed() -> void:
	_set_pause_open(not _pause_dimmer.visible)
	settings_pressed.emit()


func _on_ability_pressed() -> void:
	ability_pressed.emit()


func _on_chevron_pressed() -> void:
	scorecard_expanded = not scorecard_expanded
	_apply_scorecard_state()
	scorecard_toggled.emit(scorecard_expanded)


func _apply_scorecard_state() -> void:
	scorecard_body.visible = scorecard_expanded
	chevron_button.rotation_degrees = 0.0 if scorecard_expanded else 180.0
	if scorecard_expanded:
		scorecard.add_theme_stylebox_override("panel", _style_card_open)
		scorecard_header.add_theme_stylebox_override("panel", _style_header_open)
	else:
		scorecard.add_theme_stylebox_override("panel", _style_card_closed)
		scorecard_header.add_theme_stylebox_override("panel", _style_header_closed)


func _on_show_players_toggled(enabled: bool) -> void:
	show_players_changed.emit(enabled)
