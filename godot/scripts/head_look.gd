class_name HeadLook
extends SkeletonModifier3D
## She turns her head toward things: a sudden noise, food close by. Runs after the animation, on the Neck and Head
## bones (the neck takes a little of the turn, the head the rest), limited and eased so it looks alive, not robotic.

var body: Node3D
var neck := -1
var head := -1
var target := Vector3.ZERO
var weight := 0.0          # 0 = follow the animation only, 1 = look fully at target
var _yaw := 0.0
var _pitch := 0.0

const MAX_YAW := deg_to_rad(55.0)
const MAX_UP := deg_to_rad(30.0)
const MAX_DOWN := deg_to_rad(25.0)


func setup(rat: Node3D, skel: Skeleton3D) -> void:
	body = rat
	neck = skel.find_bone("Neck")
	head = skel.find_bone("Head")


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or body == null or head < 0:
		return
	var dt := minf(get_process_delta_time() if is_inside_tree() else 0.016, 0.05)
	var want_yaw := 0.0
	var want_pitch := 0.0
	if weight > 0.01:
		var hp := skel.global_transform * skel.get_bone_global_pose(head).origin
		var l: Vector3 = body.global_transform.basis.inverse() * (target - hp)
		var flat := Vector2(l.x, l.z).length()
		if flat > 0.02 or absf(l.y) > 0.02:
			want_yaw = clampf(atan2(l.x, l.z), -MAX_YAW, MAX_YAW) * weight
			want_pitch = clampf(atan2(l.y, maxf(flat, 0.001)), -MAX_DOWN, MAX_UP) * weight
	var k := clampf(dt * 7.0, 0.0, 1.0)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	if absf(_yaw) < 0.001 and absf(_pitch) < 0.001:
		return
	var inv := skel.global_basis.orthonormalized().inverse()
	var up_s := (inv * body.global_basis.y).normalized()
	var side_s := (inv * body.global_basis.x).normalized()
	for pair in [[neck, 0.35], [head, 0.65]]:
		var b: int = pair[0]
		if b < 0:
			continue
		var w: float = pair[1] if neck >= 0 else 1.0
		var gi := skel.get_bone_global_pose(b).basis.orthonormalized().inverse()
		var q := skel.get_bone_pose_rotation(b)
		# turning toward +x of the body is a turn around up by +yaw; looking up is around side by -pitch
		q = q * Quaternion((gi * up_s).normalized(), _yaw * w) * Quaternion((gi * side_s).normalized(), -_pitch * w)
		skel.set_bone_pose_rotation(b, q)
