@tool
extends Node3D

const RAINBOW := {
	"mat_rainbow_1": Color("E43B3B"),
	"mat_rainbow_2": Color("F28C28"),
	"mat_rainbow_3": Color("F2D04B"),
	"mat_rainbow_4": Color("5BBF5B"),
	"mat_rainbow_5": Color("4A7FD4"),
	"mat_rainbow_6": Color("7B5BBF"),
	"mat_rainbow_7": Color("8A4AE0"),
}

const PUTTING_NODES: Array[String] = [
	"Green",
	"GreenFar",
	"Pavement",
	"Road",
	"Stairs",
	"SoccerPitch",
]

const PLAY_NODES: Array[String] = [
	"Green",
	"Pavement",
	"Stairs",
]

const FOOT_WALL_NODES: Array[String] = [
	"QuadBuildings",
	"LawLibrary",
	"BrickHall",
	"VillageHall",
	"BoulderWall",
	"Grandstand",
	"GrandstandRoof",
	"Platform",
	"Tram",
]

var _tree_spots: Array[Vector3] = []
var _gaps: Array[Dictionary] = []

const RAINBOW_ORDER: Array[Color] = [
	Color("E43B3B"),
	Color("F28C28"),
	Color("F2D04B"),
	Color("5BBF5B"),
	Color("4A7FD4"),
	Color("7B5BBF"),
	Color("8A4AE0"),
]


func _ready() -> void:
	if get_node_or_null("Cliffs") != null:
		return
	if Engine.is_editor_hint():
		_rebuild_course()
		return
	if has_meta("defer_rebuild") or has_meta("warmed"):
		return
	_rebuild_playable()
	call_deferred("_rebuild_visuals")


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear_generated()
		_restore_imported()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		call_deferred("_rebuild_course")


func _rebuild_course() -> void:
	_rebuild_playable()
	_rebuild_visuals()


func _rebuild_playable() -> void:
	_clear_generated()
	_gaps = _hazard_gaps()
	_stash_tree_spots()
	_hide_imported_cup()
	_build_rainbow_stairs()
	_flatten_kerbs()
	_restyle_materials()
	_prepare_village_layout()
	_punch_cup()
	_close_building_abyss()
	_dress_play_extras()
	_dress_play_gaps()
	if not Engine.is_editor_hint():
		_add_collision()
	_add_bumpers()


func _rebuild_visuals() -> void:
	if not is_inside_tree():
		return
	if get_node_or_null("Cliffs") != null:
		return
	_spawn_course_trees()
	_dress_quad_west()
	_add_cliffs()


func warm_rebuild() -> void:
	if get_node_or_null("Cliffs") != null:
		set_meta("warmed", true)
		return
	_clear_generated()
	_gaps = _hazard_gaps()
	await get_tree().process_frame
	_stash_tree_spots()
	_hide_imported_cup()
	_build_rainbow_stairs()
	await get_tree().process_frame
	_flatten_kerbs()
	_restyle_materials()
	await get_tree().process_frame
	_prepare_village_layout()
	_punch_cup()
	_close_building_abyss()
	_dress_play_extras()
	_dress_play_gaps()
	await get_tree().process_frame
	await _add_collision_async()
	_add_bumpers()
	await get_tree().process_frame
	_rebuild_visuals()
	set_meta("warmed", true)


func _hazard_gaps() -> Array[Dictionary]:
	var hole := get_node_or_null("HolePoint") as Node3D
	var cup := hole.position if hole != null else Vector3(0.0, 0.0, -20.0)
	var raw: Array[Dictionary] = []
	if get_node_or_null("QuadBuildings") != null:
		raw.append(_gap(4.6, -16.4, 0.95))
		raw.append(_gap(-4.5, -30.2, 0.9))
	elif get_node_or_null("LawLibrary") != null:
		raw.append(_gap(4.5, -19.0, 1.0))
		raw.append(_gap(-4.6, -35.4, 0.95))
		raw.append(_gap(4.4, -52.8, 0.9))
	elif get_node_or_null("VillageHall") != null:
		raw.append(_gap(4.5, -13.6, 1.0))
		raw.append(_gap(-4.6, -31.2, 0.95))
		raw.append(_gap(4.4, -41.0, 0.9))
	var out: Array[Dictionary] = []
	for g in raw:
		var pos := Vector3(float(g.x), 0.0, float(g.z))
		var keep := float(g.r) + 2.4
		if pos.distance_to(Vector3.ZERO) < 5.2:
			continue
		if pos.distance_to(Vector3(cup.x, 0.0, cup.z)) < keep:
			continue
		out.append(g)
	return out


func _gap(x: float, z: float, radius: float) -> Dictionary:
	return { "x": x, "z": z, "r": radius }


func _in_gap_xz(x: float, z: float, pad: float = 0.0) -> bool:
	for g in _gaps:
		var dx := x - float(g.x)
		var dz := z - float(g.z)
		var limit := float(g.r) + pad
		if dx * dx + dz * dz < limit * limit:
			return true
	return false


func _tri_hits_gap(a: Vector3, b: Vector3, c: Vector3, pad: float = 0.16) -> bool:
	if _in_gap_xz(a.x, a.z, pad) or _in_gap_xz(b.x, b.z, pad) or _in_gap_xz(c.x, c.z, pad):
		return true
	var mid := (a + b + c) / 3.0
	if _in_gap_xz(mid.x, mid.z, pad):
		return true
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var pc := Vector2(c.x, c.z)
	for g in _gaps:
		var center := Vector2(float(g.x), float(g.z))
		if _circle_hits_tri(center, float(g.r) + pad, pa, pb, pc):
			return true
	return false


func _circle_hits_tri(p: Vector2, radius: float, a: Vector2, b: Vector2, c: Vector2) -> bool:
	if _point_in_tri(p, a, b, c):
		return true
	return (
		_dist_point_seg(p, a, b) < radius
		or _dist_point_seg(p, b, c) < radius
		or _dist_point_seg(p, c, a) < radius
	)


func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)


func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _gap_surface_y(z: float) -> float:
	if get_node_or_null("Stairs") != null and z <= -8.0 and z >= -26.0:
		return _rainbow_y(z)
	return 0.03


func _dress_play_gaps() -> void:
	if _gaps.is_empty():
		return
	var root := Node3D.new()
	root.name = "PlayGaps"
	_gen(root)
	add_child(root)
	var well := MapKit.toon(Color("161310"), Color("070605"), 0, 1.0, Color(0.32, 0.52, 0.62), 0.0)
	var rim := MapKit.toon(Color("C4B8A6"), Color("8E8678"), 0, 1.0, Color(0.32, 0.52, 0.62), 0.0)
	for g in _gaps:
		var x := float(g.x)
		var z := float(g.z)
		var r := float(g.r)
		var y := _gap_surface_y(z)
		_gen(MapKit.cylinder(root, r, 8.4, Vector3(x, y - 4.22, z), well, 20, CSGShape3D.OPERATION_UNION, false))
		var lip := 0.1
		var span := r * 2.0
		_gen(MapKit.box(root, Vector3(span + 0.22, lip, 0.1), Vector3(x, y + 0.02, z - r), rim, CSGShape3D.OPERATION_UNION, false))
		_gen(MapKit.box(root, Vector3(span + 0.22, lip, 0.1), Vector3(x, y + 0.02, z + r), rim, CSGShape3D.OPERATION_UNION, false))
		_gen(MapKit.box(root, Vector3(0.1, lip, span), Vector3(x - r, y + 0.02, z), rim, CSGShape3D.OPERATION_UNION, false))
		_gen(MapKit.box(root, Vector3(0.1, lip, span), Vector3(x + r, y + 0.02, z), rim, CSGShape3D.OPERATION_UNION, false))


func _add_rainbow_step(index: int, width: float, top: float, bot: float, z_a: float, z_b: float, mat: Material) -> void:
	var hit := _gap_on_span(z_a, z_b, width)
	if hit.is_empty():
		_place_rainbow_step(index, width, 0.0, top, bot, z_a, z_b, mat)
		return
	var gx := float(hit.x)
	var gr := float(hit.r)
	var left := gx - gr + width * 0.5
	var right := width * 0.5 - (gx + gr)
	if left > 0.18:
		_place_rainbow_step(index, left, (gx - gr - width * 0.5) * 0.5, top, bot, z_a, z_b, mat)
	if right > 0.18:
		_place_rainbow_step(index + 100, right, (width * 0.5 + gx + gr) * 0.5, top, bot, z_a, z_b, mat)


