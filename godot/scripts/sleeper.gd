class_name Sleeper
extends Node3D
## Someone asleep in the room (the kid in night 13, party guests in night 14), ported from the prototype's sleepers.
## A sleep meter that noise lowers; at zero they wake up: the kid screams for Mom (and wakes the cat), a guest grumbles.
## While awake they look around and spot an unhidden rat in front of them. Then they doze off again.

var kind := "guest"
var face := Vector3.FORWARD
var sense := 1.0
var sleep := 1.0
var awake_t := 0.0
var anim: ClipPlayer

var _stage := 0
var _calm := 0.0
var _snore := 1.0
var _said := 0.0

var G: Game:
	get: return Game.I


func setup(d: Dictionary, model: Node3D) -> void:
	kind = str(d.get("kind", "guest"))
	sense = float(d.get("sense", 1.0))
	face = Nights.dir(float(d.get("face", 0.0)))
	anim = ClipPlayer.new(model)
	_lie()


func _lie() -> void:
	anim.play("sleep_bed" if kind == "kid" else "sleep_floor", 0.4)


func hear(at: Vector3, radius: float, amt: float) -> void:
	if awake_t > 0.0:
		return
	var d := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if d >= radius:
		return
	sleep -= amt * (1.0 - d / radius) * (1.0 + G.stars * 0.2) * sense
	_calm = 2.5
	if sleep <= 0.0:
		_wake()


func _wake() -> void:
	awake_t = 12.0 if kind == "kid" else 9.0
	sleep = 0.0
	G.run.sleeperWoke = true
	if kind == "kid":
		G.bubble_on("MOOOM! A RAT!!!", self, 1.1, 2.6)
		G.add_alarm(45.0)
		anim.play("sit_up_scream", 0.1, true)
		if G.cat.mode == CatAI.Mode.SLEEP:
			G.cat.wake_up(global_position)
	else:
		G.bubble_on("Huh? Wha…", self, 1.1, 2.0)
		G.add_alarm(20.0)
		anim.play("sit_up", 0.1, true)


func sees_rat() -> bool:
	var rat := G.rat
	if awake_t <= 0.0 or rat.hidden() or rat.in_nest:
		return false
	var d := rat.global_position - global_position
	d.y = 0.0
	if d.length() > 2.6 or rad_to_deg(face.angle_to(d)) > 52.0:
		return false
	return G.ray(global_position + Vector3.UP * 0.6, rat.global_position + Vector3.UP * 0.06).is_empty()


func _process(dt: float) -> void:
	if not G.playing():
		return
	_said -= dt
	if awake_t > 0.0:
		awake_t -= dt
		if sees_rat():
			G.add_alarm(dt * 14.0)
			if _said <= 0.0:
				_said = 1.5
				G.bubble_on("There! A rat!", self, 1.1, 1.2)
		if awake_t <= 0.0:
			sleep = 0.55
			_stage = 1
			G.bubble_on("…zzz", self, 1.0, 1.4)
			_lie()
		return
	_calm -= dt
	if _calm <= 0.0:
		sleep = minf(1.0, sleep + dt * 0.04)
	var st := 0 if sleep > 0.6 else (1 if sleep > 0.3 else 2)
	if st > _stage:
		G.bubble_on("Mmm…" if st == 1 else ("Mom…?" if kind == "kid" else "*snort*"), self, 1.0, 1.3)
	_stage = st
	_snore -= dt
	if _snore <= 0.0 and st == 0:
		_snore = 3.4
		if kind != "kid" and G.rat.global_position.distance_to(global_position) < 5.0:
			G.bubble_on("Zzzz", self, 0.9, 1.4)
