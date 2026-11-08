class_name TailSway
extends SkeletonModifier3D
## The tail lags behind the body: it swings out when she turns, lifts when she falls and flicks when she lands.
## Runs after the animation on the tail bones (Tail1 … Tail7), bending each a little more than the one before.

var body: Node3D           # the rat (yaw and velocity are read from it)
var bones: PackedInt32Array = []
var _yaw := 0.0            # body yaw last frame
var _vy := 0.0             # body vertical speed last frame
var _sx := 0.0             # sideways swing (radians at the tip), and its speed
var _svx := 0.0
var _sy := 0.0             # up/down swing, and its speed
var _svy := 0.0
var _t := 0.0


func setup(rat: Node3D, skel: Skeleton3D) -> void:
	body = rat
	for i in range(1, 8):
		var b := skel.find_bone("Tail%d" % i)
		if b >= 0:
			bones.append(b)
	_yaw = rat.rotation.y


func kick(up: float) -> void:
	_svy += up


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or body == null or bones.is_empty():
		return
	var dt := maxf(get_process_delta_time() if is_inside_tree() else 0.016, 0.001)
	dt = minf(dt, 0.05)
	_t += dt
	var yaw := body.rotation.y
	var yaw_rate := wrapf(yaw - _yaw, -PI, PI) / dt
	_yaw = yaw
	var vel: Vector3 = body.get("velocity") if body.get("velocity") != null else Vector3.ZERO
	var vy := vel.y
	var acc_y := (vy - _vy) / dt
	_vy = vy
	var speed := Vector2(vel.x, vel.z).length()
	# springs: the tail trails the turn, droops when climbing, lifts in a fall, and wags a little at a run
	var tx := clampf(-yaw_rate * 0.09, -0.9, 0.9) + sin(_t * 9.0) * clampf(speed - 0.4, 0.0, 1.0) * 0.12
	var ty := clampf(-vy * 0.35, -0.6, 0.6) - clampf(acc_y * 0.004, -0.4, 0.4)
	_svx += (tx - _sx) * 60.0 * dt
	_svx *= exp(-7.0 * dt)
	_sx += _svx * dt
	_svy += (ty - _sy) * 50.0 * dt
	_svy *= exp(-6.0 * dt)
	_sy += _svy * dt
	var inv := skel.global_basis.orthonormalized().inverse()
	var up_s := (inv * body.global_basis.y).normalized()     # bend sideways around the body's up
	var side_s := (inv * body.global_basis.x).normalized()   # bend up/down around the body's side
	var n := bones.size()
	for i in n:
		var b := bones[i]
		var w := (0.5 + float(i) / n) / n * 1.4  # the tip bends more
		var gb := skel.get_bone_global_pose(b).basis.orthonormalized()
		var gi := gb.inverse()
		var q := skel.get_bone_pose_rotation(b)
		q = q * Quaternion((gi * up_s).normalized(), _sx * w) * Quaternion((gi * side_s).normalized(), _sy * w)
		skel.set_bone_pose_rotation(b, q)
