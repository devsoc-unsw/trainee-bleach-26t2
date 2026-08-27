extends Node3D

@export var target: Node3D
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 3.0
@export var max_zoom: float = 15.0
@export var min_pitch: float = -70.0
@export var max_pitch: float = -10.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var yaw: float = 0.0
var pitch: float = -30.0
var dragging: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Camera ready")
	spring_arm.spring_length = 8.0
	_update_rotation()

# Runs every physics frame, good for continuous updates to something
func _physics_process(_delta: float) -> void:
	if target:
		global_position = target.global_position

# Runs every time the user interacts with the game screen
func _input(event: InputEvent) -> void:
	
	if event is InputEventMouseButton:		
		# Mouse capabilities
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				#print("Right click")
				dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				#print("Zooming out")
				spring_arm.spring_length = clamp(
					spring_arm.spring_length - zoom_speed,
					min_zoom,
					max_zoom
				)
			MOUSE_BUTTON_WHEEL_DOWN:
				#print("Zooming in")
				spring_arm.spring_length = clamp(
					spring_arm.spring_length + zoom_speed,
					min_zoom,
					max_zoom
				)
				#print("spring_length now: ", spring_arm.spring_length)
	
	# Trackpad capabilities
	elif event is InputEventPanGesture:
		#print("zooming")
		spring_arm.spring_length = clamp(
			spring_arm.spring_length + event.delta.y * zoom_speed,
			min_zoom,
			max_zoom
		)

	elif event is InputEventMouseMotion and dragging:
		#print("Moving camera")
		yaw -= event.relative.x * orbit_speed
		pitch = clamp(pitch - event.relative.y * orbit_speed * 57.3, min_pitch, max_pitch)
		_update_rotation()


func _update_rotation() -> void:
	rotation = Vector3(deg_to_rad(pitch), yaw, 0)
