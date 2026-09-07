class_name SpeedPad
extends Area3D

signal crossed(pad: SpeedPad, body: Node)

var boost_dir := Vector3.FORWARD
var strength := 11.0
var _ready_at := 0


func setup(pos: Vector3, dir: Vector3, length: float = 2.6, width: float = 1.45, power: float = 11.0) -> void:
	boost_dir = dir
	boost_dir.y = 0.0
	if boost_dir.length_squared() < 0.0001:
		boost_dir = Vector3.FORWARD
	boost_dir = boost_dir.normalized()
	strength = power
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	_build(length, width)
	global_position = pos
	var yaw := atan2(boost_dir.x, boost_dir.z)
	rotation.y = yaw
	body_entered.connect(_on_body)


func can_boost() -> bool:
	return Time.get_ticks_msec() >= _ready_at


func mark_used() -> void:
	_ready_at = Time.get_ticks_msec() + 520


func _build(length: float, width: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.55, length)
	shape.shape = box
	shape.position.y = 0.2
	add_child(shape)
	var slab := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.06, length)
	slab.mesh = mesh
	slab.position.y = 0.03
	slab.material_override = MapKit.toon(Color("F2B84B"), Color("C48422"))
	add_child(slab)
	var chevron_z := -length * 0.28
	for i in 3:
		_add_chevron(Vector3(0, 0.07, chevron_z + float(i) * 0.42), width * 0.42)


func _add_chevron(pos: Vector3, span: float) -> void:
	for side in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(span * 0.42, 0.05, 0.12)
		bar.mesh = mesh
		bar.position = pos + Vector3(side * span * 0.18, 0, 0)
		bar.rotation.y = side * 0.7
		bar.material_override = MapKit.toon(Color("FFF3C2"), Color("E0A030"))
		add_child(bar)


func _on_body(body: Node) -> void:
	if body is PuttBall:
		crossed.emit(self, body)
