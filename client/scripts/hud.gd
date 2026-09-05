extends CanvasLayer

signal camera_pressed
signal look_pressed
signal settings_pressed
signal ability_pressed
signal power_used(kind: String)
signal quit_pressed
signal courses_pressed
signal phone_link_pressed
signal aim_mode_changed(phone: bool)
signal chat_submitted(text: String)
signal spectate_follow_pressed
signal spectate_free_pressed
signal spectate_prev_pressed
signal spectate_next_pressed
signal scorecard_toggled(expanded: bool)
signal results_skip_pressed
signal results_hold_finished

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
var _chat_header: PanelContainer
var _chat_body: Control
var _chat_chevron: Button
var _chat_expanded := true
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
var _phone_dimmer: ColorRect
var _phone_code: Label
var _phone_urls: Label
var _phone_local: Label
var _phone_qr: TextureRect
var _phone_status: Label
var _phone_qr_data := ""
var _aim_mouse_btns: Array[Button] = []
var _aim_phone_btns: Array[Button] = []
var _results_dimmer: ColorRect
var _results_content: Control
var _results_title: Label
var _results_sub: Label
var _results_rows: VBoxContainer
var _results_tween: Tween
var _results_hold_label: Label
var _results_skip: Button
var _results_ends_at := 0.0
var _results_hold_open := false
var _kickoff_dimmer: ColorRect
var _kickoff_label: Label
var _kickoff_tween: Tween
var _phone_opened_ms := 0
var _shield_slot: PowerSlot
var _shrink_slot: PowerSlot


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
	_build_phone_panel()
	_build_spectate_bar()
	_build_power_hud()
	_refresh_stats()
	_apply_scorecard_state()
	_apply_chat_state()
	if not scorecard_header.gui_input.is_connected(_on_scorecard_header_input):
		scorecard_header.gui_input.connect(_on_scorecard_header_input)
		scorecard_header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var score_header_row: Control = scorecard_header.get_node_or_null("HeaderRow")
	if score_header_row:
		score_header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score_title: Control = scorecard_header.get_node_or_null("HeaderRow/Title")
	if score_title:
		score_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_view_buttons()
	set_chat_visible(GameSession.online)


func _process(delta: float) -> void:
	if timer_running:
		elapsed += delta
		_refresh_timer()
	_refresh_results_hold()


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


