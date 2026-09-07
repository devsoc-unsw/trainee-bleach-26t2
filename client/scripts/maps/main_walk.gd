extends Node3D

const MALL_LEN := 52.0
const MALL_Z0 := -2.0


func _ready() -> void:
	var ground := MapKit.combiner(self)
	var grass := MapKit.grass()
	var pavement := MapKit.toon(MapKit.CONCRETE, MapKit.CONCRETE_SHADE)
	var asphalt := MapKit.toon(MapKit.ASPHALT, MapKit.ASPHALT_SHADE)
	var brick := MapKit.toon(MapKit.BRICK, MapKit.BRICK_SHADE)
	var cream := MapKit.toon(MapKit.CREAM)
	var gold := MapKit.toon(Color("C9A227"), Color("8F7014"))
	var steel := MapKit.toon(Color("B8B8BE"), Color("8A8A92"))

	MapKit.box(ground, Vector3(28, 0.2, 10), Vector3(0, 0.1, 6.4), asphalt)
	MapKit.box(self, Vector3(0.18, 0.04, 9.2), Vector3(0, 0.22, 6.4), gold, CSGShape3D.OPERATION_UNION, false)

	var mall_z := MALL_Z0 - MALL_LEN * 0.5
	MapKit.box(ground, Vector3(5.2, 0.2, MALL_LEN), Vector3(0, 0.1, mall_z), pavement)
	MapKit.box(ground, Vector3(4.4, 0.2, MALL_LEN), Vector3(-4.8, 0.1, mall_z), grass)
	MapKit.box(ground, Vector3(4.4, 0.2, MALL_LEN), Vector3(4.8, 0.1, mall_z), grass)

	var kerb := MapKit.toon(Color("B7B2A8"), Color("938E84"))
	MapKit.box(self, Vector3(0.25, 0.28, MALL_LEN), Vector3(-7.15, 0.14, mall_z), kerb)
	MapKit.box(self, Vector3(0.25, 0.28, MALL_LEN), Vector3(7.15, 0.14, mall_z), kerb)

	var lawn_z := MALL_Z0 - MALL_LEN - 6.0
	MapKit.box(ground, Vector3(16, 0.2, 14), Vector3(0, 0.1, lawn_z), grass)

	var hole_pos := Vector3(2.4, 0.2, lawn_z - 3.2)
	MapKit.cup_cut(ground, Vector3(hole_pos.x, 0.1, hole_pos.z))

	MapKit.box(self, Vector3(7.5, 0.42, 3.2), Vector3(-7.2, 0.21, 4.6), pavement)
	MapKit.box(self, Vector3(9.0, 0.08, 0.12), Vector3(-7.2, 0.26, 5.35), steel)
	MapKit.box(self, Vector3(9.0, 0.08, 0.12), Vector3(-7.2, 0.26, 3.85), steel)
	for i in 8:
		var x := -10.8 + float(i) * 1.05
		MapKit.box(self, Vector3(0.18, 0.08, 1.7), Vector3(x, 0.22, 4.6), MapKit.toon(Color("6B5344")))

	MapKit.box(self, Vector3(6.4, 2.1, 2.2), Vector3(-8.4, 1.35, 4.6), cream)
	MapKit.box(self, Vector3(5.6, 0.7, 2.05), Vector3(-8.4, 1.55, 4.6), MapKit.toon(MapKit.GLASS, Color("4A9BB8")))
	MapKit.box(self, Vector3(6.5, 0.18, 2.4), Vector3(-8.4, 2.45, 4.6), gold)
	var tram_label := MapKit.label(self, "L2", Vector3(-8.4, 2.75, 5.8), 42)
	tram_label.rotation.y = 0

	var z := -6.0
	while z > MALL_Z0 - MALL_LEN + 4.0:
		MapKit.tree(self, Vector3(-4.6, 0.2, z), 3.3)
		MapKit.tree(self, Vector3(4.6, 0.2, z - 3.5), 3.7)
		z -= 8.5

	var bench := MapKit.toon(Color("B08968"), Color("8A6548"))
	MapKit.box(self, Vector3(1.8, 0.12, 0.5), Vector3(3.4, 0.42, -18), bench)
	MapKit.box(self, Vector3(0.12, 0.36, 0.5), Vector3(2.6, 0.18, -18), bench)
	MapKit.box(self, Vector3(0.12, 0.36, 0.5), Vector3(4.2, 0.18, -18), bench)

	var bin_mat := MapKit.toon(Color("C9CDD2"), Color("8F949A"))
	MapKit.cylinder(self, 0.22, 0.7, Vector3(-3.2, 0.55, -28), bin_mat, 10)
	MapKit.cylinder(self, 0.22, 0.18, Vector3(-3.2, 0.95, -28), MapKit.toon(Color("E23B3B")), 10)
	MapKit.cylinder(self, 0.22, 0.7, Vector3(-2.6, 0.55, -28), bin_mat, 10)
	MapKit.cylinder(self, 0.22, 0.18, Vector3(-2.6, 0.95, -28), MapKit.toon(Color("F2D04B")), 10)

	var lib_z := lawn_z - 8.6
	MapKit.box(self, Vector3(18, 8.2, 5.5), Vector3(0, 4.2, lib_z), brick)
	MapKit.box(self, Vector3(14, 5.4, 0.3), Vector3(0, 3.6, lib_z + 2.85), MapKit.toon(MapKit.GLASS, Color("4A9BB8")))
	MapKit.box(self, Vector3(6, 1.4, 0.35), Vector3(0, 7.4, lib_z + 2.9), cream)
	var lib_label := MapKit.label(self, "LAW LIBRARY", Vector3(0, 7.45, lib_z + 3.15), 56)
	lib_label.rotation.y = 0

	MapKit.marker(self, "Tee", Vector3(0, 0.22, 0.4))
	MapKit.marker(self, "HolePoint", hole_pos)
