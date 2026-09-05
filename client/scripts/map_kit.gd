class_name MapKit
extends RefCounted

const TOON_SHADER: Shader = preload("res://shaders/ac_toon.gdshader")
const GRASS_SHADER: Shader = preload("res://shaders/ac_grass.gdshader")
const FOLIAGE_SHADER: Shader = preload("res://shaders/ac_foliage.gdshader")
const BARK_SHADER: Shader = preload("res://shaders/ac_bark.gdshader")
const CLIFF_SHADER: Shader = preload("res://shaders/ac_cliff.gdshader")

static var _leaf_mesh: ArrayMesh
static var _scale_mesh: ArrayMesh

const CREAM := Color("F6F1E6")
const TEAL := Color("4CB8B0")
const BRICK := Color("8A5A44")
const BRICK_SHADE := Color("6A4030")
const CONCRETE := Color("A8A49A")
const CONCRETE_SHADE := Color("7E7A72")
const ASPHALT := Color("4A4A4E")
const ASPHALT_SHADE := Color("323236")
const TRUNK := Color("C4B08A")
const FOLIAGE := Color("4F7A3E")
const FOLIAGE_SHADE := Color("355528")
const GLASS := Color("7EC8E0")
const WHITE := Color("F4F1EA")
const CUP_INNER := 0.195
const CUP_OUTER := 0.275
const CUP_DEPTH := 0.18
const MENU_CAM_POS := Vector3(0.85, 1.55, 3.45)
const MENU_CAM_LOOK := Vector3(2.85, 0.38, -0.55)
const MENU_CAM_FOV := 28.0


static func frame_menu_camera(camera: Camera3D) -> Transform3D:
	camera.fov = MENU_CAM_FOV
	camera.position = MENU_CAM_POS
	camera.look_at(MENU_CAM_LOOK, Vector3.UP)
	return camera.global_transform


static func menu_camera_orbit(t: float) -> Vector3:
	return Vector3(sin(t * 0.11) * 0.42, sin(t * 0.17) * 0.1, cos(t * 0.09) * 0.32)


