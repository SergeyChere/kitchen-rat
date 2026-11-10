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
var sneak_speed := 0.68  # round 5: 0.4 was so slow nobody sneaked — a real tradeoff needs a usable speed
var gravity := 18.0  # demo polish: was 12.0 — she floated on high hops and falls. Falls are snappier now;
# hop_impulse grew with it (v = 1.7 * sqrt(18/12)), so the hop reaches the same height as before
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
## Movement feel ported from GDQuest's Godot 4 3D third-person controller (MIT, see THIRD_PARTY.md):
## velocity eases toward the wanted one (lerp × acceleration), a dead stop under a small speed, the body turns toward
## the last clear input direction (not every tiny stick wobble), a jump that goes higher while Space is held, and a
## nudge off walls when she's pushing but not moving.
var acceleration := 15.0  # snappy start
var brake := 24.0         # and a short stop
const COYOTE := 0.12      # s after leaving an edge that Space still hops
const JUMP_BUFFER := 0.15 # s before landing that Space is remembered
var _coyote := 0.0
var _low_roof := false  # hopping under something: no higher hop for holding Space
var _jump_buf := 0.0
var air_acceleration := 6.0  # demo polish: was 2.0, a hop could not be corrected in the air at all
var rotation_speed := 12.0
var stopping_speed := 0.05
var hop_impulse := 2.08  # scaled with gravity: same hop apex (2.08^2 / (2*18) = 1.7^2 / (2*12))
var hop_hold_force := 9.0  # scaled with gravity, so holding Space stretches the hop as much as before
var _last_strong_dir := Vector3.BACK
var _was_on_floor := true
var _air_top := 0.0
var _sway := 0.0
var _rustle := 0.0
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
var _kind := ""  # up (climb an edge), grab (caught an edge in the air), down (jump down), descend (climb down), pole (up a leg)
var _grabbed := false  # one ledge grab per hop
var _hopping := false  # in the air after her own hop (only then she reaches for an edge)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.12  # demo polish: was 0.05, she un-stuck and micro-fell stepping off shelves
	_make_dust()


# ---------- squash & stretch, dust (from Kenney's Starter Kit 3D Platformer, MIT) ----------

var _dust_trail: CPUParticles3D


func _dust_emitter(amount: int, burst: bool) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = amount
	e.lifetime = 0.55 if burst else 0.45
	e.one_shot = burst
	e.explosiveness = 0.95 if burst else 0.0
	e.emitting = false
	e.local_coords = false
	e.direction = Vector3.UP
	e.spread = 80.0 if burst else 40.0
	e.initial_velocity_min = 0.08 if burst else 0.02
	e.initial_velocity_max = 0.22 if burst else 0.06
	e.gravity = Vector3(0, -0.05, 0)
	e.damping_min = 0.4
	e.damping_max = 0.8
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.03 if burst else 0.015
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(0.3, 1.0)); c.add_point(Vector2(1, 1.3))
	e.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(0.78, 0.74, 0.68, 0.45 if burst else 0.25))
	g.set_color(1, Color(0.78, 0.74, 0.68, 0.0))
	e.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) ** 1.5))
	m.albedo_texture = ImageTexture.create_from_image(img)
	q.material = m
	e.mesh = q
	add_child(e)
	e.position = Vector3(0, 0.01, 0)
	return e


func _make_dust() -> void:
	_dust_trail = _dust_emitter(14, false)


## Stretch tall on take-off, squash flat on landing; the model eases back to its shape.
func _pop(v: Vector3) -> void:
	if model:
		model.scale = v


func _land_fx(drop: float) -> void:
	if tail:
		tail.kick(-2.5 * clampf(drop, 0.1, 1.0))
	if drop > STUN_DROP:
		_stun = clampf(0.8 + (drop - STUN_DROP) * 1.6, 0.8, 2.2)
		add_noise(0.6)
		if Game.I:
			Game.I.bubble_at("@#!", global_position + Vector3.UP * 0.22, _stun, Color(1.0, 0.92, 0.5))
	var k := clampf(drop / 0.45, 0.3, 1.0)
	_pop(Vector3(1.0 + 0.25 * k, 1.0 - 0.25 * k, 1.0 + 0.12 * k))


const STUN_DROP := 0.85   # falls higher than this daze her for a moment
var _stun := 0.0
var _teeter := 0.0
var _teeter_cd := 0.0
var _pre_slide := Vector3.ZERO
var tail: TailSway


func stunned() -> bool: return _stun > 0.0


# ---------- swimming (the kitchen sink) ----------

