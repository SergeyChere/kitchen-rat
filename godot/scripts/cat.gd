class_name CatAI
extends Agent
## The cat, ported from the prototype's updateCat. Modes:
## away · sleep (a sleep meter that noise lowers; half awake it lifts its head and looks) · eat → to bed ·
## wander / idle · investigate (a noise) · search · chase · watch (the rat is up high: it waits below).
## It can't climb (only at 3 stars of the wanted level it jumps up onto a table, chair or counter after her), can't
## get under furniture, and loses you in hiding spots. Noises: the louder and the closer, the more they alert it.

enum Mode { AWAY, SLEEP, EAT, TO_BED, WANDER, IDLE, INVESTIGATE, SEARCH, CHASE, WATCH }

var mode := Mode.AWAY
var alert := 0.0
var sleep := 1.0
var bed := Vector3.ZERO
var bowl := Vector3.ZERO
var sees := false
var night: Dictionary

var _last := Vector3.ZERO
var _lost := 0.0
var _search := 0.0
var _watch := 0.0
var _idle := 0.0
var _sit := 1.0
var _repath := 0.0
var _meow := 0.0
var _zzz := 1.0
var _calm := 0.0
var _eat := 0.0
var _stage := 0
var _going_home := false
var _jt := -1.0  # a jump up or down in progress (0…1)
var _jfrom := Vector3.ZERO
var _jto := Vector3.ZERO
var _top := false  # up on a table / counter after the rat
var _top_t := 0.0
var _jump_cd := 0.0


func awake() -> bool: return mode != Mode.AWAY and mode != Mode.SLEEP


func setup(n: Dictionary) -> void:
	# gait: the clips' own foot speeds, measured from the paws on the floor (tester --test=stride)
	walk_clip_speed = 0.18; run_clip_speed = 0.39; run_from = 1.05
	accel = 5.0; decel = 8.0; turn_rate = 7.0
	night = n
	bed = Nights.pos(n.get("catBed"))
	bowl = Nights.pos(n.get("bowl")) if (n.get("bowl", []) as Array).size() >= 2 else bed
	global_position = bed
	rotation.y = Nights.yaw_to(Nights.dir(PI * 0.8))
	match str(n.get("cat", "away")):
		"away": mode = Mode.AWAY
		"eating":
			mode = Mode.EAT; sleep = 0.0; _eat = float(n.get("eatTime", 40))
			global_position = bowl + Vector3(0.26, 0, 0.04)
		"awake":
			mode = Mode.IDLE; _idle = 2.5; sleep = 0.0
			if (n.get("catStart", []) as Array).size() >= 2:
				global_position = Nights.pos(n.catStart)
				rotation.y = PI
		_: mode = Mode.SLEEP; sleep = 1.0
	visible = mode != Mode.AWAY


func _sense() -> float: return float(night.get("catSense", 1.0))
func _range() -> float: return ((1.5 + G.stars * 0.1) if (mode == Mode.IDLE and _sit > 0.5) else (2.6 + G.stars * 0.15)) * _sense()
func _rat_hidden() -> bool: return rat.hidden() or rat.in_nest


func hear(at: Vector3, radius: float, big: bool, amt: float, from_knock: bool) -> void:
	if mode == Mode.AWAY:
		return
	var d := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if mode == Mode.SLEEP:
		if d >= radius:
			return
		sleep -= amt * (1.0 - d / radius) * (1.0 + G.stars * 0.25) * float(night.get("sleepSense", 1.0))
		_calm = 2.5
		_last = at
		if sleep <= 0.0:
			wake_up(at)
		return
	var heard := radius * _sense()
	if d >= heard or mode == Mode.CHASE or mode == Mode.WATCH:
		return
	# how much it heard: louder (amt, big) and closer count more; a faint far squeak only turns its head
	var k := (1.0 - d / heard) * clampf(amt, 0.1, 1.0) * (1.6 if big else 1.0)
	alert = clampf(alert + k * 0.5, 0.0, 0.95)
	if k < 0.3 and not from_knock:
		_last = at
		turn(at - global_position, 1.0)
		if mode == Mode.WANDER or mode == Mode.IDLE:
			mode = Mode.IDLE; _idle = 1.5; path.clear()
		G.bubble_on("?", self, 0.5, 0.8)
		return
	if true:
		if from_knock and mode != Mode.INVESTIGATE:
			G.tasks.flag("lure")
		if mode != Mode.INVESTIGATE:
			Sfx.play("meow_q", global_position + Vector3.UP * 0.3)
		mode = Mode.INVESTIGATE
		_last = at
		alert = maxf(alert, 0.25 if radius < 1.0 else 0.4)
		path_to(at)
		_sit = 0.0
		if big or _meow <= 0.0:
			_meow = 2.0
			G.bubble_on("Meow?" if big else "?", self, 0.5, 1.2)