func show_kickoff(text: String) -> void:
	_ensure_kickoff()
	_kickoff_label.text = text
	_kickoff_label.reset_size()
	_kickoff_label.pivot_offset = _kickoff_label.get_minimum_size() * 0.5
	_kickoff_dimmer.visible = true
	_kickoff_label.scale = Vector2(0.72, 0.72)
	_kickoff_label.modulate.a = 0.0
	if _kickoff_tween:
		_kickoff_tween.kill()
	_kickoff_tween = create_tween()
	_kickoff_tween.set_parallel(true)
	_kickoff_tween.tween_property(_kickoff_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_kickoff_tween.tween_property(_kickoff_label, "modulate:a", 1.0, 0.12)


func set_powerups(left_kind: String = "", left_left: float = 0.0, right_kind: String = "", right_left: float = 0.0) -> void:
	_ensure_power_hud()
	if _shield_slot:
		_shield_slot.set_slot(left_kind, left_left)
	if _shrink_slot:
		_shrink_slot.set_slot(right_kind, right_left)


func _build_power_hud() -> void:
	_ensure_power_hud()


func _ensure_power_hud() -> void:
	if _shield_slot:
		return
	_shield_slot = _bind_power_slot($Root/Abilities/Slot1)
	_shrink_slot = _bind_power_slot($Root/Abilities/Slot2)
	var leftover := $Root/Abilities.get_node_or_null("AbilityButton")
	if leftover:
		leftover.visible = false
		leftover.queue_free()
	var bar: Control = $Root/Abilities
	bar.offset_left = -146.0


func _bind_power_slot(host: Control) -> PowerSlot:
	host.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	var slot := PowerSlot.new()
	slot.kind = ""
	slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.pressed.connect(func() -> void:
		if slot.kind != "":
			power_used.emit(slot.kind)
	)
	host.add_child(slot)
	return slot


func hide_kickoff() -> void:
	if _kickoff_dimmer:
		_kickoff_dimmer.visible = false
	if _kickoff_tween:
		_kickoff_tween.kill()
		_kickoff_tween = null


func _ensure_kickoff() -> void:
	if _kickoff_dimmer:
		return
	_kickoff_dimmer = ColorRect.new()
	_kickoff_dimmer.color = Color(0.08, 0.07, 0.06, 0.22)
	_kickoff_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kickoff_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kickoff_dimmer.visible = false
	$Root.add_child(_kickoff_dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kickoff_dimmer.add_child(center)
	_kickoff_label = Label.new()
	_kickoff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kickoff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kickoff_label.pivot_offset = Vector2(160, 48)
	UiStyle.apply_font(_kickoff_label, true, 88, Color("F6C84C"))
	_kickoff_label.add_theme_color_override("font_outline_color", Color(0.28, 0.16, 0.05, 0.9))
	_kickoff_label.add_theme_constant_override("outline_size", 16)
	center.add_child(_kickoff_label)


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
	if not is_inside_tree():
		return
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
			"color": UiStyle.to_color(p.get("color", "#E23B3B")),
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
		var tint := UiStyle.to_color(payload.get("color", "#3A322C"), UiStyle.INK)
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
	# Phone poses come from an autoload, so this can run while a course swap is
	# tearing the 3D world down. The viewport or camera may already be gone.
	if not is_inside_tree():
		return Vector2.UP
	var viewport := get_viewport()
	if viewport == null or not is_instance_valid(viewport):
		return Vector2.UP
	if not viewport.has_method("get_camera_3d"):
		return Vector2.UP
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null or not is_instance_valid(cam):
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
	swatch.color = UiStyle.to_color(color)
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

	var body := scorecard_body
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	col.add_child(_make_roster_header())
	col.add_child(_players_box)
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
	_chat_header = header
	header.add_theme_stylebox_override("panel", _style_header_open)
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.gui_input.connect(_on_chat_header_input)
	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_theme_constant_override("separation", 8)
	header.add_child(header_row)
	var title := Label.new()
	title.text = "CHAT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_font(title, true, 18, Color("F6F1E6"))
	header_row.add_child(title)
	_chat_chevron = Button.new()
	_chat_chevron.custom_minimum_size = Vector2(34, 34)
	_chat_chevron.pivot_offset = Vector2(17, 17)
	_chat_chevron.focus_mode = Control.FOCUS_NONE
	_chat_chevron.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chat_chevron.icon = chevron_button.icon
	_chat_chevron.expand_icon = true
	_chat_chevron.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copy_chevron_look(_chat_chevron)
	_chat_chevron.pressed.connect(_toggle_chat)
	header_row.add_child(_chat_chevron)
	layout.add_child(header)

	var body := MarginContainer.new()
	_chat_body = body
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
	_apply_chat_state()
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
	UiStyle.apply_ghost_button(_courses_btn)
	_courses_btn.visible = not GameSession.online
	_courses_btn.pressed.connect(func() -> void:
		_set_pause_open(false)
		courses_pressed.emit()
	)
	col.add_child(_courses_btn)

	_add_aim_mode_row(col, true)

	var phone := Button.new()
	phone.text = "LINK PHONE"
	phone.custom_minimum_size = Vector2(0, 46)
	phone.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(phone, true, 16, Color.WHITE)
	phone.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 18, 12))
	phone.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 18, 12))
	phone.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 18, 12))
	phone.pressed.connect(func() -> void:
		phone_link_pressed.emit()
		_set_pause_open(false)
	)
	col.add_child(phone)

	var resume := Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(0, 46)
	resume.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(resume, true, 16, UiStyle.BROWN)
	UiStyle.apply_ghost_button(resume)
	resume.pressed.connect(func() -> void: _set_pause_open(false))
	col.add_child(resume)


func _set_pause_open(on: bool) -> void:
	_pause_dimmer.visible = on
	if _courses_btn:
		_courses_btn.visible = not GameSession.online
	if on:
		_refresh_aim_mode_buttons()


func show_phone_panel(on: bool) -> void:
	if _phone_dimmer:
		_phone_dimmer.visible = on
	if on:
		_phone_opened_ms = Time.get_ticks_msec()


