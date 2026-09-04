extends Node3D

signal ball_sunk
signal sunk_finished

@export var max_sink_speed: float = 6.5

@onready var sink_area: Area3D = $SinkArea
@onready var drop_point: Marker3D = $DropPoint
@onready var win_menu: CanvasLayer = $WinMenu

var _sunk: bool = false


func _ready() -> void:
	_build_funnel()
	_build_confetti()
	sink_area.body_entered.connect(_on_body_entered)


func _build_funnel() -> void:
	var cream := MapKit.toon(Color(0.93, 0.9, 0.82), Color(0.72, 0.62, 0.5))
	var well := StandardMaterial3D.new()
	well.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	well.albedo_color = Color(0.1, 0.08, 0.07)
	var lip := MeshInstance3D.new()
	lip.name = "Lip"
	lip.mesh = MapKit.cup_lip_mesh()
	lip.material_override = cream
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lip)
	var walls := MeshInstance3D.new()
	walls.name = "Liner"
	walls.mesh = MapKit.cup_wall_mesh()
	walls.material_override = cream
	walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(walls)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "LinerFloor"
	floor_mesh.mesh = MapKit.cup_floor_mesh()
	floor_mesh.material_override = well
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)
	var body := StaticBody3D.new()
	body.name = "CupBody"
	body.physics_material_override = MapKit.putting_physics()
	var wall_col := CollisionShape3D.new()
	wall_col.shape = MapKit.cup_wall_mesh().create_trimesh_shape()
	body.add_child(wall_col)
	var floor_col := CollisionShape3D.new()
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = MapKit.CUP_INNER
	floor_shape.height = 0.04
	floor_col.shape = floor_shape
	floor_col.position.y = -0.4
	body.add_child(floor_col)
	add_child(body)


func show_results(hole: int, par: int, strokes: int, time_text: String) -> void:
	if win_menu and win_menu.has_method("present"):
		win_menu.present(hole, par, strokes, time_text)


func _on_body_entered(body: Node3D) -> void:
	if _sunk:
		return
	if not body is RigidBody3D:
		return
	if not body.has_method("sink"):
		return
	if body.linear_velocity.length() > max_sink_speed:
		return

	_sunk = true
	body.sink()
	ball_sunk.emit()
	_drop_ball(body)


func _build_confetti() -> void:
	_make_confetti_emitter(
		"Confetti",
		Vector3(0.09, 0.05, 0.012),
		72,
		Vector3(0.0, -0.04, 0.0),
		6.2,
		10.5,
		48.0
	)
	_make_confetti_emitter(
		"ConfettiBits",
		Vector3(0.045, 0.045, 0.01),
		88,
		Vector3(0.0, -0.02, 0.0),
		4.4,
		8.6,
		62.0
	)


func _make_confetti_emitter(
	node_name: String,
	piece_size: Vector3,
	amount: int,
	pos: Vector3,
	speed_min: float,
	speed_max: float,
	spread: float
) -> void:
	var bits := GPUParticles3D.new()
	bits.name = node_name
	bits.position = pos
	bits.amount = amount
	bits.lifetime = 2.4
	bits.one_shot = true
	bits.explosiveness = 0.96
	bits.randomness = 0.45
	bits.local_coords = false
	bits.emitting = false
	bits.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 14, 20))
	bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var piece := BoxMesh.new()
	piece.size = piece_size
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.vertex_color_use_as_albedo = true
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	piece.material = paper
	bits.draw_pass_1 = piece
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.07
	proc.direction = Vector3(0, 1, 0)
	proc.spread = spread
	proc.initial_velocity_min = speed_min
	proc.initial_velocity_max = speed_max
	proc.gravity = Vector3(0, -13.5, 0)
	proc.radial_accel_min = 1.8
	proc.radial_accel_max = 4.2
	proc.damping_min = 1.1
	proc.damping_max = 2.8
	proc.angular_velocity_min = -28.0
	proc.angular_velocity_max = 28.0
	proc.angle_min = -180.0
	proc.angle_max = 180.0
	proc.scale_min = 0.7
	proc.scale_max = 1.45
	proc.scale_curve = _confetti_scale_curve()
	proc.color_initial_ramp = _confetti_colors()
	proc.color_ramp = _confetti_fade()
	bits.process_material = proc
	add_child(bits)


func _confetti_colors() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 1.0])
	grad.colors = PackedColorArray([
		Color("FF4D4D"),
		Color("FF8A2B"),
		Color("FFE14A"),
		Color("5BD46A"),
		Color("3FD0C6"),
		Color("4F8CFF"),
		Color("B45CFF"),
		Color("FF6BA8"),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 128
	return tex


func _confetti_fade() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


func _confetti_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.95))
	curve.add_point(Vector2(1.0, 0.35))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


func _burst_confetti() -> void:
	for node_name in ["Confetti", "ConfettiBits"]:
		var bits := get_node_or_null(node_name) as GPUParticles3D
		if bits == null:
			continue
		bits.restart()
		bits.emitting = true


func _drop_ball(ball: Node3D) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(ball, "global_position", drop_point.global_position, 0.58)
	tween.tween_callback(_burst_confetti)
	tween.tween_interval(0.45)
	tween.tween_callback(func() -> void: sunk_finished.emit())
