class_name Rat
extends CharacterBody3D
## The mother rat: walk / run / sneak relative to the camera, sniff, and the prototype's aimed jump —
## face a higher surface (or an edge) and a yellow ring shows where Space will land her.

signal surface_changed(id: String)
signal landed(drop: float)

const MASK := 1  # raycasts hit the world, never the rat (layer 2)
const CEILING := 2.5

var walk_speed := 0.9
var run_speed := 1.9
var sneak_speed := 0.4
var gravity := 12.0
var max_jump_up := 0.62
var max_jump_reach := 0.9
var capacity := 3

var anim: ClipPlayer
var model: Node3D  # the rat model (tilted while she climbs)
var mouth: Node3D  # follows the head bone: what she carries is held in her teeth
var marker: Node3D
var cam_yaw := 0.0  # set by the camera every frame

var frozen := true
var scripted := false  # a cutscene moves her and picks her animation
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
var stand_shape: CollisionShape3D  # set by Game: the upright capsule and the one along her body
var body_shape: CollisionShape3D
var crouched := false  # sneaking makes her low enough to get under a sofa
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
var _edge := Vector3.ZERO  # where the surface she climbs onto begins
var _climb_edge := Vector3.ZERO


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
	f.position = Vector3(0, -0.006 + i * 0.012, 0.01 - i * 0.025)
	f.rotation = Vector3.ZERO
	f.scale = Vector3.ONE * 0.6  # a mouthful


func _set_crouch(on: bool) -> void:
	if on == crouched or stand_shape == null:
		return
	crouched = on
	var cap := stand_shape.shape as CapsuleShape3D
	cap.radius = 0.045 if on else 0.055
	cap.height = 0.09 if on else 0.12
	stand_shape.position.y = 0.047 if on else 0.062
	var bc := body_shape.shape as CapsuleShape3D
	bc.radius = 0.033 if on else 0.04
	body_shape.position.y = 0.04 if on else 0.065


## Drop the last thing she carries in front of her (key G). Returns it, or null.
func drop_one() -> Food:
	if carried.is_empty() or jumping:
		return null
	var f: Food = carried.pop_back()
	f.carried = false
	var at := global_position + global_transform.basis.z * 0.1
	var hit := _ray(at + Vector3.UP * 0.15, at + Vector3.DOWN * 0.3)
	if not hit.is_empty():
		at = hit.position
	f.reparent(Game.I._builder.foods, true)
	f.global_position = at
	f.rotation = Vector3.ZERO
	f.scale = Vector3.ONE
	f.set_meta("dropped_at", at)  # not picked up again until she walks away from it
	return f


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
	if scripted:
		_show_marker(false)
		return
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
	if not sneaking and crouched and not Game.I.sphere_free(global_position + Vector3.UP * 0.105, 0.03):
		sneaking = true  # no room to stand up under the sofa: stay low
		running = false
	_set_crouch(sneaking)

	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw))  # the camera looks along +Z of its yaw
	var right := Vector3(-fwd.z, 0, fwd.x)
	var d := Vector3.ZERO if sniffing else (fwd * mv.y + right * mv.x)
	var spd := run_speed if running else (sneak_speed if sneaking else walk_speed)
	spd *= 0.5 if dragging() else maxf(0.45, 1.0 - 0.18 * carry_weight())  # loaded she's clearly slower
	if d.length() > 0.01:
		rotation.y = rotate_toward(rotation.y, Nights.yaw_to(d), 10.0 * dt)

	if _land_t > 0.0:
		spd *= 0.4  # getting up after a landing (longer after a big drop)
	var before := global_position
	# a little weight: she speeds up and slows down over a moment (slower to get going with a load)
	var want := Vector2(d.x, d.z) * spd
	var cur := Vector2(velocity.x, velocity.z)
	var rate := (9.0 * (1.0 - 0.12 * carry_weight())) if want.length() > cur.length() * 0.9 else 7.0
	if not is_on_floor():
		rate *= 0.15  # in the air she keeps her momentum
	cur = cur.move_toward(want, rate * dt)
	velocity.x = cur.x
	velocity.z = cur.y
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

	if model and not jumping:
		# the hop: nose up going up, nose down coming down
		var tilt := 0.0 if is_on_floor() else clampf(velocity.y * 10.0, -15.0, 22.0)
		model.rotation.x = lerp_angle(model.rotation.x, -deg_to_rad(tilt), clampf(dt * 14.0, 0.0, 1.0))
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
			# a hop forward: front paws first, like a real rat (not straight up like a ball)
			velocity.y = 2.2
			var fw := global_transform.basis.z
			velocity.x += fw.x * 0.9
			velocity.z += fw.z * 0.9
			Sfx.play("jump", global_position)
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
			o.y = minf(o.y, CEILING - 0.03)  # start under the ceiling, not on top of it
			var hit := _ray(o, Vector3(o.x, p0.y - 0.5, o.z))
			if not hit.is_empty():
				var dy: float = hit.position.y - p0.y
				if dy > 0.07 and dy <= max_jump_up and hit.normal.y > 0.75 and _clear(hit.position) and _path_clear(p0, hit.position):
					_target = _inward(hit.position, f)
					_edge = hit.position
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
	if up:
		_climb_edge = _edge
		_dur = clampf(0.55 + (_to.y - _from.y) * 0.9, 0.6, 1.1)
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
		p = _climb_pos(t)
	else:
		p.y = _from.y + 0.1 * sin(t * PI) + dy * t * t
	# a real flight down: something in the way (a chair back, a wall, a lamp) stops her and she drops
	if not _jump_up:
		var hit := move_and_collide(p - global_position, true)
		if hit and hit.get_normal().y < 0.5:
			var away := hit.get_normal()
			away.y = 0.0
			jumping = false
			if model:
				model.rotation.x = 0.0
			velocity = away.normalized() * 0.4 + Vector3.DOWN * 0.5
			Sfx.play("thud", global_position, -10.0, 1.6)
			return
	global_position = p
	if model:
		model.rotation.x = -deg_to_rad(_climb_tilt(t)) if _jump_up else 0.0
	if t < 1.0:
		return
	jumping = false
	if model:
		model.rotation.x = 0.0
	velocity = Vector3(0, -0.5, 0)
	var drop := _from.y - _to.y
	_land_t = clampf(0.12 + drop * 0.35, 0.12, 0.5) if not _jump_up else 0.12
	add_noise(0.15 if _jump_up else 0.35)
	_update_surface()
	landed.emit(_from.y - _to.y)