func set_phone_waiting() -> void:
	if _phone_code:
		_phone_code.text = ""
		_phone_code.visible = false
	if _phone_urls:
		_phone_urls.text = ""
		_phone_urls.visible = false
	if _phone_local:
		_phone_local.text = ""
		_phone_local.visible = false
	if _phone_qr:
		_phone_qr.visible = false
		_phone_qr.texture = null
	if _phone_status:
		_phone_status.text = "Starting phone remote..."


func set_phone_urls(urls: PackedStringArray, local_url: String = "") -> void:
	if _phone_urls:
		_phone_urls.text = "\n".join(urls)
		_phone_urls.visible = not urls.is_empty()
	if _phone_local:
		_phone_local.text = "This PC: %s" % local_url if not local_url.is_empty() else ""
		_phone_local.visible = not local_url.is_empty()


func set_phone_status(text: String) -> void:
	if _phone_status:
		_phone_status.text = text


func set_phone_qr_png(bytes: PackedByteArray) -> void:
	if _phone_qr == null or bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	_phone_qr.texture = ImageTexture.create_from_image(img)
	_phone_qr.visible = true


func set_phone_info(code: String, linked: bool, qr: String = "") -> void:
	if _phone_code:
		_phone_code.text = code if not code.is_empty() else "...."
		_phone_code.visible = not code.is_empty()
	if not qr.is_empty():
		_phone_qr_data = qr
		_apply_phone_qr(qr)
	if _phone_status:
		_phone_status.text = "Phone linked. Hold to aim, then swing. Menus: swing to select." if linked else "Scan to link your phone."


func _apply_phone_qr(data_url: String) -> void:
	if _phone_qr == null:
		return
	var marker := "base64,"
	var at := data_url.find(marker)
	if at < 0:
		return
	var bytes := Marshalls.base64_to_raw(data_url.substr(at + marker.length()))
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	_phone_qr.texture = ImageTexture.create_from_image(img)
	_phone_qr.visible = true


func _build_phone_panel() -> void:
	_phone_dimmer = ColorRect.new()
	_phone_dimmer.visible = false
	_phone_dimmer.color = Color(0.08, 0.1, 0.09, 0.55)
	_phone_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_phone_dimmer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
				if Time.get_ticks_msec() - _phone_opened_ms < 280:
					return
				show_phone_panel(false)
	)
	$Root.add_child(_phone_dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phone_dimmer.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.card(24))
	card.custom_minimum_size = Vector2(360, 0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var title := Label.new()
	title.text = "PHONE REMOTE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(title, true, 20, UiStyle.INK)
	col.add_child(title)
	_add_aim_mode_row(col, false)
	_phone_qr = TextureRect.new()
	_phone_qr.custom_minimum_size = Vector2(220, 220)
	_phone_qr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_phone_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_phone_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_phone_qr.visible = false
	col.add_child(_phone_qr)
	_phone_code = Label.new()
	_phone_code.text = ""
	_phone_code.visible = false
	_phone_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(_phone_code, true, 28, UiStyle.TEAL)
	col.add_child(_phone_code)
	_phone_urls = Label.new()
	_phone_urls.visible = false
	_phone_urls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_urls.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiStyle.apply_font(_phone_urls, false, 13, UiStyle.TEAL)
	col.add_child(_phone_urls)
	_phone_local = Label.new()
	_phone_local.visible = false
	_phone_local.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_local.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiStyle.apply_font(_phone_local, false, 13, UiStyle.BROWN_SOFT)
	col.add_child(_phone_local)
	_phone_status = Label.new()
	_phone_status.text = "Scan the code on the same Wi-Fi. No app or setup needed."
	_phone_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phone_status.custom_minimum_size = Vector2(280, 0)
	UiStyle.apply_font(_phone_status, false, 14, UiStyle.INK)
	col.add_child(_phone_status)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 44)
	close.focus_mode = Control.FOCUS_NONE
	UiStyle.apply_font(close, true, 15, UiStyle.BROWN)
	UiStyle.apply_ghost_button(close)
	close.pressed.connect(func() -> void: show_phone_panel(false))
	col.add_child(close)
	_refresh_aim_mode_buttons()


