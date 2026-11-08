class_name CatAI
extends Agent
## The cat, ported from the prototype's updateCat. Modes:
## away · sleep (a sleep meter that noise lowers; half awake it lifts its head and looks) · eat → to bed ·
## wander / idle · investigate (a noise) · search · chase · watch (the rat is up high: it waits below).
## It can't climb, can't get under furniture, and loses you in hiding spots.

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


func awake() -> bool: return mode != Mode.AWAY and mode != Mode.SLEEP


func setup(n: Dictionary) -> void:
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
	if d < radius * _sense() and mode != Mode.CHASE and mode != Mode.WATCH:
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


func _process(dt: float) -> void:
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

	if speed > 1.3: play("run", 0.15)
	elif speed > 0.05: play("walk")
	elif mode == Mode.SEARCH: play("look_around")
	else: play("idle_sit", 0.3)

	if G.grace_t <= 0.0 and not _rat_hidden() and not rat.jumping and rat.global_position.y < 0.3 and dist < 0.3:
		play("pounce", 0.05)
		G.caught("Gotcha!", global_position + Vector3.UP * 0.58)
