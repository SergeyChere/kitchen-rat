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
# The clips' OWN foot speeds at playback 1.0 (m/s), measured from the paws on the
# floor with the stride tester (round 8). They are TINY — the rig was authored
# ambling (walk feet: 0.09 m/s against her 0.9 m/s body speed, a 10x mismatch) —
# which is exactly why she ice-skated ("swam") when just walking. The gaits are
# now sped from these numbers, so the feet travel at the body's speed.
const WALK_CLIP := 0.09
const RUN_CLIP := 0.63
const SNEAK_CLIP := 0.055
const CARRY_CLIP := 0.08
# Round 9 (asked): at slow gaits the true stride rate made her legs look SHORT —
# a blur of tiny steps. The slow gaits run at 80% of the stride rate (slightly
# fewer steps; a whisper of slide returns, worth it). The run was approved
# exactly as measured — it is NOT softened.
var gravity := 18.0  # demo polish: was 12.0 — she floated on high hops and falls. Falls are snappier now;
# hop_impulse grew with it (v = 1.7 * sqrt(18/12)), so the hop reaches the same height as before
var max_jump_up := 0.54  # round 11: the tall wall climb is DELETED (the user's call) — one spring
# is all she has; anything higher is reached over other furniture (chair 0.41 → counter
# 0.92 is a 0.51 step; the pantry crates climb in 0.40 steps; a 0.52 stool tops the bench)
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
var _kind := ""  # up (one spring onto an edge), grab (caught an edge in the air), down (jump down), descend (climb down)
var _grabbed := false  # one ledge grab per hop
var _hopping := false  # in the air after her own hop (only then she reaches for an edge)
var _embed_t := 0.0  # round 14: stuck-in-geometry rescue timer


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4  # round 14: layer 4 = rat-only solids (the cat's bed)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.12  # demo polish: was 0.05, she un-stuck and micro-fell stepping off shelves


# ---------- squash & stretch (from Kenney's Starter Kit 3D Platformer, MIT) ----------





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
	if model != null and _rig_done:
		model.position = _model_home  # round 7: no leftover root-motion offset
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
	# round 15: her dust is Game's mesh puffs now (world_fx.puff, kicked up
	# per stride in Game._footsteps) — the CPU particle trail never
	# rendered on some drivers, so the rings outlived it.
	noise_level = move_toward(noise_level, 0.0, dt * 1.5)
	# round 14 (playtest: she ends up inside walls and furniture): if her core
	# is embedded in something solid, step out to the nearest free offset.
	_embed_t -= dt
	if _embed_t <= 0.0 and not jumping:
		_embed_t = 0.3
		if not Game.I.sphere_free(global_position + Vector3.UP * 0.08, 0.04):
			for off in [Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0), Vector3(0, 0, 0.15), Vector3(0, 0, -0.15), Vector3(0.11, 0, 0.11), Vector3(-0.11, 0, 0.11), Vector3(0.11, 0, -0.11), Vector3(-0.11, 0, -0.11)]:
				if Game.I.sphere_free(global_position + off + Vector3.UP * 0.08, 0.04):
					global_position += off
					velocity = Vector3.ZERO
					break
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
		# round 14 (asked: with a run-up she should clear a gap between pieces of
		# furniture — a little further, not far): momentum buys +0.38 m of scan.
		var fast := Vector2(velocity.x, velocity.z).length() > 1.55
		var dd := 0.14
		while dd <= max_jump_reach + (0.38 if fast else 0.0) and not _has_target and not dragging():  # round 12: no up-offers while hauling — the dispatch bars them anyway, and one would hide the drop behind her
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
			# round 12: while dragging she walks BACKWARDS, facing away from where
			# she's going — so the drop she is backing toward is behind her facing.
			# Scan the way she faces first, then the way she is actually moving.
			var dirs := [f, -f] if dragging() else [f]
			for df in dirs:
				if _has_target:
					break
				dd = 0.12
				var saw_gap := false
				while dd <= (0.98 if fast else 0.6):
					var o: Vector3 = p0 + df * dd + Vector3.UP * 0.1
					var hit := _ray(o, o + Vector3.DOWN * 4.0)
					dd += 0.04
					if hit.is_empty():
						saw_gap = true
						continue
					var drop := p0.y - (hit.position as Vector3).y
					if drop > 0.35:
						saw_gap = true
					# round 14: at a run, a LEVEL landing across a real gap (she
					# saw void or floor between) is a target too — counter to
					# island, chair to chair. Without the run it stays a drop.
					if drop <= 0.12 and not (fast and saw_gap and drop >= -0.02):
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
				model.position = _model_home  # round 7: no leftover root-motion offset
			velocity = away.normalized() * 0.4 + Vector3.DOWN * 0.5
			Sfx.play("thud", global_position, -10.0, 1.6)
			return
	global_position = p
	# round 7: cancel the clip's root motion (see _climb_rig) — the path moves her,
	# the clip only poses her
	if _root_bone >= 0 and model != null:
		model.position = _model_home - _skel.get_bone_pose_position(_root_bone)

	if model:
		var tilt := 0.0
		match _kind:
			"up", "grab": tilt = _climb_tilt(t)
			"descend": tilt = -60.0 * smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.85, 1.0, t))
		model.rotation.x = -deg_to_rad(tilt)
	if t < 1.0:
		return
	jumping = false
	if model:
		model.rotation.x = 0.0
		model.position = _model_home  # round 7: hand the model node back from the root-motion cancel
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
# Round 7: the climb rig. The baked clips carry ROOT MOTION — jump_up's root bone
# translates through its own little arc. Stacked on the parametric path, that arc
# played TWICE (hers + the clip's), which is most of why climbs looked puppeted.
# During a climb the path is the only transport: the root's pose offset is
# cancelled out of the model node every frame and the clip becomes pure acting.
var _skel: Skeleton3D
var _root_bone := -1
var _model_home := Vector3(0.0, 0.018, 0.0)
var _rig_done := false


