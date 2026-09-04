extends Node3D

const BALL_SCENE := preload("res://scenes/Ball.tscn")
const ITEM_SCRIPT := preload("res://scripts/title_menu_item.gd")

@onready var ui: CanvasLayer = $UI
@onready var camera: Camera3D = $Camera3D
@onready var world: Node3D = $World
@onready var logo: Control = $UI/Root/Left/Logo
@onready var menu_panel: VBoxContainer = $UI/Root/Left/Menu
@onready var menu_list: VBoxContainer = $UI/Root/Left/Menu
@onready var player_name_label: Label = $UI/Root/PlayerBar/Row/Name
@onready var settings_dimmer: ColorRect = $UI/SettingsDimmer

var _index := 0
var _items: Array[Button] = []
var _actions: Array[Callable] = []
var _settings_open := false
var _cam_base: Transform3D
var _t := 0.0


func _ready() -> void:
	_build_course()
	_cam_base = MapKit.frame_menu_camera(camera)
	_build_menu()
	_setup_settings()
	player_name_label.text = GameSession.player_name
	get_viewport().size_changed.connect(_apply_responsive)
	_apply_responsive()
	_play_intro()
	_select(0)


func _process(delta: float) -> void:
	_t += delta
	camera.global_position = _cam_base.origin + MapKit.menu_camera_orbit(_t)
	camera.look_at(MapKit.MENU_CAM_LOOK, Vector3.UP)


