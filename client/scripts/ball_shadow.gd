extends MeshInstance3D

@export var max_distance: float = 2.5
@export var height_bias: float = 0.012

var _parent: Node3D


func _ready() -> void:
	_parent = get_parent() as Node3D
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(_delta: float) -> void:
	if _parent == null:
		return
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = _parent.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0.0, -max_distance, 0.0))
	query.exclude = [_parent.get_rid()]
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		visible = false
		return
	visible = true
	global_position = hit.position + hit.normal * height_bias
	var up: Vector3 = hit.normal
	var right := Vector3.FORWARD.cross(up)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT.cross(up)
	right = right.normalized()
	var fwd := up.cross(right).normalized()
	global_transform.basis = Basis(right, up, fwd).scaled(Vector3.ONE * clampf(1.0 - origin.distance_to(hit.position) / max_distance, 0.35, 1.0))