func _add_aim_mode_row(parent: Control, open_phone_on_pick: bool) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var label := Label.new()
	label.text = "AIM"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_font(label, true, 13, UiStyle.BROWN)
	column.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var mouse := _aim_mode_button("MOUSE")
	var phone := _aim_mode_button("PHONE")
	mouse.pressed.connect(func() -> void: _set_aim_mode(false, false))
	phone.pressed.connect(func() -> void: _set_aim_mode(true, open_phone_on_pick))
	_aim_mouse_btns.append(mouse)
	_aim_phone_btns.append(phone)
	row.add_child(mouse)
	row.add_child(phone)


func _aim_mode_button(caption: String) -> Button:
	var btn := Button.new()
	btn.text = caption
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 40)
	UiStyle.apply_font(btn, true, 14, Color.WHITE)
	btn.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 12, 8))
	btn.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 12, 8))
	btn.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 12, 8))
	return btn


func _set_aim_mode(phone: bool, open_panel: bool) -> void:
	GameSession.prefer_mouse = not phone
	var live := false
	var link := get_node_or_null("/root/PhoneLink")
	if link != null and link.has_method("is_linked"):
		live = bool(link.call("is_linked"))
	GameSession.aim_with_phone = phone and live
	_refresh_aim_mode_buttons()
	aim_mode_changed.emit(GameSession.aim_with_phone)
	if phone and open_panel:
		phone_link_pressed.emit()
		_set_pause_open(false)


func _refresh_aim_mode_buttons() -> void:
	var phone := GameSession.aim_with_phone
	for btn in _aim_mouse_btns:
		btn.modulate = Color.WHITE if not phone else Color(1, 1, 1, 0.55)
	for btn in _aim_phone_btns:
		btn.modulate = Color.WHITE if phone else Color(1, 1, 1, 0.55)


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


func _on_chat_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_toggle_chat()


func _on_scorecard_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_on_chevron_pressed()


func _copy_chevron_look(btn: Button) -> void:
	for name in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
		var box := chevron_button.get_theme_stylebox(name)
		if box:
			btn.add_theme_stylebox_override(name, box)


func _toggle_chat() -> void:
	_chat_expanded = not _chat_expanded
	_apply_chat_state()


func _apply_chat_state() -> void:
	if _chat_body:
		_chat_body.visible = _chat_expanded
	if _chat_card:
		_chat_card.custom_minimum_size = Vector2(0, 168 if _chat_expanded else 0)
		if _chat_expanded:
			_chat_card.add_theme_stylebox_override("panel", _style_card_open)
		else:
			_chat_card.add_theme_stylebox_override("panel", _style_card_closed)
	if _chat_header:
		if _chat_expanded:
			_chat_header.add_theme_stylebox_override("panel", _style_header_open)
		else:
			_chat_header.add_theme_stylebox_override("panel", _style_header_closed)
	if _chat_chevron:
		_chat_chevron.pivot_offset = Vector2(17, 17)
		_chat_chevron.rotation_degrees = 0.0 if _chat_expanded else 180.0
	if not _chat_expanded and _chat_input and _chat_input.has_focus():
		_chat_input.release_focus()


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


func is_showing_results() -> bool:
	return _results_dimmer != null and _results_dimmer.visible


func can_skip_results() -> bool:
	return _results_hold_open and _results_skip != null and _results_skip.visible


func show_round_results(hole_index: int, last_hole: bool, results: Array, hole_par: int) -> void:
	var ranked := _sorted_result_dicts(results, "strokes", "time")
	await _present_results("Results", "Hole %d" % (hole_index + 1), _result_rows_from(
		ranked, "strokes", "time"
	), false)


func show_standings_results(results: Array) -> void:
	var ranked := _sorted_result_dicts(results, "total", "totalTime")
	await _present_results("Scores", "Standings", _result_rows_from(
		ranked, "total", "totalTime"
	), true)


func show_match_results(placings: Array) -> void:
	var ranked := _sorted_result_dicts(placings, "total", "time")
	await _present_results("Final", "Scores", _result_rows_from(
		ranked, "total", "time"
	), true)