func _place_rainbow_step(index: int, width: float, x: float, top: float, bot: float, z_a: float, z_b: float, mat: Material) -> void:
	var step := MapKit.box(
		self,
		Vector3(width, maxf(top - bot, 0.1), absf(z_b - z_a) + 0.02),
		Vector3(x, (top + bot) * 0.5, (z_a + z_b) * 0.5),
		mat,
		CSGShape3D.OPERATION_UNION,
		false
	)
	step.name = "RainbowStep_%d" % index
	step.set_meta("no_cliff", true)
	_gen(step)


func _gap_on_span(z_a: float, z_b: float, width: float) -> Dictionary:
	var z_lo := minf(z_a, z_b)
	var z_hi := maxf(z_a, z_b)
	for g in _gaps:
		if absf(float(g.x)) > width * 0.5 - 0.12:
			continue
		if float(g.z) + float(g.r) <= z_lo or float(g.z) - float(g.r) >= z_hi:
			continue
		return g
	return {}


func _add_stair_slope(width: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var from := Vector3(0.0, y0, z0)
	var to := Vector3(0.0, y1, z1)
	var hit := _gap_on_span(z0, z1, width)
	if hit.is_empty():
		_gen(MapKit.slope_collider(self, width, 0.16, from, to))
		return
	var gx := float(hit.x)
	var gr := float(hit.r) + 0.04
	var left_w := gx - gr + width * 0.5
	var right_w := width * 0.5 - (gx + gr)
	if left_w > 0.35:
		var cx := (-width * 0.5 + gx - gr) * 0.5
		_gen(MapKit.slope_collider(self, left_w, 0.16, Vector3(cx, y0, z0), Vector3(cx, y1, z1)))
	if right_w > 0.35:
		var cx := (width * 0.5 + gx + gr) * 0.5
		_gen(MapKit.slope_collider(self, right_w, 0.16, Vector3(cx, y0, z0), Vector3(cx, y1, z1)))
	for seg in _slope_gap_segments(z0, z1):
		var t0 := inverse_lerp(z0, z1, seg.x)
		var t1 := inverse_lerp(z0, z1, seg.y)
		_gen(MapKit.slope_collider(
			self,
			gr * 2.0,
			0.16,
			Vector3(gx, lerpf(y0, y1, t0), seg.x),
			Vector3(gx, lerpf(y0, y1, t1), seg.y)
		))


func _slope_gap_segments(z0: float, z1: float) -> Array[Vector2]:
	var z_lo := minf(z0, z1)
	var z_hi := maxf(z0, z1)
	var cuts: Array[Vector2] = []
	for g in _gaps:
		var gz := float(g.z)
		var gr := float(g.r)
		if gz + gr <= z_lo or gz - gr >= z_hi:
			continue
		cuts.append(Vector2(gz - gr, gz + gr))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x
	)
	var segs: Array[Vector2] = []
	var cursor := z_lo
	for cut in cuts:
		if cut.x > cursor + 0.08:
			segs.append(Vector2(cursor, cut.x))
		cursor = maxf(cursor, cut.y)
	if z_hi > cursor + 0.08:
		segs.append(Vector2(cursor, z_hi))
	if segs.is_empty():
		segs.append(Vector2(z_lo, z_hi))
	return segs


