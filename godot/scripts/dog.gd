class_name DogAI
extends Agent
## The dog (night 17), ported from the prototype's updateDog. It sleeps until a noise or the rat gets close, then
## follows her scent trail on the floor (30 seconds long; a puddle or the litter box washes it off), chases her when
## it sees her, barks, and gets distracted by a knocked-over ball. It can't climb or get under furniture.

enum Mode { SLEEP, TRACK, CHASE, PLAY }

var mode := Mode.SLEEP
var sleep := 1.0
var sees := false
var trail: Array = []  # [position, time]

var _calm := 0.0
var _lost := 0.0
var _bark := 0.0
var _repath := 0.0
var _play := 0.0


func setup(at: Vector3) -> void:
	global_position = at
	rotation.y = Nights.yaw_to(Vector3.LEFT)
	eye_height = 0.4


func awake() -> bool: return mode != Mode.SLEEP


func hear(at: Vector3, radius: float, amt: float) -> void:
	if mode != Mode.SLEEP:
		return
	var d := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if d >= radius:
		return
	sleep -= amt * (1.0 - d / radius) * 1.2
	_calm = 2.5
	if sleep <= 0.0:
		wake_up()


func wake_up() -> void:
	if mode != Mode.SLEEP:
		return
	mode = Mode.TRACK
	sleep = 0.0
	G.run.dogWoke = true
	G.bubble_on("*sniff sniff* WOOF?", self, 0.75, 1.8)
	if anim:
		anim.play("wake_up", 0.1, true)


## A knocked-over thing landed: chase it instead.
func distract(at: Vector3, kind: String) -> void:
	if mode == Mode.SLEEP or global_position.distance_to(at) > 4.5:
		return
	mode = Mode.PLAY
	_play = 7.0
	path_to(at)
	G.bubble_on("Woof? Ball!", self, 0.75, 1.4)
	if kind == "ball":
		G.tasks.set_flag("dogBall")


func wash_trail() -> void:
	if trail.is_empty():
		return
	trail.clear()
	G.tasks.set_flag("trailBroken")
	G.bubble_at("Scent washed off", rat.global_position + Vector3.UP * 0.25, 1.4, Color(0.54, 0.7, 0.88))


func _see() -> bool:
	if rat.hidden() or rat.in_nest:
		return false
	var d := dist_rat()
	return (d < 0.4 or (d < 3.0 and angle_to_rat() < 43.0)) and line_of_sight()


func _process(dt: float) -> void:
	if not G.playing():
		sees = false
		return
	var now := G.night_time
	if rat.surface_id == "floor" and not rat.jumping and rat.global_position.y < 0.05:
		if trail.is_empty() or (trail[-1][0] as Vector3).distance_to(rat.global_position) > 0.1:
			trail.append([rat.global_position, now])
	while not trail.is_empty() and now - float(trail[0][1]) > 30.0:
		trail.pop_front()

	var dist := dist_rat()
	speed = 0.0
	_bark -= dt
	if mode == Mode.SLEEP:
		sees = false
		_calm -= dt
		if _calm <= 0.0:
			sleep = minf(1.0, sleep + dt * 0.04)
		if dist < 0.3:
			wake_up()
		if dist < 1.2:
			G.tasks.set_flag("passDog")
		play("sleep", 0.4)
		return

	sees = G.grace_t <= 0.0 and _see()
	if sees and mode != Mode.CHASE and mode != Mode.PLAY:
		mode = Mode.CHASE
		_lost = 0.0
		G.run.dogChased = true
	match mode:
		Mode.CHASE:
			_lost = 0.0 if sees else _lost + dt
			_repath -= dt
			if _repath <= 0.0:
				_repath = 0.3
				path_to(G.grid.free_point(rat.global_position))
			follow(1.65 + G.stars * 0.06, dt)
			if _bark <= 0.0:
				_bark = 1.3
				G.noise(global_position, 5.0, "WOOF! WOOF!", true, 0.6, false, "dog")
			if _lost > 2.5:
				mode = Mode.TRACK
				path.clear()
		Mode.PLAY:
			if not follow(1.5, dt):
				_play -= dt
				rotate_y(dt * 3.0)
				if randf() < dt:
					G.bubble_on("*happy panting*", self, 0.7, 1.0)
				if _play <= 0.0:
					mode = Mode.TRACK
					path.clear()
		_:
			_repath -= dt
			if _repath <= 0.0 or path.is_empty():
				_repath = 1.0
				if not trail.is_empty():
					var ni := 0
					var nd := 1e9
					for i in trail.size():
						var d2 := (trail[i][0] as Vector3).distance_to(global_position)
						if d2 < nd:
							nd = d2
							ni = i
					path_to(G.grid.free_point(trail[mini(trail.size() - 1, ni + 6)][0]))
					if randf() < 0.3:
						G.bubble_on("*sniff sniff*", self, 0.7, 1.0)
				else:
					path_to(G.grid.random_free(2.0, global_position))
			follow(0.95, dt)

	if speed > 1.3: play("run", 0.15)
	elif speed > 0.05: play("sniff_ground" if mode == Mode.TRACK else "walk")
	elif mode == Mode.PLAY: play("play")
	else: play("idle")

	if G.grace_t <= 0.0 and not rat.hidden() and not rat.in_nest and rat.surface_id == "floor" and not rat.jumping and rat.global_position.y < 0.05 and dist < 0.28:
		G.caught("WOOF!", global_position + Vector3.UP * 0.8)
		mode = Mode.TRACK
		path.clear()
		trail.clear()
