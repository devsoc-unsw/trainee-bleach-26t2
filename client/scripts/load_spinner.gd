class_name LoadSpinner
extends ColorRect

const SPINNER_SHADER := preload("res://shaders/ui_spinner.gdshader")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = SPINNER_SHADER
	material = mat
