extends Node3D
class_name GhostBall

var player_id: String = ""
var display_name: String = ""
var target_pos: Vector3 = Vector3.ZERO
var holed: bool = false
var _snapped: bool = false

func setup(id: String, p_name: String, colour: Color) -> void:
	player_id = id
	display_name = p_name

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var faded := colour
	faded.a = 0.7
	mat.albedo_color = faded
	mesh.material_override = mat
	add_child(mesh)

	var label := Label3D.new()
	label.text = p_name
	label.position = Vector3(0, 0.28, 0)
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = colour
	add_child(label)

func apply_state(pos: Vector3, is_holed: bool) -> void:
	target_pos = pos
	holed = is_holed
	if not _snapped:
		global_position = pos
		_snapped = true

func _process(delta: float) -> void:
	if not _snapped:
		return
	global_position = global_position.lerp(target_pos, clampf(12.0 * delta, 0.0, 1.0))
