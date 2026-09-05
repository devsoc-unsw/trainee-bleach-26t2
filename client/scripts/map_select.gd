extends Node3D

const BALL_SCENE := preload("res://scenes/Ball.tscn")
const COLS := 3

@onready var world: Node3D = $World
@onready var camera: Camera3D = $Camera3D
@onready var grid: GridContainer = %Grid
@onready var back_btn: Button = %Back
@onready var title_label: Label = $UI/Root/Margin/Layout/Header/Title
@onready var spacer: Control = $UI/Root/Margin/Layout/Header/Spacer

var _index := -1
var _tiles: Array[CourseTile] = []
var _cam_base: Transform3D
var _t := 0.0
var _clock: Label
var _quick: Button


func _ready() -> void:
	_build_backdrop()
	_cam_base = MapKit.frame_menu_camera(camera)
	_build_tiles()
	_build_vote_chrome()
	back_btn.pressed.connect(_go_back)
	GameSession.vote_updated.connect(_refresh_votes)
	_refresh_votes()
	_tick_countdown()


func _process(delta: float) -> void:
	_t += delta
	camera.global_position = _cam_base.origin + MapKit.menu_camera_orbit(_t)
	camera.look_at(MapKit.MENU_CAM_LOOK, Vector3.UP)
	_tick_countdown()
	_sync_phone_selection()


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


func _build_vote_chrome() -> void:
	if not _voting():
		return
	back_btn.visible = false
	title_label.text = "PICK A COURSE"
	_clock = Label.new()
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.custom_minimum_size = Vector2(88, 44)
	UiStyle.apply_font(_clock, true, 22, Color.WHITE)
	_clock.add_theme_color_override("font_outline_color", Color(0.18, 0.28, 0.22, 0.85))
	_clock.add_theme_constant_override("outline_size", 8)
	spacer.add_child(_clock)

	if GameSession.hosting:
		_quick = Button.new()
		_quick.set_script(load("res://scripts/fancy_button.gd"))
		_quick.text = "QUICK START"
		_quick.custom_minimum_size = Vector2(168, 44)
		_quick.focus_mode = Control.FOCUS_NONE
		UiStyle.apply_font(_quick, true, 14, Color.WHITE)
		_quick.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.TEAL, 16, 10))
		_quick.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.TEAL_HOVER, 16, 10))
		_quick.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.TEAL_PRESS, 16, 10))
		_quick.add_theme_color_override("font_hover_color", Color.WHITE)
		_quick.add_theme_color_override("font_pressed_color", Color.WHITE)
		_quick.pressed.connect(GameSession.quick_start_match)
		var header: HBoxContainer = back_btn.get_parent()
		header.add_child(_quick)
		spacer.custom_minimum_size = Vector2(88, 0)
	else:
		spacer.custom_minimum_size = Vector2(168, 0)


func _voting() -> bool:
	return GameSession.online and not GameSession.active_lobby.is_empty()


func _tick_countdown() -> void:
	if _clock == null:
		return
	var left := int(ceili(GameSession.vote_seconds_left()))
	_clock.text = "0:%02d" % left


func _build_tiles() -> void:
	for child in grid.get_children():
		child.queue_free()
	_tiles.clear()
	grid.columns = COLS
	for id in GameSession.ORDER:
		var tile := CourseTile.new()
		grid.add_child(tile)
		tile.setup_map(GameSession.get_map(id))
		var captured := _tiles.size()
		tile.hovered.connect(func() -> void:
			if PhoneLink.pointer_live():
				return
			_select(captured)
		)
		tile.unhovered.connect(func() -> void:
			if PhoneLink.pointer_live():
				return
			if _index == captured:
				_select(-1)
		)
		tile.chosen.connect(func() -> void:
			_select(captured)
			_play_selected()
		)
		_tiles.append(tile)


func _refresh_votes() -> void:
	for tile in _tiles:
		var n := 0
		if _voting() and GameSession.vote_counts.has(tile.map_id):
			n = int(GameSession.vote_counts[tile.map_id])
		tile.set_vote_count(n)
		tile.set_voted(_voting() and tile.map_id == GameSession.my_vote and not GameSession.my_vote.is_empty())
	_tick_countdown()


func _sync_phone_selection() -> void:
	if not PhoneLink.pointer_live():
		return
	var idx := _index_of_hovered()
	if idx != _index:
		_select(idx)


func _index_of_hovered() -> int:
	var hit := PhoneLink.hovered_control()
	if hit == null:
		return -1
	var node: Node = hit
	while node != null:
		for i in _tiles.size():
			if _tiles[i] == node:
				return i
		node = node.get_parent()
	return -1


func _select(index: int) -> void:
	if _tiles.is_empty() or index < 0:
		_index = -1
		for tile in _tiles:
			tile.set_selected(false)
		return
	_index = clampi(index, 0, _tiles.size() - 1)
	for i in _tiles.size():
		_tiles[i].set_selected(i == _index)


func _play_selected() -> void:
	if _index < 0 or _index >= _tiles.size():
		return
	var tile := _tiles[_index]
	if tile.locked or tile.map_id.is_empty():
		return
	GameSession.play_map(tile.map_id)


func _go_back() -> void:
	if _voting():
		return
	if GameSession.online and not GameSession.active_lobby.is_empty():
		GameSession.return_to_lobby()
		return
	GameSession.open_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_play_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_select(_tiles.size() - 1 if _index < 0 else _index - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select(0 if _index < 0 else _index + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_select(0 if _index < 0 else _index + COLS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_select(_tiles.size() - 1 if _index < 0 else _index - COLS)
		get_viewport().set_input_as_handled()