const BREATH := 8.0      # s she can paddle before it counts as caught
var water: SinkWater
var _air := 0.0
var _air_shown := -1
var _paddle := 0.0


func start_swim(w: SinkWater) -> void:
	water = w
	_air = BREATH
	_air_shown = -1
	velocity = Vector3.ZERO
	_hopping = false
	_set_crouch(false)
	global_position.y = w.level - 0.045
	Sfx.play("splash", global_position)
	add_noise(0.4)
	if Game.I:
		Game.I.noise(global_position, 1.4, "Splash!", false, 0.3)
		Game.I.toast("In the sink! Face the edge and press %s to climb out" % Keys.label("jump"))


func stop_swim() -> void:
	water = null
	if model:
		model.position.y = 0.018
		model.rotation.x = 0.0


func _tick_swim(dt: float) -> void:
	_air -= dt
	var mv := Input.get_vector("left", "right", "back", "forward")
	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var d := fwd * mv.y + right * mv.x
	if d.length() > 0.2:
		_last_strong_dir = d.normalized()
		rotation.y = lerp_angle(rotation.y, Nights.yaw_to(_last_strong_dir), clampf(dt * 8.0, 0.0, 1.0))
	var want := d * 0.3  # paddling: slow
	var h := Vector3(velocity.x, 0.0, velocity.z).lerp(want, clampf(dt * 4.0, 0.0, 1.0))
	velocity = Vector3(h.x, 0.0, h.z)
	var before := global_position
	move_and_slide()
	global_position.y = water.level - 0.045
	move_speed = Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(dt, 0.0001)
	_paddle += dt * (6.0 + move_speed * 20.0)
	if model:
		model.position.y = 0.018 + sin(_paddle) * 0.006  # bobbing, head just above the water
		model.rotation.x = lerp_angle(model.rotation.x, deg_to_rad(-12.0), clampf(dt * 8.0, 0.0, 1.0))
	if anim:
		anim.play("run", 0.2)
		anim.set_speed(0.6 + move_speed * 2.0)
	noise_level = maxf(noise_level, 0.2)
	if Input.is_action_just_pressed("jump") and _climb_out():
		return
	var left := ceili(_air)
	if left != _air_shown and left <= 5 and left > 0 and Game.I:
		_air_shown = left
		Game.I.bubble_at("Glub… %d" % left, global_position + Vector3.UP * 0.18, 0.9, Color(0.6, 0.85, 1.0))
		Sfx.play("splash", global_position, -14.0, 1.4)
	if _air <= 0.0:
		stop_swim()
		if Game.I:
			Game.I.caught("Glub! Too long in the water", global_position)
			if global_position.distance_to(Game.I.hole_point()) > 0.6:
				teleport(Game.I.hole_point() + Vector3(0.22, 0.02, -0.22), PI * 0.75)  # (caught right after being caught)


## Space while swimming: grab the edge she faces (or the nearest one) and climb out onto it.
func _climb_out() -> bool:
	var face := global_transform.basis.z
	face.y = 0.0
	var dirs: Array[Vector3] = [face.normalized()]
	for k in 8:
		dirs.append(Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)))
	for i in dirs.size():
		var dir: Vector3 = dirs[i]
		for reach in ([0.1, 0.16, 0.22] if i == 0 else [0.1, 0.14]):
			var o: Vector3 = global_position + dir * float(reach) + Vector3.UP * 0.3
			var hit := _ray(o, o + Vector3.DOWN * 0.4)
			if hit.is_empty() or hit.normal.y < 0.75 or hit.position.y < water.level + 0.03:
				continue
			stop_swim()
			rotation.y = Nights.yaw_to(dir)
			Sfx.play("splash", global_position, -6.0, 1.2)
			_start_kind("grab", _inward(hit.position, dir), hit.position, 0.6)
			return true
	Sfx.play("splash", global_position, -10.0, 1.3)  # just splashing about
	return false


## Wedged: she is trying to walk, hasn't moved for a moment and her body is touching furniture (squeezed under a
## low shelf, between legs and a crossbar…). She slips out to the nearest spot where she fits, the way she was
## heading if she can.
var _wedged_t := 0.0


## Is her body (either collider) pushed into furniture right now?
func overlapping() -> bool:
	return _overlap_shape(stand_shape) or _overlap_shape(body_shape)