static func toon(
	lit: Color,
	shade: Color = Color(0, 0, 0, 0),
	pattern: int = 0,
	pattern_scale: float = 1.0,
	pattern_color: Color = Color(0.32, 0.52, 0.62)
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", lit)
	if shade.a <= 0.0:
		shade = Color(lit.r * 0.72, lit.g * 0.7, lit.b * 0.68)
	mat.set_shader_parameter("shade", shade)
	mat.set_shader_parameter("toon_cutoff", 0.48)
	mat.set_shader_parameter("pattern", pattern)
	mat.set_shader_parameter("pattern_scale", pattern_scale)
	mat.set_shader_parameter("pattern_color", pattern_color)
	return mat


static func pavers() -> ShaderMaterial:
	return toon(CONCRETE, CONCRETE_SHADE, 1, 0.78)


static func brick_wall() -> ShaderMaterial:
	return toon(BRICK, BRICK_SHADE, 2, 0.52)


static func quad_brick() -> ShaderMaterial:
	return toon(Color("C4A57A"), Color("9A7D55"), 2, 0.34)


static func quad_plaster() -> ShaderMaterial:
	return toon(Color("D8C9A4"), Color("B8A67E"))


static func metal_silver() -> ShaderMaterial:
	return toon(Color("C5C8CE"), Color("8B9098"))


static func metal_dark() -> ShaderMaterial:
	return toon(Color("2C2E33"), Color("16181C"))


static func louver_glass() -> ShaderMaterial:
	return toon(Color("4A5A68"), Color("2A3844"), 5, 0.09, Color("1A2228"))


static func cream_building() -> ShaderMaterial:
	return toon(CREAM, Color(0.78, 0.7, 0.58), 3, 1.65, Color(0.42, 0.62, 0.72))


static func grass(
	lit: Color = Color(0.27, 0.45, 0.28),
	shade: Color = Color(0.16, 0.32, 0.2),
	check_size: float = 0.85,
	cup_pos: Vector3 = Vector3.ZERO,
	cup_radius: float = 0.0
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("grass_lit", lit)
	mat.set_shader_parameter("grass_shade", shade)
	mat.set_shader_parameter("check_size", check_size)
	mat.set_shader_parameter("cup_pos", cup_pos)
	mat.set_shader_parameter("cup_radius", cup_radius)
	return mat


static func foliage(lit: Color, shade: Color, invert_tip: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.set_shader_parameter("albedo", lit)
	mat.set_shader_parameter("shade", shade)
	mat.set_shader_parameter("wrap", 0.84)
	mat.set_shader_parameter("toon_soft", 0.3)
	mat.set_shader_parameter("invert_tip", invert_tip)
	return mat


static func bark(lit: Color, mark: Color, shade: Color, style: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BARK_SHADER
	mat.set_shader_parameter("albedo", lit)
	mat.set_shader_parameter("mark", mark)
	mat.set_shader_parameter("shade", shade)
	mat.set_shader_parameter("style", style)
	return mat


static func combiner(parent: Node3D, collision: bool = true) -> CSGCombiner3D:
	var node := CSGCombiner3D.new()
	node.use_collision = collision
	parent.add_child(node)
	return node


static func box(
	parent: Node3D,
	size: Vector3,
	pos: Vector3,
	mat: Material,
	operation: CSGShape3D.Operation = CSGShape3D.OPERATION_UNION,
	collides: Variant = null
) -> CSGBox3D:
	var node := CSGBox3D.new()
	node.size = size
	node.position = pos
	node.material = mat
	node.operation = operation
	node.use_collision = not (parent is CSGCombiner3D) if collides == null else bool(collides)
	parent.add_child(node)
	return node


static func cylinder(
	parent: Node3D,
	radius: float,
	height: float,
	pos: Vector3,
	mat: Material,
	sides: int = 12,
	operation: CSGShape3D.Operation = CSGShape3D.OPERATION_UNION,
	collides: Variant = null
) -> CSGCylinder3D:
	var node := CSGCylinder3D.new()
	node.radius = radius
	node.height = height
	node.position = pos
	node.sides = sides
	node.material = mat
	node.operation = operation
	node.use_collision = not (parent is CSGCombiner3D) if collides == null else bool(collides)
	parent.add_child(node)
	return node


static func putting_physics() -> PhysicsMaterial:
	var phys := PhysicsMaterial.new()
	phys.friction = 0.28
	phys.bounce = 0.04
	return phys


static func slope_xform(from: Vector3, to: Vector3, thickness: float) -> Transform3D:
	var mid := (from + to) * 0.5
	var to_start := from - mid
	if to_start.length_squared() < 0.0001:
		return Transform3D(Basis.IDENTITY, mid)
	var z_axis := to_start.normalized()
	var x_axis := Vector3.UP.cross(z_axis)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis, z_axis), mid - y_axis * (thickness * 0.5))


static func slope_box(
	parent: Node3D,
	width: float,
	thickness: float,
	from: Vector3,
	to: Vector3,
	mat: Material,
	collides: bool = false
) -> CSGBox3D:
	var node := CSGBox3D.new()
	node.size = Vector3(width, thickness, from.distance_to(to))
	node.material = mat
	node.use_collision = collides
	node.transform = slope_xform(from, to, thickness)
	parent.add_child(node)
	return node


static func slope_collider(
	parent: Node3D,
	width: float,
	thickness: float,
	from: Vector3,
	to: Vector3
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.physics_material_override = putting_physics()
	body.transform = slope_xform(from, to, thickness)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, from.distance_to(to))
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


static func slab_collider(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.physics_material_override = putting_physics()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


static func cup_funnel_mesh(
	inner: float = CUP_INNER,
	outer: float = CUP_OUTER,
	depth: float = CUP_DEPTH,
	segments: int = 32,
	rings: int = 12
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var ca0 := cos(a0)
		var sa0 := sin(a0)
		var ca1 := cos(a1)
		var sa1 := sin(a1)
		for r in rings:
			var u0 := float(r) / float(rings)
			var u1 := float(r + 1) / float(rings)
			var rad0 := lerpf(outer, inner, u0)
			var rad1 := lerpf(outer, inner, u1)
			var y0 := -depth * (1.0 - sqrt(maxf(0.0, 1.0 - u0 * u0)))
			var y1 := -depth * (1.0 - sqrt(maxf(0.0, 1.0 - u1 * u1)))
			var p00 := Vector3(ca0 * rad0, y0, sa0 * rad0)
			var p10 := Vector3(ca1 * rad0, y0, sa1 * rad0)
			var p01 := Vector3(ca0 * rad1, y1, sa0 * rad1)
			var p11 := Vector3(ca1 * rad1, y1, sa1 * rad1)
			_add_tri(st, p00, p01, p11)
			_add_tri(st, p00, p11, p10)
	st.generate_normals()
	return st.commit()


static func cup_wall_mesh(
	radius: float = CUP_INNER,
	top: float = 0.0,
	bottom: float = -0.42,
	segments: int = 32
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var t0 := Vector3(cos(a0) * radius, top, sin(a0) * radius)
		var t1 := Vector3(cos(a1) * radius, top, sin(a1) * radius)
		var b0 := Vector3(cos(a0) * radius, bottom, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, bottom, sin(a1) * radius)
		_add_tri(st, t0, b0, b1)
		_add_tri(st, t0, b1, t1)
	st.generate_normals()
	return st.commit()


static func cup_floor_mesh(radius: float = CUP_INNER, y: float = -0.42, segments: int = 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(0.0, y, 0.0)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, y, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y, sin(a1) * radius)
		_add_tri(st, origin, p1, p0)
	st.generate_normals()
	return st.commit()


static func cup_lip_mesh(inner: float = CUP_INNER, outer: float = CUP_OUTER, y: float = 0.004, segments: int = 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var i0 := Vector3(cos(a0) * inner, y, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, y, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, y, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, y, sin(a1) * outer)
		_add_tri(st, i0, o0, o1)
		_add_tri(st, i0, o1, i1)
	st.generate_normals()
	return st.commit()


static func putting_green_mesh(aabb: AABB, _hole: Vector3 = Vector3.ZERO, _hole_r: float = 0.0, _segments: int = 48) -> ArrayMesh:
	return putting_green_slab(aabb)


static func putting_green_slab(aabb: AABB) -> ArrayMesh:
	var x0 := aabb.position.x
	var x1 := aabb.position.x + aabb.size.x
	var z0 := aabb.position.z
	var z1 := aabb.position.z + aabb.size.z
	var top := aabb.position.y + aabb.size.y
	var bot := aabb.position.y
	if top - bot < 0.04:
		bot = top - 0.08
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_tri(st, Vector3(x0, top, z0), Vector3(x0, top, z1), Vector3(x1, top, z1))
	_add_tri(st, Vector3(x0, top, z0), Vector3(x1, top, z1), Vector3(x1, top, z0))
	_add_tri(st, Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, bot, z0))
	_add_tri(st, Vector3(x0, top, z0), Vector3(x1, bot, z0), Vector3(x0, bot, z0))
	_add_tri(st, Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x1, bot, z1))
	_add_tri(st, Vector3(x1, top, z0), Vector3(x1, bot, z1), Vector3(x1, bot, z0))
	_add_tri(st, Vector3(x1, top, z1), Vector3(x0, top, z1), Vector3(x0, bot, z1))
	_add_tri(st, Vector3(x1, top, z1), Vector3(x0, bot, z1), Vector3(x1, bot, z1))
	_add_tri(st, Vector3(x0, top, z1), Vector3(x0, top, z0), Vector3(x0, bot, z0))
	_add_tri(st, Vector3(x0, top, z1), Vector3(x0, bot, z0), Vector3(x0, bot, z1))
	st.generate_normals()
	return st.commit()


static func putting_green_collision_mesh(aabb: AABB, hole: Vector3, hole_r: float, cells: int = 28) -> ArrayMesh:
	var x0 := aabb.position.x
	var x1 := aabb.position.x + aabb.size.x
	var z0 := aabb.position.z
	var z1 := aabb.position.z + aabb.size.z
	var top := aabb.position.y + aabb.size.y
	var r2 := hole_r * hole_r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in cells:
		var xa := lerpf(x0, x1, float(ix) / float(cells))
		var xb := lerpf(x0, x1, float(ix + 1) / float(cells))
		for iz in cells:
			var za := lerpf(z0, z1, float(iz) / float(cells))
			var zb := lerpf(z0, z1, float(iz + 1) / float(cells))
			var mx := (xa + xb) * 0.5
			var mz := (za + zb) * 0.5
			var dx := mx - hole.x
			var dz := mz - hole.z
			if dx * dx + dz * dz < r2:
				continue
			var a := Vector3(xa, top, za)
			var b := Vector3(xb, top, za)
			var c := Vector3(xb, top, zb)
			var d := Vector3(xa, top, zb)
			_add_tri(st, a, d, c)
			_add_tri(st, a, c, b)
	st.generate_normals()
	return st.commit()


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_smooth_group(-1)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func cup_cut(parent: Node3D, pos: Vector3, radius: float = 0.25) -> CSGCylinder3D:
	return cylinder(
		parent,
		radius,
		0.55,
		pos,
		null,
		20,
		CSGShape3D.OPERATION_SUBTRACTION
	)


static func marker(parent: Node3D, node_name: String, pos: Vector3) -> Marker3D:
	var node := Marker3D.new()
	node.name = node_name
	node.position = pos
	parent.add_child(node)
	return node


static func label(parent: Node3D, text: String, pos: Vector3, font_size: int = 64) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.position = pos
	node.font_size = font_size
	node.pixel_size = 0.012
	node.modulate = CREAM
	node.outline_modulate = Color(0.35, 0.28, 0.22)
	node.outline_size = 6
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func dress_quad_facade(
	parent: Node3D,
	origin: Vector3,
	width: float,
	ground_y: float,
	yaw: float,
	with_entrance: bool = false
) -> Node3D:
	var face := Node3D.new()
	face.name = "QuadFacade"
	face.position = Vector3(origin.x, ground_y, origin.z)
	face.rotation.y = yaw
	parent.add_child(face)
	if width < 6.0:
		return face

	var brick := quad_brick()
	var plaster := quad_plaster()
	var silver := metal_silver()
	var dark := metal_dark()
	var glass := toon(Color("6A8A9C"), Color("3A5464"))
	var shade := toon(Color("6A5A44"), Color("4A3C30"))
	var combo := combiner(face, false)
	var half := width * 0.5
	var door_w := 3.4 if with_entrance else 0.0
	var col_h := 3.28
	var bay := 3.2

	box(combo, Vector3(width + 0.2, col_h, 0.22), Vector3(0.0, col_h * 0.5, -0.72), shade, CSGShape3D.OPERATION_UNION, false)
	box(combo, Vector3(width + 0.15, 0.18, 1.05), Vector3(0.0, col_h + 0.05, 0.18), brick, CSGShape3D.OPERATION_UNION, false)

	var x := -half + 1.15
	while x <= half - 0.7:
		var in_door := with_entrance and absf(x) < door_w * 0.52
		if not in_door:
			box(combo, Vector3(0.78, col_h, 0.68), Vector3(x, col_h * 0.5, 0.34), brick, CSGShape3D.OPERATION_UNION, false)
			cylinder(combo, 0.15, col_h - 0.12, Vector3(x, col_h * 0.5, -0.12), silver, 10, CSGShape3D.OPERATION_UNION, false)
		x += bay

	if with_entrance:
		box(combo, Vector3(door_w, 2.55, 0.16), Vector3(0.0, 1.28, -0.52), toon(Color("3A322C"), Color("221C18")), CSGShape3D.OPERATION_UNION, false)
		box(combo, Vector3(door_w + 0.35, 0.16, 0.28), Vector3(0.0, 2.62, -0.28), plaster, CSGShape3D.OPERATION_UNION, false)
		var sign := label(face, "Quadrangle West", Vector3(0.0, 2.95, 0.22), 42)
		sign.rotation.y = PI
		sign.modulate = Color("F4EFE4")

	box(combo, Vector3(width + 0.1, 0.12, 0.58), Vector3(0.0, col_h + 0.16, 0.28), plaster, CSGShape3D.OPERATION_UNION, false)
	_quad_rail(combo, width, col_h + 0.22, dark, glass)

	box(combo, Vector3(width + 0.1, 0.32, 0.1), Vector3(0.0, 6.05, 0.06), plaster, CSGShape3D.OPERATION_UNION, false)
	box(combo, Vector3(width + 0.1, 0.32, 0.1), Vector3(0.0, 8.48, 0.06), plaster, CSGShape3D.OPERATION_UNION, false)

	var win := louver_glass()
	var frame := dark
	var storeys: Array[float] = [4.15, 6.55]
	for storey in storeys:
		var wx := -half + 1.35
		while wx <= half - 1.2:
			var skip_door: bool = with_entrance and storey < 5.0 and absf(wx) < door_w * 0.55
			var skip_bay: bool = with_entrance and storey > 5.5 and absf(wx) < 2.4
			if not skip_door and not skip_bay:
				box(combo, Vector3(0.5, 1.55, 0.05), Vector3(wx, storey + 0.78, 0.05), frame, CSGShape3D.OPERATION_UNION, false)
				box(combo, Vector3(0.4, 1.42, 0.04), Vector3(wx, storey + 0.78, 0.08), win, CSGShape3D.OPERATION_UNION, false)
			wx += 1.55

	if with_entrance:
		box(combo, Vector3(4.7, 0.1, 0.78), Vector3(0.0, 6.42, 0.42), dark, CSGShape3D.OPERATION_UNION, false)
		box(combo, Vector3(4.55, 1.05, 0.06), Vector3(0.0, 6.98, 0.78), glass, CSGShape3D.OPERATION_UNION, false)
		box(combo, Vector3(4.7, 0.08, 0.78), Vector3(0.0, 7.52, 0.42), dark, CSGShape3D.OPERATION_UNION, false)
		box(combo, Vector3(0.08, 1.1, 0.78), Vector3(-2.3, 6.97, 0.42), dark, CSGShape3D.OPERATION_UNION, false)
		box(combo, Vector3(0.08, 1.1, 0.78), Vector3(2.3, 6.97, 0.42), dark, CSGShape3D.OPERATION_UNION, false)
		cylinder(combo, 0.22, 0.42, Vector3(-1.1, 6.68, 0.28), toon(FOLIAGE, FOLIAGE_SHADE), 8, CSGShape3D.OPERATION_UNION, false)
		cylinder(combo, 0.18, 0.36, Vector3(1.25, 6.64, 0.22), toon(FOLIAGE, FOLIAGE_SHADE), 8, CSGShape3D.OPERATION_UNION, false)

	box(combo, Vector3(width - 0.4, 1.45, 0.1), Vector3(0.0, 9.45, 0.08), toon(Color("5A7384"), Color("2E4452")), CSGShape3D.OPERATION_UNION, false)
	box(combo, Vector3(width + 0.35, 0.2, 0.95), Vector3(0.0, 10.28, 0.22), dark, CSGShape3D.OPERATION_UNION, false)
	var bx := -half + 1.4
	while bx <= half - 1.2:
		box(combo, Vector3(0.08, 0.38, 0.55), Vector3(bx, 10.02, 0.28), dark, CSGShape3D.OPERATION_UNION, false)
		bx += 3.2
	return face


static func _quad_rail(combo: Node3D, width: float, y: float, dark: Material, glass: Material) -> void:
	var half := width * 0.5
	box(combo, Vector3(width + 0.05, 0.05, 0.5), Vector3(0.0, y, 0.28), dark, CSGShape3D.OPERATION_UNION, false)
	box(combo, Vector3(width + 0.05, 0.04, 0.5), Vector3(0.0, y + 0.82, 0.28), dark, CSGShape3D.OPERATION_UNION, false)
	box(combo, Vector3(width + 0.02, 0.72, 0.03), Vector3(0.0, y + 0.42, 0.48), glass, CSGShape3D.OPERATION_UNION, false)
	var px := -half + 0.8
	while px <= half - 0.6:
		box(combo, Vector3(0.05, 0.86, 0.05), Vector3(px, y + 0.43, 0.48), dark, CSGShape3D.OPERATION_UNION, false)
		px += 1.55


static func menu_backdrop(world: Node3D) -> void:
	var ground := combiner(world, false)
	box(ground, Vector3(160, 0.2, 160), Vector3(4, 0.1, -6), grass())
	var wood := toon(Color("6B4428"), Color("4A2E1A"))
	box(world, Vector3(22, 0.45, 0.45), Vector3(2, 0.32, 4.2), wood, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(0.45, 0.45, 28), Vector3(-8.6, 0.32, -6), wood, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(0.45, 0.45, 28), Vector3(12.4, 0.32, -8), wood, CSGShape3D.OPERATION_UNION, false)
	for pos in [
		Vector3(13.2, 0.2, -7), Vector3(-10.5, 0.2, -8), Vector3(16.0, 0.2, -16),
	]:
		tree(world, pos, 3.4 + absf(pos.x) * 0.04)
	box(world, Vector3(8.5, 5.5, 4.2), Vector3(2.5, 2.85, -22), brick_wall(), CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(5.5, 3.2, 0.25), Vector3(2.5, 2.6, -19.85), toon(GLASS), CSGShape3D.OPERATION_UNION, false)
	menu_horizon(world)


static func menu_horizon(world: Node3D) -> void:
	var cream := cream_building()
	var brick := brick_wall()
	# Wide far buildings so the sky ground never reads as a grey void.
	box(world, Vector3(90, 26, 10), Vector3(4, 12.5, -36), cream, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(22, 18, 8), Vector3(-18, 8.6, -30), brick, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(18, 14, 7), Vector3(24, 6.6, -31), brick, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(10, 22, 70), Vector3(-42, 10.5, -8), cream, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(10, 20, 70), Vector3(50, 9.5, -10), cream, CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(14, 8, 0.35), Vector3(-8, 8.2, -31.2), toon(GLASS), CSGShape3D.OPERATION_UNION, false)
	box(world, Vector3(16, 7, 0.35), Vector3(16, 10.4, -31.2), toon(GLASS), CSGShape3D.OPERATION_UNION, false)


static func cliff() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLIFF_SHADER
	mat.set_shader_parameter("dirt", Color("6B4A2C"))
	mat.set_shader_parameter("rock", Color("8A6A44"))
	mat.set_shader_parameter("moss", Color("3F4A28"))
	mat.set_shader_parameter("abyss", Color(0.02, 0.015, 0.01))
	return mat


static func append_mesh_cliffs(
	st: SurfaceTool,
	mesh: Mesh,
	xform: Transform3D,
	cup: Vector3,
	drop: float = 16.0,
	shared: Variant = null,
	outer_only: bool = false
) -> void:
	var bag: Dictionary = shared if shared is Dictionary else {"edges": {}, "centroid": Vector3.ZERO, "count": 0}
	var owns := not (shared is Dictionary)
	var edges: Dictionary = bag.get("edges", {})
	var centroid: Vector3 = bag.get("centroid", Vector3.ZERO)
	var count: int = int(bag.get("count", 0))
	var world_aabb := AABB()
	var have_aabb := false
	if outer_only:
		world_aabb = xform * mesh.get_aabb()
		have_aabb = true
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
			var a := xform * verts[ia]
			var b := xform * verts[ib]
			var c := xform * verts[ic]
			var n := (b - a).cross(c - a)
			if n.y <= 0.12:
				continue
			centroid += (a + b + c)
			count += 3
			if have_aabb:
				if _edge_on_aabb_rim(a, b, world_aabb, 0.4):
					_tally_edge(edges, a, b)
				if _edge_on_aabb_rim(b, c, world_aabb, 0.4):
					_tally_edge(edges, b, c)
				if _edge_on_aabb_rim(c, a, world_aabb, 0.4):
					_tally_edge(edges, c, a)
			else:
				_tally_edge(edges, a, b)
				_tally_edge(edges, b, c)
				_tally_edge(edges, c, a)
	if not owns:
		bag["edges"] = edges
		bag["centroid"] = centroid
		bag["count"] = count
		return
	if count <= 0:
		return
	_emit_cliffs(st, edges, centroid / float(count), cup, drop)


static func append_box_cliffs(
	st: SurfaceTool,
	size: Vector3,
	xform: Transform3D,
	cup: Vector3,
	drop: float = 16.0,
	shared: Variant = null
) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var corners: Array[Vector3] = [
		xform * Vector3(-hx, hy, -hz),
		xform * Vector3(hx, hy, -hz),
		xform * Vector3(hx, hy, hz),
		xform * Vector3(-hx, hy, hz),
	]
	var bag: Dictionary = shared if shared is Dictionary else {"edges": {}, "centroid": Vector3.ZERO, "count": 0}
	var owns := not (shared is Dictionary)
	var edges: Dictionary = bag.get("edges", {})
	var centroid: Vector3 = bag.get("centroid", Vector3.ZERO)
	var count: int = int(bag.get("count", 0))
	for i in 4:
		centroid += corners[i]
		count += 1
		_tally_edge(edges, corners[i], corners[(i + 1) % 4])
	if not owns:
		bag["edges"] = edges
		bag["centroid"] = centroid
		bag["count"] = count
		return
	if count <= 0:
		return
	_emit_cliffs(st, edges, centroid / float(count), cup, drop)


static func emit_shared_cliffs(st: SurfaceTool, shared: Dictionary, cup: Vector3, drop: float = 16.0) -> void:
	var count := int(shared.get("count", 0))
	if count <= 0:
		return
	_emit_cliffs(st, shared.get("edges", {}), shared["centroid"] / float(count), cup, drop)


static func _emit_cliffs(st: SurfaceTool, edges: Dictionary, centroid: Vector3, cup: Vector3, drop: float) -> void:
	for key in edges:
		var info: Dictionary = edges[key]
		if int(info["n"]) != 1:
			continue
		var a: Vector3 = info["a"]
		var b: Vector3 = info["b"]
		if _seg_near_cup(a, b, cup, 1.8):
			continue
		if _line_through_cup(a, b, cup, 0.6):
			continue
		if a.distance_to(b) < 0.04:
			continue
		_cliff_quad(st, a, b, drop, centroid)


static func _edge_on_aabb_rim(a: Vector3, b: Vector3, aabb: AABB, slop: float) -> bool:
	var sides_a := _aabb_rim_sides(a, aabb, slop)
	var sides_b := _aabb_rim_sides(b, aabb, slop)
	if sides_a == 0 or sides_b == 0:
		return false
	return (sides_a & sides_b) != 0


static func _aabb_rim_sides(p: Vector3, aabb: AABB, slop: float) -> int:
	var mask := 0
	if absf(p.x - aabb.position.x) <= slop:
		mask |= 1
	if absf(p.x - (aabb.position.x + aabb.size.x)) <= slop:
		mask |= 2
	if absf(p.z - aabb.position.z) <= slop:
		mask |= 4
	if absf(p.z - (aabb.position.z + aabb.size.z)) <= slop:
		mask |= 8
	return mask


static func _seg_near_cup(a: Vector3, b: Vector3, cup: Vector3, radius: float) -> bool:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ac := Vector3(cup.x - a.x, 0.0, cup.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.0001 else clampf(ac.dot(ab) / len2, 0.0, 1.0)
	var closest := Vector3(a.x, 0.0, a.z) + ab * t
	return closest.distance_to(Vector3(cup.x, 0.0, cup.z)) < radius


static func _line_through_cup(a: Vector3, b: Vector3, cup: Vector3, radius: float) -> bool:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(cup.x - a.x, cup.z - a.z)
	var seg_len := ab.length()
	if seg_len < 0.001:
		return ac.length() < radius
	return absf(ab.x * ac.y - ab.y * ac.x) / seg_len < radius


static func emit_void_bumpers(parent: Node3D, shared: Dictionary, cup: Vector3) -> void:
	var count := int(shared.get("count", 0))
	if count <= 0:
		return
	var centroid: Vector3 = shared["centroid"] / float(count)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Bumpers"
	body.physics_material_override = bumper_physics()
	parent.add_child(body)
	var added := 0
	var edges: Dictionary = shared.get("edges", {})
	for key in edges:
		var info: Dictionary = edges[key]
		if int(info["n"]) != 1:
			continue
		var a: Vector3 = info["a"]
		var b: Vector3 = info["b"]
		var length := a.distance_to(b)
		if length < 0.06:
			continue
		if _seg_near_cup(a, b, cup, CUP_OUTER + 0.15):
			continue
		var mid := (a + b) * 0.5
		var along := b - a
		var outward := Vector3(-along.z, 0.0, along.x)
		if outward.length_squared() < 0.0001:
			continue
		outward = outward.normalized()
		if outward.dot(mid - Vector3(centroid.x, mid.y, centroid.z)) < 0.0:
			outward = -outward
		var size := Vector3(0.12, 0.14, length + 0.04)
		var xf := _bumper_xform(a, b, outward, size.y)
		_add_oriented_box_mesh(st, xf, size)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.transform = xf
		body.add_child(col)
		added += 1
	if added == 0:
		body.queue_free()
		return
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "BumperRim"
	mesh_i.mesh = mesh
	mesh_i.material_override = toon(Color("E8DFD0"), Color("C4B8A6"))
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_i)


static func bumper_physics() -> PhysicsMaterial:
	var phys := PhysicsMaterial.new()
	phys.friction = 0.22
	phys.bounce = 0.2
	return phys


static func _bumper_xform(a: Vector3, b: Vector3, outward: Vector3, height: float) -> Transform3D:
	var along := b - a
	var z_axis := along.normalized()
	var x_axis := Vector3(outward.x, 0.0, outward.z)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.UP.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	var mid := (a + b) * 0.5
	var origin := mid + y_axis * (height * 0.42) - x_axis * 0.02
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


static func _add_oriented_box_mesh(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p: Array[Vector3] = [
		xf * Vector3(-hx, -hy, -hz),
		xf * Vector3(hx, -hy, -hz),
		xf * Vector3(hx, -hy, hz),
		xf * Vector3(-hx, -hy, hz),
		xf * Vector3(-hx, hy, -hz),
		xf * Vector3(hx, hy, -hz),
		xf * Vector3(hx, hy, hz),
		xf * Vector3(-hx, hy, hz),
	]
	_add_mesh_quad(st, p[0], p[1], p[2], p[3])
	_add_mesh_quad(st, p[4], p[7], p[6], p[5])
	_add_mesh_quad(st, p[0], p[4], p[5], p[1])
	_add_mesh_quad(st, p[3], p[2], p[6], p[7])
	_add_mesh_quad(st, p[0], p[3], p[7], p[4])
	_add_mesh_quad(st, p[1], p[5], p[6], p[2])


static func _add_mesh_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_smooth_group(-1)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _tally_edge(edges: Dictionary, a: Vector3, b: Vector3) -> void:
	var ka := _qkey(a)
	var kb := _qkey(b)
	var key := _ekey(ka, kb)
	if edges.has(key):
		edges[key]["n"] = int(edges[key]["n"]) + 1
	else:
		edges[key] = {"n": 1, "a": a, "b": b}


static func _qkey(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 40.0), roundi(v.y * 40.0), roundi(v.z * 40.0))


static func _ekey(a: Vector3i, b: Vector3i) -> String:
	if a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z <= b.z))):
		return "%d:%d:%d|%d:%d:%d" % [a.x, a.y, a.z, b.x, b.y, b.z]
	return "%d:%d:%d|%d:%d:%d" % [b.x, b.y, b.z, a.x, a.y, a.z]


static func _cliff_quad(st: SurfaceTool, a: Vector3, b: Vector3, drop: float, centroid: Vector3) -> void:
	var a2 := a + Vector3(0.0, -drop, 0.0)
	var b2 := b + Vector3(0.0, -drop, 0.0)
	var mid := (a + b) * 0.5
	var edge := b - a
	var outward := Vector3(-edge.z, 0.0, edge.x)
	if outward.dot(mid - centroid) < 0.0:
		var tmp := a
		a = b
		b = tmp
		tmp = a2
		a2 = b2
		b2 = tmp
	var u0 := a.x + a.z
	var u1 := b.x + b.z
	st.set_smooth_group(-1)
	st.set_uv(Vector2(u0, 0.0))
	st.add_vertex(a)
	st.set_uv(Vector2(u1, 0.0))
	st.add_vertex(b)
	st.set_uv(Vector2(u1, 1.0))
	st.add_vertex(b2)
	st.set_uv(Vector2(u0, 0.0))
	st.add_vertex(a)
	st.set_uv(Vector2(u1, 1.0))
	st.add_vertex(b2)
	st.set_uv(Vector2(u0, 1.0))
	st.add_vertex(a2)


static func tree(parent: Node3D, pos: Vector3, height: float = 3.4) -> void:
	_ensure_tree_meshes()
	var root := Node3D.new()
	root.position = pos
	root.set_meta("generated", true)
	parent.add_child(root)

	var pine := int(absf(pos.x * 11.0 + pos.z * 5.0)) % 3 == 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(pos.x, pos.z))
	var trunk_h := height * (0.42 if pine else 0.36)
	var bark_mat := bark(
		Color("C8A46E") if not pine else Color("6E4630"),
		Color("7A5230") if not pine else Color("C4A07A"),
		Color("8A6844") if not pine else Color("4A2E20"),
		1 if pine else 0
	)

	var lean_ang := rng.randf() * TAU
	var lean := Vector3(cos(lean_ang), 0.0, sin(lean_ang)) * trunk_h * rng.randf_range(0.16, 0.4)
	var wobble := rng.randf_range(0.55, 1.15)
	var trunk := MeshInstance3D.new()
	trunk.mesh = _build_trunk_mesh(
		trunk_h,
		0.22 if pine else 0.3,
		0.08 if pine else 0.1,
		lean,
		wobble,
		rng
	)
	trunk.material_override = bark_mat
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trunk)

	var mid := _trunk_center(0.48, trunk_h, lean, wobble)
	var mid_dir := (_trunk_center(0.62, trunk_h, lean, wobble) - mid).normalized()
	var side := Vector3(-mid_dir.z, 0.15, mid_dir.x).normalized()
	_branch_stub(root, mid + side * 0.04, (side + Vector3(0, 0.45, 0)).normalized(), 0.28 if pine else 0.38, bark_mat, rng)
	if not pine:
		_branch_stub(root, _trunk_center(0.66, trunk_h, lean, wobble), (-side * 0.7 + Vector3(0, 0.5, 0.2)).normalized(), 0.26, bark_mat, rng)

	_blob(root, 0.34 if pine else 0.4, Vector3(0, 0.07, 0), bark_mat, Vector3(1.2, 0.38, 1.2))
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf() * 0.2
		_blob(
			root,
			0.12 if pine else 0.14,
			Vector3(cos(a) * 0.22, 0.05, sin(a) * 0.22),
			bark_mat,
			Vector3(1.15, 0.42, 1.15)
		)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.2
	shape.height = trunk_h
	col.shape = shape
	col.position = Vector3(0, trunk_h * 0.5, 0)
	body.add_child(col)
	root.add_child(body)

	var canopy := Node3D.new()
	canopy.position = _trunk_center(1.0, trunk_h, lean, wobble)
	root.add_child(canopy)
	if pine:
		_pine_canopy(canopy, height, rng)
	else:
		_round_canopy(canopy, height, rng)


