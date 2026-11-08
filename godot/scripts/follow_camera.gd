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
## From GDQuest's third-person controller (MIT): the camera follows the height of the ground she stands on, eased, not
## her body, so hops and little drops don't bob the view.
var _ground_y := INF
var _sniff_k := 0.0  # 0…1 while she sniffs: a little closer and calmer
var _hide_k := 0.0  # 0…1 while she hides: the camera sinks to the floor, peeking out with her
var _pivot_y := INF
var _run_k := 0.0    # 0…1 how fast she runs: a wider, trailing view
var _sneak_k := 0.0  # 0…1 sneaking: closer and calmer
var _trauma := 0.0   # camera shake (shake())
var _shake_t := 0.0


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
	_ground_y = INF
	_pivot_y = INF


func _unhandled_input(e: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if e is InputEventMouseMotion:
		var sens := sensitivity * lerpf(1.0, 0.5, _sniff_k)
		yaw -= deg_to_rad(e.relative.x * sens)
		pitch = pitch - e.relative.y * sens * (-1.0 if invert_y else 1.0)
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
	var rr := target as Rat
	_sniff_k = move_toward(_sniff_k, 1.0 if rr and rr.sniffing else 0.0, _dt * 3.0)
	_hide_k = move_toward(_hide_k, 1.0 if rr and rr.hidden() else 0.0, _dt * 2.5)
	# speed in the camera: a running rat gets a wider, trailing view; sneaking pulls it in close and calm
	var fast := 0.0
	if rr and rr.running and rr.moving():
		fast = clampf((rr.move_speed - rr.walk_speed) / maxf(rr.run_speed - rr.walk_speed, 0.01), 0.0, 1.0)
	_run_k = lerpf(_run_k, fast, clampf(_dt * (3.0 if fast > _run_k else 2.0), 0.0, 1.0))
	_sneak_k = move_toward(_sneak_k, 1.0 if rr and rr.sneaking and not rr.hidden() else 0.0, _dt * 2.0)
	cam.fov = clampf(fov + zoom - 8.0 * _sniff_k + 7.0 * _run_k - 4.0 * _sneak_k, 30.0, 110.0)
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
		var ty := target.global_position.y
		var grounded := rat == null or rat.is_on_floor() or rat.jumping or rat.carrier != null
		if _ground_y == INF or grounded or ty < _ground_y:
			_ground_y = ty
		var want_y := _ground_y + lerpf(lerpf(height, 0.045, _hide_k), 0.07, high)
		_pivot_y = want_y if _pivot_y == INF else lerpf(_pivot_y, want_y, clampf(_dt * 8.0, 0.0, 1.0))
		global_position = Vector3(target.global_position.x, _pivot_y, target.global_position.z)
		global_position.y = minf(global_position.y, Rat.CEILING - 0.12)
		arm.spring_length = lerpf(distance, 0.5, high) * lerpf(1.0, 0.8, _sniff_k) * lerpf(1.0, 0.6, _hide_k) * (1.0 + 0.14 * _run_k) * (1.0 - 0.12 * _sneak_k)
		if _hide_k > 0.0 and high <= 0.0:
			rotation.x = deg_to_rad(lerpf(pitch, clampf(pitch, -12.0, 6.0), _hide_k))  # a level, floor-high look
		if high > 0.0:
			rotation.x = deg_to_rad(clampf(pitch, -35.0, lerpf(hi, -2.0, high)))
		cam.near = 0.02
	if rat and rat.model:
		# hidden in the rat's-eye view, and when a wall has pushed the camera right up to her
		rat.model.visible = not first_person and cam.global_position.distance_to(global_position) > 0.2
	_tick_shake(_dt)
	if target is Rat:
		(target as Rat).cam_yaw = yaw


## Camera shake: a hard landing, a crash, being caught. trauma 0…1 adds up and fades; the shake grows with its square
## (small knocks barely move it, big ones do), as in Squirrel Eiserloh's "Juicing your cameras" talk.
func shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _tick_shake(dt: float) -> void:
	_trauma = maxf(_trauma - dt * 1.5, 0.0)
	var k := _trauma * _trauma
	if k <= 0.0001:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		cam.rotation.z = 0.0
		return
	_shake_t += dt * 28.0
	cam.h_offset = k * 0.035 * (sin(_shake_t * 1.1) + 0.6 * sin(_shake_t * 2.7 + 1.3))
	cam.v_offset = k * 0.03 * (sin(_shake_t * 1.3 + 2.1) + 0.5 * sin(_shake_t * 3.1))
	cam.rotation.z = k * 0.05 * sin(_shake_t * 0.9 + 0.7)
