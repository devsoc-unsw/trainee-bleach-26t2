class_name CoursePickup
extends Area3D

signal collected(kind: String, pickup_id: String)

const BOB_H := 0.08
const SPIN := 1.6

var kind := "shield"
var pickup_id := ""
var live := true
var _orb: Node3D
var _base_y := 0.0
var _t := 0.0


func setup(id: String, pickup_kind: String, pos: Vector3) -> void:
	pickup_id = id
	kind = pickup_kind
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	_build()
	global_position = pos
	_base_y = pos.y
	body_entered.connect(_on_body)


func set_live(on: bool) -> void:
	live = on
	visible = on
	set_deferred("monitoring", on)


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.42
	shape.shape = sphere
	add_child(shape)
	_orb = Node3D.new()
	add_child(_orb)
	if kind == "shrink":
		_add_ball(_orb, 0.16, Color("F2D04B"), Color("C9A22A"))
		_add_ball(_orb, 0.09, Color("FFF4C2"), Color("E6C04A"), Vector3(0, 0.22, 0))
	elif kind == "gust":
		_add_ball(_orb, 0.15, Color("4CB8B0"), Color("2A8A84"))
		for i in 2:
			var swirl := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.16
			torus.outer_radius = 0.24
			torus.rings = 16
			torus.ring_segments = 12
			swirl.mesh = torus
			swirl.material_override = MapKit.toon(Color("7ED8D0"), Color("3A9A94"))
			swirl.rotation_degrees = Vector3(70.0 if i == 0 else -40.0, 20.0 * float(i), 0.0)
			swirl.scale = Vector3.ONE * (1.0 if i == 0 else 0.72)
			_orb.add_child(swirl)
	else:
		_add_ball(_orb, 0.2, Color("9A9690"), Color("6E6A66"))
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.2
		torus.outer_radius = 0.28
		torus.rings = 18
		torus.ring_segments = 12
		ring.mesh = torus
		ring.material_override = MapKit.toon(Color("C8C4BE"), Color("7A7672"))
		ring.rotation_degrees = Vector3(70, 0, 0)
		_orb.add_child(ring)
	var glow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.34
	disc.bottom_radius = 0.34
	disc.height = 0.03
	disc.radial_segments = 16
	glow.mesh = disc
	glow.position = Vector3(0, -0.22, 0)
	var glow_lit := Color("B8B4AE")
	var glow_shade := Color("7A7672")
	if kind == "shrink":
		glow_lit = Color("F2D04B")
		glow_shade = Color("C9A22A")
	elif kind == "gust":
		glow_lit = Color("7ED8D0")
		glow_shade = Color("3A9A94")
	glow.material_override = MapKit.toon(glow_lit, glow_shade)
	add_child(glow)


func _add_ball(parent: Node3D, radius: float, lit: Color, shade: Color, offset := Vector3.ZERO) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 18
	sphere.rings = 10
	mesh.mesh = sphere
	mesh.position = offset
	mesh.material_override = MapKit.toon(lit, shade)
	parent.add_child(mesh)


func _process(delta: float) -> void:
	if not live or _orb == null:
		return
	_t += delta
	_orb.rotation.y += delta * SPIN
	_orb.position.y = sin(_t * 2.4) * BOB_H


func _on_body(body: Node) -> void:
	if not live:
		return
	if body is PuttBall and not (body as PuttBall).is_holed:
		collected.emit(kind, pickup_id)
