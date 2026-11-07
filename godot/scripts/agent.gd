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
	path = G.grid.find_path(global_position, p)


## Walk along the path. Returns false when there is nothing left to walk.
func follow(spd: float, dt: float) -> bool:
	if path.is_empty():
		return false
	var p := global_position
	var t := path[0]
	t.y = p.y
	var d := t - p
	var dist := d.length()
	if dist < 0.03:
		path.remove_at(0)
		return not path.is_empty()
	global_position = p + d / dist * minf(dist, spd * dt)
	turn(d, dt * 10.0)
	speed = spd
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