func _overlap_shape(cs: CollisionShape3D) -> bool:
	if cs == null or not is_inside_tree():
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	var sh: Shape3D = cs.shape.duplicate()
	if sh is CapsuleShape3D:
		(sh as CapsuleShape3D).radius *= 0.92  # touching is fine, sunk in is not
	q.shape = sh
	q.transform = cs.global_transform
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _unwedge(d: Vector3, dt: float) -> void:
	if d.length() < 0.1 or move_speed > 0.03 or jumping or not is_on_floor() or Game.I == null:
		_wedged_t = 0.0
		return
	var gm := Game.I
	_wedged_t = _wedged_t + dt if overlapping() else 0.0
	if _wedged_t < 0.6:
		return
	_wedged_t = 0.0
	var dir := d.normalized()
	var best := Vector3.INF
	var best_score := INF
	for k in 16:
		var a := k * TAU / 16.0
		var v := Vector3(cos(a), 0.0, sin(a))
		for r in [0.08, 0.14, 0.22, 0.32]:
			var p: Vector3 = global_position + v * float(r)
			if not gm.sphere_free(p + Vector3.UP * 0.07, 0.06) or not gm.sphere_free(p + Vector3.UP * 0.07 + dir * 0.09, 0.045) and not gm.sphere_free(p + Vector3.UP * 0.07 - dir * 0.09, 0.045):
				continue
			var ground := _ray(p + Vector3.UP * 0.1, p + Vector3.DOWN * 0.15)
			if ground.is_empty():
				continue
			var score: float = float(r) - v.dot(dir) * 0.1
			if score < best_score:
				best_score = score
				best = ground.position
			break
	if best != Vector3.INF:
		global_position = best + Vector3.UP * 0.005
		velocity = Vector3.ZERO


# ---------- body language ----------

var head_look: HeadLook
var _exert := 0.0        # 0…1: builds up while she runs, she pants for a while after
var _breath_t := 0.0
var _noise_at := Vector3.ZERO
var _noise_t := 0.0      # s left to keep looking at the last noise


## The breathing she shows in her body: slow and small at rest, quick and deep after a sprint.
func _breath(dt: float) -> Vector3:
	_exert = clampf(_exert + (dt / 3.0 if running and moving() else -dt / 5.0), 0.0, 1.0)
	_breath_t += dt * TAU * lerpf(1.3, 4.2, _exert)
	var still := 1.0 - clampf(move_speed / walk_speed, 0.0, 1.0) * 0.8
	var a := lerpf(0.012, 0.045, _exert) * still
	var b := sin(_breath_t)
	return Vector3(1.0 + a * b, 1.0 + a * 1.3 * b, 1.0)


## A sudden sound somewhere: she turns her head to it for a moment.
func notice(at: Vector3) -> void:
	if at.distance_to(global_position) < 4.0:
		_noise_at = at
		_noise_t = 1.6


func _tick_look(dt: float) -> void:
	if head_look == null:
		return
	_noise_t = maxf(_noise_t - dt, 0.0)
	var w := 0.0
	if jumping or sniffing or carrier != null or frozen or scripted or dragging():
		w = 0.0
	elif _noise_t > 0.0:
		head_look.target = _noise_at
		w = 1.0
	elif not running and Game.I:
		var best: Food = null
		var bd := 0.9
		for f in Game.I.foods:
			if not is_instance_valid(f) or f.carried or not f.visible:
				continue
			var d: float = f.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = f
		if best:
			head_look.target = best.global_position
			w = 0.8
	head_look.weight = move_toward(head_look.weight, w, dt * 4.0)


## At the edge of a raised surface (a table, a counter, the fridge) she stops and teeters instead of running off.
## Walking slowly to an edge she climbs down (_try_descend); Space jumps down on purpose.
func _hold_edge(dt: float) -> void:
	_teeter = maxf(_teeter - dt, 0.0)
	_teeter_cd = maxf(_teeter_cd - dt, 0.0)
	if not is_on_floor() or surface_id == "floor" or _hopping:
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length() < 0.05:
		return
	var dir := h.normalized()
	var p := global_position + dir * (0.07 + h.length() * 0.06) + Vector3.UP * 0.05
	var hit := _ray(p, p + Vector3.DOWN * 0.18)
	if not hit.is_empty():
		return
	# no ground just ahead: take away the speed toward the edge
	var into := h.dot(dir)
	velocity.x -= dir.x * into
	velocity.z -= dir.z * into
	if _teeter_cd <= 0.0 and into > walk_speed * 0.6:
		_teeter = 0.45
		_teeter_cd = 1.2
		Sfx.play("squeak", global_position, -10.0)