func _result_rows_from(ranked: Array, score_field: String, time_field: String) -> Array:
	var rows: Array = []
	var place := 1
	var prev_score := -1
	var prev_time := -1.0
	for i in ranked.size():
		var r: Dictionary = ranked[i]
		var score := int(r.get(score_field, r.get("putts", 0)))
		var clock := _row_time(r, time_field)
		if i > 0 and (score != prev_score or not is_equal_approx(clock, prev_time)):
			place = i + 1
		prev_score = score
		prev_time = clock
		rows.append(_result_row_data(
			place,
			String(r.get("name", "Player")),
			String(r.get("playerId", r.get("id", ""))),
			UiStyle.to_color(r.get("color", "#E23B3B")),
			score,
			clock,
			true
		))
	return rows


func begin_results_hold(ends_at_ms: float = 0.0, can_skip: bool = false) -> void:
	_ensure_results_overlay()
	if ends_at_ms <= 0.0:
		ends_at_ms = Time.get_unix_time_from_system() * 1000.0 + 10000.0
	_results_ends_at = ends_at_ms
	_results_hold_open = true
	if _results_skip:
		_results_skip.visible = can_skip
	_refresh_results_hold()


func clear_results_hold() -> void:
	_results_hold_open = false
	_results_ends_at = 0.0
	if _results_skip:
		_results_skip.visible = false


func finish_results_hold() -> void:
	if not _results_hold_open:
		return
	_results_hold_open = false
	results_hold_finished.emit()


func fade_out_results(restore_chrome: bool = true) -> void:
	if _results_dimmer == null or not _results_dimmer.visible:
		if restore_chrome:
			_set_play_chrome(true)
		return
	if _results_tween and is_instance_valid(_results_tween):
		_results_tween.kill()
	_results_tween = create_tween()
	_results_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_results_tween.tween_property(_results_dimmer, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await _results_tween.finished
	if not is_inside_tree():
		return
	_results_dimmer.visible = false
	clear_results_hold()
	if restore_chrome:
		_set_play_chrome(true)


func _sorted_result_dicts(results: Array, field: String, time_field: String = "") -> Array:
	var rows: Array = []
	for item in results:
		if item is Dictionary:
			rows.append(item)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get(field, 0))
		var right := int(b.get(field, 0))
		var left_t := _row_time(a, time_field)
		var right_t := _row_time(b, time_field)
		if GameSession.is_free_for_all():
			if not is_equal_approx(left_t, right_t):
				return left_t < right_t
			if left != right:
				return left < right
		else:
			if left != right:
				return left < right
			if not is_equal_approx(left_t, right_t):
				return left_t < right_t
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return rows


func _row_time(row: Dictionary, time_field: String) -> float:
	if time_field.is_empty():
		return 0.0
	if row.has(time_field):
		return float(row.get(time_field, 0))
	if time_field == "totalTime" and row.has("time"):
		return float(row.get("time", 0))
	return float(row.get("time", 0))


func _present_results(title: String, subtitle: String, rows: Array, crossfade: bool) -> void:
	_ensure_results_overlay()
	_set_play_chrome(false)
	show_spectate(false)
	$Root.move_child(_results_dimmer, -1)
	var already_up := _results_dimmer.visible and _results_dimmer.modulate.a > 0.05
	if crossfade and already_up:
		await _tween_modulate(_results_rows, 0.0, 0.22)
		if not is_inside_tree():
			return
	var cards := _fill_result_board(title, subtitle, rows)
	_results_content.modulate.a = 1.0
	_results_rows.modulate.a = 1.0
	_results_dimmer.visible = true
	_results_dimmer.modulate.a = 1.0
	$Root.move_child(_results_dimmer, -1)
	await _reveal_result_rows(cards)


