extends Node3D

const HOLD_COLORS: Array[Color] = [
	Color("E23B3B"),
	Color("F28C28"),
	Color("F2D04B"),
	Color("4CB8B0"),
	Color("4A7FD4"),
	Color("7B5BBF"),
	Color("F4F1EA"),
]


func _ready() -> void:
	var ground := MapKit.combiner(self)
	var grass := MapKit.grass()
	var dirt := MapKit.grass(Color(0.42, 0.4, 0.28), Color(0.28, 0.26, 0.18), 1.1)
	var white := MapKit.toon(MapKit.WHITE)
	var wall_mat := MapKit.toon(Color("9AA0A6"), Color("6E747A"))

	MapKit.box(ground, Vector3(26, 0.2, 34), Vector3(0, 0.1, -12), grass)
	MapKit.box(ground, Vector3(8, 0.18, 6), Vector3(8.4, 0.11, -12.5), dirt)

	var hole_pos := Vector3(7.2, 0.2, -21.5)
	MapKit.cup_cut(ground, Vector3(hole_pos.x, 0.1, hole_pos.z))

	_field_markings(white)
	_goal(Vector3(0, 0, -4.5), white)
	_goal(Vector3(0, 0, -19.5), white)

	MapKit.box(self, Vector3(1.1, 4.2, 11.5), Vector3(4.8, 2.2, -14.2), wall_mat)
	_holds(Vector3(4.25, 0.4, -14.2))

	MapKit.tree(self, Vector3(-10.5, 0.2, -2), 3.8)
	MapKit.tree(self, Vector3(-9.6, 0.2, -16), 3.4)
	MapKit.tree(self, Vector3(10.2, 0.2, -3.5), 3.2)
	MapKit.tree(self, Vector3(-8.8, 0.2, -24), 3.6)

	var title := MapKit.label(self, "VILLAGE GREEN", Vector3(0, 5.4, -28), 58)
	title.rotation.y = 0

	MapKit.marker(self, "Tee", Vector3(0, 0.22, 2.2))
	MapKit.marker(self, "HolePoint", hole_pos)


func _field_markings(white: Material) -> void:
	MapKit.box(self, Vector3(12.2, 0.03, 0.08), Vector3(0, 0.215, -4.5), white, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(self, Vector3(12.2, 0.03, 0.08), Vector3(0, 0.215, -19.5), white, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(self, Vector3(0.08, 0.03, 15.1), Vector3(-6.1, 0.215, -12), white, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(self, Vector3(0.08, 0.03, 15.1), Vector3(6.1, 0.215, -12), white, CSGShape3D.OPERATION_UNION, false)
	MapKit.box(self, Vector3(12.2, 0.03, 0.08), Vector3(0, 0.215, -12), white, CSGShape3D.OPERATION_UNION, false)
	MapKit.cylinder(self, 1.15, 0.03, Vector3(0, 0.215, -12), white, 16, CSGShape3D.OPERATION_UNION, false)


func _goal(pos: Vector3, white: Material) -> void:
	MapKit.box(self, Vector3(0.14, 2.2, 0.14), pos + Vector3(-1.9, 1.2, 0), white)
	MapKit.box(self, Vector3(0.14, 2.2, 0.14), pos + Vector3(1.9, 1.2, 0), white)
	MapKit.box(self, Vector3(3.94, 0.14, 0.14), pos + Vector3(0, 2.28, 0), white)
	var net := MapKit.toon(Color(0.92, 0.93, 0.95, 1), Color(0.7, 0.72, 0.76))
	MapKit.box(self, Vector3(3.7, 2.0, 0.04), pos + Vector3(0, 1.15, -0.55), net, CSGShape3D.OPERATION_UNION, false)


func _holds(origin: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	for i in 28:
		var y := 0.45 + rng.randf() * 3.3
		var z := origin.z + rng.randf_range(-5.1, 5.1)
		var size := Vector3(
			0.22 + rng.randf() * 0.16,
			0.14 + rng.randf() * 0.12,
			0.18 + rng.randf() * 0.16
		)
		MapKit.box(
			self,
			size,
			Vector3(origin.x, y, z),
			MapKit.toon(HOLD_COLORS[i % HOLD_COLORS.size()])
		)
