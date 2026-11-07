class_name OwnerAI
extends Agent
## The owner, ported from the prototype's startVisit / updateHuman. He comes in through the door on the east wall,
## either on a schedule (a glass of water, a flashlight patrol) or when the wanted level reaches his star.
## He sees far (even onto tables), chases, swats with a slipper, and leaves when he loses interest.

enum Mode { AWAY, COMING, PATROL, LOOK, DRINK, CHASE, LEAVING }

var mode := Mode.AWAY
var door := Vector3.ZERO
var flashlight: SpotLight3D
var room_light: Light3D
var _step_d := 0.0
var body: Node3D
var sees := false
var night: Dictionary

var _plan: Dictionary = {}
var _plan_active := false
var _plan_started := false
var _chased := false
var _known := false
var _visit := 0
var _wp := 0
var _t := 0.0
var _t2 := 0.0
var _see := 0.0
var _lost := 0.0
var _low := 0.0
var _sweep := 0.0
var _repath := 0.0
var _last := Vector3.ZERO


func in_room() -> bool: return mode != Mode.AWAY and mode != Mode.COMING
func _star() -> int: return Nights.threat_star(night, "owner")
func _has_plan() -> bool: return str(_plan.get("type", "")) != ""


func setup(n: Dictionary, door_point: Vector3) -> void:
	night = n
	door = door_point
	_plan = n.get("owner", {})
	eye_height = 1.5
	global_position = door
	_show(false)


func _show(on: bool) -> void:
	if body:
		body.visible = on
	if flashlight:
		flashlight.visible = on and _has_plan() and _plan_active and not bool(_plan.get("light", true))


func _room_light(on: bool) -> void:
	if room_light:
		if room_light.visible != on:
			Sfx.play("light_switch", room_light.global_position)
		room_light.visible = on


func hear(at: Vector3, _radius: float, big: bool) -> void:
	if (mode == Mode.PATROL or mode == Mode.LOOK) and global_position.distance_to(at) < (7.0 if big else 3.2):
		mode = Mode.PATROL
		path_to(at)
		_last = at
		_known = true


func _start_visit() -> void:
	_visit += 1
	_plan_active = true; _plan_started = false; _chased = false
	mode = Mode.COMING; _t = 2.4
	var water := str(_plan.type) == "water"
	G.bubble_at("Stomp… stomp… *yawn*" if water else "Click. A flashlight…", door + Vector3.UP * 1.2, 2.2)
	G.banner("The owner is coming!" if water else "Flashlight patrol!", "Hide under furniture or in a crack until he leaves.", 3.5)


func _end_visit() -> void:
	mode = Mode.LEAVING
	path_to(door)