func wake_up(toward = null) -> void:
	if mode == Mode.AWAY:
		visible = true
		global_position = bed
	elif mode != Mode.SLEEP:
		return
	mode = Mode.SEARCH
	_search = 1.8; _sit = 0.6; sleep = 0.0
	G.add_alarm(4.0)
	if toward is Vector3:
		turn(toward - global_position, 1.0)
	G.bubble_on("MRRAW?!", self, 0.46, 1.6)
	Sfx.play("meow_angry", global_position + Vector3.UP * 0.3)
	if str(night.get("cat", "")) == "sleep" and not G.run.catWoke:
		G.banner("You woke the cat!", "Now it prowls the room. Stay out of its sight and hide under furniture.", 4.5)
	G.run.catWoke = true


## After it catches the rat it wanders off for a while.
func after_catch() -> void:
	if mode == Mode.SLEEP or mode == Mode.AWAY:
		return
	mode = Mode.WANDER
	alert = 0.0; _sit = 0.0
	path = G.grid.find_path(global_position, G.grid.random_free(3.8, G.hole_point()))
	G.bubble_on("Hmph.", self, 0.5, 1.2)


## Lying down she sits on top of the cushion, not inside it (and the curled pose sits a little low anyway).
func _lift(dt: float) -> void:
	if anim == null or anim.ap == null:
		return
	var m := anim.ap.owner as Node3D
	if m == null:
		return
	var lying := mode == Mode.SLEEP
	var on_bed := Vector2(global_position.x - bed.x, global_position.z - bed.z).length() < 0.2
	var want := (0.045 + (0.05 if on_bed else 0.0)) if lying else 0.0
	m.position.y = move_toward(m.position.y, want, dt * 0.6) if dt > 0.0 else want


var _breath_base := Vector3.ZERO
var _eyes_done := false


func _living_model(dt: float) -> void:
	# round 5: a sleeping cat BREATHES (a slow swell, ~3.4 s a breath), and her eyes get a
	# fix — the model's Eyes mesh is separate: slightly smaller, a true amber iris with a
	# faint night shine, instead of the flat grey they shipped with.
	if anim == null or anim.ap == null:
		return
	var m := anim.ap.get_parent() as Node3D
	if m == null:
		return
	if _breath_base == Vector3.ZERO:
		_breath_base = m.scale
	if not _eyes_done:
		_eyes_done = true
		var eyes := find_child("Eyes", true, false) as MeshInstance3D
		if eyes:
			eyes.scale = Vector3.ONE * 0.92
			for i in eyes.mesh.get_surface_count():
				var src := eyes.get_active_material(i)
				if src is BaseMaterial3D:
					var d := (src as BaseMaterial3D).duplicate() as StandardMaterial3D
					var nm := d.resource_name
					if nm.contains("Iris"):
						d.albedo_color = Color(0.95, 0.62, 0.15)
						d.emission_enabled = true
						d.emission = Color(0.9, 0.5, 0.1)
						d.emission_energy_multiplier = 0.35
					elif nm.contains("Eye"):
						d.albedo_color = Color(0.07, 0.06, 0.06)
					eyes.set_surface_override_material(i, d)
	if mode == Mode.SLEEP:
		var b := 1.0 + 0.02 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 3.4)
		m.scale = Vector3(_breath_base.x * (2.0 - b), _breath_base.y * b, _breath_base.z * (2.0 - b))
	elif m.scale != _breath_base:
		m.scale = _breath_base


