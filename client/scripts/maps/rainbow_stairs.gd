extends Node3D

const RAINBOW: Array[Color] = [
	Color("E23B3B"),
	Color("F28C28"),
	Color("F2D04B"),
	Color("5BBF5B"),
	Color("4CB8B0"),
	Color("4A7FD4"),
	Color("7B5BBF"),
]

const WIDTH := 12.0
const TREAD := 1.5
const RISE := 0.046
const STEP_COUNT := 10
const LANDING_DEPTH := 5.2
const QUAD_DEPTH := 18.0
const QUAD_WIDTH := 20.0


func _ready() -> void:
	var ground := MapKit.combiner(self)
	var grass := MapKit.grass()
	var pavers := MapKit.pavers()

	var landing_h := 0.2
	MapKit.box(ground, Vector3(WIDTH, landing_h, LANDING_DEPTH), Vector3(0, landing_h * 0.5, 0), pavers)

	var stairs_start_z := -LANDING_DEPTH * 0.5
	var stairs_len := float(STEP_COUNT) * TREAD
	var rise_total := float(STEP_COUNT) * RISE
	var last_z := stairs_start_z - stairs_len
	var quad_top := landing_h + rise_total
	for i in STEP_COUNT:
		var t0 := float(i) / float(STEP_COUNT)
		var t1 := float(i + 1) / float(STEP_COUNT)
		MapKit.slope_box(
			self,
			WIDTH,
			landing_h,
			Vector3(0.0, landing_h + rise_total * t0, stairs_start_z - stairs_len * t0),
			Vector3(0.0, landing_h + rise_total * t1, stairs_start_z - stairs_len * t1),
			MapKit.toon(RAINBOW[i % RAINBOW.size()]),
			false
		)
	MapKit.slope_collider(
		self,
		WIDTH,
		landing_h + 0.04,
		Vector3(0.0, landing_h, stairs_start_z),
		Vector3(0.0, quad_top, last_z)
	)

	var quad_z := last_z - QUAD_DEPTH * 0.5
	MapKit.box(
		ground,
		Vector3(QUAD_WIDTH, 0.2, QUAD_DEPTH),
		Vector3(0, quad_top - 0.1, quad_z),
		grass
	)

	var hole_pos := Vector3(3.6, quad_top, quad_z - 4.2)
	MapKit.cup_cut(ground, Vector3(hole_pos.x, quad_top - 0.1, hole_pos.z))

	var rail_mat := MapKit.toon(Color("D8D2C6"), Color("B7B0A4"))
	var stairs_mid_z := (stairs_start_z + last_z) * 0.5
	MapKit.box(self, Vector3(0.28, 0.7, stairs_len + 0.4), Vector3(-WIDTH * 0.5, 0.45, stairs_mid_z), rail_mat)
	MapKit.box(self, Vector3(0.28, 0.7, stairs_len + 0.4), Vector3(WIDTH * 0.5, 0.45, stairs_mid_z), rail_mat)

	var back_z := quad_z - QUAD_DEPTH * 0.5 - 0.6
	var tan := MapKit.quad_brick()
	MapKit.box(self, Vector3(22, 10.8, 1.6), Vector3(0, quad_top + 5.3, back_z), tan)
	MapKit.box(self, Vector3(1.6, 10.8, 14), Vector3(-QUAD_WIDTH * 0.5 - 0.3, quad_top + 5.3, quad_z - 2), tan)
	MapKit.box(self, Vector3(1.6, 10.8, 14), Vector3(QUAD_WIDTH * 0.5 + 0.3, quad_top + 5.3, quad_z - 2), tan)
	MapKit.dress_quad_facade(self, Vector3(0.0, quad_top, back_z + 0.82), QUAD_WIDTH, quad_top, 0.0, true)
	MapKit.dress_quad_facade(self, Vector3(-QUAD_WIDTH * 0.5, quad_top, quad_z), QUAD_DEPTH, quad_top, PI * 0.5, false)
	MapKit.dress_quad_facade(self, Vector3(QUAD_WIDTH * 0.5, quad_top, quad_z), QUAD_DEPTH, quad_top, -PI * 0.5, false)

	MapKit.tree(self, Vector3(-7.2, quad_top, quad_z + 5.5), 3.2)
	MapKit.tree(self, Vector3(7.4, quad_top, quad_z + 4.8), 3.6)
	MapKit.tree(self, Vector3(-6.5, quad_top, quad_z - 5.8), 3.0)

	var planter := MapKit.toon(Color("C7B89A"), Color("9C8B70"))
	MapKit.box(self, Vector3(1.6, 0.38, 1.6), Vector3(-2.2, quad_top + 0.19, quad_z + 1.5), planter)
	MapKit.cylinder(self, 0.55, 0.7, Vector3(-2.2, quad_top + 0.7, quad_z + 1.5), MapKit.toon(MapKit.FOLIAGE, MapKit.FOLIAGE_SHADE), 10)

	MapKit.marker(self, "Tee", Vector3(0, landing_h + 0.02, 1.4))
	MapKit.marker(self, "HolePoint", hole_pos)
