class_name FollowCamera
extends Node3D
## Third-person orbit camera close to the floor. Mouse looks around, the wheel changes the field of view, walls push it
## in (SpringArm3D; when that brings it right up to her, the rat is hidden instead of filling the screen). V switches to
## the rat's-eye view (from her head).

var target: Node3D
var distance := 0.75
var min_distance := 0.3
var max_distance := 1.8
var height := 0.12
var sensitivity := 0.25
var invert_y := false
var fov := 60.0  # from the settings
var zoom := 0.0  # the wheel: degrees added to the field of view
var first_person := false
var yaw := PI  # 0 looks toward +Z (south)
var pitch := -16.0
var arm: SpringArm3D
var cam: Camera3D


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.collision_mask = 1 | 4  # the world and the ceiling
	var sh := SphereShape3D.new()
	sh.radius = 0.06  # keeps the lens a little away from walls and furniture, so it doesn't see into them
	arm.shape = sh
	arm.margin = 0.03
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
		pitch = pitch - e.relative.y * sensitivity * (-1.0 if invert_y else 1.0)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 4.0, -30.0, 40.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 4.0, -30.0, 40.0)


func _process(_dt: float) -> void:
	if target == null:
		return
	if Input.is_action_just_pressed("view") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		first_person = not first_person
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var lo := -70.0
	var hi := 45.0 if first_person else 8.0  # looking up from behind would push the camera into the floor
	if look.length() > 0.1:
		yaw -= look.x * 2.6 * _dt
		pitch = pitch - look.y * 120.0 * _dt
	pitch = clampf(pitch, lo, hi)
	cam.fov = clampf(fov + zoom, 30.0, 110.0)
	rotation = Vector3(deg_to_rad(pitch), yaw + PI, 0.0)  # the camera looks along -Z; +PI makes yaw 0 look toward +Z
	var rat := target as Rat
	if first_person and rat and rat.mouth:
		# from her eyes: a little behind and above the snout
		global_position = rat.mouth.global_position + Vector3.UP * 0.03 - rat.global_transform.basis.z * 0.05
		arm.spring_length = 0.0
		cam.near = 0.005
	else:
		# up on the cabinets, right under the ceiling: a closer, flatter view so the camera doesn't scrape along the
		# ceiling and walls (and look into them)
		var high := clampf((target.global_position.y - 1.6) / 0.5, 0.0, 1.0)
		global_position = target.global_position + Vector3.UP * lerpf(height, 0.07, high)
		global_position.y = minf(global_position.y, Rat.CEILING - 0.12)
		arm.spring_length = lerpf(distance, 0.5, high)
		if high > 0.0:
			rotation.x = deg_to_rad(clampf(pitch, -35.0, lerpf(hi, -2.0, high)))
		cam.near = 0.02
	if rat and rat.model:
		# hidden in the rat's-eye view, and when a wall has pushed the camera right up to her
		rat.model.visible = not first_person and cam.global_position.distance_to(global_position) > 0.2
	if target is Rat:
		(target as Rat).cam_yaw = yaw