func _process(dt: float) -> void:
	_living_model(dt)
	_lift(dt)
	if not G.playing() or mode == Mode.AWAY:
		sees = false
		return
	var dist := dist_rat()
	speed = 0.0
	_meow -= dt

	if mode == Mode.EAT or mode == Mode.TO_BED:
		if mode == Mode.EAT:
			turn(bowl - global_position, dt * 4.0)
			_eat -= dt; _zzz -= dt
			if _zzz <= 0.0:
				_zzz = 2.6
				G.bubble_on("Crunch crunch", self, 0.4, 1.2)
				Sfx.play("crunch", global_position + Vector3.UP * 0.2)
			if _eat <= 0.0:
				mode = Mode.TO_BED
				path_to(bed)
				G.bubble_on("*yawn*", self, 0.44, 1.4)
			play("eat")
		elif not follow(0.7, dt):
			mode = Mode.SLEEP; sleep = 1.0; _stage = 0; _sit = 1.0
			global_position = bed
		else:
			play("walk")
		var near := not _rat_hidden() and (dist < 0.4 or (dist < 1.1 and angle_to_rat() < 28.0)) and line_of_sight()
		sees = near
		if near:
			mode = Mode.CHASE; alert = 1.0
			G.bubble_on("MEOW!", self, 0.5, 1.2)
		return

	if mode == Mode.SLEEP:
		sees = false
		_calm -= dt
		if _calm <= 0.0:
			sleep = minf(1.0, sleep + dt * 0.045)
		var st := 0 if sleep > 0.6 else (1 if sleep > 0.3 else 2)
		if st > _stage:
			G.bubble_on("Mrr…" if st == 1 else "…?", self, 0.44, 1.4)
		_stage = st
		play(["sleep", "stir", "head_up"][st], 0.4)
		_zzz -= dt
		if _zzz <= 0.0 and st == 0:
			_zzz = 3.2
			Sfx.play("purr", global_position + Vector3.UP * 0.2)
		if st == 2:
			turn(_last - global_position, dt * 2.0)
			if not _rat_hidden() and dist < 1.7 and angle_to_rat() < 46.0 and line_of_sight():
				wake_up(rat.global_position)
				alert = 0.8
				return
		if dist < 0.32 or G.stars >= Nights.threat_star(night, "cat"):
			wake_up(rat.global_position)
		return

	_jump_cd -= dt
	if _jt >= 0.0 or _top:
		_tick_top(dt, dist)
		return

	var rat_high := rat.global_position.y >= 0.3
	var in_cone := dist < _range() and angle_to_rat() < 35.5
	sees = G.grace_t <= 0.0 and not _rat_hidden() and (in_cone or dist < 0.34) and line_of_sight()
	if sees:
		alert += dt * (1.3 + (1.0 - dist / 2.6) * 3.0)
		_last = rat.global_position
		G.add_alarm(dt * 4.0)
	elif mode != Mode.CHASE and mode != Mode.WATCH:
		alert -= dt * 0.45
	alert = clampf(alert, 0.0, 1.0)

	if alert >= 1.0 and mode != Mode.CHASE and mode != Mode.WATCH:
		mode = Mode.WATCH if rat_high else Mode.CHASE
		_lost = 0.0; _watch = 4.0; _repath = 0.0; _sit = 0.0
		G.add_alarm(6.0)
		G.bubble_on("Meow?!" if rat_high else "MEOW!", self, 0.52, 1.2)
		Sfx.play("meow" if rat_high else "meow_angry", global_position + Vector3.UP * 0.3)
	elif alert > 0.35 and sees and (mode == Mode.WANDER or mode == Mode.IDLE):
		mode = Mode.INVESTIGATE
		path_to(rat.global_position)
		_sit = 0.0

	var mul := 1.0 + G.stars * 0.05
	match mode:
		Mode.CHASE:
			if rat_high and sees:
				mode = Mode.WATCH; _watch = 4.0; _repath = 0.0
			else:
				_lost = 0.0 if sees else _lost + dt
				_repath -= dt
				if _repath <= 0.0:
					_repath = 0.25
					path_to(rat.global_position if sees else _last)
				if not follow(1.72 * mul, dt) and sees:
					turn(to_rat(), dt * 7.0)
				if _lost > 1.4:
					mode = Mode.SEARCH; _search = 2.4; alert = 0.6
		Mode.WATCH:
			_repath -= dt
			if _repath <= 0.0:
				_repath = 0.5
				path_to(G.grid.free_point(rat.global_position))
			if not follow(1.2, dt):
				turn(to_rat(), dt * 5.0)
				if _meow <= 0.0 and sees:
					_meow = 2.2
					G.bubble_on("Meow…" if randf() < 0.5 else "Get down here!", self, 0.52, 1.4)
					Sfx.play("meow", global_position + Vector3.UP * 0.3)
			_try_jump_up()
			_watch -= dt * 0.35 if sees else dt
			if not rat_high and sees:
				mode = Mode.CHASE; _lost = 0.0; _repath = 0.0
			elif _watch <= 0.0:
				mode = Mode.WANDER; alert = 0.2; path.clear()
				G.bubble_on("Hmph.", self, 0.5, 1.2)
		Mode.INVESTIGATE:
			if not follow(1.0 * mul, dt):
				mode = Mode.SEARCH; _search = 1.8
		Mode.SEARCH:
			_search -= dt
			rotate_y(dt * 2.2)
			_sit = maxf(0.0, _sit - dt * 2.0)
			if _search <= 0.0:
				mode = Mode.WANDER; alert = minf(alert, 0.2); path.clear()
		Mode.IDLE:
			_idle -= dt
			_sit = minf(1.0, _sit + dt * 2.0) if _idle > 1.2 else maxf(0.0, _sit - dt * 2.0)
			rotate_y(sin(Time.get_ticks_msec() / 1000.0 * 0.9) * dt * 0.6)
			if _idle <= 0.0:
				mode = Mode.WANDER; path.clear(); _sit = 0.0
		_:
			if path.is_empty():
				_going_home = randf() < 0.22
				var home := (bowl + Vector3(0.24, 0, 0)) if (night.get("bowl", []) as Array).size() >= 2 else (bed + Vector3(0.36, 0, 0))
				path_to(home if _going_home else G.grid.random_free(2.6, global_position))
			if not follow(0.7 * (1.0 + G.stars * 0.08), dt):
				mode = Mode.IDLE
				_idle = 4.0 if _going_home else 1.5 + randf() * 3.5
	if mode == Mode.CHASE:
		G.run.chased = true

	if move_anim(): pass
	elif mode == Mode.SEARCH: play("look_around")
	else: play("idle_sit", 0.3)

	if G.grace_t <= 0.0 and not _rat_hidden() and not rat.jumping and rat.global_position.y < 0.3 and dist < 0.3:
		play("pounce", 0.05)
		G.caught("Gotcha!", global_position + Vector3.UP * 0.58)