## Bumping into loose things (a fallen apple, a cup on the floor…) nudges them along.
func _push_things() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb == null or rb.freeze:
			continue
		var n := -c.get_normal()
		n.y = 0.0
		if n.length() < 0.01:
			continue
		var sp := maxf(_pre_slide.dot(n.normalized()), 0.0)
		if sp < 0.05:
			continue
		rb.apply_central_impulse(n.normalized() * minf(sp, 1.2) * 1.1 * rb.mass)  # a shove: it rolls on a little ahead of her


func moving() -> bool: return move_speed > 0.05
func hidden() -> bool:
	# floor spots count at floor level; an elevated crack (counter, cabinet top) counts at its own height
	if hide_spot == null or jumping:
		return false
	return global_position.y < 0.05 or hide_spot.global_position.y > 0.1
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
	# snapped up: it pops into her mouth (overshoots, settles) and she gives a happy little bob
	var to := f.position
	f.position = to + Vector3(0, -0.035, 0.02)
	f.scale = Vector3.ONE * 0.95
	var tw := f.create_tween().set_parallel(true)
	tw.tween_property(f, "position", to, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "scale", Vector3.ONE * 0.6, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop(Vector3(1.06, 0.92, 1.04))


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


## What she carries swings with her steps; heavy cheese hangs low; dragging rustles.
func _tick_carry(dt: float) -> void:
	if carried.is_empty():
		return
	_sway += dt * (4.0 + move_speed * 14.0)
	var amp := clampf(move_speed / run_speed, 0.0, 1.0)
	var heavy := carry_weight() >= 2
	for i in carried.size():
		var f := carried[i]
		f.rotation.z = sin(_sway + i * 0.7) * 0.25 * amp
		f.rotation.x = (0.35 if heavy else 0.0) + absf(cos(_sway)) * 0.15 * amp
	if dragging() and moving():
		_rustle -= dt
		if _rustle <= 0.0:
			_rustle = 0.35
			Sfx.play("scrape", global_position, -10.0, randf_range(0.9, 1.1))
			add_noise(0.3)


## Drop the last thing she carries in front of her (key G). Returns it, or null.
func drop_one() -> Food:
	if carried.is_empty() or jumping:
		return null
	var f: Food = carried.pop_back()
	f.carried = false
	# tossed: it flies a little ahead and rolls to a stop
	var fw := global_transform.basis.z
	var at := global_position + fw * 0.32
	var hit := _ray(at + Vector3.UP * 0.15, at + Vector3.DOWN * 3.0)
	if not hit.is_empty():
		at = hit.position
	var from := f.global_position
	f.reparent(Game.I._builder.foods, true)
	f.global_position = from
	f.rotation = Vector3.ZERO
	f.scale = Vector3.ONE * f.wscale
	var roll := at + fw * 0.06
	var hit2 := _ray(roll + Vector3.UP * 0.05, roll + Vector3.DOWN * 0.06)
	if hit2.is_empty():
		roll = at
	var tw := f.create_tween()
	tw.tween_method(func(t: float): f.global_position = from.lerp(at, t) + Vector3.UP * sin(t * PI) * 0.1; f.rotation.x = t * 4.0, 0.0, 1.0, 0.32)
	tw.tween_callback(func(): Sfx.play("land", at, -8.0, 1.8))
	tw.tween_property(f, "global_position", roll, 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "rotation:x", 6.0, 0.2)
	f.set_meta("dropped_at", roll)  # not picked up again until she walks away from it
	return f


## Put her somewhere instantly (after being caught).
func teleport(p: Vector3, yaw: float) -> void:
	if water:
		stop_swim()
	jumping = false
	carrier = null
	stuck_t = 0.0
	global_position = p
	rotation.y = yaw
	velocity = Vector3.ZERO
	hide_spot = null
	in_nest = false
	_was_on_floor = true
	_grabbed = false
	_last_strong_dir = Vector3(sin(yaw), 0, cos(yaw))


func _physics_process(dt: float) -> void:
	if model:
		model.scale = model.scale.lerp(_breath(dt), clampf(dt * 10.0, 0.0, 1.0))
	_tick_look(dt)
	if _dust_trail:
		_dust_trail.emitting = running and is_on_floor() and move_speed > walk_speed and not jumping and not hidden()
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

	if water:
		_tick_swim(dt)
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
	if _stun > 0.0:
		d = Vector3.ZERO  # dazed after a big fall
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	if is_on_floor() and d.length() > 0.01 and cur.length() > 0.25 and not dragging():
		# turning in an arc: at speed the way she goes swings round toward the stick instead of snapping to it
		var cd := cur.normalized()
		var ang := cd.signed_angle_to(d.normalized(), Vector3.UP)
		var k := clampf((cur.length() - 0.25) / maxf(run_speed - 0.25, 0.01), 0.0, 1.0)
		var rate := lerpf(11.0, 4.5, k)
		if absf(ang) > 2.4:
			d *= 0.25  # turning right round: slow down first, which tightens the turn
		var step := clampf(ang, -rate * dt, rate * dt)
		d = cd.rotated(Vector3.UP, step) * d.length()
		var vy0 := velocity.y
		velocity = cur.rotated(Vector3.UP, step)  # the momentum turns with her
		velocity.y = vy0
	if d.length() > 0.2:
		_last_strong_dir = d.normalized()
	if d.length() > 0.01:
		# dragging something big she walks backwards, pulling it after her
		var face := -_last_strong_dir if dragging() else _last_strong_dir
		# she is long: turning beside a wall would swing her body into it (and she'd sink in), so a turn that
		# pushes her into something waits until she has stepped away
		var was_in := _overlap_shape(body_shape)
		var old_yaw := rotation.y
		rotation.y = lerp_angle(rotation.y, Nights.yaw_to(face), clampf(dt * rotation_speed, 0.0, 1.0))
		if not was_in and _overlap_shape(body_shape):
			rotation.y = old_yaw

	if _land_t > 0.0:
		spd *= 0.4  # getting up after a landing (longer after a big drop)
	if is_on_floor() and not running and _try_descend(d):
		_play_anim()
		return
	var before := global_position
	# velocity eases toward the wanted one; in the air she mostly keeps her momentum
	var acc := (acceleration * (1.0 - 0.12 * carry_weight())) if is_on_floor() else air_acceleration
	var want := d * spd
	var y_vel := velocity.y
	velocity.y = 0.0
	if is_on_floor() and want.length() < 0.001:
		acc = brake  # letting go of the keys: she stops short, she doesn't skate
	velocity = velocity.lerp(want, clampf(acc * dt, 0.0, 1.0))
	if want.length() < 0.001 and velocity.length() < stopping_speed:
		velocity = Vector3.ZERO
	velocity.y = y_vel
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.5
	_hold_edge(dt)
	velocity.y -= gravity * dt
	if not is_on_floor() and velocity.y > 0.0 and Input.is_action_pressed("jump") and not _low_roof:
		velocity.y += hop_hold_force * dt  # hold Space: a higher hop
	_pre_slide = Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_push_things()
	# pushing but not moving: slide off the wall a little (stuck on a corner)
	if (global_position - before).length() < 0.0002 and Vector2(velocity.x, velocity.z).length() > 0.05 and get_slide_collision_count() > 0:
		global_position += get_wall_normal() * 0.004
	# landing after a fall or a hop (the aimed jumps land on their own)
	if not is_on_floor():
		_air_top = maxf(_air_top, global_position.y) if not _was_on_floor else global_position.y
		_try_ledge_grab()
		if jumping:
			_play_anim()
			return
	elif not _was_on_floor:
		var drop := _air_top - global_position.y
		if drop > 0.05:
			landed.emit(drop)
			_land_fx(drop)
			_land_t = clampf(0.08 + drop * 0.35, 0.08, 0.5)
	_was_on_floor = is_on_floor()
	if is_on_floor():
		_grabbed = false
		_hopping = false
		_low_roof = false
	var moved := global_position - before
	moved.y = 0.0
	move_speed = moved.length() / dt if dt > 0.0 else 0.0
	blocked = d.length() > 0.1 and move_speed < spd * 0.35
	_unwedge(d, dt)
	if moving():
		add_noise(0.8 if running else (0.0 if sneaking else 0.25))
	_tick_carry(dt)
	if _land_t > 0.0:
		_land_t -= dt
	if _stun > 0.0:
		_stun -= dt

	if model and not jumping:
		# the hop: nose up going up, nose down coming down
		var tilt := (-4.0 if carry_weight() >= 2 else 0.0) if is_on_floor() else clampf(velocity.y * 10.0, -15.0, 22.0)  # heavy: head down
		model.rotation.x = lerp_angle(model.rotation.x, -deg_to_rad(tilt), clampf(dt * 14.0, 0.0, 1.0))
		# teetering at an edge: a quick wobble; dazed after a fall: a slow sway
		var roll := 0.0
		if _teeter > 0.0:
			roll = sin(_teeter * 38.0) * 9.0 * (_teeter / 0.45)
			model.rotation.x += deg_to_rad(8.0) * (_teeter / 0.45)  # nose down, peering over
		elif _stun > 0.0:
			roll = sin(Time.get_ticks_msec() * 0.006) * 10.0 * clampf(_stun, 0.0, 1.0)
		model.rotation.z = lerp_angle(model.rotation.z, deg_to_rad(roll), clampf(dt * 16.0, 0.0, 1.0))
	_update_surface()
	_find_jump_target()
	# forgiving jumps: Space pressed a moment before landing still jumps on landing (buffer), and a moment after
	# walking off an edge still hops (coyote time)
	_coyote = COYOTE if is_on_floor() else maxf(_coyote - dt, 0.0)
	_jump_buf = maxf(_jump_buf - dt, 0.0)
	var press := Input.is_action_just_pressed("jump")
	if press and not is_on_floor() and _coyote <= 0.0:
		_jump_buf = JUMP_BUFFER
		press = false
	elif not press and _jump_buf > 0.0 and is_on_floor():
		press = true
		_jump_buf = 0.0
	if press:
		var grounded := is_on_floor() or (_coyote > 0.0 and not _hopping)
		if stuck_t > 0.0 or _stun > 0.0:
			pass
		elif Game.I.use_tunnel():
			pass
		elif _has_target and (not dragging() or not _target_up):
			# round 5: dragging a sausage she may still jump DOWN (pulling it off a table was
			# impossible before — she wedged at the edge for good); climbing UP with it stays barred
			_start_jump(_target, _target_up)
		elif _try_pole():
			pass
		elif grounded and not dragging():
			# a hop forward: front paws first, like a real rat (not straight up like a ball)
			_coyote = 0.0
			velocity.y = hop_impulse
			# under a table or a sofa: a lower hop, so she bumps her head instead of going through the top
			var roof := _ray(global_position + Vector3.UP * 0.1, global_position + Vector3.UP * 0.5)
			if not roof.is_empty():
				var room: float = roof.position.y - (global_position.y + 0.13)
				velocity.y = minf(hop_impulse, sqrt(2.0 * gravity * maxf(room, 0.0)))
				_low_roof = true
			_hopping = true
			_pop(Vector3(0.9, 1.16, 0.95))
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
	marker.visible = false  # no ring: Space near an edge just does the right thing
	if on:
		marker.global_position = _target + Vector3.UP * 0.004


func _start_jump(to: Vector3, up: bool) -> void:
	jumping = true
	_pop(Vector3(0.88, 1.2, 0.94))
	Sfx.play("jump", global_position)
	_jump_up = up
	_kind = "up" if up else "down"
	_from = global_position
	_to = to
	_t = 0.0
	_dur = clampf(0.3 + _from.distance_to(_to) * 0.35, 0.35, 0.8)
	if up:
		_climb_edge = _edge
		_dur = clampf(0.36 + (_to.y - _from.y) * 0.4, 0.42, 0.66)  # round 4: snappier still — a spring, not a ride
	var flat := Vector3(_to.x - _from.x, 0, _to.z - _from.z)
	if flat.length() > 0.01:
		rotation.y = Nights.yaw_to(flat)
	_show_marker(false)


func _tick_jump(dt: float) -> void:
	_t += dt / _dur
	var t := clampf(_t, 0.0, 1.0)
	var p := _from.lerp(_to, t)
	var dy := _to.y - _from.y
	match _kind:
		"up", "grab": p = _climb_pos(t)
		"descend": p = _descend_pos(t)
		"pole": p = _pole_pos(t)
		_: p.y = _from.y + 0.1 * sin(t * PI) + dy * t * t
	# a real flight down: something in the way (a chair back, a wall, a lamp) stops her and she drops
	if _kind == "down":
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
		var tilt := 0.0
		match _kind:
			"up", "grab": tilt = _climb_tilt(t)
			"pole": tilt = 85.0 * (1.0 - smoothstep(0.75, 1.0, t)) * smoothstep(0.0, 0.15, t)
			"descend": tilt = -60.0 * smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.85, 1.0, t))
		model.rotation.x = -deg_to_rad(tilt)
	if t < 1.0:
		return
	jumping = false
	if model:
		model.rotation.x = 0.0
	velocity = Vector3(0, -0.5, 0)
	if _kind == "up" or _kind == "grab":
		_pop(Vector3(1.12, 0.78, 1.08))  # round 4: landing squash after a climb — weight, not a glide-stop
	var drop := _from.y - _to.y
	_land_t = clampf(0.12 + drop * 0.35, 0.12, 0.5) if _kind == "down" else 0.1
	add_noise(0.35 if _kind == "down" else 0.12)
	_update_surface()
	if _kind == "down" or _kind == "up":
		_land_fx(maxf(drop, 0.15))
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
	if t < 0.30:  # run in and rear up
		var k := t / 0.30
		var q := _from.lerp(base, smoothstep(0.0, 1.0, k))
		q.y = _from.y + reach * 0.4 * smoothstep(0.5, 1.0, k)
		return q
	if t < 0.42:  # paws on the edge: a loaded crouch, not a pause — she dips, then springs
		var k2 := (t - 0.30) / 0.12
		var q := base
		q.y = _from.y + reach * (0.4 + 0.6 * k2) - 0.028 * sin(k2 * PI)
		return q
	var k := (t - 0.42) / 0.58  # the push: up the face first, then over the edge
	# Round 3 split the diagonal glide into up-then-over; round 4 makes the rise itself ballistic:
	# an ease-out cubic is fast off the push and soft at the top, the shape gravity gives a real
	# scramble — smoothstep's slow start was what still read as floating.
	var q := base.lerp(_to, smoothstep(0.32, 1.0, k))
	var kr := clampf(k / 0.55, 0.0, 1.0)
	var rise := 1.0 - pow(1.0 - kr, 3.0)
	var settle := smoothstep(0.55, 1.0, k)
	q.y = _from.y + reach + (dy - reach) * rise + 0.03 * rise * (1.0 - settle)
	return q


