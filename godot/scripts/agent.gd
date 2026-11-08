class_name Agent
extends Node3D
## Something that walks the A* grid on the floor (the cat, the owner): follows a path, turns, picks animations.

var anim: ClipPlayer
var eye_height := 0.25
var path: Array[Vector3] = []
var speed := 0.0

var G: Game:
	get: return Game.I
var rat: Rat:
	get: return Game.I.rat


func path_to(p: Vector3) -> void:
	path = []
	if G.nav and G.nav.ready():
		path = G.nav.find_path(global_position, p)
	if path.is_empty():
		path = G.grid.find_path(global_position, p)


## How it walks (set per character). Speeds in m/s, turning in rad/s.
var accel := 4.0          # speeding up
var decel := 7.0          # slowing down
var turn_rate := 6.0      # turning while walking
var turn_in_place := 1.9  # target more than this far behind (rad): stop and turn on the spot first
var walk_clip_speed := 0.5  # how fast the walk clip's feet move: the clip plays at speed / this, so feet don't slide
var run_clip_speed := 1.0
var run_from := 1.2       # faster than this: the run clip (with a little hysteresis)

var turning := false      # turning on the spot this frame
var _s := 0.0             # current ground speed (eased)
var _followed := -10      # process frame of the last follow()
var _running := false


## Walk along the path. Returns false when there is nothing left to walk.
## The body turns toward the next point at a limited rate and moves where it faces (so it walks arcs, never sideways),
## speeds up and slows down instead of starting/stopping dead, eases into the last point, and turns on the spot
## when the way on is behind it (as the TPS demo's robot does).
func follow(spd: float, dt: float) -> bool:
	var f := Engine.get_process_frames()
	if f - _followed > 3:
		_s = 0.0  # it stood still for a while: start from rest
	_followed = f
	turning = false
	if path.is_empty():
		_s = 0.0
		return false
	var p := global_position
	# corner rounding: move on to the next point a little before reaching this one
	while path.size() > 1 and _flat(path[0] - p) < maxf(0.06, _s * 0.2):
		path.remove_at(0)
	var t := path[0]
	t.y = p.y
	var d := t - p
	var dist := d.length()
	if path.size() == 1 and dist < 0.03:
		path.remove_at(0)
		_s = 0.0
		return false
	var dir := d / maxf(dist, 0.0001)
	var face := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var ang := absf(face.signed_angle_to(dir, Vector3.UP))
	var want := spd
	if path.size() == 1 and spd < run_from:
		want = minf(spd, maxf(0.12, dist * 2.2))  # ease into the stop
	if ang > turn_in_place and _s < 0.25:
		turning = true
		want = 0.0
	else:
		want *= lerpf(0.25, 1.0, clampf(cos(ang), 0.0, 1.0))  # slow down for a sharp turn
	_s = move_toward(_s, want, (accel if want > _s else decel) * dt)
	var rate := turn_rate * (1.4 if turning else 1.0)
	rotation.y = rotate_toward(rotation.y, Nights.yaw_to(dir), rate * dt)
	face = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var step := face * minf(_s * dt, dist + 0.02)
	step += _keep_apart(face) * dt
	if G.nav and G.nav.ready():
		if not G.nav.on_mesh(p + step) and G.nav.on_mesh(p):
			step = dir * minf(_s * dt, dist)  # an arc would clip furniture: go straight along the path
	elif G.grid and G.grid.blocked_at(p + step) and not G.grid.blocked_at(p):
		step = dir * minf(_s * dt, dist)  # an arc would clip furniture: go straight along the path
	global_position = p + step
	speed = _s
	return true


## Step aside from the others (cat, owner, dog) instead of walking through them.
func _keep_apart(face: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for o in [G.cat, G.owner_ai, G.dog]:
		if o == null or o == self or not is_instance_valid(o) or not (o as Node3D).visible:
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.55 and l > 0.001:
			var side := face.cross(Vector3.UP)
			if side.dot(d) < 0.0:
				side = -side
			push += (d / l * 0.4 + side * 0.6) * (0.55 - l) * 2.0
	return push


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Walk/run/turn animation by actual speed, played at a rate that matches the feet to the ground.
## Returns false when standing still (the caller picks its idle).
func move_anim(walk_clip := "walk", run_clip := "run") -> bool:
	if anim == null:
		return speed > 0.05 or turning
	if turning and speed < 0.05:
		anim.play(walk_clip, 0.25)
		anim.set_speed(0.9)  # small steps on the spot
		return true
	if speed <= 0.05:
		_running = false
		return false
	_running = speed > (run_from * 0.88 if _running else run_from)
	if _running and anim.has(run_clip):
		anim.play(run_clip, 0.3)
		anim.set_speed(clampf(speed / run_clip_speed, 0.5, 3.5))
	else:
		anim.play(walk_clip, 0.3)
		anim.set_speed(clampf(speed / walk_clip_speed, 0.5, 3.5))
	return true


func turn(d: Vector3, k: float) -> void:
	d.y = 0.0
	if d.length() < 0.001:
		return
	rotation.y = lerp_angle(rotation.y, Nights.yaw_to(d), clampf(k, 0.0, 1.0))


func to_rat() -> Vector3:
	return rat.global_position - global_position


func dist_rat() -> float:
	var d := to_rat()
	d.y = 0.0
	return d.length()


## Angle (degrees) between where we look (+ an extra yaw, radians) and the rat.
func angle_to_rat(extra_yaw := 0.0) -> float:
	var d := to_rat()
	d.y = 0.0
	var f := global_transform.basis.z.rotated(Vector3.UP, extra_yaw)
	f.y = 0.0
	return rad_to_deg(f.angle_to(d))


func line_of_sight() -> bool:
	return G.ray(global_position + Vector3.UP * eye_height, rat.global_position + Vector3.UP * 0.06).is_empty()


func play(clip: String, blend := 0.2) -> void:
	if anim:
		anim.play(clip, blend)
		anim.set_speed(1.0)
