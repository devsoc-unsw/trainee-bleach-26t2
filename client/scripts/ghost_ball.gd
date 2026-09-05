extends RigidBody3D

var player_id := ""
var display_name := ""
var target := Vector3.ZERO
var color := Color.WHITE


func setup(id: String, tint: Color, pos: Vector3, player_name: String = "") -> void:
	player_id = id
	display_name = player_name
	color = tint
	target = pos
	global_position = pos
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	collision_layer = 0
	collision_mask = 0
	freeze = true
	gravity_scale = 0.0
	sleeping = true
	if has_node("Shadow"):
		$Shadow.visible = true
	_tint()
	if not player_name.is_empty() and get_node_or_null("NameTag") == null:
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = player_name
		tag.position = Vector3(0, 0.32, 0)
		tag.font_size = 28
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = tint
		add_child(tag)


func _tint() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.material_override == null:
		return
	var mat := mesh.material_override.duplicate() as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("color_lit", color.lerp(Color.WHITE, 0.12))
	mat.set_shader_parameter("color_shade", color.darkened(0.28))
	mat.set_shader_parameter("dimple_color", color.darkened(0.14))
	mat.set_shader_parameter("stripe_color", color)
	mat.set_shader_parameter("stripe_width", 0.0)
	mesh.material_override = mat


func _process(delta: float) -> void:
	global_position = global_position.lerp(target, 1.0 - exp(-delta * 16.0))