## Climbing down: to the edge, nose down, and down the side onto the surface below.
func _descend_pos(t: float) -> Vector3:
	var edge := _climb_edge
	if t < 0.25:
		var q := _from.lerp(Vector3(edge.x, _from.y, edge.z), smoothstep(0.0, 1.0, t / 0.25))
		return q
	var k := (t - 0.25) / 0.75
	var q := Vector3(edge.x, _from.y, edge.z).lerp(_to, smoothstep(0.0, 1.0, k))
	q.y = lerpf(_from.y, _to.y, smoothstep(0.0, 1.0, k))
	return q


## Up a chair or table leg: straight up its side, then over onto the top.
func _pole_pos(t: float) -> Vector3:
	var base := _climb_edge  # at the leg, on the floor
	if t < 0.12:
		return _from.lerp(base, t / 0.12)
	if t < 0.78:
		var kk := (t - 0.12) / 0.66
		var q := base
		# little grip pulses on the way up: she climbs the leg in pushes, not on a lift
		var push := smoothstep(0.0, 1.0, kk) + sin(kk * PI * 3.0) * 0.012 * sin(kk * PI)
		q.y = lerpf(_from.y, _to.y - 0.04, clampf(push, 0.0, 1.0))
		return q
	var k := (t - 0.78) / 0.22
	var q := Vector3(base.x, _to.y - 0.04, base.z).lerp(_to, smoothstep(0.0, 1.0, k))
	q.y = lerpf(_to.y - 0.04, _to.y, k)
	return q