static func _blob(parent: Node3D, radius: float, pos: Vector3, mat: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 22
	mesh.rings = 14
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.scale = scale
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func _trunk_center(t: float, height: float, lean: Vector3, wobble: float) -> Vector3:
	var side := lean * sin(t * PI * 0.92) * (0.18 + 0.82 * t)
	var perp := Vector3(-lean.z, 0.0, lean.x)
	if perp.length_squared() > 0.0001:
		side += perp.normalized() * sin(t * PI * wobble) * lean.length() * 0.3
	return Vector3(0.0, t * height, 0.0) + side


static func _build_trunk_mesh(
	height: float,
	bottom_r: float,
	top_r: float,
	lean: Vector3,
	wobble: float,
	rng: RandomNumberGenerator
) -> ArrayMesh:
	var rings := 16
	var segs := 14
	var bulge := rng.randf_range(0.1, 0.22)
	var lump_phase := rng.randf() * TAU
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for j in rings:
		var t := float(j) / float(rings - 1)
		var center := _trunk_center(t, height, lean, wobble)
		var flare := 1.0 + pow(1.0 - t, 2.15) * 0.72
		var mid := 1.0 + bulge * sin(clampf(t * 1.2, 0.0, 1.0) * PI)
		var taper := lerpf(1.0, top_r / maxf(bottom_r, 0.04), t * 0.55 + t * t * 0.45)
		var rad := bottom_r * flare * mid * taper
		var oval := 1.05 + 0.1 * sin(t * 3.8 + lump_phase)
		for i in segs:
			var a := TAU * float(i) / float(segs)
			var lump := 1.0 + 0.1 * sin(a * 3.0 + t * 5.2 + lump_phase)
			verts.append(center + Vector3(cos(a) * rad * oval * lump, 0.0, sin(a) * rad * lump))
	for j in rings - 1:
		for i in segs:
			var i2 := (i + 1) % segs
			var a := verts[j * segs + i]
			var b := verts[j * segs + i2]
			var c := verts[(j + 1) * segs + i]
			var d := verts[(j + 1) * segs + i2]
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	st.index()
	return st.commit()


static func _branch_stub(
	parent: Node3D,
	origin: Vector3,
	dir: Vector3,
	length: float,
	mat: Material,
	rng: RandomNumberGenerator
) -> void:
	if dir.length_squared() < 0.001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.028 * rng.randf_range(0.85, 1.15)
	mesh.bottom_radius = 0.072 * rng.randf_range(0.9, 1.15)
	mesh.height = length
	mesh.radial_segments = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d := dir.normalized()
	node.transform = Transform3D(_orient(d, rng.randf() * TAU), origin + d * length * 0.42)
	parent.add_child(node)
	_blob(parent, 0.055, origin + d * length * 0.95, mat, Vector3(1.15, 0.65, 1.15))


static func _round_canopy(root: Node3D, height: float, rng: RandomNumberGenerator) -> void:
	var s := height / 3.4
	var lit := foliage(Color("4E8A46"), Color("2A5A30"))
	var deep := foliage(Color("3E7440"), Color("244A2C"))
	_blob(root, 0.38 * s, Vector3(0.0, 0.04 * s, 0.0), deep, Vector3(1.15, 0.82, 1.15))
	var clusters: Array[Dictionary] = [
		{"c": Vector3(-0.58 * s, 0.16 * s, 0.1 * s), "r": 0.78 * s},
		{"c": Vector3(0.55 * s, 0.14 * s, -0.12 * s), "r": 0.82 * s},
		{"c": Vector3(0.02 * s, 0.62 * s, 0.04 * s), "r": 0.7 * s},
	]
	for cluster in clusters:
		var cluster_c: Vector3 = cluster["c"]
		var cluster_r: float = cluster["r"]
		_blob(root, cluster_r * 0.72, cluster_c, deep, Vector3(1.04, 0.94, 1.04))
		_scatter_leaves(root, cluster_c, cluster_r * 0.92, 34, 0.42 * s, lit, rng)


static func _pine_canopy(root: Node3D, height: float, rng: RandomNumberGenerator) -> void:
	var s := height / 3.4
	var green := foliage(Color("4E8A4A"), Color("2A5A32"), 0.2)
	_blob(root, 0.36 * s, Vector3(0.0, 0.06 * s, 0.0), green, Vector3(1.12, 0.8, 1.12))
	_blob(root, 0.5 * s, Vector3(0.0, 0.38 * s, 0.0), green, Vector3(1.05, 0.92, 1.05))
	_blob(root, 0.28 * s, Vector3(0.0, 0.88 * s, 0.0), green, Vector3(1.0, 1.05, 1.0))
	_scatter_scales(root, Vector3(0, 0.55 * s, 0), 0.28 * s, 0.06 * s, 12, 0.5 * s, green, rng, 0.12)
	_scatter_scales(root, Vector3(0, 0.42 * s, 0), 0.55 * s, 0.08 * s, 18, 0.62 * s, green, rng, 0.16)
	_scatter_scales(root, Vector3(0, 0.22 * s, 0), 0.82 * s, 0.08 * s, 22, 0.72 * s, green, rng, 0.2, PI / 22.0)
	_scatter_scales(root, Vector3(0, 1.05 * s, 0), 0.16 * s, 0.04 * s, 8, 0.4 * s, green, rng, 0.1)
	_scatter_scales(root, Vector3(0, 0.88 * s, 0), 0.38 * s, 0.06 * s, 14, 0.52 * s, green, rng, 0.14, PI / 14.0)
	_scatter_scales(root, Vector3(0, 0.7 * s, 0), 0.58 * s, 0.07 * s, 16, 0.58 * s, green, rng, 0.18)


static func _scatter_leaves(
	parent: Node3D,
	center: Vector3,
	radius: float,
	count: int,
	leaf_scale: float,
	mat: Material,
	rng: RandomNumberGenerator
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _leaf_mesh
	mm.instance_count = count
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 4:
		guard += 1
		var dir := _fib_dir(guard + rng.randi_range(0, 8), count + 12)
		if dir.y < -0.72:
			continue
		var basis := _orient(dir, rng.randf() * TAU)
		var scale := Vector3.ONE * leaf_scale * rng.randf_range(0.82, 1.18)
		var xform := Transform3D(basis.scaled(scale), center + dir * radius * rng.randf_range(0.78, 1.02))
		mm.set_instance_transform(placed, xform)
		var lift := clampf(dir.y * 0.18 + 0.82, 0.72, 0.98)
		mm.set_instance_color(placed, Color(lift, lift, lift, 1.0))
		placed += 1
	mm.instance_count = placed
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _scatter_scales(
	parent: Node3D,
	center: Vector3,
	radius: float,
	y_jitter: float,
	count: int,
	scale_len: float,
	mat: Material,
	rng: RandomNumberGenerator,
	outward_pull: float = 0.18,
	phase: float = 0.0
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _scale_mesh
	mm.instance_count = count
	for i in count:
		var a := TAU * float(i) / float(count) + phase + rng.randf() * 0.08
		var outward := Vector3(cos(a), 0.0, sin(a))
		var hang := (Vector3(0, -1, 0) + outward * outward_pull).normalized()
		var origin := (
			center
			+ outward * radius * rng.randf_range(0.52, 0.78)
			+ Vector3(0, 0.12 * scale_len + rng.randf_range(-y_jitter, y_jitter), 0)
		)
		var basis := _orient(hang, rng.randf() * TAU)
		var sc := Vector3.ONE * scale_len * rng.randf_range(0.9, 1.12)
		mm.set_instance_transform(i, Transform3D(basis.scaled(sc), origin))
		var tip := rng.randf_range(0.88, 1.0)
		mm.set_instance_color(i, Color(tip, tip, tip, 1.0))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _orient(dir: Vector3, roll: float) -> Basis:
	var y_axis := dir.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).rotated(y_axis, roll)


static func _fib_dir(i: int, n: int) -> Vector3:
	var y := 1.0 - (float(i % n) / float(maxi(n - 1, 1))) * 2.0
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var theta := PI * (3.0 - sqrt(5.0)) * float(i)
	return Vector3(cos(theta) * r, y, sin(theta) * r)


static func _ensure_tree_meshes() -> void:
	if _leaf_mesh != null:
		return
	_leaf_mesh = _build_lobe_leaf()
	_scale_mesh = _build_teardrop()


static func _lobe_radius(theta: float) -> float:
	var a := theta - PI * 0.5
	var d0 := absf(wrapf(a, -PI, PI))
	var d1 := absf(wrapf(a - 2.18, -PI, PI))
	var d2 := absf(wrapf(a + 2.18, -PI, PI))
	return 0.12 + 0.78 * exp(-d0 * d0 * 2.35) + 0.6 * exp(-d1 * d1 * 2.55) + 0.6 * exp(-d2 * d2 * 2.55)


static func _build_lobe_leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var thick := 0.055
	var front: Array[Vector3] = [Vector3(0, 0.08, thick)]
	var back: Array[Vector3] = [Vector3(0, 0.08, -thick)]
	for i in segs:
		var t := TAU * float(i) / float(segs)
		var r := _lobe_radius(t)
		var p := Vector3(cos(t) * r, sin(t) * r, 0.0)
		front.append(p + Vector3(0, 0, thick))
		back.append(p - Vector3(0, 0, thick))
	for i in segs:
		var n := 1 + ((i + 1) % segs)
		st.add_vertex(front[0])
		st.add_vertex(front[1 + i])
		st.add_vertex(front[n])
		st.add_vertex(back[0])
		st.add_vertex(back[n])
		st.add_vertex(back[1 + i])
		st.add_vertex(front[1 + i])
		st.add_vertex(back[1 + i])
		st.add_vertex(front[n])
		st.add_vertex(front[n])
		st.add_vertex(back[1 + i])
		st.add_vertex(back[n])
	st.generate_normals()
	st.index()
	return st.commit()


static func _build_teardrop() -> ArrayMesh:
	var profile := PackedVector2Array([
		Vector2(0.04, 0.0),
		Vector2(0.18, -0.1),
		Vector2(0.3, -0.34),
		Vector2(0.26, -0.62),
		Vector2(0.14, -0.9),
		Vector2(0.0, -1.05),
	])
	var segs := 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for p in profile:
		for i in segs:
			var a := TAU * float(i) / float(segs)
			verts.append(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
	var rings := profile.size()
	for j in rings - 1:
		for i in segs:
			var i2 := (i + 1) % segs
			var a := verts[j * segs + i]
			var b := verts[j * segs + i2]
			var c := verts[(j + 1) * segs + i]
			var d := verts[(j + 1) * segs + i2]
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	st.index()
	return st.commit()