# ---------- 3 stars: jumping up after her ----------

## Up onto the table / chair / counter she is on, if it's low enough for a cat (≤ 1 m) and the cat is right below.
func _try_jump_up() -> void:
	if G.stars < 3 or _jump_cd > 0.0 or rat.jumping or _rat_hidden() or not rat.is_on_floor():
		return
	var ry := rat.global_position.y
	if ry < 0.3 or ry > 1.0:
		return
	var flat := Vector3(global_position.x - rat.global_position.x, 0, global_position.z - rat.global_position.z)
	if flat.length() > 1.0:
		return
	var land := rat.global_position + flat.normalized() * minf(0.28, flat.length())
	var hit := G.ray(land + Vector3.UP * 0.4, land + Vector3.DOWN * 0.3)
	if hit.is_empty() or absf(hit.position.y - ry) > 0.05:
		land = rat.global_position + flat.normalized() * 0.12
		hit = G.ray(land + Vector3.UP * 0.4, land + Vector3.DOWN * 0.3)
		if hit.is_empty() or absf(hit.position.y - ry) > 0.05:
			return
	_jump(hit.position)
	_top_t = 6.0
	G.bubble_on("MRRAOW!", self, 0.52, 1.2)
	Sfx.play("meow_angry", global_position + Vector3.UP * 0.3)


func _jump(to: Vector3) -> void:
	_jfrom = global_position
	_jto = to
	_jt = 0.0
	path.clear()
	play("pounce", 0.05)


func _tick_top(dt: float, dist: float) -> void:
	if _jt >= 0.0:  # in the air
		_jt += dt / 0.5
		var t := minf(_jt, 1.0)
		var p := _jfrom.lerp(_jto, t)
		p.y = lerpf(_jfrom.y, _jto.y, t) + 0.3 * sin(t * PI)
		global_position = p
		turn(_jto - _jfrom, dt * 10.0)
		play("pounce", 0.05)
		if t >= 1.0:
			_jt = -1.0
			global_position = _jto
			_top = _jto.y > 0.2
			if not _top:
				mode = Mode.SEARCH; _search = 1.5; _jump_cd = 3.0
			Sfx.play("land", global_position, 2.0, 0.7)
		return
	# on top: go for her along the surface, never off the edge
	_top_t -= dt
	G.run.chased = true
	var same := absf(rat.global_position.y - global_position.y) < 0.12 and not _rat_hidden()
	if same:
		var d := Vector3(rat.global_position.x - global_position.x, 0, rat.global_position.z - global_position.z)
		var step := minf(d.length(), 1.3 * dt)
		var np := global_position + d.normalized() * step
		var hit := G.ray(np + Vector3.UP * 0.3, np + Vector3.DOWN * 0.2)
		if not hit.is_empty() and absf(hit.position.y - global_position.y) < 0.05:
			global_position = np
			speed = 1.3
		turn(d, dt * 8.0)
		play("run" if speed > 0.0 else "idle_sit", 0.15)
		if G.grace_t <= 0.0 and not rat.jumping and dist < 0.3:
			play("pounce", 0.05)
			G.caught("Gotcha!", global_position + Vector3.UP * 0.58)
	else:
		play("idle_sit", 0.3)
	if _top_t <= 0.0 or not same and _top_t < 4.5:
		# down again, to the floor nearby
		var down := G.grid.free_point(global_position + global_transform.basis.z * 0.45)
		down.y = 0.0
		_top = false
		_jump(down)
