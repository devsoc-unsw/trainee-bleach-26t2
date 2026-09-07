extends Button

const GOLD_SHADER: Shader = preload("res://shaders/ui_gold_check.gdshader")

signal hovered
signal unhovered

var selected := false

var _mat: ShaderMaterial
var _view: SubViewport
var _label: Label
var _amount := 0.0
var _t := 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	flat = true
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_entered.connect(func() -> void: hovered.emit())
	mouse_exited.connect(func() -> void: unhovered.emit())
	_setup_preview()
	_apply_chrome()
	set_process(true)


func set_selected(on: bool) -> void:
	selected = on
	_apply_chrome()


func _setup_preview() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = GOLD_SHADER
	var preview_box := SubViewportContainer.new()
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.stretch = true
	preview_box.material = _mat
	preview_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview_box)
	_view = SubViewport.new()
	_view.transparent_bg = true
	_view.handle_input_locally = false
	_view.disable_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_box.add_child(_view)
	_label = Label.new()
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.add_child(_label)
	add_theme_color_override("font_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_hover_pressed_color", Color(0, 0, 0, 0))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	add_theme_constant_override("outline_size", 0)


func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if selected else 0.0
	_amount = lerpf(_amount, target, 1.0 - exp(-delta * 14.0))
	if _mat != null:
		_mat.set_shader_parameter("selected", _amount)
		_mat.set_shader_parameter("time", _t)
	if _label != null and _label.text != text:
		_label.text = text
	pivot_offset = Vector2(0.0, size.y * 0.5)
	var sc := lerpf(1.0, 1.06, _amount)
	scale = Vector2.ONE * sc


func _apply_chrome() -> void:
	var idle := StyleBoxEmpty.new()
	idle.content_margin_left = 10
	idle.content_margin_right = 16
	idle.content_margin_top = 8
	idle.content_margin_bottom = 10
	add_theme_stylebox_override("normal", idle)
	add_theme_stylebox_override("hover", idle)
	add_theme_stylebox_override("pressed", idle)
	add_theme_stylebox_override("focus", idle)
	if _label == null:
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	if font != null:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.28, 0.14, 0.05, 0.92))
	_label.add_theme_constant_override("outline_size", 12)
	_label.offset_left = 10
	_label.offset_right = -8
