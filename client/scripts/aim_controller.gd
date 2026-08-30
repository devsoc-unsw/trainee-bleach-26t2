extends Node3D

@export var ball: RigidBody3D
@export var camera_rig: Node3D
@export var max_drag_px: float = 220.0
@export var arrow_base_length: float = 1.0
@export var arrow_max_length: float = 5.0
@export var max_deviation_degrees: float = 3.0

var aiming: bool = false
var drag_start_screen: Vector2
var camera: Camera3D
var trajectory_mesh: MeshInstance3D
var immediate_mesh: ImmediateMesh

func _ready() -> void:
	camera = camera_rig.camera
	
	immediate_mesh = ImmediateMesh.new()
	trajectory_mesh = MeshInstance3D.new()
	trajectory_mesh.mesh = immediate_mesh
	add_child(trajectory_mesh)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trajectory_mesh.material_override = mat


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				aiming = true
				drag_start_screen = event.position
			else: # release
				if aiming:
					aiming = false
					immediate_mesh.clear_surfaces() # successful shot removes arrow
					_release_shot(event.position)
					
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if aiming:
				aiming = false
				print("Shot cancelled, right mouse button clicked")
				immediate_mesh.clear_surfaces() # shot cancel removes arrow
	
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if aiming:
			aiming = false
			print("Shot cancelled, escape button pressed")
			immediate_mesh.clear_surfaces() # shot cancel removes arrow


func _process(_delta: float) -> void:
	if aiming:
		var mouse_pos = get_viewport().get_mouse_position()
		_update_trajectory_preview(mouse_pos)


func _compute_shot(end_screen: Vector2) -> Dictionary:
	var drag_screen = end_screen - drag_start_screen
	var drag_px = drag_screen.length()
	var power = clamp(drag_px / max_drag_px, 0.0, 1.0)

	var cam_right = camera.global_transform.basis.x
	var cam_fwd = -camera.global_transform.basis.z
	cam_right.y = 0.0
	cam_fwd.y = 0.0
	cam_right = cam_right.normalized()
	cam_fwd = cam_fwd.normalized()

	var world_drag = cam_right * drag_screen.x + cam_fwd * (-drag_screen.y)
	var direction = -world_drag.normalized() if drag_px > 1.0 else Vector3.FORWARD

	return {"direction": direction, "power": power}


func _apply_yaw_deviation(direction: Vector3, max_degrees: float) -> Vector3:
	var random_degrees = randf_range(-max_degrees, max_degrees)
	return direction.rotated(Vector3.UP, deg_to_rad(random_degrees))

# aim arrow direction calculation
func _update_trajectory_preview(mouse_pos: Vector2) -> void:
	var shot = _compute_shot(mouse_pos)
	
	var jitter_degrees = shot.power * shot.power * max_deviation_degrees
	var jittered_direction = _apply_yaw_deviation(shot.direction, jitter_degrees)

	var launch_dir = jittered_direction.normalized()

	var arrow_length = lerp(arrow_base_length, arrow_max_length, shot.power)
	var start = ball.global_position
	var end = start + launch_dir * arrow_length

	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()

# 
func _release_shot(end_screen: Vector2) -> void:
	var shot = _compute_shot(end_screen)
	var deviation_degrees = shot.power * shot.power * max_deviation_degrees
	var direction = _apply_yaw_deviation(shot.direction, deviation_degrees)
	
	ball.hit(direction, shot.power)
	var dir_2d = Vector2(direction.x, direction.z)
	
