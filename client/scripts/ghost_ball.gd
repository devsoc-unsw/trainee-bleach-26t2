extends RigidBody3D

const BALL_HIT_LAYER := 4

var player_id := ""
var display_name := ""
var target := Vector3.ZERO
var color := Color.WHITE
var solid := false
var knock := Vector3.ZERO
var _hold_net := 0
var _shield := false
var _shrink := false


func setup(id: String, tint: Color, pos: Vector3, player_name: String = "") -> void:
	player_id = id
	display_name = player_name
	color = tint
	target = pos
	global_position = pos
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	sleeping = true
	set_solid(false)
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
	_write_transform()


func set_solid(on: bool) -> void:
	solid = on
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		shape.disabled = not on
	collision_layer = BALL_HIT_LAYER if on else 0
	collision_mask = BALL_HIT_LAYER if on else 0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func place_at(pos: Vector3) -> void:
	target = pos
	global_position = pos
	knock = Vector3.ZERO
	_write_transform()


func set_powers(shield: bool, shrink: bool) -> void:
	_shield = shield
	_shrink = shrink
	PuttBall.apply_visual_size(self, PuttBall.SHRINK_SCALE if shrink else 1.0)
	_tint()
	var tag := get_node_or_null("NameTag") as Label3D
	if tag:
		tag.position.y = 0.32 * (PuttBall.SHRINK_SCALE if shrink else 1.0)


func has_shield() -> bool:
	return _shield


func has_shrink() -> bool:
	return _shrink


func apply_knock(velocity: Vector3) -> void:
	if _shield:
		return
	knock = velocity
	target = global_position
	_hold_net = Time.get_ticks_msec() + 320


func take_network_pos(pos: Vector3) -> void:
	if Time.get_ticks_msec() < _hold_net:
		return
	target = pos


func _tint() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.material_override == null:
		return
	var mat := mesh.material_override.duplicate() as ShaderMaterial
	if mat == null:
		return
	var tint: Color = PuttBall.SHIELD_GREY if _shield else color
	mat.set_shader_parameter("color_lit", tint.lerp(Color.WHITE, 0.12))
	mat.set_shader_parameter("color_shade", tint.darkened(0.28))
	mat.set_shader_parameter("dimple_color", tint.darkened(0.14))
	mat.set_shader_parameter("stripe_color", tint)
	mat.set_shader_parameter("stripe_width", 0.0)
	mesh.material_override = mat


func _process(delta: float) -> void:
	if knock.length_squared() > 0.01:
		target += knock * delta
		knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-delta * 5.0))
	global_position = global_position.lerp(target, 1.0 - exp(-delta * 16.0))
	_write_transform()


func _write_transform() -> void:
	if not solid:
		return
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
