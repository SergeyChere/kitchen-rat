class_name FollowCamera
extends Node3D
## Third-person orbit camera close to the floor. Mouse looks around, the wheel zooms, walls push it in (SpringArm3D).

var target: Node3D
var distance := 0.75
var min_distance := 0.3
var max_distance := 1.8
var height := 0.12
var sensitivity := 0.25
var invert_y := false
var fov := 60.0
var yaw := PI  # 0 looks toward +Z (south)
var pitch := -16.0
var arm: SpringArm3D
var cam: Camera3D


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	var sh := SphereShape3D.new()
	sh.radius = 0.04
	arm.shape = sh
	arm.margin = 0.02
	add_child(arm)
	cam = Camera3D.new()
	cam.near = 0.02
	cam.far = 40.0
	cam.fov = 60.0
	arm.add_child(cam)
	cam.current = true


func snap(new_yaw: float) -> void:
	yaw = new_yaw
	pitch = -16.0


func _unhandled_input(e: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		yaw -= deg_to_rad(e.relative.x * sensitivity)
		pitch = clampf(pitch - e.relative.y * sensitivity * (-1.0 if invert_y else 1.0), -70.0, 20.0)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - 0.08, min_distance, max_distance)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + 0.08, min_distance, max_distance)


func _process(_dt: float) -> void:
	if target == null:
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.1:
		yaw -= look.x * 2.6 * _dt
		pitch = clampf(pitch - look.y * 120.0 * _dt, -70.0, 20.0)
	global_position = target.global_position + Vector3.UP * height
	cam.fov = fov
	rotation = Vector3(deg_to_rad(pitch), yaw + PI, 0.0)  # the camera looks along -Z; +PI makes yaw 0 look toward +Z
	arm.spring_length = distance
	if target is Rat:
		(target as Rat).cam_yaw = yaw