func _climb_rig() -> void:
	if _rig_done or model == null:
		return
	_rig_done = true
	_model_home = model.position
	_skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel != null:
		_root_bone = _skel.find_bone("root")


## Piecewise-smooth keyframe curve (round 6, for the climb stages).
func _keys(u: float, keys: Array) -> float:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if u <= float(b[0]):
			var k := clampf((u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, k))
	return float(keys[keys.size() - 1][1])


func _climb_pos(t: float) -> Vector3:
	var flat := Vector3(_to.x - _from.x, 0, _to.z - _from.z)
	var dirv := flat.normalized() if flat.length() > 0.001 else global_transform.basis.z
	var edge_d := clampf(Vector3(_climb_edge.x - _from.x, 0, _climb_edge.z - _from.z).length(), 0.0, flat.length())
	var base := _from + dirv * maxf(0.0, edge_d - 0.13)  # snout at the edge, hind paws under it
	var dy := _to.y - _from.y
	var reach := minf(dy, 0.13)  # how far up she stretches before the hop
	if t < 0.26:  # run in and rear up
		var k := t / 0.26
		var q := _from.lerp(base, smoothstep(0.0, 1.0, k))
		q.y = _from.y + reach * 0.35 * smoothstep(0.4, 1.0, k)
		return q
	if t < 0.40:  # the crouch: she loads her hind legs, nose up the face — THEN springs
		var k2 := (t - 0.26) / 0.14
		var q := base
		q.y = _from.y + reach * 0.35 - 0.026 * sin(k2 * PI * 0.5)
		return q
	var u := (t - 0.40) / 0.60
	var low := reach * 0.35 - 0.026
	# Round 11: EVERY climb is the one approved spring now. The tall wall climb —
	# and its fold and two-jump successors — is deleted on the user's call, and
	# the scanner's cap (max_jump_up) means a face this code sees is never more
	# than one spring tall. High places are reached over other furniture.
	var q := base.lerp(_to, smoothstep(0.55, 1.0, u))
	var rs := _keys(u, [[0.0, 0.0], [0.45, 0.72], [1.0, 1.0]])
	q.y = _from.y + low + (dy - low) * rs + 0.02 * rs * (1.0 - smoothstep(0.7, 1.0, u))
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
func _start_kind(kind: String, to: Vector3, edge: Vector3, dur: float) -> void:
	_climb_rig()
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
	# round 12 (playtest): dragging is NO bar here any more — hauling a chicken leg
	# DOWN off a table is the whole point of dragging, and with this refused she
	# could only back blindly off the edge and fall with it
	if running or surface_id == "floor" or d.length() < 0.2:
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


func _climb_tilt(t: float) -> float:
	# round 7: the warped clip poses the body now — round 6's 76-80 degrees ON TOP
	# of the clip's own pitch doubled the rotation into a backflip. This is only a
	# lean: into the face on the spring, rolling over the edge at the end.
	if t < 0.26:
		return 30.0 * smoothstep(0.35, 1.0, t / 0.26)
	if t < 0.40:  # crouching: leans in a touch further as she loads the spring
		return 30.0 + 8.0 * smoothstep(0.0, 1.0, (t - 0.26) / 0.14)
	var u := (t - 0.40) / 0.60
	return _keys(u, [[0.0, 36.0], [0.45, 20.0], [0.85, -12.0], [1.0, 0.0]])  # round 11: the one spring's lean, for every climb


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
	if jumping:
		# round 7: warp the one-shot onto the jump's length — its crouch, launch
		# and pull-over land with the path's stages instead of ending at 0.42 s
		# and freezing for the rest of the way up
		anim.set_speed(clampf((0.42 if _jump_up else 0.25) / maxf(_dur * 0.85, 0.05), 0.5, 1.8))
	else:
		# round 8: feet must match the GROUND, not the intent — the clip is sped
		# from her ACTUAL velocity against the clips' own measured foot speeds
		# (WALK_CLIP & co, tester --test=stride); intent-speed was the ice-skating
		var cbase := 0.0
		match clip:
			"walk": cbase = WALK_CLIP
			"run": cbase = RUN_CLIP
			"sneak": cbase = SNEAK_CLIP
			"carry_walk": cbase = CARRY_CLIP
		var hspd := Vector3(velocity.x, 0.0, velocity.z).length()
		if cbase > 0.0 and is_on_floor() and hspd > 0.05:
			anim.set_speed(clampf(hspd / cbase * (1.0 if clip == "run" else 0.8), 0.3, 14.0))
		else:
			anim.set_speed(0.15 if clip == "sneak" else 1.0)