func _tween_modulate(node: CanvasItem, alpha: float, seconds: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _results_tween and is_instance_valid(_results_tween):
		_results_tween.kill()
	if seconds <= 0.02:
		node.modulate.a = alpha
		return
	_results_tween = create_tween()
	_results_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_results_tween.tween_property(node, "modulate:a", alpha, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _results_tween.finished
	if is_instance_valid(node):
		node.modulate.a = alpha


func _fill_result_board(title: String, subtitle: String, rows: Array) -> Array:
	_results_title.text = title
	UiStyle.apply_font(_results_title, true, 56, Color(1, 1, 1, 0.96))
	_results_sub.text = subtitle
	UiStyle.apply_font(_results_sub, true, 18, Color(1, 1, 1, 0.55))
	_results_sub.visible = not subtitle.is_empty()
	for child in _results_rows.get_children():
		_results_rows.remove_child(child)
		child.queue_free()
	var cards: Array = []
	for i in rows.size():
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 10)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i > 0:
			group.add_child(_make_result_divider())
		var row: Dictionary = rows[i]
		group.add_child(_make_result_line(row))
		group.modulate.a = 0.0
		_results_rows.add_child(group)
		cards.append(group)
	return cards


func _reveal_result_rows(cards: Array) -> void:
	for i in range(cards.size() - 1, -1, -1):
		var node := cards[i] as CanvasItem
		if node == null or not is_instance_valid(node):
			continue
		if _results_tween and is_instance_valid(_results_tween):
			_results_tween.kill()
		node.modulate.a = 0.0
		_results_tween = create_tween()
		_results_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_results_tween.tween_property(node, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await _results_tween.finished
		if is_instance_valid(node):
			node.modulate.a = 1.0
		if is_inside_tree():
			await get_tree().create_timer(0.12).timeout


func _result_row_data(
	place: int,
	player_name: String,
	player_id: String,
	colour: Color,
	putts: int,
	time_sec: float,
	show_time: bool = true
) -> Dictionary:
	return {
		"place": place,
		"name": player_name,
		"id": player_id,
		"color": colour,
		"putts": putts,
		"time": time_sec,
		"show_time": show_time,
	}


func _format_clock(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _refresh_results_hold() -> void:
	if not _results_hold_open:
		return
	var left := maxf(0.0, _results_ends_at / 1000.0 - Time.get_unix_time_from_system())
	if _results_hold_label:
		_results_hold_label.text = str(maxi(ceili(left), 0))
	if left <= 0.0:
		finish_results_hold()


func _ordinal(place: int) -> String:
	var tens := place % 100
	var ones := place % 10
	if tens >= 11 and tens <= 13:
		return "%dth" % place
	if ones == 1:
		return "%dst" % place
	if ones == 2:
		return "%dnd" % place
	if ones == 3:
		return "%drd" % place
	return "%dth" % place


func _set_play_chrome(on: bool) -> void:
	var top := $Root.get_node_or_null("TopBar") as Control
	if top:
		top.visible = on
	var abilities := $Root.get_node_or_null("Abilities") as Control
	if abilities:
		abilities.visible = on
	var dock := $Root.get_node_or_null("LeftDock") as Control
	if dock:
		dock.visible = on
	if not on:
		show_phone_panel(false)
		show_spectate(false)
		if _pause_dimmer:
			_pause_dimmer.visible = false
	elif _chat_card:
		_chat_card.visible = GameSession.online


func _ensure_results_overlay() -> void:
	if _results_dimmer:
		return
	_results_dimmer = ColorRect.new()
	_results_dimmer.color = Color(0.04, 0.05, 0.07, 0.84)
	_results_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_dimmer.visible = false
	$Root.add_child(_results_dimmer)
	_results_content = Control.new()
	_results_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_dimmer.add_child(_results_content)
	_results_title = Label.new()
	_results_title.text = "Results"
	_results_title.anchor_left = 0.0
	_results_title.anchor_top = 0.0
	_results_title.anchor_right = 0.0
	_results_title.anchor_bottom = 0.0
	_results_title.offset_left = 48.0
	_results_title.offset_top = 28.0
	_results_title.offset_right = 420.0
	_results_title.offset_bottom = 100.0
	UiStyle.apply_font(_results_title, true, 56, Color(1, 1, 1, 0.96))
	_results_content.add_child(_results_title)
	_results_sub = Label.new()
	_results_sub.anchor_left = 0.0
	_results_sub.anchor_top = 0.0
	_results_sub.anchor_right = 0.0
	_results_sub.anchor_bottom = 0.0
	_results_sub.offset_left = 52.0
	_results_sub.offset_top = 96.0
	_results_sub.offset_right = 420.0
	_results_sub.offset_bottom = 124.0
	UiStyle.apply_font(_results_sub, true, 18, Color(1, 1, 1, 0.55))
	_results_content.add_child(_results_sub)
	var board := MarginContainer.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_theme_constant_override("margin_left", 72)
	board.add_theme_constant_override("margin_right", 72)
	board.add_theme_constant_override("margin_top", 150)
	board.add_theme_constant_override("margin_bottom", 110)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_content.add_child(board)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(center)
	_results_rows = VBoxContainer.new()
	_results_rows.add_theme_constant_override("separation", 10)
	_results_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_rows.custom_minimum_size = Vector2(780, 0)
	center.add_child(_results_rows)
	var hold := HBoxContainer.new()
	hold.alignment = BoxContainer.ALIGNMENT_CENTER
	hold.add_theme_constant_override("separation", 18)
	hold.anchor_left = 0.0
	hold.anchor_right = 1.0
	hold.anchor_top = 1.0
	hold.anchor_bottom = 1.0
	hold.offset_left = 48.0
	hold.offset_right = -48.0
	hold.offset_top = -92.0
	hold.offset_bottom = -28.0
	hold.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_content.add_child(hold)
	_results_hold_label = Label.new()
	_results_hold_label.text = "10"
	_results_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_hold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.apply_font(_results_hold_label, true, 36, Color(1, 1, 1, 0.92))
	hold.add_child(_results_hold_label)
	_results_skip = Button.new()
	_results_skip.text = "SKIP · SWING"
	_results_skip.visible = false
	_results_skip.focus_mode = Control.FOCUS_NONE
	_results_skip.custom_minimum_size = Vector2(168, 48)
	UiStyle.apply_ghost_button(_results_skip)
	UiStyle.apply_font(_results_skip, true, 18, UiStyle.INK)
	_results_skip.pressed.connect(func() -> void: results_skip_pressed.emit())
	hold.add_child(_results_skip)


func _make_result_divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


func _make_result_line(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.08, 0.1, 0.78)
	panel.set_corner_radius_all(12)
	panel.border_width_left = 2
	panel.border_width_top = 2
	panel.border_width_right = 2
	panel.border_width_bottom = 2
	panel.border_color = Color(1, 1, 1, 0.32)
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var place_l := Label.new()
	place_l.text = _ordinal(int(row.get("place", 1)))
	place_l.custom_minimum_size = Vector2(92, 0)
	place_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.apply_font(place_l, true, 36, Color(1, 1, 1, 0.96))
	box.add_child(place_l)
	box.add_child(_make_colour_portrait(row.get("color", Color("E23B3B"))))
	var name_l := Label.new()
	name_l.text = String(row.get("name", "Player"))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.apply_font(name_l, true, 26, Color(1, 1, 1, 0.96))
	box.add_child(name_l)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	var putts := int(row.get("putts", 0))
	stats.add_child(_make_stat_value("%d %s" % [putts, "putt" if putts == 1 else "putts"]))
	if bool(row.get("show_time", true)):
		stats.add_child(_make_stat_value(_format_clock(float(row.get("time", 0)))))
	box.add_child(stats)
	return card


func _make_colour_portrait(colour: Variant) -> Panel:
	var tint: Color = colour if colour is Color else UiStyle.to_color(colour)
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(76, 76)
	var style := StyleBoxFlat.new()
	style.bg_color = tint.darkened(0.12)
	style.set_corner_radius_all(16)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(1, 1, 1, 0.92)
	frame.add_theme_stylebox_override("panel", style)
	var orb := Panel.new()
	orb.set_anchors_preset(Control.PRESET_CENTER)
	orb.offset_left = -20.0
	orb.offset_top = -20.0
	orb.offset_right = 20.0
	orb.offset_bottom = 20.0
	var orb_style := StyleBoxFlat.new()
	orb_style.bg_color = tint.lightened(0.08)
	orb_style.set_corner_radius_all(999)
	orb.add_theme_stylebox_override("panel", orb_style)
	frame.add_child(orb)
	return frame


func _make_stat_value(text: String) -> Label:
	var value := Label.new()
	value.text = text
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.apply_font(value, true, 28, Color(1, 1, 1, 0.96))
	return value
