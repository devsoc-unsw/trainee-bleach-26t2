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
	"Pavement",
	"Road",
	"Stairs",
	"SoccerPitch",
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
	_rebuild_course()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear_generated()
		_restore_imported()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		call_deferred("_rebuild_course")


func _rebuild_course() -> void:
	_clear_generated()
	_replace_blockout_trees()
	_hide_imported_cup()
	_build_rainbow_stairs()
	_flatten_kerbs()
	_restyle_materials()
	_punch_cup()
	_close_building_abyss()
	_dress_quad_west()
	if not Engine.is_editor_hint():
		_add_collision()
	_add_cliffs()
	_add_bumpers()


func _gen(node: Node) -> Node:
	if node != null:
		node.set_meta("generated", true)
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


func _replace_blockout_trees() -> void:
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
		if Engine.is_editor_hint():
			child.visible = false
		else:
			to_free.append(child)
		MapKit.tree(self, pos, 3.2 + absf(pos.x) * 0.03)
	for node in to_free:
		node.queue_free()


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
		_gen(MapKit.box(
			self,
			Vector3(w, wall_h, depth),
			Vector3(gx1 + w * 0.5, y, z_mid),
			cream,
			CSGShape3D.OPERATION_UNION,
			not Engine.is_editor_hint()
		))
	if any_l and gx0 - face_l > 0.05:
		var w := gx0 - face_l + 0.18
		_gen(MapKit.box(
			self,
			Vector3(w, wall_h, depth),
			Vector3(gx0 - w * 0.5, y, z_mid),
			cream,
			CSGShape3D.OPERATION_UNION,
			not Engine.is_editor_hint()
		))
	if any_b and gz0 - face_b > 0.04:
		var d := gz0 - face_b + 0.18
		_gen(MapKit.box(
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
	green.visible = false
	var aabb: AABB = green.mesh.get_aabb()
	var baked := green.global_transform.basis.get_scale().abs()
	var size := Vector3(
		maxf(aabb.size.x * baked.x, 0.2),
		0.08,
		maxf(aabb.size.z * baked.z, 0.2)
	)
	var box := BoxMesh.new()
	box.size = size
	var play := MeshInstance3D.new()
	play.name = "GreenPlay"
	play.mesh = box
	play.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gen(play)
	add_child(play)
	var basis := green.global_transform.basis.orthonormalized()
	var top_local := Vector3(
		aabb.get_center().x,
		aabb.position.y + aabb.size.y,
		aabb.get_center().z
	)
	# Sit just under pavement / road so the two surfaces do not z-fight.
	var origin := green.to_global(top_local) - basis.y * (size.y * 0.5 + 0.02)
	play.global_transform = Transform3D(basis, origin)
	play.material_override = MapKit.grass(
		Color(0.27, 0.45, 0.28),
		Color(0.16, 0.32, 0.2),
		0.85,
		hole_point.global_position,
		MapKit.CUP_INNER
	)
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
		var step := MapKit.box(
			self,
			Vector3(width, maxf(top - bot, 0.1), absf(z_b - z_a) + 0.02),
			Vector3(0.0, (top + bot) * 0.5, (z_a + z_b) * 0.5),
			MapKit.toon(RAINBOW_ORDER[int(floor(float(i) / float(per_color)))]),
			CSGShape3D.OPERATION_UNION,
			false
		)
		step.name = "RainbowStep_%d" % i
		step.set_meta("no_cliff", true)
		_gen(step)
	# Playable surface is the original ramp; visuals sit just under it.
	_gen(MapKit.slope_collider(self, width + 0.08, 0.32, Vector3(0.0, y0, z0), Vector3(0.0, y1, z1)))

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
			MapKit.toon(Color("B2ADA4"), Color("8F8A82"), 1, 0.45),
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
	var phys := MapKit.putting_physics()
	var bump := MapKit.bumper_physics()
	for mesh_i in _meshes():
		if mesh_i.is_queued_for_deletion() or mesh_i.mesh == null:
			continue
		if not _should_collide(mesh_i):
			continue
		if _is_building_mesh(mesh_i):
			_add_building_body(mesh_i, bump)
			continue
		if str(mesh_i.name) == "Green":
			_add_green_collision(mesh_i, phys)
			continue
		mesh_i.create_trimesh_collision()
		for child in mesh_i.get_children():
			var body := child as StaticBody3D
			if body != null:
				body.physics_material_override = bump if str(mesh_i.name).begins_with("Hedge") else phys
	_add_building_borders(bump)


func _add_green_play_collision(play: MeshInstance3D, hole_world: Vector3) -> void:
	var box := play.mesh as BoxMesh
	if box == null:
		return
	var size: Vector3 = box.size
	var x0 := size.x * -0.5
	var x1 := size.x * 0.5
	var z0 := size.z * -0.5
	var z1 := size.z * 0.5
	var hole := play.to_local(hole_world)
	var r := MapKit.CUP_OUTER
	var body := StaticBody3D.new()
	body.name = "GreenBody"
	body.physics_material_override = MapKit.putting_physics()
	play.add_child(body)
	if hole.x + r < x0 or hole.x - r > x1 or hole.z + r < z0 or hole.z - r > z1:
		_add_green_box(body, size, Vector3.ZERO)
		return
	var xl := clampf(hole.x - r, x0, x1)
	var xr := clampf(hole.x + r, x0, x1)
	var zb := clampf(hole.z - r, z0, z1)
	var zt := clampf(hole.z + r, z0, z1)
	_add_green_box(body, Vector3(xl - x0, size.y, z1 - z0), Vector3((x0 + xl) * 0.5, 0.0, (z0 + z1) * 0.5))
	_add_green_box(body, Vector3(x1 - xr, size.y, z1 - z0), Vector3((xr + x1) * 0.5, 0.0, (z0 + z1) * 0.5))
	_add_green_box(body, Vector3(xr - xl, size.y, z1 - zt), Vector3((xl + xr) * 0.5, 0.0, (zt + z1) * 0.5))
	_add_green_box(body, Vector3(xr - xl, size.y, zb - z0), Vector3((xl + xr) * 0.5, 0.0, (z0 + zb) * 0.5))


func _add_green_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	if size.x < 0.04 or size.y < 0.04 or size.z < 0.04:
		return
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)


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
			var mid := (a + b + c) / 3.0
			var dx := mid.x - cup.x
			var dz := mid.z - cup.z
			if dx * dx + dz * dz < cut2:
				continue
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	st.generate_normals()
	var cut_mesh := st.commit()
	if cut_mesh.get_surface_count() == 0:
		mesh_i.create_trimesh_collision()
	else:
		var body := StaticBody3D.new()
		body.physics_material_override = phys
		var col := CollisionShape3D.new()
		col.shape = cut_mesh.create_trimesh_shape()
		body.add_child(col)
		mesh_i.add_child(body)
	for child in mesh_i.get_children():
		var body := child as StaticBody3D
		if body != null:
			body.physics_material_override = phys


func _should_collide(mesh_i: MeshInstance3D) -> bool:
	if not mesh_i.visible:
		return false
	var n := str(mesh_i.name)
	if n == "Green" or n == "HoleCut" or n == "Cliffs" or n == "Abyss" or n == "Stairs" or n == "BumperRim" or n == "GreenPlay":
		return false
	if n.begins_with("Kerb") or n.begins_with("RainbowStep"):
		return false
	return true


func _is_building_mesh(mesh_i: MeshInstance3D) -> bool:
	return FOOT_WALL_NODES.has(str(mesh_i.name))


func _add_building_body(mesh_i: MeshInstance3D, phys: PhysicsMaterial) -> void:
	var volumes := _building_volumes(mesh_i)
	if volumes.is_empty():
		mesh_i.create_trimesh_collision()
		for child in mesh_i.get_children():
			var body := child as StaticBody3D
			if body != null:
				body.physics_material_override = phys
		return
	var body := StaticBody3D.new()
	body.name = "%sBody" % mesh_i.name
	body.physics_material_override = phys
	add_child(body)
	for aabb in volumes:
		_add_box_collider(body, aabb)


func _add_building_borders(phys: PhysicsMaterial) -> void:
	var putting := _merged_named_aabb(PUTTING_NODES)
	if putting.size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.name = "BuildingBorders"
	body.physics_material_override = phys
	add_child(body)
	var added := false
	for node_id in FOOT_WALL_NODES:
		var mesh_i := get_node_or_null(node_id) as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null:
			continue
		for aabb in _building_volumes(mesh_i):
			if _add_inner_border(body, aabb, putting):
				added = true
	if not added:
		body.queue_free()


func _add_inner_border(body: StaticBody3D, aabb: AABB, putting: AABB) -> bool:
	var pc := putting.get_center()
	var bc := aabb.get_center()
	var thick := 0.28
	var height := clampf(aabb.size.y, 1.4, 4.0)
	# Wall to the right of the corridor: inner face is min X.
	if bc.x > pc.x and aabb.position.x > pc.x - 1.0:
		var x := aabb.position.x
		var z0 := maxf(aabb.position.z, putting.position.z - 1.0)
		var z1 := minf(aabb.position.z + aabb.size.z, putting.position.z + putting.size.z + 1.0)
		if z1 - z0 < 0.6:
			return false
		_add_box_collider(body, AABB(Vector3(x - thick * 0.35, aabb.position.y, z0), Vector3(thick, height, z1 - z0)))
		return true
	# Wall to the left of the corridor: inner face is max X.
	if bc.x < pc.x and aabb.position.x + aabb.size.x < pc.x + 1.0:
		var x := aabb.position.x + aabb.size.x
		var z0 := maxf(aabb.position.z, putting.position.z - 1.0)
		var z1 := minf(aabb.position.z + aabb.size.z, putting.position.z + putting.size.z + 1.0)
		if z1 - z0 < 0.6:
			return false
		_add_box_collider(body, AABB(Vector3(x - thick * 0.65, aabb.position.y, z0), Vector3(thick, height, z1 - z0)))
		return true
	# Wall ahead (−Z): inner face is max Z (facing the tee).
	if bc.z < pc.z and aabb.position.z + aabb.size.z < pc.z:
		var z := aabb.position.z + aabb.size.z
		var x0 := maxf(aabb.position.x, putting.position.x - 1.0)
		var x1 := minf(aabb.position.x + aabb.size.x, putting.position.x + putting.size.x + 1.0)
		if x1 - x0 < 0.6:
			return false
		_add_box_collider(body, AABB(Vector3(x0, aabb.position.y, z - thick * 0.65), Vector3(x1 - x0, height, thick)))
		return true
	return false


func _add_box_collider(body: StaticBody3D, aabb: AABB) -> void:
	if aabb.size.x < 0.15 or aabb.size.y < 0.15 or aabb.size.z < 0.15:
		return
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	col.shape = shape
	col.position = aabb.get_center()
	body.add_child(col)


func _building_volumes(mesh_i: MeshInstance3D) -> Array[AABB]:
	var putting := _merged_named_aabb(PUTTING_NODES)
	var full: AABB = mesh_i.mesh.get_aabb()
	if putting.size == Vector3.ZERO:
		return [full]
	var pc := putting.get_center()
	var wraps := full.position.x < pc.x and full.position.x + full.size.x > pc.x and full.size.x > putting.size.x * 0.75
	if not wraps:
		return [full]
	return _split_wrapping_volumes(mesh_i, putting, full)


func _split_wrapping_volumes(mesh_i: MeshInstance3D, putting: AABB, full: AABB) -> Array[AABB]:
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
		aabb.position.y = full.position.y
		aabb.size.y = maxf(full.size.y, 3.0)
		if aabb.size.x > 0.45 and aabb.size.z > 0.45:
			out.append(aabb)
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
				return MapKit.toon(RAINBOW[rk] as Color)
	if key.find("pavement") >= 0 or key.find("platform") >= 0 or key.find("kerb") >= 0:
		return MapKit.pavers()
	if key.find("asphalt") >= 0 or node_key == "road":
		return MapKit.toon(MapKit.ASPHALT, MapKit.ASPHALT_SHADE, 1, 1.6)
	if key.find("brick") >= 0:
		return MapKit.brick_wall()
	if key.find("cream") >= 0:
		return MapKit.cream_building()
	if key.find("glass") >= 0:
		return MapKit.toon(Color("6BB8D0"), Color("3A7A90"), 0, 1.0, Color("8ED4E8"))
	if key.find("hedge") >= 0 or key.find("foliage") >= 0:
		return MapKit.toon(Color("4A7A3C"), Color("2A4A28"), 4, 1.0)
	if key.find("trunk") >= 0:
		return MapKit.toon(Color("C4A06A"), Color("8A6A40"))
	if key.find("metal") >= 0:
		return MapKit.toon(Color("B8B8BE"), Color("8A8A92"))
	if key.find("cup") >= 0:
		return MapKit.toon(Color("3A322C"))
	if key.find("white") >= 0:
		return MapKit.toon(MapKit.WHITE)
	if node_key.find("quad") >= 0:
		return MapKit.quad_brick()
	if node_key.find("law") >= 0 or node_key.find("hall") >= 0 or node_key.find("grandstand") >= 0:
		if albedo.g > albedo.r * 0.9 and albedo.b > albedo.r * 0.85:
			return MapKit.toon(Color("6BB8D0"), Color("3A7A90"))
		if albedo.r > 0.55 and albedo.g > 0.5:
			return MapKit.cream_building()
		return MapKit.brick_wall()
	return MapKit.toon(albedo)
