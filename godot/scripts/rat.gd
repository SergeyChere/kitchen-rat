class_name Rat
extends CharacterBody3D
## The mother rat: walk / run / sneak relative to the camera, sniff, and the prototype's aimed jump —
## face a higher surface (or an edge) and a yellow ring shows where Space will land her.

signal surface_changed(id: String)
signal landed(drop: float)

const MASK := 1  # raycasts hit the world, never the rat (layer 2)

var walk_speed := 0.9
var run_speed := 1.9
var sneak_speed := 0.4
var gravity := 12.0
var max_jump_up := 0.62
var max_jump_reach := 0.9
var capacity := 3

var anim: ClipPlayer
var mouth: Node3D
var marker: Node3D
var cam_yaw := 0.0  # set by the camera every frame

var frozen := true
var sneaking := false
var running := false
var sniffing := false
var in_nest := false
var hide_spot: HideSpot
var jumping := false
var move_speed := 0.0
var noise_level := 0.0
var surface_id := "floor"
var blocked := false
var carried: Array[Food] = []
var carrier: Node3D  # riding the robot vacuum
var stuck_t := 0.0  # caught in sticky tape, a cage or spray

var _sneak_toggle := false
var _jump_up := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _dur := 0.5
var _land_t := 0.0
var _has_target := false
var _target_up := false
var _target := Vector3.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.05


func moving() -> bool: return move_speed > 0.05
func hidden() -> bool: return hide_spot != null and global_position.y < 0.05 and not jumping
func hide_kind() -> String: return hide_spot.id if hidden() else ""
func has_jump_target() -> bool: return _has_target
func add_noise(v: float) -> void: noise_level = maxf(noise_level, v)


func dragging() -> bool:
	for f in carried:
		if f.big():
			return true
	return false


func carry_weight() -> int:
	var w := 0
	for f in carried:
		w += f.weight()
	return w


func carry(f: Food) -> void:
	carried.append(f)
	f.carried = true
	var i := carried.size() - 1
	f.reparent(mouth if mouth else self, false)
	f.position = Vector3(0, i * 0.015, -i * 0.03)
	f.rotation = Vector3.ZERO


## Put her somewhere instantly (after being caught).
func teleport(p: Vector3, yaw: float) -> void:
	jumping = false
	carrier = null
	stuck_t = 0.0
	global_position = p
	rotation.y = yaw
	velocity = Vector3.ZERO
	hide_spot = null
	in_nest = false


func _physics_process(dt: float) -> void:
	noise_level = move_toward(noise_level, 0.0, dt * 1.5)
	if frozen:
		move_speed = 0.0
		sniffing = false
		_show_marker(false)
		_play_anim()
		return
	if jumping:
		_tick_jump(dt)
		_play_anim()
		return
	if carrier:
		move_speed = 0.0
		velocity = Vector3.ZERO
		sneaking = Input.is_action_pressed("sneak") or _sneak_toggle
		if Input.is_action_just_pressed("sneak_toggle"):
			_sneak_toggle = not _sneak_toggle
			sneaking = _sneak_toggle
		_show_marker(false)
		if anim: anim.play("sneak")
		return

	var mv := Input.get_vector("left", "right", "back", "forward")
	if stuck_t > 0.0:
		mv = Vector2.ZERO
	if Input.is_action_just_pressed("sneak_toggle"):
		_sneak_toggle = not _sneak_toggle
	sniffing = Input.is_action_pressed("sniff") and is_on_floor()
	running = Input.is_action_pressed("run") and mv.length() > 0.1 and not sniffing and not dragging()
	if running:
		_sneak_toggle = false
	sneaking = not running and (Input.is_action_pressed("sneak") or _sneak_toggle)

	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw))  # the camera looks along +Z of its yaw
	var right := Vector3(-fwd.z, 0, fwd.x)
	var d := Vector3.ZERO if sniffing else (fwd * mv.y + right * mv.x)
	var spd := run_speed if running else (sneak_speed if sneaking else walk_speed)
	spd *= 0.55 if dragging() else (1.0 - 0.13 * carry_weight())
	if d.length() > 0.01:
		rotation.y = rotate_toward(rotation.y, Nights.yaw_to(d), 10.0 * dt)

	var before := global_position
	velocity.x = d.x * spd
	velocity.z = d.z * spd
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.5
	velocity.y -= gravity * dt
	move_and_slide()
	var moved := global_position - before
	moved.y = 0.0
	move_speed = moved.length() / dt if dt > 0.0 else 0.0
	blocked = d.length() > 0.1 and move_speed < spd * 0.35
	if moving():
		add_noise(0.8 if running else (0.0 if sneaking else 0.25))
	if _land_t > 0.0:
		_land_t -= dt

	_update_surface()
	_find_jump_target()
	if Input.is_action_just_pressed("jump"):
		if stuck_t > 0.0:
			pass
		elif Game.I.use_tunnel():
			pass
		elif _has_target and not (_target_up and dragging()):
			_start_jump(_target, _target_up)
		elif is_on_floor():
			velocity.y = 2.2
	_play_anim()


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	return Game.I.ray(a, b)