func _process(dt: float) -> void:
	sees = false
	if not G.playing():
		return
	speed = 0.0
	if _star() > 5 and not _has_plan():
		return
	var at: Array = _plan.get("at", [])
	if _has_plan() and mode == Mode.AWAY and _visit < at.size() and G.night_time >= float(at[_visit]):
		_start_visit()
	if mode == Mode.AWAY:
		if G.stars >= _star():
			mode = Mode.COMING; _t = 2.4
			G.bubble_at("Stomp… stomp… stomp…", door + Vector3.UP * 1.2, 2.2)
		return
	if mode == Mode.COMING:
		_t -= dt
		if _t > 0.0:
			return
		mode = Mode.PATROL
		global_position = door
		rotation.y = Nights.yaw_to(Vector3.LEFT)
		Sfx.play("door", door + Vector3.UP)
		path.clear(); _lost = 0.0; _see = 0.0; _low = 0.0; _t = 0.0
		_show(true)
		_room_light(not (_plan_active and _has_plan() and not bool(_plan.get("light", true))))
		G.bubble_on("That’s it, rat, you’re done!" if G.stars >= 5 else "Who’s rustling in here?!", self, 1.95, 2.4)
		return
	if mode == Mode.PATROL and _plan_active and not _plan_started:
		_plan_started = true; path.clear(); _wp = 0

	_t += dt
	var dist := dist_rat()
	var in_cone := dist < 3.3 and angle_to_rat(_sweep) < 28.6
	sees = mode != Mode.LEAVING and not (rat.hidden() or rat.in_nest) and (in_cone or dist < 0.5) and line_of_sight()
	if sees:
		G.run.seenOwner = true
		_see += dt; _last = rat.global_position; _known = true
		G.add_alarm(dt * 12.0)
	else:
		_see = maxf(0.0, _see - dt * 0.5)
	var mul := 1.0 + maxi(0, G.stars - _star()) * 0.05

	if mode != Mode.LEAVING and mode != Mode.CHASE and _see > 0.35:
		mode = Mode.CHASE; _lost = 0.0; _repath = 0.0
		G.add_alarm(6.0)
		G.bubble_on("Why, you little…!" if randf() < 0.5 else "There you are!", self, 1.95, 1.6)

	match mode:
		Mode.PATROL:
			_sweep = sin(_t * 1.3) * 0.55
			if _plan_active and path.is_empty():
				if str(_plan.type) == "water":
					if _wp == 0:
						path_to(Nights.pos(_plan.get("stand")))
						_wp = 1
					else:
						mode = Mode.DRINK
						_t2 = float(_plan.get("stay", 14.0))
						rotation.y = Nights.yaw_to(Nights.dir(float(_plan.get("face", 0.0))))
						G.bubble_on("*glug glug*", self, 1.95, 2.0)
				else:
					var route: Array = _plan.get("route", [])
					if _wp < route.size():
						path_to(Nights.world(float(route[_wp].x), float(route[_wp].y)))
						_wp += 1
					else:
						_end_visit()
			if mode == Mode.PATROL:
				if path.is_empty():
					var tgt := G.grid.free_point(_last + Vector3(randf_range(-1.1, 1.1), 0, randf_range(-1.1, 1.1))) if (_known and randf() < 0.55) else G.grid.random_free(2.0, global_position)
					path_to(tgt)
				if not follow(0.85 * mul, dt):
					mode = Mode.LOOK; _t2 = 1.6; path.clear()
		Mode.LOOK:
			_t2 -= dt
			_sweep = sin(_t * 2.4) * 0.9
			if _t2 <= 0.0:
				mode = Mode.PATROL
				if _plan_active and _chased:
					_end_visit()
		Mode.DRINK:
			_t2 -= dt
			_sweep = sin(_t * 0.7) * 0.15
			if _t2 <= 0.0:
				G.bubble_on("Ahh. Back to bed.", self, 1.95, 1.8)
				_end_visit()
		Mode.CHASE:
			_chased = true
			_sweep *= maxf(0.0, 1.0 - dt * 5.0)
			_lost = 0.0 if sees else _lost + dt
			_repath -= dt
			if _repath <= 0.0:
				_repath = 0.3
				path_to(G.grid.free_point(rat.global_position if sees else _last))
			if not follow(1.5 * mul, dt) and sees:
				turn(to_rat(), dt * 6.0)
			if _lost > 2.2:
				mode = Mode.LOOK; _t2 = 2.5; path.clear()
				G.bubble_on("Where did it go?..", self, 1.95, 1.8)
		Mode.LEAVING:
			_sweep *= 0.95
			if not _has_plan() and G.stars >= _star():
				mode = Mode.PATROL; path.clear()
			elif not follow(0.95, dt):
				var clean := _plan_active and not _chased
				mode = Mode.AWAY; _known = false; _plan_active = false; _plan_started = false
				Sfx.play("door", door + Vector3.UP)
				_show(false)
				_room_light(false)
				G.tasks.flag("ownerLeft")
				if clean:
					G.tasks.flag("ownerClean")
				return

	if mode != Mode.LEAVING and mode != Mode.CHASE and not _plan_active:
		if G.stars < _star():
			_low += dt
			if _low > 8.0:
				mode = Mode.LEAVING
				path_to(door)
				G.bubble_on("Must be nothing… Back to bed.", self, 1.95, 2.0)
		else:
			_low = 0.0

	if flashlight:
		flashlight.visible = _plan_active and _has_plan() and not bool(_plan.get("light", true))
		flashlight.rotation = Vector3(deg_to_rad(-18.0), _sweep + PI, 0.0)

	_step_d += speed * dt
	if _step_d > 0.6:
		_step_d = 0.0
		Sfx.play("stomp", global_position, 0.0, 1.0, 0.1)
	if speed > 1.2: play("run", 0.15)
	elif speed > 0.05: play("walk")
	elif mode == Mode.DRINK: play("drink")
	elif flashlight and flashlight.visible: play("flashlight_sweep")
	else: play("look_around" if mode == Mode.LOOK else "idle")

	var reach := 0.29 + (0.32 if rat.global_position.y > 0.2 else 0.1)
	if mode != Mode.LEAVING and not (rat.hidden() or rat.in_nest) and not rat.jumping and rat.global_position.y < 1.1 and dist < reach and G.grace_t <= 0.0:
		mode = Mode.LOOK; _t2 = 2.0; path.clear(); _see = 0.0
		if anim:
			anim.play("swat", 0.05, true)
		G.caught("WHACK! Slipper!", global_position + Vector3.UP * 2.0)