func _build_course() -> void:
	var ground := MapKit.combiner(world, false)
	MapKit.box(ground, Vector3(160, 0.2, 160), Vector3(4, 0.1, -6), MapKit.grass())
	var wood := MapKit.toon(Color("6B4428"), Color("4A2E1A"))
	MapKit.box(world, Vector3(22, 0.45, 0.45), Vector3(2, 0.32, 4.2), wood, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(world, Vector3(0.45, 0.45, 28), Vector3(-8.6, 0.32, -6), wood, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(world, Vector3(0.45, 0.45, 28), Vector3(12.4, 0.32, -8), wood, CSGShape3D.OPERATION_UNION, false)

	for pos in [
		Vector3(10.5, 0.2, -2), Vector3(13.2, 0.2, -7), Vector3(11.8, 0.2, -12),
		Vector3(16.0, 0.2, -5), Vector3(14.4, 0.2, -16), Vector3(9.6, 0.2, -18),
		Vector3(-10.5, 0.2, -8), Vector3(-12.2, 0.2, -14), Vector3(18.0, 0.2, -11),
	]:
		MapKit.tree(world, pos, 3.4 + absf(pos.x) * 0.04)

	var rock := MapKit.toon(Color("5A5A5E"), Color("3A3A3E"))
	MapKit.box(world, Vector3(2.4, 1.4, 1.8), Vector3(-6.2, 0.7, 3.2), rock, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(world, Vector3(1.6, 0.9, 1.4), Vector3(-4.8, 0.45, 4.1), rock, CSGShape3D.OPERATION_UNION, false)

	var brick := MapKit.toon(MapKit.BRICK, MapKit.BRICK_SHADE)
	MapKit.box(world, Vector3(8.5, 5.5, 4.2), Vector3(2.5, 2.85, -22), brick, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(world, Vector3(5.5, 3.2, 0.25), Vector3(2.5, 2.6, -19.85), MapKit.toon(MapKit.GLASS), CSGShape3D.OPERATION_UNION, false)

	MapKit.cylinder(world, 0.03, 1.1, Vector3(3.35, 0.75, -1.15), MapKit.toon(MapKit.CREAM), 8, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(world, Vector3(0.42, 0.24, 0.04), Vector3(3.58, 1.12, -1.15), MapKit.toon(Color("E23B3B")), CSGShape3D.OPERATION_UNION, false)
	MapKit.menu_horizon(world)

	var ball: RigidBody3D = BALL_SCENE.instantiate()
	ball.freeze = true
	ball.gravity_scale = 0.0
	ball.sleeping = true
	ball.position = Vector3(2.55, 0.32, -0.55)
	if ball.has_node("Shadow"):
		ball.get_node("Shadow").visible = false
	world.add_child(ball)


func _build_menu() -> void:
	for child in menu_list.get_children():
		child.queue_free()
	_items.clear()
	_actions = [_on_solo, _on_multiplayer, _on_settings]
	menu_list.mouse_filter = Control.MOUSE_FILTER_STOP
	var labels := ["Solo Play", "Multiplayer", "Settings"]
	for i in labels.size():
		var btn := Button.new()
		btn.set_script(ITEM_SCRIPT)
		btn.text = labels[i]
		btn.custom_minimum_size = Vector2(0, 48)
		var font_var := FontVariation.new()
		font_var.base_font = UiStyle.FONT_EXTRA
		font_var.spacing_glyph = 1
		btn.add_theme_font_override("font", font_var)
		btn.add_theme_font_size_override("font_size", 28)
		var idx := i
		btn.hovered.connect(func() -> void: _select(idx))
		btn.pressed.connect(func() -> void: _activate(idx))
		menu_list.add_child(btn)
		_items.append(btn)


func _select(index: int) -> void:
	_index = clampi(index, 0, _items.size() - 1)
	for i in _items.size():
		if _items[i].has_method("set_selected"):
			_items[i].set_selected(i == _index)


func _activate(index: int) -> void:
	if index < 0 or index >= _actions.size():
		return
	_select(index)
	_actions[index].call()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_open:
		if event.is_action_pressed("ui_cancel"):
			_close_settings()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		_select(0 if _index < 0 else _index + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_select(_items.size() - 1 if _index < 0 else _index - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _index >= 0:
			_activate(_index)
		get_viewport().set_input_as_handled()


func _play_intro() -> void:
	logo.modulate.a = 0.0
	menu_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(logo, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(menu_panel, "modulate:a", 1.0, 0.4).set_delay(0.12)


func _apply_responsive() -> void:
	var size := get_viewport().get_visible_rect().size
	var wide := size.x >= 900.0
	var pad := 28.0 if wide else 16.0
	var col_w := 312.0 if wide else minf(size.x - pad * 2.0, 360.0)
	$UI/Root/Left.offset_left = pad
	$UI/Root/Left.offset_top = 22 if wide else 14
	$UI/Root/Left.offset_right = pad + col_w
	$UI/Root/Left/Logo/Unsw.add_theme_font_size_override("font_size", 22 if wide else 16)
	$UI/Root/Left/Logo/Title.add_theme_font_size_override("font_size", 42 if wide else 28)


func _setup_settings() -> void:
	settings_dimmer.visible = false
	settings_dimmer.modulate.a = 0.0
	settings_dimmer.gui_input.connect(_on_dimmer_gui)
	$UI/SettingsDimmer/Card/Layout/Back.pressed.connect(_close_settings)
	var name_edit: LineEdit = $UI/SettingsDimmer/Card/Layout/NameEdit
	name_edit.text = GameSession.player_name
	name_edit.text_changed.connect(func(v: String) -> void:
		GameSession.player_name = v.strip_edges()
		if GameSession.player_name.is_empty():
			GameSession.player_name = "Player"
		player_name_label.text = GameSession.player_name
	)
	var vol: HSlider = $UI/SettingsDimmer/Card/Layout/Volume
	vol.value = GameSession.master_volume
	_set_volume_label(vol.value)
	vol.value_changed.connect(func(v: float) -> void:
		GameSession.set_master_volume(v)
		_set_volume_label(v)
	)


func _set_volume_label(amount: float) -> void:
	var label: Label = $UI/SettingsDimmer/Card/Layout/VolumeRow/VolumeValue
	label.text = "%d%%" % int(round(amount * 100.0))


func _on_solo() -> void:
	GameSession.open_select()


func _on_multiplayer() -> void:
	GameSession.open_lobbies()


func _on_settings() -> void:
	_settings_open = true
	settings_dimmer.visible = true
	var tw := create_tween()
	tw.tween_property(settings_dimmer, "modulate:a", 1.0, 0.2)


func _close_settings() -> void:
	_settings_open = false
	var tw := create_tween()
	tw.tween_property(settings_dimmer, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func() -> void: settings_dimmer.visible = false)


func _on_dimmer_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_close_settings()