func _update_surface() -> void:
	var hit := _ray(global_position + Vector3.UP * 0.08, global_position + Vector3.DOWN * 0.12)
	if hit.is_empty():
		return
	var id := Game.surface_of(hit.collider)
	if id != surface_id:
		surface_id = id
		surface_changed.emit(id)


# ---------- aimed jump ----------

func _find_jump_target() -> void:
	_has_target = false
	if not sniffing and is_on_floor():
		var p0 := global_position
		var f := global_transform.basis.z.normalized()
		var dd := 0.14
		while dd <= max_jump_reach and not _has_target:
			var o := p0 + f * dd + Vector3.UP * (max_jump_up + 0.2)
			var hit := _ray(o, o + Vector3.DOWN * (max_jump_up + 0.7))
			if not hit.is_empty():
				var dy: float = hit.position.y - p0.y
				if dy > 0.07 and dy <= max_jump_up and hit.normal.y > 0.75 and _clear(hit.position) and _path_clear(p0, hit.position):
					_target = _inward(hit.position, f)
					_target_up = true
					_has_target = true
			dd += 0.04
		if not _has_target and surface_id != "floor":
			dd = 0.12
			while dd <= 0.6:
				var o := p0 + f * dd + Vector3.UP * 0.1
				var hit := _ray(o, o + Vector3.DOWN * 4.0)
				dd += 0.04
				if hit.is_empty() or p0.y - hit.position.y <= 0.12:
					continue
				if hit.normal.y > 0.75 and _clear(hit.position):
					_target = hit.position
					_target_up = false
					_has_target = true
				break
	_show_marker(_has_target)


func _inward(p: Vector3, f: Vector3) -> Vector3:
	var o := p + f * 0.08 + Vector3.UP * 0.2
	var hit := _ray(o, o + Vector3.DOWN * 0.4)
	if not hit.is_empty() and absf(hit.position.y - p.y) < 0.03 and _clear(hit.position):
		return hit.position
	return p


func _clear(p: Vector3) -> bool:
	return Game.I.sphere_free(p + Vector3.UP * 0.08, 0.05)


func _path_clear(a: Vector3, b: Vector3) -> bool:
	var up := Vector3(a.x, b.y + 0.12, a.z)
	return _ray(a + Vector3.UP * 0.1, up).is_empty() and _ray(up, b + Vector3.UP * 0.12).is_empty()


func _show_marker(on: bool) -> void:
	if marker == null:
		return
	marker.visible = on
	if on:
		marker.global_position = _target + Vector3.UP * 0.004


func _start_jump(to: Vector3, up: bool) -> void:
	jumping = true
	Sfx.play("jump", global_position)
	_jump_up = up
	_from = global_position
	_to = to
	_t = 0.0
	_dur = clampf(0.3 + _from.distance_to(_to) * 0.35, 0.35, 0.8)
	var flat := Vector3(_to.x - _from.x, 0, _to.z - _from.z)
	if flat.length() > 0.01:
		rotation.y = Nights.yaw_to(flat)
	_show_marker(false)


func _tick_jump(dt: float) -> void:
	_t += dt / _dur
	var t := clampf(_t, 0.0, 1.0)
	var p := _from.lerp(_to, t)
	var dy := _to.y - _from.y
	if _jump_up:
		p.y = _from.y + dy * sin(t * PI * 0.5) + 0.25 * t * (1.0 - t)
	else:
		p.y = _from.y + 0.1 * sin(t * PI) + dy * t * t
	global_position = p
	if t < 1.0:
		return
	jumping = false
	velocity = Vector3(0, -0.5, 0)
	_land_t = 0.2
	add_noise(0.15 if _jump_up else 0.35)
	_update_surface()
	landed.emit(_from.y - _to.y)


# ---------- animation ----------

func _play_anim() -> void:
	if anim == null:
		return
	var clip := "idle"
	if jumping:
		clip = "jump_up" if _jump_up else "jump_down"
	elif _land_t > 0.0:
		clip = "land"
	elif sniffing:
		clip = "sniff"
	elif moving():
		clip = "drag" if dragging() else ("run" if running else ("sneak" if sneaking else ("carry_walk" if not carried.is_empty() else "walk")))
	anim.play(clip)
	var base := run_speed if running else (sneak_speed if sneaking else walk_speed)
	anim.set_speed(clampf(move_speed / base, 0.6, 1.4) if moving() and not jumping else 1.0)