func _cut_rects(tiles: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for tile in tiles:
		out.append_array(_cut_rect(tile, hole))
	return out


func _cut_rect(box: Rect2, hole: Rect2) -> Array[Rect2]:
	var hit := box.intersection(hole)
	if hit.size.x < 0.03 or hit.size.y < 0.03:
		return [box]
	var out: Array[Rect2] = []
	if hit.position.x > box.position.x + 0.02:
		out.append(Rect2(box.position.x, box.position.y, hit.position.x - box.position.x, box.size.y))
	var box_r := box.position.x + box.size.x
	var hit_r := hit.position.x + hit.size.x
	if hit_r < box_r - 0.02:
		out.append(Rect2(hit_r, box.position.y, box_r - hit_r, box.size.y))
	if hit.position.y > box.position.y + 0.02:
		out.append(Rect2(hit.position.x, box.position.y, hit.size.x, hit.position.y - box.position.y))
	var box_t := box.position.y + box.size.y
	var hit_t := hit.position.y + hit.size.y
	if hit_t < box_t - 0.02:
		out.append(Rect2(hit.position.x, hit_t, hit.size.x, box_t - hit_t))
	return out


func _dress_play_extras() -> void:
	var root := Node3D.new()
	root.name = "PlayExtras"
	_gen(root)
	add_child(root)
	if get_node_or_null("QuadBuildings") != null:
		_extras_rainbow(root)
	elif get_node_or_null("LawLibrary") != null:
		_extras_mall(root)
	elif get_node_or_null("VillageHall") != null:
		_extras_village(root)


func _rainbow_y(z: float) -> float:
	if z >= -8.0:
		return 0.0
	if z <= -26.0:
		return 1.4
	return 1.4 * ((-z) - 8.0) / 18.0


func _extras_rainbow(root: Node3D) -> void:
	var paver := MapKit.pavers()
	var lawn := MapKit.grass()
	var brick := MapKit.brick_wall()
	var cream := MapKit.quad_plaster()
	# Tee (0,0,0) -> plaza -> stairs -> hole (1.15, 1.4, -33.4).
	# Keep x ~= -2 .. 2 clear. Quad / hedges block side hops except behind the tee.
	_extra_wall(root, Vector3(4.2, 0.78, 0.36), Vector3(-3.2, 0.39, -3.5), brick)
	_extra_post(root, Vector3(1.4, 0.4, -3.65), 0.88, cream)
	_extra_ramp(root, 1.7, Vector3(3.4, 0.05, -6.8), Vector3(3.4, 0.5, -8.3), paver)
	var isle_a := Vector3(-10.4, 0.3, 6.4)
	_extra_island(root, isle_a, Vector3(3.4, 0.32, 3.0), lawn, Vector3(-5.8, 0.06, 2.2), true)
	_extra_ramp(root, 2.2, Vector3(-5.8, 0.06, 2.2), Vector3(-9.2, 0.46, 5.4), paver)
	var isle_b := Vector3(8.8, 0.3, 6.2)
	_extra_island(root, isle_b, Vector3(3.2, 0.3, 2.8), lawn, Vector3(4.6, 0.06, 2.0), true)
	_extra_ramp(root, 2.1, Vector3(4.6, 0.06, 2.0), Vector3(7.6, 0.45, 5.0), paver)
	var stair_z := -18.4
	var stair_y := _rainbow_y(stair_z)
	_extra_wall(root, Vector3(3.0, 0.7, 0.32), Vector3(3.9, stair_y + 0.35, stair_z), brick)
	_extra_post(root, Vector3(2.2, stair_y + 0.42, stair_z - 0.15), 0.84, cream)
	_extra_wall(root, Vector3(3.2, 0.74, 0.32), Vector3(4.9, 1.77, -28.0), brick)
	_extra_post(root, Vector3(-4.8, 1.82, -28.2), 0.85, cream)
	var knoll := Vector3(-6.2, 1.52, -35.2)
	_extra_island(root, knoll, Vector3(2.8, 0.3, 2.4), lawn, Vector3(-3.8, 1.42, -33.0), false)
	_extra_ramp(root, 2.0, Vector3(-3.8, 1.42, -33.0), Vector3(-5.6, 1.67, -34.6), paver)


func _extras_mall(root: Node3D) -> void:
	var paver := MapKit.pavers()
	var lawn := MapKit.grass()
	var brick := MapKit.brick_wall()
	var cream := MapKit.cream_building()
	# Tee (0,0,0) -> mall -> hole (1.8, 0, -58.5). Alternating 4 m+ gaps.
	_extra_wall(root, Vector3(4.4, 0.82, 0.36), Vector3(3.2, 0.41, -8.2), brick)
	_extra_post(root, Vector3(-1.2, 0.4, -8.35), 0.9, cream)
	_extra_wall(root, Vector3(4.6, 0.84, 0.36), Vector3(-3.3, 0.42, -17.8), brick)
	_extra_post(root, Vector3(1.6, 0.42, -17.95), 0.92, cream)
	_extra_ramp(root, 1.8, Vector3(2.6, 0.05, -26.2), Vector3(2.6, 0.52, -27.8), paver)
	_extra_wall(root, Vector3(4.4, 0.84, 0.36), Vector3(3.2, 0.42, -35.2), brick)
	_extra_post(root, Vector3(-1.4, 0.42, -35.35), 0.9, cream)
	_extra_wall(root, Vector3(4.2, 0.8, 0.36), Vector3(-3.2, 0.4, -45.6), brick)
	_extra_post(root, Vector3(1.5, 0.4, -45.75), 0.86, cream)
	var isle_l := Vector3(-9.2, 0.15, -27.0)
	_extra_island(root, isle_l, Vector3(2.8, 0.36, 2.8), lawn, Vector3(-6.5, 0.06, -25.4), false)
	_extra_ramp(root, 2.1, Vector3(-6.5, 0.06, -25.4), Vector3(-8.4, 0.33, -26.6), paver)
	var isle_r1 := Vector3(9.4, 0.15, -29.4)
	_extra_island(root, isle_r1, Vector3(2.8, 0.36, 2.8), lawn, Vector3(6.4, 0.06, -27.8), false)
	_extra_ramp(root, 2.1, Vector3(6.4, 0.06, -27.8), Vector3(8.4, 0.33, -29.0), paver)
	var isle_r2 := Vector3(9.0, 0.15, -44.6)
	_extra_island(root, isle_r2, Vector3(3.0, 0.36, 2.8), lawn, Vector3(6.2, 0.06, -42.6), false)
	_extra_ramp(root, 2.1, Vector3(6.2, 0.06, -42.6), Vector3(8.2, 0.33, -44.0), paver)


func _prepare_village_layout() -> void:
	if get_node_or_null("VillageHall") == null:
		return
	var hole := get_node_or_null("HolePoint") as Node3D
	if hole != null:
		hole.position = Vector3(1.8, 0.0, -56.4)
	set_meta("play_z_min", -64.0)
	var far := MeshInstance3D.new()
	far.name = "GreenFar"
	var box := BoxMesh.new()
	box.size = Vector3(14.5, 0.08, 22.0)
	far.mesh = box
	far.position = Vector3(-0.75, -0.04, -53.0)
	far.visible = false
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gen(far)
	add_child(far)


func _extras_village(root: Node3D) -> void:
	var brick := MapKit.brick_wall()
	var cream := MapKit.cream_building()
	var planter := MapKit.toon(Color("C7B89A"), Color("9C8B70"))
	var bench := MapKit.toon(Color("B08968"), Color("8A6548"))
	var bin_mat := MapKit.toon(Color("C9CDD2"), Color("8F949A"))
	var steel := MapKit.metal_silver()
	var wall_mat := MapKit.toon(Color("9AA0A6"), Color("6E747A"))
	# Forward line only: tee -> past the boulder wall -> along the pitch ->
	# Village Hall -> cup on the far lawn. No back-tee or pitch-side detours.
	_extra_wall(root, Vector3(4.6, 0.88, 0.38), Vector3(3.8, 0.44, -6.2), brick)
	_extra_post(root, Vector3(-1.6, 0.44, -6.35), 0.9, cream)
	_village_planter(root, Vector3(-4.4, 0.2, -7.2), planter)
	_extra_wall(root, Vector3(4.8, 0.9, 0.4), Vector3(3.6, 0.45, -14.4), brick)
	_extra_post(root, Vector3(-1.2, 0.44, -14.55), 0.92, cream)
	_village_boulder(root, Vector3(-7.2, 0.55, -13.6), wall_mat)
	_village_boulder(root, Vector3(-6.6, 0.42, -16.8), wall_mat)
	_extra_wall(root, Vector3(4.4, 0.88, 0.38), Vector3(-3.8, 0.44, -24.2), brick)
	_extra_post(root, Vector3(1.8, 0.44, -24.35), 0.9, cream)
	_village_bench(root, Vector3(4.6, 0.2, -26.4), bench)
	_extra_wall(root, Vector3(4.6, 0.88, 0.38), Vector3(3.4, 0.44, -34.6), brick)
	_extra_post(root, Vector3(-1.4, 0.44, -34.75), 0.88, cream)
	_village_planter(root, Vector3(-4.8, 0.2, -36.2), planter)
	_extra_wall(root, Vector3(4.2, 0.86, 0.36), Vector3(-3.6, 0.43, -45.4), brick)
	_extra_post(root, Vector3(1.7, 0.43, -45.55), 0.86, cream)
	_village_boulder(root, Vector3(-6.8, 0.5, -46.8), wall_mat)
	_extra_wall(root, Vector3(4.0, 0.84, 0.36), Vector3(3.2, 0.42, -51.8), brick)
	_extra_post(root, Vector3(-1.8, 0.42, -51.95), 0.84, cream)
	_village_bin(root, Vector3(-4.6, 0.2, -8.8), bin_mat, Color("E23B3B"))
	_village_bin(root, Vector3(4.4, 0.2, -28.6), bin_mat, Color("F2D04B"))
	_village_bin(root, Vector3(-4.2, 0.2, -48.8), bin_mat, Color("4CB8B0"))
	_village_lamp(root, Vector3(5.6, 0.2, -11.0), steel)
	_village_lamp(root, Vector3(-5.8, 0.2, -30.4), steel)
	_village_lamp(root, Vector3(5.4, 0.2, -49.6), steel)
	MapKit.tree(root, Vector3(-6.4, 0.2, -40.6), 3.5)
	MapKit.tree(root, Vector3(4.8, 0.2, -42.8), 3.2)
	MapKit.tree(root, Vector3(-5.8, 0.2, -53.2), 3.8)
	MapKit.tree(root, Vector3(4.2, 0.2, -58.4), 3.4)
	var title := MapKit.label(root, "VILLAGE GREEN", Vector3(0.2, 5.6, -63.0), 52)
	title.rotation.y = 0
	_gen(title)


func _village_planter(root: Node3D, pos: Vector3, mat: Material) -> void:
	_extra_wall(root, Vector3(1.5, 0.42, 1.5), pos + Vector3(0.0, 0.21, 0.0), mat)
	_gen(MapKit.cylinder(root, 0.5, 0.7, pos + Vector3(0.0, 0.72, 0.0), MapKit.toon(MapKit.FOLIAGE, MapKit.FOLIAGE_SHADE), 10))


func _village_bench(root: Node3D, pos: Vector3, mat: Material) -> void:
	_extra_wall(root, Vector3(1.8, 0.12, 0.48), pos + Vector3(0.0, 0.22, 0.0), mat)
	_extra_wall(root, Vector3(0.12, 0.36, 0.48), pos + Vector3(-0.78, 0.0, 0.0), mat)
	_extra_wall(root, Vector3(0.12, 0.36, 0.48), pos + Vector3(0.78, 0.0, 0.0), mat)


func _village_bin(root: Node3D, pos: Vector3, body: Material, lid: Color) -> void:
	_extra_post(root, pos + Vector3(0.0, 0.35, 0.0), 0.7, body)
	_gen(MapKit.cylinder(root, 0.22, 0.16, pos + Vector3(0.0, 0.78, 0.0), MapKit.toon(lid), 10))


func _village_lamp(root: Node3D, pos: Vector3, mat: Material) -> void:
	_extra_post(root, pos + Vector3(0.0, 1.2, 0.0), 2.4, mat)
	_gen(MapKit.box(root, Vector3(0.36, 0.16, 0.36), pos + Vector3(0.0, 2.48, 0.0), MapKit.toon(Color("F6E39A"), Color("C9B05A")), CSGShape3D.OPERATION_UNION, false))


func _village_boulder(root: Node3D, pos: Vector3, mat: Material) -> void:
	_extra_wall(root, Vector3(1.35, 1.1, 1.15), pos, mat)


func _extra_wall(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	_gen(MapKit.box(root, size, pos, mat, CSGShape3D.OPERATION_UNION, false))
	_extra_box_body(root, size, pos, MapKit.bumper_physics())


func _extra_island(root: Node3D, pos: Vector3, size: Vector3, mat: Material, entry: Vector3, skirt: bool) -> void:
	_gen(MapKit.box(root, size, pos, mat, CSGShape3D.OPERATION_UNION, false))
	_extra_box_body(root, size, pos, MapKit.putting_physics())
	var lip := MapKit.toon(Color("C4B8A6"), Color("8E8678"))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var ly := pos.y + size.y * 0.5 + 0.06
	var to_entry := entry - pos
	var skip_x := 0
	var skip_z := 0
	if absf(to_entry.x) >= absf(to_entry.z):
		skip_x = 1 if to_entry.x > 0.0 else -1
	else:
		skip_z = 1 if to_entry.z > 0.0 else -1
	if skip_z != -1:
		_gen(MapKit.box(root, Vector3(size.x + 0.16, 0.14, 0.16), Vector3(pos.x, ly, pos.z - hz), lip, CSGShape3D.OPERATION_UNION, false))
		_extra_box_body(root, Vector3(size.x + 0.16, 0.14, 0.16), Vector3(pos.x, ly, pos.z - hz), MapKit.bumper_physics())
	if skip_z != 1:
		_gen(MapKit.box(root, Vector3(size.x + 0.16, 0.14, 0.16), Vector3(pos.x, ly, pos.z + hz), lip, CSGShape3D.OPERATION_UNION, false))
		_extra_box_body(root, Vector3(size.x + 0.16, 0.14, 0.16), Vector3(pos.x, ly, pos.z + hz), MapKit.bumper_physics())
	if skip_x != -1:
		_gen(MapKit.box(root, Vector3(0.16, 0.14, size.z), Vector3(pos.x - hx, ly, pos.z), lip, CSGShape3D.OPERATION_UNION, false))
		_extra_box_body(root, Vector3(0.16, 0.14, size.z), Vector3(pos.x - hx, ly, pos.z), MapKit.bumper_physics())
	if skip_x != 1:
		_gen(MapKit.box(root, Vector3(0.16, 0.14, size.z), Vector3(pos.x + hx, ly, pos.z), lip, CSGShape3D.OPERATION_UNION, false))
		_extra_box_body(root, Vector3(0.16, 0.14, size.z), Vector3(pos.x + hx, ly, pos.z), MapKit.bumper_physics())
	if skirt:
		var dirt_h := 7.5
		_gen(MapKit.box(
			root,
			Vector3(size.x, dirt_h, size.z),
			pos + Vector3(0.0, -size.y * 0.5 - dirt_h * 0.5, 0.0),
			MapKit.cliff(),
			CSGShape3D.OPERATION_UNION,
			false
		))


func _extra_ramp(root: Node3D, width: float, from: Vector3, to: Vector3, mat: Material) -> void:
	var start := MapKit.flatten_ramp(from, to, 8.0)
	_gen(MapKit.slope_box(root, width, 0.16, start, to, mat, false))
	_gen(MapKit.slope_collider(root, width + 0.08, 0.14, start, to))


func _extra_post(root: Node3D, pos: Vector3, height: float, mat: Material) -> void:
	_gen(MapKit.cylinder(root, 0.16, height, pos, mat, 10, CSGShape3D.OPERATION_UNION, false))
	var body := StaticBody3D.new()
	body.physics_material_override = MapKit.bumper_physics()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.16
	shape.height = height
	col.shape = shape
	body.add_child(col)
	_gen(body)
	root.add_child(body)


func _extra_box_body(root: Node3D, size: Vector3, pos: Vector3, phys: PhysicsMaterial) -> void:
	var body := StaticBody3D.new()
	body.physics_material_override = phys
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_gen(body)
	root.add_child(body)


func _gen(node: Node) -> Node:
	if node != null:
		node.set_meta("generated", true)
	return node


func _mark_wall(node: Node) -> Node:
	_gen(node)
	if node is CSGShape3D:
		(node as CSGShape3D).collision_layer = 1 | 2
		(node as CSGShape3D).collision_mask = 0
	elif node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 1 | 2
		(node as CollisionObject3D).collision_mask = 0
	return node


func _clear_generated() -> void:
	var dump: Array[Node] = []
	for child in get_children():
		if child.has_meta("generated"):
			dump.append(child)
	for node in dump:
		node.free()


func _restore_imported() -> void:
	for child in get_children():
		var n := str(child.name)
		if n.begins_with("Tree_") or n.begins_with("Kerb") or n == "Stairs" or n == "HoleCut" or n == "Green":
			child.visible = true
		var mesh_i := child as MeshInstance3D
		if mesh_i != null and mesh_i.mesh != null:
			for surf in mesh_i.mesh.get_surface_count():
				mesh_i.set_surface_override_material(surf, null)


func _add_cliffs() -> void:
	var cup := Vector3(10000.0, 0.0, 10000.0)
	var hole_point := get_node_or_null("HolePoint") as Node3D
	if hole_point != null:
		cup = hole_point.global_position
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shared := {"edges": {}, "centroid": Vector3.ZERO, "count": 0}
	for mesh_i in _meshes():
		if not _is_putting_mesh(mesh_i):
			continue
		if str(mesh_i.name) == "Green":
			var aabb: AABB = mesh_i.mesh.get_aabb()
			var xform := mesh_i.global_transform * Transform3D(Basis.IDENTITY, aabb.get_center())
			MapKit.append_box_cliffs(st, aabb.size, xform, cup, 16.0, shared)
			continue
		MapKit.append_mesh_cliffs(st, mesh_i.mesh, mesh_i.global_transform, cup, 16.0, shared)
	_append_foot_walls(st, shared, cup)
	_ignore_stair_side_cliffs(shared)
	MapKit.emit_shared_cliffs(st, shared, cup)
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var cliffs := MeshInstance3D.new()
	cliffs.name = "Cliffs"
	cliffs.mesh = mesh
	cliffs.material_override = MapKit.cliff()
	cliffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gen(cliffs)
	add_child(cliffs)


func _add_bumpers() -> void:
	var cup := Vector3(10000.0, 0.0, 10000.0)
	var hole_point := get_node_or_null("HolePoint") as Node3D
	if hole_point != null:
		cup = hole_point.position
	var putting: Array[MeshInstance3D] = []
	var neighbors: Array[MeshInstance3D] = []
	for mesh_i in _meshes():
		if not _is_putting_mesh(mesh_i):
			continue
		neighbors.append(mesh_i)
		if str(mesh_i.name) == "Stairs":
			continue
		putting.append(mesh_i)
	if putting.is_empty():
		return
	var root := Node3D.new()
	root.name = "Bumpers"
	_gen(root)
	add_child(root)
	var mat := MapKit.toon(Color("E56B8A"), Color("C44E6E"))
	for mesh_i in putting:
		_rim_putting_mesh(root, mesh_i, neighbors, cup, mat)


func _is_putting_mesh(mesh_i: MeshInstance3D) -> bool:
	if mesh_i.mesh == null or mesh_i.is_queued_for_deletion():
		return false
	return PUTTING_NODES.has(str(mesh_i.name))


func _rim_putting_mesh(
	root: Node3D,
	mesh_i: MeshInstance3D,
	putting: Array[MeshInstance3D],
	cup: Vector3,
	mat: Material
) -> void:
	var verts := _mesh_verts(mesh_i.mesh)
	if verts.is_empty():
		return
	var aabb: AABB = mesh_i.mesh.get_aabb()
	# Left / right drop-offs only. Front and back rims sit on play-through
	# joints (stairs → green) and block the hole.
	var sides: Array[Dictionary] = [
		{"axis": 0, "bound": aabb.position.x + aabb.size.x},
		{"axis": 0, "bound": aabb.position.x},
	]
	for side in sides:
		_rim_side(root, verts, side, aabb, mesh_i, putting, cup, mat)


func _rim_side(
	root: Node3D,
	verts: PackedVector3Array,
	side: Dictionary,
	aabb: AABB,
	self_mesh: MeshInstance3D,
	putting: Array[MeshInstance3D],
	cup: Vector3,
	mat: Material
) -> void:
	var axis: int = int(side["axis"])
	var bound: float = float(side["bound"])
	var along := 2 if axis == 0 else 0
	var lip: Array[Vector3] = []
	for v in verts:
		var c := v.x if axis == 0 else v.z
		if absf(c - bound) > 0.22:
			continue
		lip.append(v)
	if lip.size() < 2:
		return
	var bins := {}
	for v in lip:
		var key := roundi((v.x if along == 0 else v.z) * 5.0)
		if not bins.has(key) or v.y > bins[key].y:
			bins[key] = v
	var pts: Array[Vector3] = []
	for key in bins:
		pts.append(bins[key])
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.x < b.x if along == 0 else a.z < b.z
	)
	var center := aabb.get_center()
	for i in range(pts.size() - 1):
		_spawn_rim_box(root, pts[i], pts[i + 1], center, self_mesh, putting, cup, mat)


func _spawn_rim_box(
	root: Node3D,
	a: Vector3,
	b: Vector3,
	center: Vector3,
	self_mesh: MeshInstance3D,
	putting: Array[MeshInstance3D],
	cup: Vector3,
	mat: Material
) -> void:
	var along := b - a
	along.y = 0.0
	var length := along.length()
	if length < 0.28:
		return
	var mid := (a + b) * 0.5
	if Vector2(mid.x - cup.x, mid.z - cup.z).length() < MapKit.CUP_OUTER + 0.2:
		return
	var inward := Vector3(center.x - mid.x, 0.0, center.z - mid.z)
	if inward.length_squared() < 0.0001:
		inward = Vector3(along.z, 0.0, -along.x)
	inward = inward.normalized()
	var outward := -inward
	if _blocked_by_neighbor(mid + outward * 0.55, self_mesh, putting):
		return
	var inner := _quad_inner_x()
	if inner > 0.0 and mid.z < -5.5 and mid.z > -28.5:
		return
	var height := 0.22
	var width := 0.18
	# Sit fully on the lip: outer face flush with the putting edge.
	var pos := Vector3(mid.x, mid.y + height * 0.5, mid.z) + inward * (width * 0.5)
	var node := MapKit.box(
		root,
		Vector3(width, height, length + 0.06),
		pos,
		mat,
		CSGShape3D.OPERATION_UNION,
		not Engine.is_editor_hint()
	)
	_gen(node)
	node.rotation.y = atan2(along.x, along.z)
	node.name = "Rim"


func _inside_other_putting(p: Vector3, self_mesh: MeshInstance3D, putting: Array[MeshInstance3D]) -> bool:
	for other in putting:
		if other == self_mesh or other.mesh == null:
			continue
		var a: AABB = other.mesh.get_aabb()
		a = a.grow(0.2)
		a.position.y -= 2.0
		a.size.y += 4.0
		if a.has_point(p):
			return true
	return false


func _blocked_by_neighbor(p: Vector3, self_mesh: MeshInstance3D, putting: Array[MeshInstance3D]) -> bool:
	if _inside_other_putting(p, self_mesh, putting):
		return true
	for mesh_i in _meshes():
		var n := str(mesh_i.name)
		if not n.begins_with("Hedge") and not FOOT_WALL_NODES.has(n):
			continue
		if mesh_i.mesh == null:
			continue
		var a: AABB = mesh_i.mesh.get_aabb()
		if a.position.x < -1.0 and a.position.x + a.size.x > 1.0 and a.size.x > 16.0:
			continue
		a = a.grow(0.15)
		a.position.y -= 2.0
		a.size.y += 4.0
		if a.has_point(p):
			return true
	return false


func _quad_inner_x() -> float:
	var mesh_i := get_node_or_null("QuadBuildings") as MeshInstance3D
	if mesh_i == null or mesh_i.mesh == null:
		return 0.0
	var best := 1.0e9
	for v in _mesh_verts(mesh_i.mesh):
		if absf(v.y) > 0.05:
			continue
		if v.z > -5.5 or v.z < -29.0:
			continue
		var ax := absf(v.x)
		if ax > 7.0 and ax < best:
			best = ax
	return 0.0 if best > 1.0e8 else best


func _mesh_verts(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for surf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		out.append_array(arrays[Mesh.ARRAY_VERTEX])
	return out


func _append_foot_walls(st: SurfaceTool, shared: Dictionary, cup: Vector3) -> void:
	var ground := _merged_named_aabb(PUTTING_NODES)
	for node_id in FOOT_WALL_NODES:
		var mesh_i := get_node_or_null(node_id) as MeshInstance3D
		_foot_wall_from(mesh_i, ground, st, shared, cup)
	for mesh_i in _meshes():
		if mesh_i == null or not str(mesh_i.name).begins_with("Hedge"):
			continue
		_foot_wall_from(mesh_i, ground, st, shared, cup)


func _foot_wall_from(mesh_i: MeshInstance3D, ground: AABB, st: SurfaceTool, shared: Dictionary, cup: Vector3) -> void:
	if mesh_i == null or mesh_i.mesh == null:
		return
	for aabb in _foot_volumes(mesh_i):
		if aabb.size.x < 0.4 or aabb.size.z < 0.4:
			continue
		var gx0 := ground.position.x
		var gx1 := ground.position.x + ground.size.x
		var gz0 := ground.position.z
		var gz1 := ground.position.z + ground.size.z
		var x0 := aabb.position.x
		var x1 := x0 + aabb.size.x
		var z0 := aabb.position.z
		var z1 := z0 + aabb.size.z
		var overlap := clampf(aabb.size.y * 0.5, 0.9, 1.6)
		if aabb.size.y < 0.85:
			overlap = clampf(aabb.size.y * 0.7, 0.12, aabb.size.y * 0.85)
		var lip_y := aabb.position.y + overlap
		var pad := 0.14
		if x0 < gx0 - 0.15:
			_foot_strip(st, shared, cup, x0 - pad, minf(gx0, x1), z0 - pad, z1 + pad, lip_y)
		if x1 > gx1 + 0.15:
			_foot_strip(st, shared, cup, maxf(gx1, x0), x1 + pad, z0 - pad, z1 + pad, lip_y)
		if z0 < gz0 - 0.15:
			_foot_strip(st, shared, cup, x0 - pad, x1 + pad, z0 - pad, minf(gz0, z1), lip_y)
		if z1 > gz1 + 0.15:
			_foot_strip(st, shared, cup, x0 - pad, x1 + pad, maxf(gz1, z0), z1 + pad, lip_y)


func _foot_volumes(mesh_i: MeshInstance3D) -> Array[AABB]:
	var putting := _merged_named_aabb(PUTTING_NODES)
	var full: AABB = mesh_i.mesh.get_aabb()
	if putting.size == Vector3.ZERO:
		return [full]
	var pc := putting.get_center()
	var wraps := (
		full.position.x < pc.x
		and full.position.x + full.size.x > pc.x
		and full.size.x > putting.size.x * 0.75
	)
	if not wraps:
		return [full]
	return _split_foot_volumes(mesh_i, putting)


func _split_foot_volumes(mesh_i: MeshInstance3D, putting: AABB) -> Array[AABB]:
	var pc := putting.get_center()
	var gz0 := putting.position.z
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var back := PackedVector3Array()
	for v in _mesh_verts(mesh_i.mesh):
		if v.z < gz0 - 0.4:
			back.append(v)
		elif v.y < 1.6:
			if v.x < pc.x - 1.5:
				left.append(v)
			elif v.x > pc.x + 1.5:
				right.append(v)
	var out: Array[AABB] = []
	for pts in [left, right, back]:
		if pts.size() < 3:
			continue
		var aabb := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			aabb = aabb.expand(p)
		if aabb.size.x > 0.45 and aabb.size.z > 0.45:
			out.append(aabb)
	return out


func _foot_strip(
	st: SurfaceTool,
	shared: Dictionary,
	cup: Vector3,
	x0: float,
	x1: float,
	z0: float,
	z1: float,
	lip_y: float
) -> void:
	if x1 - x0 < 0.2 or z1 - z0 < 0.2:
		return
	var size := Vector3(x1 - x0, 0.16, z1 - z0)
	var xform := Transform3D(
		Basis.IDENTITY,
		Vector3((x0 + x1) * 0.5, lip_y - 0.08, (z0 + z1) * 0.5)
	)
	MapKit.append_box_cliffs(st, size, xform, cup, 16.0, shared)


func _ignore_stair_side_cliffs(shared: Dictionary) -> void:
	if get_node_or_null("Stairs") == null:
		return
	var edges: Dictionary = shared.get("edges", {})
	for key in edges:
		if int(edges[key]["n"]) != 1:
			continue
		var a: Vector3 = edges[key]["a"]
		var b: Vector3 = edges[key]["b"]
		var mid := (a + b) * 0.5
		if absf(a.z - b.z) < absf(a.x - b.x):
			continue
		if absf(mid.x) < 5.55 or absf(mid.x) > 6.45:
			continue
		if mid.z > -7.6 or mid.z < -26.4:
			continue
		edges[key]["n"] = 2


func _merged_named_aabb(names: Array[String]) -> AABB:
	var acc := AABB()
	var any := false
	for n in names:
		var mesh_i := get_node_or_null(n) as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null:
			continue
		var a: AABB = mesh_i.mesh.get_aabb()
		acc = a if not any else acc.merge(a)
		any = true
	return acc


func _stash_tree_spots() -> void:
	_tree_spots.clear()
	var to_free: Array[Node] = []
	for child in get_children():
		if not str(child.name).begins_with("Tree_"):
			continue
		var pos: Vector3 = Vector3.ZERO
		var spatial := child as Node3D
		if spatial != null:
			pos = spatial.global_position
		var mesh_i := child as MeshInstance3D
		if mesh_i != null and mesh_i.mesh != null:
			var aabb: AABB = mesh_i.mesh.get_aabb()
			var center: Vector3 = aabb.position + aabb.size * 0.5
			pos = Vector3(center.x, aabb.position.y, center.z)
		_tree_spots.append(pos)
		if Engine.is_editor_hint():
			child.visible = false
		else:
			to_free.append(child)
	for node in to_free:
		node.queue_free()


func _spawn_course_trees() -> void:
	for pos in _tree_spots:
		MapKit.tree(self, pos, 3.2 + absf(pos.x) * 0.03)


func _close_building_abyss() -> void:
	var green := get_node_or_null("Green") as MeshInstance3D
	var buildings := get_node_or_null("QuadBuildings") as MeshInstance3D
	if green == null or green.mesh == null or buildings == null or buildings.mesh == null:
		return
	var g: AABB = green.mesh.get_aabb()
	var cream := MapKit.quad_brick()
	var vols := _building_volumes(buildings)
	if vols.is_empty():
		return
	var gx0 := g.position.x
	var gx1 := g.position.x + g.size.x
	var gz0 := g.position.z
	var gz1 := g.position.z + g.size.z
	var gc := g.get_center()
	var face_r := gx1
	var face_l := gx0
	var face_b := -1.0e9
	var any_r := false
	var any_l := false
	var any_b := false
	var wall_y0 := 0.0
	var wall_h := 11.0
	for vol in vols:
		var x0 := vol.position.x
		var x1 := x0 + vol.size.x
		var z1 := vol.position.z + vol.size.z
		wall_y0 = minf(wall_y0, vol.position.y)
		wall_h = maxf(wall_h, vol.size.y)
		if x0 < gc.x and x1 > gc.x:
			if x1 > gx1:
				face_r = maxf(face_r, x1)
				any_r = true
			if x0 < gx0:
				face_l = minf(face_l, x0)
				any_l = true
			if z1 < gc.z:
				face_b = maxf(face_b, z1)
				any_b = true
			continue
		if x0 >= gx1 - 0.2:
			face_r = maxf(face_r, x0) if any_r else x0
			if x0 > gx1:
				any_r = true
		if x1 <= gx0 + 0.2:
			face_l = minf(face_l, x1) if any_l else x1
			if x1 < gx0:
				any_l = true
		if z1 <= gz0 + 0.2:
			face_b = maxf(face_b, z1)
			any_b = true
	var depth := gz1 - gz0 + 0.55
	var z_mid := (gz0 + gz1) * 0.5
	var y := wall_y0 + wall_h * 0.5
	if any_r and face_r - gx1 > 0.05:
		var w := face_r - gx1 + 0.18
		_mark_wall(MapKit.box(
			self,
			Vector3(w, wall_h, depth),
			Vector3(gx1 + w * 0.5, y, z_mid),
			cream,
			CSGShape3D.OPERATION_UNION,
			not Engine.is_editor_hint()
		))
	if any_l and gx0 - face_l > 0.05:
		var w := gx0 - face_l + 0.18
		_mark_wall(MapKit.box(
			self,
			Vector3(w, wall_h, depth),
			Vector3(gx0 - w * 0.5, y, z_mid),
			cream,
			CSGShape3D.OPERATION_UNION,
			not Engine.is_editor_hint()
		))
	if any_b and gz0 - face_b > 0.04:
		var d := gz0 - face_b + 0.18
		_mark_wall(MapKit.box(
			self,
			Vector3(gx1 - gx0 + 0.35, wall_h, d),
			Vector3(gc.x, y, gz0 - d * 0.5),
			cream,
			CSGShape3D.OPERATION_UNION,
			not Engine.is_editor_hint()
		))


func _dress_quad_west() -> void:
	var green := get_node_or_null("Green") as MeshInstance3D
	if green == null or green.mesh == null:
		return
	if get_node_or_null("QuadBuildings") == null:
		return
	var g: AABB = green.mesh.get_aabb()
	var y0 := g.position.y + g.size.y
	var gx0 := g.position.x
	var gx1 := gx0 + g.size.x
	var gz0 := g.position.z
	var gz1 := gz0 + g.size.z
	var root := Node3D.new()
	root.name = "QuadWestDress"
	_gen(root)
	add_child(root)
	MapKit.dress_quad_facade(root, Vector3((gx0 + gx1) * 0.5, y0, gz0), gx1 - gx0, y0, 0.0, true)
	MapKit.dress_quad_facade(root, Vector3(gx0, y0, (gz0 + gz1) * 0.5), gz1 - gz0, y0, PI * 0.5, false)
	MapKit.dress_quad_facade(root, Vector3(gx1, y0, (gz0 + gz1) * 0.5), gz1 - gz0, y0, -PI * 0.5, false)


func _hide_imported_cup() -> void:
	var cup := get_node_or_null("HoleCut") as GeometryInstance3D
	if cup == null:
		return
	cup.visible = false
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cup is MeshInstance3D:
		(cup as MeshInstance3D).material_override = MapKit.toon(Color(0.93, 0.9, 0.82))


func _punch_cup() -> void:
	var hole_point := get_node_or_null("HolePoint") as Node3D
	var green := get_node_or_null("Green") as MeshInstance3D
	if hole_point == null or green == null or green.mesh == null:
		return
	var aabb: AABB = green.mesh.get_aabb()
	var baked := green.global_transform.basis.get_scale().abs()
	var local_z0 := aabb.position.z
	var local_z1 := aabb.position.z + aabb.size.z
	if has_meta("play_z_min"):
		local_z0 = minf(local_z0, float(get_meta("play_z_min")))
	var size := Vector3(
		maxf(aabb.size.x * baked.x, 0.2),
		0.08,
		maxf((local_z1 - local_z0) * baked.z, 0.2)
	)
	var box := BoxMesh.new()
	box.size = size
	var play := MeshInstance3D.new()
	play.name = "GreenPlay"
	play.mesh = box
	play.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gen(play)
	add_child(play)
	var green_basis := green.global_transform.basis.orthonormalized()
	var top_local := Vector3(
		aabb.get_center().x,
		aabb.position.y + aabb.size.y,
		(local_z0 + local_z1) * 0.5
	)
	# Sit just under pavement / road so the two surfaces do not z-fight.
	var origin := green.to_global(top_local) - green_basis.y * (size.y * 0.5 + 0.02)
	play.global_transform = Transform3D(green_basis, origin)
	var grass := MapKit.grass(
		Color(0.27, 0.45, 0.28),
		Color(0.16, 0.32, 0.2),
		0.85,
		hole_point.global_position,
		MapKit.CUP_INNER
	).duplicate() as ShaderMaterial
	for i in mini(_gaps.size(), 3):
		var g: Dictionary = _gaps[i]
		var world := to_global(Vector3(float(g.x), 0.0, float(g.z)))
		grass.set_shader_parameter("gap%d" % i, Vector4(world.x, world.z, float(g.r), 0.0))
	play.material_override = grass
	green.visible = false
	if Engine.is_editor_hint():
		return
	_add_green_play_collision(play, hole_point.global_position)


func _build_rainbow_stairs() -> void:
	var stairs := get_node_or_null("Stairs") as MeshInstance3D
	if stairs == null:
		return
	stairs.visible = false

	var z0 := -8.0
	var z1 := -26.0
	var y0 := 0.0
	var y1 := 1.4
	var inner := _quad_inner_x()
	var width := inner * 2.0 + 0.08 if inner > 6.5 else 12.0
	var per_color := 2
	var count := RAINBOW_ORDER.size() * per_color
	var dz := (z1 - z0) / float(count)
	var dy := (y1 - y0) / float(count)
	var bot := -0.28
	for i in count:
		var z_a := z0 + dz * float(i)
		var z_b := z0 + dz * float(i + 1)
		var top := y0 + dy * float(i)
		var mat := MapKit.toon(RAINBOW_ORDER[int(floor(float(i) / float(per_color)))], Color(0, 0, 0, 0), 0, 1.0, Color(0.32, 0.52, 0.62), 0.0)
		_add_rainbow_step(i, width, top, bot, z_a, z_b, mat)
	# Continuous side strips so the ball can roll up; only the center is gapped.
	_add_stair_slope(width + 0.08, z0, z1, y0, y1)

	var rail := MapKit.toon(Color("C8C4BC"), Color("8E8A84"))
	var rail_x := width * 0.5 - 0.12
	var left_rail := MapKit.slope_box(self, 0.12, 0.1, Vector3(-rail_x, 0.72, z0), Vector3(-rail_x, 2.12, z1), rail, false)
	var right_rail := MapKit.slope_box(self, 0.12, 0.1, Vector3(rail_x, 0.72, z0), Vector3(rail_x, 2.12, z1), rail, false)
	left_rail.set_meta("no_cliff", true)
	right_rail.set_meta("no_cliff", true)
	_gen(left_rail)
	_gen(right_rail)
	_gen(MapKit.slope_collider(self, 0.2, 0.55, Vector3(-rail_x - 0.17, 0.28, z0), Vector3(-rail_x - 0.17, 1.68, z1)))
	_gen(MapKit.slope_collider(self, 0.2, 0.55, Vector3(rail_x + 0.17, 0.28, z0), Vector3(rail_x + 0.17, 1.68, z1)))
	_gen(MapKit.slab_collider(self, Vector3(13.0, 0.28, 11.2), Vector3(0.0, -0.14, -2.4)))


func _flatten_kerbs() -> void:
	for child in get_children():
		if not str(child.name).begins_with("Kerb"):
			continue
		var mesh_i := child as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null:
			continue
		mesh_i.visible = false
		var aabb: AABB = mesh_i.mesh.get_aabb()
		var size: Vector3 = aabb.size
		var center: Vector3 = aabb.position + size * 0.5
		_gen(MapKit.box(
			self,
			Vector3(size.x, 0.028, size.z),
			Vector3(center.x, 0.014, center.z),
			MapKit.toon(Color("B2ADA4"), Color("8F8A82"), 1, 0.45, Color(0.32, 0.52, 0.62), 0.0),
			CSGShape3D.OPERATION_UNION,
			false
		))


func _restyle_materials() -> void:
	for mesh_i in _meshes():
		if mesh_i.is_queued_for_deletion() or mesh_i.mesh == null:
			continue
		if str(mesh_i.name) == "Cliffs" or str(mesh_i.name) == "BumperRim" or str(mesh_i.name) == "HoleCut" or str(mesh_i.name) == "GreenPlay":
			continue
		var node_key := str(mesh_i.name).to_lower()
		for surf in mesh_i.mesh.get_surface_count():
			var src: Material = mesh_i.get_active_material(surf)
			mesh_i.set_surface_override_material(surf, _toon_from(src, node_key))


func _add_collision() -> void:
	for mesh_i in _meshes():
		_collide_one(mesh_i)


func _add_collision_async() -> void:
	var n := 0
	for mesh_i in _meshes():
		if _collide_one(mesh_i):
			n += 1
			if n % 2 == 0:
				await get_tree().process_frame


func _collide_one(mesh_i: MeshInstance3D) -> bool:
	if mesh_i == null or mesh_i.is_queued_for_deletion() or mesh_i.mesh == null:
		return false
	if not _should_collide(mesh_i):
		return false
	var phys := MapKit.putting_physics()
	var bump := MapKit.bumper_physics()
	var n := str(mesh_i.name)
	if _is_building_mesh(mesh_i):
		mesh_i.create_trimesh_collision()
		_tune_bodies(mesh_i, bump, true)
		return true
	if n == "PitchFence":
		_add_solid_boxes(mesh_i, bump, _rim_volumes(mesh_i.mesh.get_aabb(), 0.3), true)
		return true
	if _is_obstacle_mesh(mesh_i):
		var hulls: Array[AABB] = []
		hulls.append(mesh_i.mesh.get_aabb())
		_add_solid_boxes(mesh_i, bump, hulls, true)
		return true
	if n == "Green" or n == "Pavement" or n == "Road" or n == "SoccerPitch":
		_add_filtered_putting_collision(mesh_i, phys)
		return true
	mesh_i.create_trimesh_collision()
	_tune_bodies(mesh_i, phys, false)
	return true


func _add_green_play_collision(play: MeshInstance3D, hole_world: Vector3) -> void:
	var box := play.mesh as BoxMesh
	if box == null:
		return
	var size: Vector3 = box.size
	var x0 := size.x * -0.5
	var x1 := size.x * 0.5
	var z0 := size.z * -0.5
	var z1 := size.z * 0.5
	var body := StaticBody3D.new()
	body.name = "GreenBody"
	body.physics_material_override = MapKit.putting_physics()
	play.add_child(body)
	var tiles: Array[Rect2] = [Rect2(x0, z0, x1 - x0, z1 - z0)]
	var hole := play.to_local(hole_world)
	var cup_r := MapKit.CUP_OUTER
	tiles = _cut_rects(tiles, Rect2(hole.x - cup_r, hole.z - cup_r, cup_r * 2.0, cup_r * 2.0))
	for g in _gaps:
		var world := to_global(Vector3(float(g.x), play.global_position.y, float(g.z)))
		var local := play.to_local(world)
		var gr := float(g.r) + 0.22
		tiles = _cut_rects(tiles, Rect2(local.x - gr, local.z - gr, gr * 2.0, gr * 2.0))
	for tile in tiles:
		_add_green_box(
			body,
			Vector3(tile.size.x, size.y, tile.size.y),
			Vector3(tile.position.x + tile.size.x * 0.5, 0.0, tile.position.y + tile.size.y * 0.5)
		)


func _add_green_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	if size.x < 0.04 or size.y < 0.04 or size.z < 0.04:
		return
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)


func _add_filtered_putting_collision(mesh_i: MeshInstance3D, phys: PhysicsMaterial) -> void:
	_add_green_collision(mesh_i, phys)


func _add_green_collision(mesh_i: MeshInstance3D, phys: PhysicsMaterial) -> void:
	var hole_point := get_node_or_null("HolePoint") as Node3D
	var cup := Vector3.ZERO
	if hole_point != null:
		cup = hole_point.position
	var cut_r := MapKit.CUP_OUTER - 0.03
	var cut2 := cut_r * cut_r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mesh := mesh_i.mesh
	for surf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var tri_count := int(indices.size() / 3.0) if indices.size() > 0 else int(verts.size() / 3.0)
		for t in tri_count:
			var ia := 0
			var ib := 0
			var ic := 0
			if indices.size() > 0:
				ia = indices[t * 3]
				ib = indices[t * 3 + 1]
				ic = indices[t * 3 + 2]
			else:
				ia = t * 3
				ib = t * 3 + 1
				ic = t * 3 + 2
			if ic >= verts.size():
				continue
			var a: Vector3 = verts[ia]
			var b: Vector3 = verts[ib]
			var c: Vector3 = verts[ic]
			_emit_putting_tri(st, mesh_i, a, b, c, cup, cut2, 0)
	st.generate_normals()
	var cut_mesh := st.commit()
	if cut_mesh.get_surface_count() == 0:
		return
	var cut_body := StaticBody3D.new()
	cut_body.physics_material_override = phys
	var col := CollisionShape3D.new()
	col.shape = cut_mesh.create_trimesh_shape()
	cut_body.add_child(col)
	mesh_i.add_child(cut_body)
	for child in mesh_i.get_children():
		var body := child as StaticBody3D
		if body != null:
			body.physics_material_override = phys


func _emit_putting_tri(
	st: SurfaceTool,
	mesh_i: MeshInstance3D,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	cup: Vector3,
	cut2: float,
	depth: int
) -> void:
	var ga := to_local(mesh_i.to_global(a))
	var gb := to_local(mesh_i.to_global(b))
	var gc := to_local(mesh_i.to_global(c))
	var mid := (ga + gb + gc) / 3.0
	var dx := mid.x - cup.x
	var dz := mid.z - cup.z
	if dx * dx + dz * dz < cut2:
		return
	if not _tri_hits_gap(ga, gb, gc, 0.2):
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		return
	if depth >= 4:
		return
	var ab := (a + b) * 0.5
	var bc := (b + c) * 0.5
	var ca := (c + a) * 0.5
	_emit_putting_tri(st, mesh_i, a, ab, ca, cup, cut2, depth + 1)
	_emit_putting_tri(st, mesh_i, b, bc, ab, cup, cut2, depth + 1)
	_emit_putting_tri(st, mesh_i, c, ca, bc, cup, cut2, depth + 1)
	_emit_putting_tri(st, mesh_i, ab, bc, ca, cup, cut2, depth + 1)


func _should_collide(mesh_i: MeshInstance3D) -> bool:
	if not mesh_i.visible:
		return false
	var n := str(mesh_i.name)
	if n == "Green" or n == "GreenFar" or n == "HoleCut" or n == "Cliffs" or n == "Abyss" or n == "Stairs" or n == "BumperRim" or n == "GreenPlay":
		return false
	if n.begins_with("Kerb") or n.begins_with("RainbowStep"):
		return false
	return true


func _is_building_name(key: String) -> bool:
	for part in ["quad", "law", "hall", "grandstand", "boulder", "tram", "platform", "village", "brick"]:
		if key.find(part) >= 0:
			return true
	return false


func _is_building_mesh(mesh_i: MeshInstance3D) -> bool:
	var n := str(mesh_i.name)
	return FOOT_WALL_NODES.has(n) or _is_building_name(n.to_lower())


func _tune_bodies(mesh_i: Node, phys: PhysicsMaterial, walls: bool) -> void:
	for child in mesh_i.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		body.physics_material_override = phys
		body.collision_layer = 1 | 2 if walls else 1
		body.collision_mask = 0


func _is_obstacle_mesh(mesh_i: MeshInstance3D) -> bool:
	var n := str(mesh_i.name)
	return n.begins_with("Hedge") or n.begins_with("Bin") or n.begins_with("SoccerGoal")


func _add_solid_boxes(mesh_i: MeshInstance3D, phys: PhysicsMaterial, volumes: Array[AABB], walls: bool = false) -> void:
	if volumes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "%sBody" % mesh_i.name
	body.physics_material_override = phys
	body.collision_layer = 1 | 2 if walls else 1
	body.collision_mask = 0
	mesh_i.add_child(body)
	for aabb in volumes:
		_add_box_collider(body, aabb)


func _add_box_collider(body: StaticBody3D, aabb: AABB) -> void:
	if aabb.size.x < 0.08 or aabb.size.y < 0.08 or aabb.size.z < 0.08:
		return
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	col.shape = shape
	col.position = aabb.get_center()
	body.add_child(col)


func _play_aabb() -> AABB:
	return _merged_named_aabb(PLAY_NODES)


func _building_volumes(mesh_i: MeshInstance3D) -> Array[AABB]:
	var full: AABB = mesh_i.mesh.get_aabb()
	var play := _play_aabb()
	if play.size == Vector3.ZERO:
		return [full]
	var pc := play.get_center()
	var wraps: bool = (
		full.position.x < pc.x
		and full.position.x + full.size.x > pc.x
		and full.size.x > play.size.x * 0.6
	)
	if not wraps:
		return [full]
	var vols: Array[AABB] = _clip_around_play(full, play)
	if vols.is_empty():
		return [full]
	return vols


func _clip_around_play(full: AABB, play: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	var fx0 := full.position.x
	var fy0 := full.position.y
	var fz0 := full.position.z
	var fx1 := fx0 + full.size.x
	var fy1 := fy0 + maxf(full.size.y, 3.0)
	var fz1 := fz0 + full.size.z
	var px0 := play.position.x
	var pz0 := play.position.z
	var px1 := px0 + play.size.x
	var pz1 := pz0 + play.size.z
	var overlap := 0.1
	if fx0 < px0 - 0.12:
		out.append(_aabb_from(fx0, fy0, fz0, minf(fx1, px0 + overlap), fy1, fz1))
	if fx1 > px1 + 0.12:
		out.append(_aabb_from(maxf(fx0, px1 - overlap), fy0, fz0, fx1, fy1, fz1))
	if fz0 < pz0 - 0.12:
		out.append(_aabb_from(fx0, fy0, fz0, fx1, fy1, minf(fz1, pz0 + overlap)))
	if fz1 > pz1 + 0.12:
		out.append(_aabb_from(fx0, fy0, maxf(fz0, pz1 - overlap), fx1, fy1, fz1))
	return out


func _aabb_from(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> AABB:
	return AABB(Vector3(x0, y0, z0), Vector3(x1 - x0, y1 - y0, z1 - z0))


func _rim_volumes(full: AABB, thick: float) -> Array[AABB]:
	var out: Array[AABB] = []
	var x0 := full.position.x
	var y0 := full.position.y
	var z0 := full.position.z
	var x1 := x0 + full.size.x
	var y1 := y0 + maxf(full.size.y, 1.0)
	var z1 := z0 + full.size.z
	var t := clampf(thick, 0.16, 0.45)
	out.append(_aabb_from(x0, y0, z0, x0 + t, y1, z1))
	out.append(_aabb_from(x1 - t, y0, z0, x1, y1, z1))
	out.append(_aabb_from(x0 + t, y0, z0, x1 - t, y1, z0 + t))
	out.append(_aabb_from(x0 + t, y0, z1 - t, x1 - t, y1, z1))
	return out


func _meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(self, out)
	return out


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		var mesh_i := child as MeshInstance3D
		if mesh_i != null:
			out.append(mesh_i)
		_collect_meshes(child, out)


func _toon_from(src: Material, node_key: String) -> Material:
	var key := node_key
	var albedo := Color.WHITE
	if src != null:
		key = "%s %s" % [src.resource_name.to_lower(), node_key]
		var base := src as BaseMaterial3D
		if base != null:
			albedo = base.albedo_color
	if key.find("grass") >= 0 or node_key.begins_with("green") or node_key.begins_with("soccer"):
		return MapKit.grass()
	if key.find("rainbow") >= 0:
		for rainbow_key in RAINBOW:
			var rk := str(rainbow_key)
			if key.find(rk) >= 0:
				return MapKit.toon(RAINBOW[rk] as Color, Color(0, 0, 0, 0), 0, 1.0, Color(0.32, 0.52, 0.62), 0.0)
	if key.find("pavement") >= 0 or key.find("platform") >= 0 or key.find("kerb") >= 0:
		return MapKit.pavers()
	if key.find("asphalt") >= 0 or node_key == "road":
		return MapKit.toon(MapKit.ASPHALT, MapKit.ASPHALT_SHADE, 1, 1.6, Color(0.32, 0.52, 0.62), 0.0)
	if key.find("brick") >= 0:
		return MapKit.brick_wall()
	if key.find("cream") >= 0:
		return MapKit.cream_building()
	if key.find("glass") >= 0:
		return MapKit.toon(Color("6BB8D0"), Color("3A7A90"), 0, 1.0, Color("8ED4E8"), 1.0)
	if key.find("hedge") >= 0 or key.find("foliage") >= 0:
		return MapKit.toon(Color("4A7A3C"), Color("2A4A28"), 4, 1.0, Color(0.32, 0.52, 0.62), 1.0)
	if key.find("trunk") >= 0:
		return MapKit.toon(Color("C4A06A"), Color("8A6A40"))
	if key.find("metal") >= 0:
		return MapKit.toon(Color("B8B8BE"), Color("8A8A92"), 0, 1.0, Color(0.32, 0.52, 0.62), 1.0)
	if key.find("cup") >= 0:
		return MapKit.toon(Color("3A322C"))
	if key.find("white") >= 0:
		return MapKit.toon(MapKit.WHITE)
	if node_key.find("quad") >= 0:
		return MapKit.quad_brick()
	if node_key.find("law") >= 0 or node_key.find("hall") >= 0 or node_key.find("grandstand") >= 0:
		if albedo.g > albedo.r * 0.9 and albedo.b > albedo.r * 0.85:
			return MapKit.toon(Color("6BB8D0"), Color("3A7A90"), 0, 1.0, Color(0.32, 0.52, 0.62), 1.0)
		if albedo.r > 0.55 and albedo.g > 0.5:
			return MapKit.cream_building()
		return MapKit.brick_wall()
	if _is_building_name(node_key):
		return MapKit.toon(albedo, Color(0, 0, 0, 0), 0, 1.0, Color(0.32, 0.52, 0.62), 1.0)
	return MapKit.toon(albedo)