## Climbing up: she runs to the edge, rears up and grabs it with her front paws (body tipped nose-up, hind legs
## still on the floor), then pushes off with the hind legs and pulls herself over onto the top.
func _climb_pos(t: float) -> Vector3:
	var flat := Vector3(_to.x - _from.x, 0, _to.z - _from.z)
	var dirv := flat.normalized() if flat.length() > 0.001 else global_transform.basis.z
	var edge_d := clampf(Vector3(_climb_edge.x - _from.x, 0, _climb_edge.z - _from.z).length(), 0.0, flat.length())
	var base := _from + dirv * maxf(0.0, edge_d - 0.13)  # snout at the edge, hind paws under it
	var dy := _to.y - _from.y
	var reach := minf(dy, 0.13)  # how far up she stretches before the hop
	if t < 0.35:  # run in and rear up
		var k := t / 0.35
		var q := _from.lerp(base, smoothstep(0.0, 1.0, k))
		q.y = _from.y + reach * 0.4 * smoothstep(0.5, 1.0, k)
		return q
	if t < 0.55:  # paws on the edge, gathering
		var q := base
		q.y = _from.y + reach * (0.4 + 0.6 * (t - 0.35) / 0.2)
		return q
	var k := (t - 0.55) / 0.45  # the hop: up and over
	var q := base.lerp(_to, smoothstep(0.0, 1.0, k))
	q.y = _from.y + reach + (dy - reach) * sin(minf(1.0, k * 1.3) * PI * 0.5)
	return q


func _climb_tilt(t: float) -> float:
	if t < 0.35:
		return 70.0 * smoothstep(0.4, 1.0, t / 0.35)
	if t < 0.55:
		return 70.0
	return 70.0 * (1.0 - smoothstep(0.0, 1.0, (t - 0.55) / 0.45))


# ---------- animation ----------

func _play_anim() -> void:
	if anim == null:
		return
	var clip := "idle"
	if jumping:
		clip = "jump_up" if _jump_up else "jump_down"
	elif not is_on_floor() and carrier == null:
		clip = "jump_up" if velocity.y > 0.0 else "jump_down"
	elif _land_t > 0.0:
		clip = "land"
	elif sniffing:
		clip = "sniff"
	elif moving():
		clip = "drag" if dragging() else ("run" if running else ("sneak" if sneaking else ("carry_walk" if not carried.is_empty() else "walk")))
	anim.play(clip)
	var base := run_speed if running else (sneak_speed if sneaking else walk_speed)
	anim.set_speed(clampf(move_speed / base, 0.6, 1.4) if moving() and not jumping else 1.0)
