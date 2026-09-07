class_name CourseTile
extends VBoxContainer

signal hovered
signal unhovered
signal chosen

var map_id := ""
var locked := false
var selected := false
var voted := false

var _frame: PanelContainer
var _name_panel: PanelContainer
var _name_label: Label
var _voters: HBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_entered.connect(func() -> void: hovered.emit())
	mouse_exited.connect(func() -> void: unhovered.emit())
	gui_input.connect(_on_gui)


func setup_map(spec: Dictionary) -> void:
	map_id = str(spec.id)
	locked = false
	_build_chrome(str(spec.title).to_upper())
	_paint_preview(spec)
	_apply()


func setup_locked(caption: String) -> void:
	locked = true
	map_id = ""
	_build_chrome(caption)
	var fill := ColorRect.new()
	fill.color = Color(0.16, 0.32, 0.3, 1)
	fill.custom_minimum_size = Vector2(160, 92)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(fill)
	var soon := Label.new()
	soon.text = "?"
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	soon.set_anchors_preset(Control.PRESET_FULL_RECT)
	soon.anchor_right = 1
	soon.anchor_bottom = 1
	soon.add_theme_font_override("font", UiStyle.FONT_EXTRA)
	soon.add_theme_font_size_override("font_size", 42)
	soon.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	soon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(soon)
	_apply()


func set_selected(on: bool) -> void:
	selected = on and not locked
	_apply()


func set_voted(on: bool) -> void:
	voted = on and not locked
	_apply()


func set_voters(people: Array) -> void:
	if _voters == null:
		return
	for child in _voters.get_children():
		child.queue_free()
	_voters.visible = not people.is_empty()
	for person in people:
		if not person is Dictionary:
			continue
		_voters.add_child(_voter_chip(int(person.get("slot", 1)), UiStyle.to_color(person.get("color", UiStyle.TEAL))))


func _build_chrome(caption: String) -> void:
	_frame = PanelContainer.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.custom_minimum_size = Vector2(0, 168)
	add_child(_frame)

	_name_panel = PanelContainer.new()
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_name_panel)

	_name_label = Label.new()
	_name_label.text = caption
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", UiStyle.FONT_EXTRA)
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_outline_color", Color(0.12, 0.22, 0.2, 0.8))
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_panel.add_child(_name_label)


func _paint_preview(spec: Dictionary) -> void:
	_frame.clip_contents = true
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	_frame.add_child(host)

	var path := str(spec.get("preview", ""))
	var tex := _load_preview(path)
	if tex != null:
		var photo := TextureRect.new()
		photo.texture = tex
		photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(photo)
	else:
		var art := Control.new()
		art.set_script(preload("res://scripts/course_preview.gd"))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(art)
		art.call("setup", str(spec.id))
	_make_badge(host)


func _make_badge(host: Control) -> void:
	_voters = HBoxContainer.new()
	_voters.visible = false
	_voters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voters.alignment = BoxContainer.ALIGNMENT_END
	_voters.add_theme_constant_override("separation", 4)
	_voters.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_voters.anchor_left = 1.0
	_voters.anchor_right = 1.0
	_voters.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_voters.offset_left = -132.0
	_voters.offset_top = 8.0
	_voters.offset_right = -8.0
	_voters.offset_bottom = 36.0
	host.add_child(_voters)


func _voter_chip(slot: int, tint: Color) -> Control:
	var chip := Control.new()
	chip.set_script(preload("res://scripts/voter_chip.gd"))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(28, 28)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.set("slot", maxi(slot, 1))
	chip.set("tint", tint)
	return chip


func _load_preview(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var existing := ResourceLoader.load(path) as Texture2D
	if existing != null:
		return existing
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _apply() -> void:
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.08, 0.16, 0.15, 1)
	var lit := selected or voted
	border.set_border_width_all(3 if lit else 2)
	if selected:
		border.border_color = Color("F6F1E6")
	elif voted:
		border.border_color = UiStyle.TEAL
	else:
		border.border_color = Color(0.86, 0.9, 0.88, 0.85)
	border.set_corner_radius_all(2)
	_frame.add_theme_stylebox_override("panel", border)

	var name_box := StyleBoxFlat.new()
	if lit:
		name_box.bg_color = Color(1.0, 0.9, 0.28, 0.58)
		name_box.set_corner_radius_all(5)
		name_box.content_margin_left = 12
		name_box.content_margin_right = 12
		name_box.content_margin_top = 4
		name_box.content_margin_bottom = 4
		name_box.expand_margin_top = -2
		name_box.expand_margin_bottom = -1
	else:
		name_box.bg_color = Color(0, 0, 0, 0)
		name_box.content_margin_left = 8
		name_box.content_margin_right = 8
		name_box.content_margin_top = 4
		name_box.content_margin_bottom = 4
	_name_panel.add_theme_stylebox_override("panel", name_box)
	var name_color := UiStyle.INK if lit and not locked else Color(1, 1, 1, 0.45 if locked else 1.0)
	_name_label.add_theme_color_override("font_color", name_color)


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			hovered.emit()
			chosen.emit()