func _start_kind(kind: String, to: Vector3, edge: Vector3, dur: float) -> void:
	jumping = true
	_jump_up = kind != "descend"
	_kind = kind
	_from = global_position
	_to = to
	_climb_edge = edge
	_t = 0.0
	_dur = dur
	var flat := Vector3(_to.x - _from.x, 0, _to.z - _from.z)
	if flat.length() > 0.01:
		rotation.y = Nights.yaw_to(flat)
	Sfx.play("scratch", global_position, -8.0, 1.4)


## In the air after a hop: an edge right ahead within reach of her front paws? Grab it and pull up.
func _try_ledge_grab() -> void:
	if not _hopping or _grabbed or dragging() or velocity.y > 0.8:
		return
	var p0 := global_position
	var f := global_transform.basis.z.normalized()
	var dd := 0.08
	while dd <= 0.26:
		var o := p0 + f * dd + Vector3.UP * 0.4
		o.y = minf(o.y, CEILING - 0.03)
		var hit := _ray(o, Vector3(o.x, p0.y - 0.02, o.z))
		dd += 0.04
		if hit.is_empty():
			continue
		var dy: float = hit.position.y - p0.y
		# and nothing over her head on the way up (on a chair under the table she must not grab the top through it)
		if dy > 0.1 and dy < 0.42 and hit.normal.y > 0.75 and hit.position.y < CEILING - 0.25 and _clear(hit.position) \
				and _ray(p0 + Vector3.UP * 0.1, Vector3(p0.x, hit.position.y + 0.12, p0.z)).is_empty() \
				and _ray(Vector3(p0.x, hit.position.y + 0.1, p0.z), hit.position + Vector3.UP * 0.1).is_empty():
			_grabbed = true
			_edge = hit.position
			_start_kind("grab", _inward(hit.position, f), hit.position, 0.5 + maxf(dy, 0.0) * 0.8)
			velocity = Vector3.ZERO
			return


## Walking (not running) off a raised surface: she climbs down the side instead of dropping.
func _try_descend(d: Vector3) -> bool:
	if running or dragging() or surface_id == "floor" or d.length() < 0.2:
		return false
	var f := d.normalized()
	var p0 := global_position
	var ahead := p0 + f * 0.09
	if not _ray(ahead + Vector3.UP * 0.05, ahead + Vector3.DOWN * 0.06).is_empty():
		return false  # still ground under her nose
	# where the edge is, and what's below beyond it
	var edge := p0
	for i in 8:
		var q := p0 + f * (0.01 * i)
		if _ray(q + Vector3.UP * 0.05, q + Vector3.DOWN * 0.06).is_empty():
			break
		edge = q
	var land := edge + f * 0.1
	var hit := _ray(land + Vector3.UP * 0.05, land + Vector3.DOWN * 1.3)
	if hit.is_empty():
		return false
	var drop: float = p0.y - hit.position.y
	if drop < 0.12 or drop > 1.0 or hit.normal.y < 0.75 or not _clear(hit.position):
		return false
	_start_kind("descend", hit.position, edge, 0.45 + drop * 0.8)
	return true


## Space right at a chair / table / stool that's too high to jump onto: climb up its side or leg to the top
## (up to 1.2 m).
func _try_pole() -> bool:
	if dragging() or not is_on_floor():
		return false
	var p0 := global_position
	var f := global_transform.basis.z.normalized()
	var dd := 0.06
	while dd <= 0.3:
		var o := p0 + f * dd + Vector3.UP * 1.3
		o.y = minf(o.y, CEILING - 0.03)
		var hit := _ray(o, Vector3(o.x, p0.y + 0.25, o.z))
		dd += 0.03
		if hit.is_empty():
			continue
		var dy: float = hit.position.y - p0.y
		var what := Game.surface_of(hit.collider)
		if dy > 0.28 and dy <= 1.2 and hit.normal.y > 0.75 and what != "fridge" and hit.position.y < CEILING - 0.25 \
				and _clear(hit.position) and _ray(p0 + Vector3.UP * 0.1, Vector3(p0.x, hit.position.y + 0.12, p0.z)).is_empty():
			var at := p0 + f * maxf(0.0, dd - 0.03 - 0.09)  # snout at the side
			_start_kind("pole", _inward(hit.position, f), at, 0.55 + dy * 1.1)
			return true
		break
	return false


func _climb_tilt(t: float) -> float:
	if t < 0.30:
		return 70.0 * smoothstep(0.4, 1.0, t / 0.30)
	if t < 0.42:  # loading the push: leans in a touch further as she crouches
		return 70.0 + 6.0 * sin((t - 0.30) / 0.12 * PI * 0.5)
	var k := (t - 0.42) / 0.58
	if k < 0.4:  # up the face: still nose-up, easing off
		return 76.0 - 16.0 * smoothstep(0.0, 0.4, k)
	if k < 0.8:  # over the edge: the body rolls forward as the hindquarters come up
		return lerpf(60.0, -20.0, smoothstep(0.4, 0.8, k))
	return lerpf(-20.0, 0.0, smoothstep(0.8, 1.0, k))


# ---------- animation ----------

var _fast := false


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
	elif hidden() and not moving():
		clip = "sneak"  # pressed low in her hiding spot
	elif moving():
		# walk or run by how fast she actually goes (she eases into a run), as in GDQuest's walk/run blend
		# with a little hysteresis, so she doesn't flicker between the two around the switch speed
		var mid := (walk_speed + run_speed) * 0.5
		_fast = move_speed > (mid * 0.85 if _fast else mid)
		clip = "drag" if dragging() else ("run" if _fast else ("sneak" if sneaking else ("carry_walk" if not carried.is_empty() else "walk")))
	else:
		_fast = false
	var gait := ["walk", "run", "carry_walk", "sneak", "drag"]
	anim.play(clip, 0.3 if gait.has(clip) and gait.has(anim.current) else 0.15)  # long cross-fade between gaits
	var base := run_speed if clip == "run" else (sneak_speed if sneaking else walk_speed)
	anim.set_speed(clampf(move_speed / base, 0.5, 1.5) if moving() and not jumping else (0.15 if clip == "sneak" else 1.0))
