class_name Game
extends Node3D
## One night, ported from the prototype's update(): builds the room, then runs food, delivery, noise, the wanted
## level and its threats, lives, sniffing, mousetraps, poison, tasks and the clock. The HUD lives in hud.gd.

signal ended(won: bool)

static var I: Game
const STAR_AT := [10, 24, 40, 58, 80]

var night: Dictionary
var night_id := "kitchen"
var tasks: TaskTracker
var grid: NavGrid
var nav: NavWorld
var rat: Rat
var cat: CatAI
var owner_ai: OwnerAI
var cam: FollowCamera
var hud: Hud
var room_light: Light3D
var hole := Vector3.ZERO
var run := {"catWoke": false, "chased": false, "seenOwner": false, "poisonDelivered": false, "caught": false,
	"dogWoke": false, "dogChased": false, "pupCaught": false, "stuck": false, "caged": false, "sleeperWoke": false}
var env: Environment
var moon: DirectionalLight3D
var flickers: Array = []  # [light, base energy, "fire" | "tv" | "steady"]
var tv_light: OmniLight3D
var tv_on := false
var cracks: Array[Vector3] = []
var noisy: Array = []
var gnaws: Array = []
var exit_point := Vector3.ZERO
var dog: DogAI
var vacuum: VacuumAI
var pups: Array[Pup] = []
var sleepers: Array[Sleeper] = []
var pup_warn_t := 0.0
var prompt := ""
var noisy_near := ""  # the noisy thing right by her paws (the HUD noise chip turns orange)
var fx: WorldFx
var nest_pups: Array = []
var cut_bars := false
var fade := 0.0  # 0…1 black
var _fade_to := 0.0
var _cut_t := 0.0
var _cut_phase := ""
var _cues: Array = []
var _cut_cam: Camera3D
var _walk: Array = []
var _panel: Control
var _best_clock := ""
var _rain: Node
const KNOCK_SND := {"cup": "clink", "glass": "clink", "spoon": "clink", "vase": "crash", "jar": "bang", "bottle": "bang",
	"can": "bang", "apple": "thud", "book": "thud", "carton": "thud", "ball": "thud"}
var fed := 0
var lives := 3
var stars := 0
var max_stars := 0
var night_time := 0.0
var grace_t := 0.0
var in_hum := 0
var state := "intro"  # intro, play, pause, won, lost
var end_title := ""
var end_text := ""

var foods: Array[Food] = []
var traps: Array[Trap] = []
var knockables: Array[Knockable] = []
var zones: Array[Zone] = []
var high_surfaces: Array[Node3D] = []

var _evidence := 0.0
var _alarm := 0.0
var _goal_offered := false
var _quiet := 0.0  # seconds since the last noise or sighting: the wanted level cools down
var _unseen := 0.0
var _refill := 0.0
var _noise_t := 0.0
var _bump_t := 0.0
var _stars_done := {}
var _sniffing := false
var _sniff_hold := 0.0
var _scent: Array[Food] = []
var _trails: Array[MeshInstance3D] = []
var _sniff_beat := 0.0
var _builder: LevelBuilder
var _stuck_imm := 0.0
var _stuck_snd := 0.0
var _mom_trail: Array = []
var _idle_t := 0.0
var _last_rp := Vector3.ZERO
var _wash_t := 0.0
var _wash_zone: Zone
var _light_t := 0.0
var _bell_t := 0.0
var _call_t := 0.0
var _next_bolt := 8.0
var _flash_t := 0.0
var _thunder_t := 0.0
var _storm_mask := 0.0
var _blackout := false
var _mud := 0.0
var _light_mul := 1.0
var _ambient := 1.0
var _moon_e := 0.5


func _init(id := "kitchen") -> void:
	night_id = id


func _ready() -> void:
	I = self
	night = Nights.load_night(night_id)
	if Settings.calm:
		night.seconds = float(night.get("seconds", 900)) * 1.3
		night.catSense = float(night.get("catSense", 1.0)) * 0.8
		night.sleepSense = float(night.get("sleepSense", 1.0)) * 0.7
	tasks = TaskTracker.new(night.get("tasks", {}))
	tasks.completed.connect(func(t): hud.task_done(t, true); Sfx.play("task"))
	tasks.failed.connect(func(t): hud.task_done(t, false); Sfx.play("fail"))
	tasks.on_surface = func(a): return not rat.jumping and rat.surface_id.begins_with(a)
	tasks.hidden_in = func(a): return rat.hide_kind() == a
	tasks.keep_broken = _keep_broken

	_builder = LevelBuilder.new(self, night)
	_builder.build()
	_make_rat()
	_make_agents()
	hud = Hud.new()
	add_child(hud)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_builder.build_contents()
	await get_tree().physics_frame
	if Settings.quality != "low":
		SurfaceDetail.new().apply(self)
	for z in find_children("*", "Zone", true, false):
		zones.append(z)
	for b in find_children("*", "StaticBody3D", true, false):
		var s := surface_of(b)
		if s != "floor" and s != "fridge" and b.get_parent() is MeshInstance3D:
			high_surfaces.append(b.get_parent())
	var no_go := []
	for z in zones:
		if z is HideSpot and (z as HideSpot).id != "crack":
			no_go.append(z)
	grid = NavGrid.new(self, no_go)
	nav = NavWorld.new(self, no_go)
	fx = WorldFx.new(self)
	fx.name = "World fx"
	add_child(fx)
	cat.setup(night)
	var door := float(night.get("door", 300))
	owner_ai.setup(night, Nights.world(935, door if door > 0 else 300))
	_make_extras()
	var fd: Dictionary = night.get("food", {})
	for i in int(fd.get("randomCrumb", 4)): spawn_random("crumb")
	for i in int(fd.get("randomCheese", 3)): spawn_random("cheese")
	var ps := int(night.get("poisonStart", 0))
	if ps > 0:
		var c := foods.filter(func(f): return f.is_cheese() and f.id == "" and not f.poison)
		c.shuffle()
		for k in mini(ps, c.size()):
			c[k].make_poison()
	for i in 3:
		_trails.append(_make_trail())
	rat.landed.connect(_on_landed)
	apply_fx()
	_ambient = env.ambient_light_energy if env else 1.0
	_moon_e = moon.light_energy if moon else 0.5
	_last_rp = rat.global_position
	print_verbose("night ready: ", foods.size(), " food, ", zones.size(), " zones")
	if not Settings.shadows():
		for l in find_children("*", "Light3D", true, false):
			(l as Light3D).shadow_enabled = false
	for i in nest_pups.size():
		nest_pups[i].visible = i < 4 - pups.size()
	Sfx.music_night(night.get("music", {}))
	Sfx.music_duck(false)
	if bool(night.get("storm", false)):
		_rain = Sfx.loop("rain_loop")
	_ambience()
	rat.frozen = true
	if state == "intro" and not Main.I._args.has("auto"):
		_start_intro()


## Each room's background sounds: the fridge hums in the kitchen, the boiler in the pantry and the basement,
## water drips there, and a clock ticks in the living rooms. They come from where the thing is.
func _ambience() -> void:
	var decor := str(night.get("decor", "kitchen"))
	var spots := []
	if decor == "kitchen":
		spots.append(["fridge_loop", Nights.world(895, 60, 90)])
		spots.append(["clock_loop", Nights.world(955, 470, 188)])
	elif decor == "pantry":
		spots.append(["drip_loop", Nights.world(600, 560, 200)])
	else:
		spots.append(["clock_loop", Nights.world(480, 4, 180)])
	for f in night.get("furn", []):
		if str(f.t) == "boiler":
			spots.append(["boiler_loop", Nights.world(float(f.x) + float(f.w) / 2.0, float(f.y) + float(f.h) / 2.0, 100)])
		elif str(f.t) == "fridge" and decor != "kitchen":
			spots.append(["fridge_loop", Nights.world(float(f.x) + float(f.w) / 2.0, float(f.y) + float(f.h) / 2.0, 90)])
	for sp in spots:
		var n := Node3D.new()
		n.name = "Ambience " + str(sp[0])
		add_child(n)
		n.global_position = sp[1]
		Sfx.loop(sp[0], n)


func _make_rat() -> void:
	rat = Rat.new()
	rat.name = "Rat"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.055
	cap.height = 0.12
	cs.shape = cap
	cs.position = Vector3(0, 0.062, 0)
	rat.add_child(cs)
	# her body and snout, lying along her length, so her head doesn't poke into walls and furniture
	var body := CollisionShape3D.new()
	var bc := CapsuleShape3D.new()
	bc.radius = 0.04
	bc.height = 0.26
	body.shape = bc
	body.rotation = Vector3(PI / 2.0, 0, 0)
	body.position = Vector3(0, 0.065, 0.02)
	rat.add_child(body)
	rat.stand_shape = cs
	rat.body_shape = body
	add_child(rat)
	rat.global_position = Nights.world(180, 680, 2)
	rat.rotation.y = PI  # facing north, toward the mouse hole
	var model := _builder.spawn("characters/rat_mother", rat.global_position, 0.0, rat)
	model.rotation = Vector3.ZERO
	model.position = Vector3.UP * 0.018  # the paws dip a little in the run and sneak clips
	rat.anim = ClipPlayer.new(model)
	rat.model = model
	var b := LevelBuilder.aabb_of(model)
	rat.mouth = Node3D.new()
	var mouth_at := Vector3(0, model.position.y + b.size.y * 0.33, b.end.z - 0.012)  # (a model without a head bone)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = sks[0] if not sks.is_empty() else null
	var hb := sk.find_bone("Head") if sk else -1
	if sk and sk.find_bone("Tail1") >= 0:
		var ts := TailSway.new()
		ts.name = "TailSway"
		sk.add_child(ts)
		ts.setup(rat, sk)
		rat.tail = ts
	if hb >= 0:
		# held in her teeth: the mouth follows the head bone (and keeps a scale of 1, the model is scaled down);
		# the snout is ~4 cm ahead of the head bone, the mouth a little behind and below its tip
		var att := BoneAttachment3D.new()
		att.bone_name = "Head"
		sk.add_child(att)
		att.add_child(rat.mouth)
		var head_rest := sk.global_transform * sk.get_bone_global_rest(hb)
		var at := head_rest.origin + rat.global_transform.basis.z * 0.028 + Vector3.DOWN * 0.015
		rat.mouth.transform = head_rest.affine_inverse() * Transform3D(rat.global_transform.basis.orthonormalized(), at)
	else:
		rat.add_child(rat.mouth)
		rat.mouth.position = mouth_at
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 0.004
	ring.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.85, 0.2)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	rat.marker = ring
	cam = FollowCamera.new()
	cam.target = rat
	add_child(cam)
	cam.snap(PI)
	cam.sensitivity = 0.25 * Settings.sens
	cam.invert_y = Settings.invert_y
	cam.fov = Settings.fov


func _make_agents() -> void:
	cat = CatAI.new()
	cat.name = "Cat"
	add_child(cat)
	var cm := _builder.spawn("characters/cat", Vector3.ZERO, 0.0, cat)
	cm.position = Vector3.ZERO
	cat.anim = ClipPlayer.new(cm)
	owner_ai = OwnerAI.new()
	owner_ai.name = "Owner"
	add_child(owner_ai)
	var om := _builder.spawn("characters/owner", Vector3.ZERO, 0.0, owner_ai)
	om.position = Vector3.ZERO
	owner_ai.anim = ClipPlayer.new(om)
	owner_ai.body = om
	var fl := SpotLight3D.new()
	fl.spot_angle = 22.0
	fl.spot_range = 6.0
	fl.light_energy = 4.0
	fl.light_color = Color(1, 0.95, 0.8)
	fl.shadow_enabled = true
	fl.visible = false
	owner_ai.add_child(fl)
	fl.position = Vector3(0.15, 1.3, 0.2)
	owner_ai.flashlight = fl
	owner_ai.room_light = room_light


## The dog, the robot vacuum, sleepers and the pups that come along: only in the nights that have them.
func _make_extras() -> void:
	var dd: Array = night.get("dog", [])
	if dd.size() >= 2:
		dog = DogAI.new()
		dog.name = "Dog"
		add_child(dog)
		var dm := _builder.spawn("characters/dog", Vector3.ZERO, 0.0, dog)
		dm.position = Vector3.ZERO
		dog.anim = ClipPlayer.new(dm)
		dog.setup(Nights.pos(dd))
	var dock: Array = night.get("dock", [])
	if dock.size() >= 2 and (bool(night.get("vacuumStart", false)) or (night.get("threats", []) as Array).has("vacuum")):
		vacuum = VacuumAI.new()
		vacuum.name = "Robot vacuum"
		add_child(vacuum)
		var vm := _builder.spawn("characters/robot_vacuum", Vector3.ZERO, 0.0, vacuum)
		vm.position = Vector3.ZERO
		vacuum.dock = Nights.pos(dock) + Vector3(-0.3, 0, 0)
		vacuum.global_position = vacuum.dock
		vacuum.grid = NavGrid.new(self, [], 0.04, 0.075, 0.05)
		vacuum.visible = false
		if bool(night.get("vacuumStart", false)):
			vacuum.start()
	for sd in night.get("sleepers", []):
		var z := Sleeper.new()
		z.name = "Sleeper"
		add_child(z)
		var kid := str(sd.get("kind", "")) == "kid"
		var at := Nights.world(float(sd.x), float(sd.y), float(sd.get("bedH", 0)))
		if kid:
			var hit := ray(at + Vector3.UP * 1.5, at + Vector3.DOWN * 0.5)
			if not hit.is_empty(): at.y = hit.position.y
		else:
			_builder.spawn("props/sleeping_bag", Nights.world(float(sd.x), float(sd.y)), rad_to_deg(Nights.yaw_to(Nights.dir(float(sd.get("face", 0))))) + 90.0, _builder.decor)
		z.global_position = at
		z.rotation.y = Nights.yaw_to(Nights.dir(float(sd.get("face", 0))))
		var m := _builder.spawn("characters/kid" if kid else "characters/guest", at, 0.0, z)
		m.position = Vector3.ZERO
		m.rotation = Vector3.ZERO
		z.setup(sd, m)
		sleepers.append(z)
	var age := float(night.get("pupAge", 0.62))
	var list: Array = night.get("pups", [])
	for i in list.size():
		var pp := Pup.new()
		pp.name = "Pup " + str(list[i])
		add_child(pp)
		var m := _builder.spawn("characters/rat_pup", Vector3.ZERO, 0.0, pp)
		m.position = Vector3.UP * 0.01
		m.scale = Vector3.ONE * (0.75 + age * 0.55)
		pp.global_position = hole + Vector3(0.2 + i * 0.12, 0, -0.2 - i * 0.1)
		pp.rotation.y = PI
		pp.setup(str(list[i]), i, m)
		pups.append(pp)


# ---------- queries ----------

func ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


func sphere_free(p: Vector3, r: float) -> bool:
	var sh := SphereShape3D.new()
	sh.radius = r
	return _shape_free(sh, p)


func box_free(center: Vector3, half: Vector3) -> bool:
	var sh := BoxShape3D.new()
	sh.size = half * 2.0
	return _shape_free(sh, center)


func _shape_free(sh: Shape3D, p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


static func surface_of(collider: Object) -> String:
	if collider is Node and (collider as Node).has_meta("surface"):
		return str((collider as Node).get_meta("surface"))
	return "floor"


func playing() -> bool: return state == "play"
func hole_point() -> Vector3: return hole


func _keep_broken(a: String) -> bool:
	match a:
		"catWoke": return run.catWoke
		"chased": return run.chased
		"caught": return lives < 3
		"seenOwner": return run.seenOwner
		"poison": return run.poisonDelivered
		"dogChase": return run.dogChased
		"dogWoke": return run.dogWoke
		"pup": return run.pupCaught
		"sticky": return run.stuck
		"cage": return run.caged
		"sleeper": return run.sleeperWoke
		"tv": return tv_on
		"balloon":
			for z in noisy:
				if z.kind == "balloon" and z.used: return true
			return false
	return tasks.knocked.has(a)


# ---------- events ----------

## A noise heard within radius (m). amt: how much it disturbs a sleeping cat at point-blank range (1 wakes it).
func noise(at: Vector3, radius: float, label: String, big: bool, amt := -1.0, from_knock := false, src := "") -> void:
	if _storm_mask > 0.0 and not from_knock:
		return  # the thunder drowns it out
	if big:
		for pp in pups:
			if pp.kind == "shy" and not pp.lost() and pp.global_position.distance_to(at) < 3.5:
				pp.freeze_t = 3.0
				pp.force_say("Eek! I can’t move!", 1.8)
	if fx:
		fx.ring(at, radius, big)
	if amt < 0.0:
		amt = 0.9 if big else (0.3 if radius > 1.5 else 0.4)
	_alarm += 7.0 if big else (0.5 if radius > 1.5 else (2.0 if radius > 1.0 else 0.0))
	if big or radius > 1.0:
		_quiet = 0.0
	if label != "":
		bubble_at(label, at + Vector3.UP * 0.24, 1.4, Color(0.95, 0.76, 0.3))
	owner_ai.hear(at, radius, big)
	cat.hear(at, radius, big, amt, from_knock)
	for z in sleepers:
		z.hear(at, radius, amt)
	if dog and src != "dog":
		dog.hear(at, radius, amt)


func add_alarm(a: float) -> void:
	_alarm += a


## Mom hands the food over: it hops from her mouth to the nearest pup in the nest, who squeaks.
func _hand_over(f: Food) -> void:
	var pup: Node3D = null
	var best := 1e9
	for p in nest_pups:
		if p.visible and p.global_position.distance_to(rat.global_position) < best:
			best = p.global_position.distance_to(rat.global_position)
			pup = p
	if pup == null:
		f.queue_free()
		return
	var from := f.global_position
	f.reparent(self, true)
	f.global_position = from
	var to := pup.global_position + Vector3.UP * 0.04
	var tw := create_tween()
	tw.tween_method(func(t: float): if is_instance_valid(f): f.global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 0.12, 0.0, 1.0, 0.45)
	tw.tween_callback(func():
		if is_instance_valid(f): f.queue_free()
		Sfx.play("squeak", to, -6.0, randf_range(1.4, 1.7))
		var cp := ClipPlayer.new(pup)
		cp.play("eat", 0.1)
		get_tree().create_timer(1.6).timeout.connect(func(): if is_instance_valid(pup): cp.play("idle", 0.3)))


func deliver() -> void:
	var poison := 0
	var value := 0
	var cheese := false
	var weight := rat.carry_weight()
	for f in rat.carried:
		if f.poison: poison += 1
		value += f.value()
		if f.is_cheese() and not f.poison: cheese = true
		if f.id != "": tasks.delivered[f.id] = true
		foods.erase(f)
		_hand_over(f)
	tasks.delivered_any = true
	if weight >= 3:
		tasks.set_flag("full")
	rat.carried.clear()
	fed = maxi(0, fed + value - poison * 4)
	var top := hole + Vector3.UP * 0.32
	Sfx.play("poison" if poison > 0 else "deliver")
	if cheese:
		Achievements.unlock("FIRST_CHEESE")
	if poison > 0:
		run.poisonDelivered = true
		bubble_at("Poison! −%d" % (poison * 4), top, 1.6, Color(0.6, 0.88, 0.4))
		bubble_at("Ew! Tummy ache…", top + Vector3.DOWN * 0.1, 2.0)
	else:
		bubble_at("+%d" % value, top, 1.4, Color(0.95, 0.76, 0.3))
		var left := int(night.goal) - fed
		bubble_at("Cheese! Yay!" if cheese else ("Squeak! More!" if left > 8 else ("Almost full!" if left > 3 else "Just a little more!")), top + Vector3.DOWN * 0.1, 1.8)
	var refill := int((night.get("food", {}) as Dictionary).get("refill", 5))
	while refill > 0 and _loose_food() < refill + 3:
		if not spawn_random(""):
			break


func caught(text: String, at: Vector3) -> void:
	if grace_t > 0.0 or state != "play":
		return
	lives -= 1
	run.caught = true
	Sfx.play("caught")
	if text.begins_with("WHACK"):
		Sfx.play("whack", at)
	rat.carrier = null
	bubble_at(text, at, 1.6, Color(0.91, 0.4, 0.29))
	for f in rat.carried:
		f.carried = false
		f.reparent(self, true)
		var p := rat.global_position + Vector3(randf_range(-0.15, 0.15), 0.3, randf_range(-0.15, 0.15))
		var hit := ray(p, p + Vector3.DOWN * 3.0)
		f.global_position = hit.position if not hit.is_empty() else Vector3(p.x, 0, p.z)
		f.rotation = Vector3.ZERO
		f.scale = Vector3.ONE
	rat.carried.clear()
	rat.teleport(hole + Vector3(0.22, 0.02, -0.22), PI * 0.75)
	cam.snap(PI * 0.75)
	grace_t = 3.0
	cat.after_catch()
	_alarm += 10.0
	if lives <= 0:
		_end(false, "You got caught", "The pups got %d of %d and are waiting for Mom. Top wanted level: %s." % [fed, int(night.goal), _star_text(max_stars)])


func knock_landed(k: Knockable, at: Vector3) -> void:
	var breaks := k.kind == "cup" and at.y < 0.2  # a mug that hits the floor breaks
	print_verbose("knock landed ", k.kind, " at ", at)
	noise(at, 4.6, "Crash!" if breaks else k.sound(), true, -1.0, true)
	var loud := clampf(remap(k._speed, 1.2, 4.0, -8.0, 2.0), -8.0, 2.0)  # harder hit, louder
	Sfx.play("crash" if breaks else KNOCK_SND.get(k.kind, "thud"), at, loud)
	if breaks:
		var shards := _builder.spawn("props/mug_broken", Vector3(k.global_position.x, 0.0, k.global_position.z), randf() * 360.0, _builder.decor)
		if shards:
			# called from the mug's own collision signal: physics state may only change after the physics step
			k.visible = false
			k.set_deferred("collision_layer", 0)
			k.set_deferred("freeze", true)
			k.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	if vacuum and vacuum.on and vacuum.global_position.distance_to(at) < 0.8:
		vacuum.stun()
	if dog:
		dog.distract(at, k.kind)
	if k.spawn != "":
		spawn_food(k.spawn, at + Vector3(0.14, 0, 0), "", false)
	for t in traps:
		if t.sprung or Vector2(t.global_position.x - at.x, t.global_position.z - at.z).length() > 0.24:
			continue
		t.spring()
		spawn_food("cheese", t.global_position + Vector3(0.1, 0, 0.08), "bait", false)
		tasks.flag("disarm")
		Achievements.add("TRAP_BREAKER", 1, 5)
		bubble_at("Snap! Disarmed", t.global_position + Vector3.UP * 0.3, 1.4, Color(0.62, 0.82, 0.48))


## Things standing in a row fall like dominoes (the prototype's knock groups).
func knock_group(k: Knockable) -> void:
	var n := 0
	for o in knockables:
		if o != k and o.group == k.group and not o.knocked:
			n += 1
			var other := o
			get_tree().create_timer(0.22 * n).timeout.connect(func(): if is_instance_valid(other): other.knock(k.push_dir))


func _on_landed(drop: float) -> void:
	Sfx.play("land_big" if drop > 0.5 else "land", rat.global_position)
	if fx and drop > 0.15:
		fx.dust(rat.global_position, drop > 0.5)
	if drop > 0.5 and rat.surface_id == "floor":
		noise(rat.global_position, 1.6, "Thud", false, 0.55)
	for z in zones:
		if z is NoisyZone and z.contains(rat.global_position):
			(z as NoisyZone).on_landed(rat)


# ---------- loop ----------

func _unhandled_input(e: InputEvent) -> void:
	if state == "intro":
		# Space / Esc / Enter skip (not a mouse click: the first click into the window must not skip the story)
		var skip := e.is_action_pressed("jump") or e.is_action_pressed("pause") or e.is_action_pressed("ui_accept")
		if skip and _cut_t > 0.5:
			_skip_intro()
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("pause"):
		if state == "play": _set_paused(true)
		elif state == "pause" and _panel and _panel.has_meta("pause"): _set_paused(false)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("restart") and state in ["pause", "won", "lost"]:
		_restart()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and state == "play" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(dt: float) -> void:
	fade = move_toward(fade, _fade_to, dt / 0.35)
	if state == "intro":
		_tick_intro(dt)
		return
	if state == "outro":
		_tick_outro(dt)
		return
	if state != "play" or grid == null:
		return
	night_time += dt
	if night_time >= float(night.get("seconds", 900)):
		if _free_end() and fed >= int(night.goal):
			_end(true, "The nest is full!", "Dawn came and the pups are fed. Next night: " + str(night.get("teaser", "")))
			return
		_end(false, "Dawn", "The owners are waking up. The pups got %d of %d. There is always tomorrow night." % [fed, int(night.goal)])
		return
	grace_t = maxf(0.0, grace_t - dt)
	var rp := rat.global_position
	prompt = ""
	noisy_near = ""
	for z in noisy:
		if z.once and z.used:
			continue
		if absf(z.global_position.y - rp.y) < 0.12 and z.contains_xz(rp, 0.35):
			noisy_near = z.sound
			break
	_tick_rat_noise(dt)
	_keep_in_room(rp)
	if Input.is_action_just_pressed("drop"):
		var dropped := rat.drop_one()
		if dropped:
			if not foods.has(dropped):
				foods.append(dropped)
			Sfx.play("pickup", rp, -4.0, 0.8)
	_pick_up(rp)
	_tick_zones(rp, dt)
	_tick_knockables(rp)
	_tick_sniff(dt)
	_tick_gnaw(dt)
	_tick_sticky(dt)
	_tick_world(dt)
	_tick_pups(dt)
	_tick_food_visibility(rp)
	for t in traps:
		if t.sprung or rp.y > 0.05 or rat.jumping or Vector2(t.global_position.x - rp.x, t.global_position.z - rp.z).length() > 0.12:
			continue
		t.spring()
		caught("SNAP!", t.global_position + Vector3.UP * 0.26)
		break
	if state != "play":
		return
	_refill -= dt
	if _refill <= 0.0:
		_refill = 3.0
		var refill := int((night.get("food", {}) as Dictionary).get("refill", 5))
		if refill > 0 and _loose_food() < refill:
			spawn_random("")
	_tick_flags()
	tasks.tick()
	_tick_wanted(dt)
	var chase := cat.mode == CatAI.Mode.CHASE or owner_ai.mode == OwnerAI.Mode.CHASE or (dog != null and dog.mode == DogAI.Mode.CHASE)
	Sfx.music_layers(stars / 4.0, chase)
	if _free_end() and fed >= int(night.goal) and not _goal_offered and not (tasks.has_tasks() and tasks.chain_done()):
		_goal_offered = true
		_offer_finish()
	if fed >= int(night.goal) and (not tasks.has_tasks() or tasks.chain_done()):
		if bool(night.get("finale", false)):
			_end(true, "The End", "The family slipped out under the front door before dawn. Somewhere out there, four grown-up rats are bringing food home to their mom.")
		else:
			_end(true, "The nest is full!", "The pups are fed. Next night: " + str(night.get("teaser", "")))


var _safe_p := Vector3.INF


## A safety net: if she ever ends up outside the room (through a gap, onto a wall top), put her back where she
## last stood safely.
func _keep_in_room(rp: Vector3) -> void:
	var inside := rp.x > -4.95 and rp.x < 4.95 and rp.z > -3.1 and rp.z < 4.95 and rp.y > -0.3 and rp.y < 2.6
	if inside:
		if rat.is_on_floor() and not rat.jumping and rp.y < 2.35:
			_safe_p = rp
		return
	if _safe_p != Vector3.INF:
		rat.teleport(_safe_p, rat.rotation.y)
	else:
		rat.teleport(hole + Vector3(0, 0, -0.2), PI)
	bubble_at("Whoa!", rat.global_position + Vector3.UP * 0.3, 1.0)


func _tick_rat_noise(dt: float) -> void:
	_noise_t -= dt
	_bump_t -= dt
	if not rat.moving() or rat.jumping:
		return
	var on_floor := rat.surface_id == "floor"
	if rat.dragging() and _noise_t <= 0.0:
		Sfx.play("scrape", rat.global_position, -4.0 if rat.sneaking else 0.0)
		_noise_t = 0.6
		noise(rat.global_position, 0.6 if rat.sneaking else 1.2, "", false, 0.05 if rat.sneaking else 0.15)
	elif rat.running and _noise_t <= 0.0:
		Sfx.play("step", rat.global_position, 5.0, 0.9)
		_noise_t = 0.35
		noise(rat.global_position, 2.1, "", false, 0.3)
	elif not rat.running and not rat.sneaking and on_floor and in_hum == 0 and _noise_t <= 0.0:
		Sfx.play("step", rat.global_position)
		_noise_t = 0.45
		noise(rat.global_position, 0.95, "", false, 0.1)
	if rat.running and on_floor and rat.blocked and _bump_t <= 0.0:
		_bump_t = 0.9
		noise(rat.global_position, 1.7, "Thump!", false, 0.45)


func _pick_up(rp: Vector3) -> void:
	if rat.jumping:
		return
	for i in range(foods.size() - 1, -1, -1):
		var f := foods[i]
		if f.carried or f.hidden:
			continue
		var d := f.global_position - rp
		if f.has_meta("dropped_at"):  # she just put it down: only once she has stepped away
			if Vector2(d.x, d.z).length() > 0.3:
				f.remove_meta("dropped_at")
			continue
		if absf(d.y) > 0.12 or Vector2(d.x, d.z).length() > 0.17:
			continue
		if f.is_find:
			Sfx.play("cheese")
			toast(f.label if f.label != "" else "A find for the nest!")
			tasks.set_flag(f.type)
			tasks.flag("collected")
			foods.remove_at(i)
			f.queue_free()
			continue
		if rat.carry_weight() + f.weight() > rat.capacity:
			continue
		if fx:
			fx.sparkle(f.global_position, f.is_cheese())
		rat.carry(f)
		Sfx.play("cheese" if f.is_cheese() else "pickup", rp)
		if f.id != "":
			tasks.picked[f.id] = true
			if owner_ai.mode == OwnerAI.Mode.DRINK:
				tasks.set_flag("underNose")
		if not f.poison and not f.has_meta("evidence"):  # once per piece: dropping it (G) and picking it up again adds nothing
			f.set_meta("evidence", true)
			_evidence += 9.0 if f.is_cheese() else 3.0
		if f.is_cheese():
			bubble_at("Cheeese!", rp + Vector3.UP * 0.3, 1.2)


func _tick_zones(rp: Vector3, dt: float) -> void:
	for z in zones:
		var inside := z.contains(rp)
		if inside and not z.inside: z.enter(rat)
		if not inside and z.inside: z.exit(rat)
		z.inside = inside
		if inside: z.stay(rat, dt)


func _tick_knockables(rp: Vector3) -> void:
	var push := Input.is_action_just_pressed("push")
	for k in knockables:
		if k.knocked or rat.jumping:
			continue
		var d := k.global_position - rp
		if absf(d.y) > 0.2:
			continue
		var flat := Vector3(d.x, 0, d.z)
		var dist := flat.length()
		if k.trap and dist < 0.22 and rat.moving() and not rat.sneaking:
			k.knock(k.push_dir)
			bubble_at("Oops!", rp + Vector3.UP * 0.3, 1.2)
		elif not k.trap and push and dist < 0.3:
			k.knock(flat if flat.length() > 0.01 else rat.global_transform.basis.z)
			bubble_at("Hee hee", rp + Vector3.UP * 0.3, 1.0)
			push = false


func _tick_sniff(dt: float) -> void:
	var want := Input.is_action_pressed("sniff") and not rat.jumping
	var rp := rat.global_position
	if want and not _sniffing:
		_sniffing = true
		Sfx.play("sniff", rat.global_position)
		_sniff_hold = 0.0
		for t in traps:
			if t.sprung or t.global_position.distance_to(rp) > 2.6:
				continue
			bubble_at("Trap!", t.global_position + Vector3.UP * 0.26, 1.4, Color(0.91, 0.4, 0.29))
			if not t.found:
				tasks.flag("trapFound")
			t.reveal()
	if not want:
		_sniffing = false
	if not _sniffing:
		for tr in _trails: tr.visible = false
		return
	var before := _sniff_hold
	_sniff_hold += dt
	# "warmer, colder": she sniffs faster when the camera faces the strongest smell
	if not _scent.is_empty() and is_instance_valid(_scent[0]):
		var to := _scent[0].global_position - rp
		var cf := Vector3(sin(cam.yaw), 0, cos(cam.yaw))
		var facing := clampf(cf.dot(Vector3(to.x, 0, to.z).normalized()), 0.0, 1.0)
		_sniff_beat -= dt
		if _sniff_beat <= 0.0:
			_sniff_beat = lerpf(0.9, 0.22, facing * facing)
			Sfx.play("sniff", rp, lerpf(-12.0, -3.0, facing), lerpf(0.95, 1.25, facing))
	if _sniff_hold > 0.6:
		tasks.set_flag("sniffed")
	if (before <= 0.35 and _sniff_hold > 0.35) or floori(before / 0.5) != floori(_sniff_hold / 0.5):
		_pick_scent(before <= 0.35)
	for i in _trails.size():
		var on := i < _scent.size() and is_instance_valid(_scent[i]) and _sniff_hold > 0.35
		_trails[i].visible = on
		if on:
			_draw_trail(_trails[i], rat.mouth.global_position if rat.mouth else rp, _scent[i].global_position, _scent[i].poison, i)


func _pick_scent(first: bool) -> void:
	var rp := rat.global_position
	var cand := []
	for f in foods:
		if f.carried or f.is_find:
			continue
		var d := f.global_position - rp
		var score := Vector2(d.x, d.z).length() + absf(d.y) * 0.6 - (1.2 if f.is_cheese() else 0.0)
		if score < 9.0:
			cand.append([score, f])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	_scent.clear()
	for i in mini(3, cand.size()):
		var f: Food = cand[i][1]
		_scent.append(f)
		f.reveal_t = 7.0
		f.set_meta("scent_mark", 6.0)  # stays marked for a while after sniffing
		if f.poison and not f.has_meta("seen"):
			f.set_meta("seen", true)
			tasks.flag("poisonSeen")
		if f.hidden and f.global_position.distance_to(rp) < 1.6:
			f.hidden = false
			bubble_at("Something hidden here!", f.global_position + Vector3.UP * 0.2, 1.6)
	if not first:
		return
	if _scent.is_empty():
		bubble_at("I can’t smell anything…", rp + Vector3.UP * 0.34, 1.5)
		return
	var t := _scent[0]
	var to := t.global_position - rp
	var cf := Vector3(sin(cam.yaw), 0, cos(cam.yaw))
	var rel := rad_to_deg(cf.signed_angle_to(Vector3(to.x, 0, to.z), Vector3.UP))
	var ar := absf(rel)
	var where := "ahead" if ar < 29.0 else ("behind" if ar > 149.0 else ("to the left" if rel > 0.0 else "to the right"))
	var up := ", up high" if to.y > 0.2 else (", down low" if to.y < -0.2 else "")
	var what := "Ew, poisoned cheese" if t.poison else ("Cheese" if t.is_cheese() else "Crumbs")
	bubble_at("%s %s%s · %.1f m" % [what, where, up, Vector2(to.x, to.z).length()], rp + Vector3.UP * 0.34, 2.2)


func _tick_food_visibility(rp: Vector3) -> void:
	var open := bool(night.get("openFood", false))
	for f in foods:
		if f.carried:
			continue
		f.visible = not f.hidden and (open or f.is_find or f.reveal_t > 0.0 or f.global_position.distance_to(rp) < 1.6)


func _tick_flags() -> void:
	var rp := rat.global_position
	if cat.visible:
		var dc := Vector2(cat.global_position.x - rp.x, cat.global_position.z - rp.z).length()
		if cat.mode == CatAI.Mode.SLEEP and dc < 0.95: tasks.set_flag("passCat")
		if rat.hidden() and cat.awake() and dc < 1.4: tasks.set_flag("hidNearCat")
		if str(night.get("cat", "")) == "eating" and cat.mode == CatAI.Mode.SLEEP: tasks.set_flag("catNapping")
	if owner_ai.in_room():
		if rat.hidden(): tasks.set_flag("hidFromOwner")
		if owner_ai.mode == OwnerAI.Mode.DRINK: tasks.set_flag("ownerDrinking")
	for z in sleepers:
		if z.awake_t <= 0.0 and z.global_position.distance_to(rp) < 1.3: tasks.set_flag("passSleeper")
	if not pups.is_empty():
		var home := true
		for pp in pups:
			if pp.global_position.distance_to(hole) > 0.6: home = false
			if not gnaws.is_empty() and pp.global_position.distance_to(gnaws[0].global_position) < 0.7: tasks.set_flag("pupAtBag")
		if home: tasks.set_flag("pupHome")
	for zd in night.get("zones", []):
		var a := Nights.world(float(zd.x), float(zd.y))
		var b := Nights.world(float(zd.x) + float(zd.w), float(zd.y) + float(zd.h))
		if rp.x >= a.x and rp.x <= b.x and rp.z >= a.z and rp.z <= b.z:
			tasks.set_flag("zone_" + str(zd.id))


func _tick_wanted(dt: float) -> void:
	var seen := cat.sees or owner_ai.sees or (dog != null and dog.sees)
	for z in sleepers:
		if z.sees_rat(): seen = true
	_unseen = 0.0 if seen else _unseen + dt
	_quiet = 0.0 if seen else _quiet + dt
	if _quiet > 15.0 and _evidence > 0.0:  # quiet for a while: the house slowly forgets the thefts
		_evidence = maxf(_evidence - dt * (0.9 if rat.in_nest else 0.45), 0.0)
	if rat.in_nest and _unseen > 1.0: _alarm -= dt * 14.0
	elif _unseen > 4.0: _alarm -= dt * 5.0
	_alarm = clampf(_alarm, 0.0, 60.0)
	var ns := 0
	if bool(night.get("wanted", false)):
		for t in STAR_AT:
			if _evidence + _alarm >= t: ns += 1
	if ns > stars:
		_on_stars(ns, stars)
	elif ns < stars and state == "play":
		banner("★".repeat(ns) + ("" if ns > 0 else "☆") + " The house calms down", "Wanted level dropped" if ns > 0 else "Nobody is looking for you now", 2.5)
	stars = ns
	max_stars = maxi(max_stars, stars)


func _on_stars(ns: int, os: int) -> void:
	var threats: Array = night.get("threats", [])
	for s in range(os + 1, ns + 1):
		if _stars_done.has(s):
			continue
		_stars_done[s] = true
		Sfx.play("star_up", null, 0.0, 1.0 + s * 0.03)
		var st := "★".repeat(s)
		var t: String = threats[s - 1] if s - 1 < threats.size() else ""
		if t != "":
			_trigger_threat(t)
			match t:
				"cat": banner(st + " The cat woke up", "It can’t climb after you, but it will wait below. Hide to lose it.", 5.0)
				"owner": banner(st + " The owner woke up", "He can spot you even on tables. Hide under furniture or in a crack.", 5.0)
				"traps": banner(st + " Mousetraps!", "The owner set traps. They smell like cheese too, so sniff first (hold E).", 5.0)
				"poison": banner(st + " Poisoned cheese", "Poisoned cheese smells green. Sniff before you grab.", 5.0)
				_: banner(st + " " + t, "", 4.0)
		elif threats.is_empty():
			var tip := str(night.get("starTip", ""))
			banner(st + " The house is restless", tip if tip != "" else "Everyone is faster and sharper now", 3.5)
		else:
			banner(st + " High alert", "Everyone in the house is faster and sharper now", 4.5)
			if threats.has("traps") and s == 5:
				place_traps(2)


func _trigger_threat(t: String) -> void:
	if t == "vacuum" and vacuum: vacuum.start()
	if t == "cat": cat.wake_up()
	elif t == "traps": place_traps(3)
	elif t == "poison":
		var c := foods.filter(func(f): return f.is_cheese() and not f.poison and not f.carried)
		if not c.is_empty(): c.pick_random().make_poison()
		spawn_random("cheese")


# ---------- room mechanics: bags, sticky traps, tunnels, the storm, the washer, the exit, pups ----------

func _tick_gnaw(dt: float) -> void:
	for gs in gnaws:
		if gs.near(rat):
			prompt = ("Hold %s — gnaw it open" % Keys.label("push")) if not gs.done else ""
			if Input.is_action_pressed("push"):
				gs.gnaw(dt)
			return


func _tick_sticky(dt: float) -> void:
	if rat.stuck_t > 0.0:
		rat.stuck_t -= dt
		_stuck_snd -= dt
		prompt = "Stuck! Wait it out…"
		if _stuck_snd <= 0.0:
			_stuck_snd = 0.6
			noise(rat.global_position, 2.0, "Gnaw gnaw" if rat.stuck_t > 2.5 else "Squeak! Stuck!", false, 0.4)
			Sfx.play("gnaw" if rat.stuck_t > 2.5 else "squeak", rat.global_position, 0.0, 1.2)
		if rat.stuck_t <= 0.0:
			_stuck_imm = 1.6
		return
	_stuck_imm = maxf(0.0, _stuck_imm - dt)
	if _stuck_imm > 0.0 or rat.jumping or rat.carrier:
		return
	for z in zones:
		if z is StickyZone and absf(rat.global_position.y - z.global_position.y) < 0.06 and z.contains_xz(rat.global_position, 0.0):
			rat.stuck_t = z.time
			run.stuck = true
			if z.kind == "cage":
				run.caged = true
			tasks.flag("stuck")
			bubble_at(z.label, rat.global_position + Vector3.UP * 0.3, 1.6)
			if z.kind == "cage": Sfx.play("snap", rat.global_position)
			return


## The crack the rat stands in, if it leads somewhere through the wall (night tunnels). -1 if none.
func _tunnel_from() -> int:
	var tl: Array = night.get("tunnels", [])
	if tl.is_empty() or rat.jumping or rat.global_position.y > 0.05:
		return -1
	for i in cracks.size():
		if Vector2(cracks[i].x - rat.global_position.x, cracks[i].z - rat.global_position.z).length() < 0.3:
			for t in tl:
				if int(t.a) == i: return int(t.b)
				if int(t.b) == i: return int(t.a)
	return -1


## Called by the rat when Space is pressed: crawl through the wall if she's in a linked crack.
func use_tunnel() -> bool:
	var to := _tunnel_from()
	if to < 0 or to >= cracks.size():
		return false
	rat.teleport(cracks[to], rat.rotation.y + PI)
	tasks.flag("tunnel")
	Sfx.play("scrape")
	Achievements.add("TUNNELER", 1, 10)
	bubble_at("…through the wall", cracks[to] + Vector3.UP * 0.25, 1.4, Color(0.62, 0.82, 0.48))
	return true


## Effects of noisy things (NoisyZone calls this): the TV, the washing machine, the night light.
func noisy_effect(kind: String, z: Zone) -> void:
	tasks.flag("mistakes")
	match kind:
		"remote":
			if tv_light:
				tv_on = true
				tv_light.visible = true
				if cat.mode == CatAI.Mode.SLEEP:
					cat.wake_up(rat.global_position)
		"washer":
			_wash_t = 45.0
			tasks.set_flag("washer")
			bubble_at("Rumble rumble…", z.global_position + Vector3.UP * 0.6, 2.0)
			_wash_zone = _builder.add_zone(HumZone, "Washer hum", z.global_position, Vector3(6.0, 1.5, 6.0))
			zones.append(_wash_zone)
		"nightlight":
			if room_light and not owner_ai.in_room():
				room_light.visible = true
				_light_t = 6.0
		"puddle", "litter":
			if dog: dog.wash_trail()


func _tick_world(dt: float) -> void:
	var rp := rat.global_position
	if _tunnel_from() >= 0:
		prompt = "%s — crawl through the wall" % Keys.label("jump")
	if _wash_t > 0.0:
		_wash_t -= dt
		if _wash_zone and randf() < dt * 3.0:
			Sfx.play("scrape", _wash_zone.global_position + Vector3.UP * 0.4, -4.0, randf_range(0.6, 0.9))
		if _wash_t <= 0.0 and _wash_zone:
			if _wash_zone.inside: _wash_zone.exit(rat)
			zones.erase(_wash_zone)
			_wash_zone.queue_free()
			_wash_zone = null
	if _light_t > 0.0:
		_light_t -= dt
		if _light_t <= 0.0 and not owner_ai.in_room() and room_light:
			room_light.visible = false
	if bool(night.get("catBell", false)) and cat.awake() and cat.speed > 0.2:
		_bell_t -= dt
		if _bell_t <= 0.0:
			_bell_t = 0.5
			Sfx.play("bell", cat.global_position + Vector3.UP * 0.25)
			if randf() < 0.25 and cat.global_position.distance_to(rp) < 6.0:
				bubble_on("♪ ding", cat, 0.42, 0.8)
	if bool(night.get("storm", false)):
		_tick_storm(dt, rp)
	# a chasing cat calls the owner over
	_call_t = maxf(0.0, _call_t - dt)
	if cat.mode == CatAI.Mode.CHASE and owner_ai.mode == OwnerAI.Mode.PATROL and _call_t <= 0.0:
		_call_t = 4.0
		owner_ai.hear(rp, 20.0, true)
		bubble_on("What is it, kitty?", owner_ai, 1.95, 1.6)
	if exit_point != Vector3.ZERO and Vector2(rp.x - exit_point.x, rp.z - exit_point.z).length() < 0.45:
		tasks.set_flag("exitMom")
		if not pups.is_empty():
			var all := true
			for pp in pups:
				if pp.lost() or pp.global_position.distance_to(exit_point) > 0.75: all = false
			if all: tasks.set_flag("allOut")
	_tick_lights(dt)
	_last_rp = rp


func _tick_storm(dt: float, rp: Vector3) -> void:
	_next_bolt -= dt
	_flash_t = maxf(0.0, _flash_t - dt)
	_storm_mask = maxf(0.0, _storm_mask - dt)
	if _next_bolt <= 0.0:
		_next_bolt = 11.0 + randf() * 9.0
		_flash_t = 0.35
		_thunder_t = 1.1
		if rat.hidden():
			tasks.set_flag("hidLightning")
		else:
			# the flash shows her to anyone looking
			if cat.awake() and cat.global_position.distance_to(rp) < 4.2:
				cat.hear(rp, 6.0, true, 0.0, false)
			owner_ai.hear(rp, 5.0, true)
	if _thunder_t > 0.0:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_storm_mask = 2.6
			Sfx.play("thunder")
			bubble_at("BOOM", rp + Vector3.UP * 0.9, 1.2, Color(0.81, 0.85, 1.0))
	if _storm_mask > 0.0:
		_mud += Vector2(rp.x - _last_rp.x, rp.z - _last_rp.z).length()
		if _mud > 0.6:
			tasks.set_flag("thunderMove")
	else:
		_mud = 0.0
	if env:
		env.ambient_light_energy = _ambient * (0.55 if _blackout else 1.0) + _flash_t * 4.0
	if moon:
		moon.light_energy = _moon_e * (0.6 if _blackout else 1.0) + _flash_t * 5.0
	var bo := float(night.get("blackout", 0))
	if bo > 0.0 and not _blackout and night_time > float(night.get("seconds", 900)) * bo:
		_blackout = true
		_light_mul = 0.25
		tv_on = false
		if tv_light: tv_light.visible = false
		if room_light: room_light.visible = false
		owner_ai.room_light = null
		banner("The power went out!", "It’s pitch dark. Thunder still hides your steps.", 3.5)
		Sfx.play("light_switch")
		if rat.in_nest or rp.distance_to(hole) < 0.6:
			tasks.set_flag("homeAtBlackout")


func _tick_lights(dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in flickers.size():
		var f: Array = flickers[i]
		var l: OmniLight3D = f[0]
		if not is_instance_valid(l):
			continue
		match str(f[2]):
			"fire":
				l.light_energy = float(f[1]) * _light_mul * (0.82 + 0.12 * sin(t * 7.3 + i) + 0.08 * sin(t * 13.1 + i * 2.0))
				if randf() < dt * 5.0:
					Sfx.play("crackle", l.global_position, 0.0, 1.0, 0.2)
			"tv":
				l.light_energy = float(f[1]) * (1.9 if tv_on else 1.0) * (0.8 + 0.2 * sin(t * 3.0) * sin(t * 5.7 + 1.0))
			_: l.light_energy = float(f[1]) * _light_mul


func nearest_floor_food(from: Vector3, r: float, allow_poison: bool) -> Food:
	var best: Food = null
	var bd := r
	for f in foods:
		if f.carried or f.is_find or f.big() or f.global_position.y > 0.03 or (f.poison and not allow_poison):
			continue
		var near_trap := false
		for t in traps:
			if t.found and not t.sprung and t.global_position.distance_to(f.global_position) < 0.3: near_trap = true
		if near_trap:
			continue
		var d := f.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = f
	return best


func _tick_pups(dt: float) -> void:
	if pups.is_empty():
		return
	pup_warn_t -= dt
	var rp := rat.global_position
	if rat.surface_id == "floor" and not rat.jumping and rp.y < 0.05:
		if _mom_trail.is_empty() or (_mom_trail[-1] as Vector3).distance_to(rp) > 0.08:
			_mom_trail.append(rp)
			if _mom_trail.size() > 80: _mom_trail.pop_front()
	_idle_t = 0.0 if rat.moving() else _idle_t + dt
	if Input.is_action_just_pressed("pups"):
		var any_follow := false
		for pp in pups:
			if pp.mode == Pup.Mode.FOLLOW or pp.mode == Pup.Mode.FETCH: any_follow = true
		for pp in pups:
			if pp.lost() or pp.mode == Pup.Mode.CARRY:
				continue
			if any_follow:
				pp.mode = Pup.Mode.STAY
				var best: Vector3 = pp.global_position
				var bd := 1.4
				var found := false
				for z in zones:
					if z is HideSpot:
						var d: float = z.global_position.distance_to(pp.global_position)
						if d < bd:
							bd = d
							best = Vector3(z.global_position.x, 0, z.global_position.z)
							found = true
				pp.target = best
				pp.force_say("I’ll hide here!" if found else "I’ll wait!")
				tasks.set_flag("pupStay")
			else:
				pp.mode = Pup.Mode.FOLLOW
				pp.force_say("Coming, Mom!")
	if Input.is_action_just_pressed("fetch"):
		for pp in pups:
			if pp.mode == Pup.Mode.FOLLOW or pp.mode == Pup.Mode.STAY:
				var f := nearest_floor_food(rp, 2.0, false)
				if f:
					pp.mode = Pup.Mode.FETCH
					pp.target = f
					pp.force_say("I’ll get it!")
				else:
					pp.force_say("I don’t see any food nearby")
				break
	for pp in pups:
		pp.tick(dt, _mom_trail, _idle_t)


# ---------- spawning ----------

func _loose_food() -> int:
	var n := 0
	for f in foods:
		if not f.carried and not f.is_find: n += 1
	return n


func spawn_model_food(model: String, at: Vector3) -> Food:
	var f := Food.new()
	_builder.foods.add_child(f)
	f.global_position = at
	f.rotation.y = randf() * TAU
	var m := _builder.spawn(model, at, 0.0, f)
	if m:
		m.position = Vector3.ZERO
		m.rotation = Vector3.ZERO
	foods.append(f)
	return f


func spawn_food(type: String, at: Vector3, tag: String, poison: bool) -> Food:
	var f := spawn_model_food(Food.model_for(type), at)
	f.type = type
	f.id = tag
	if poison:
		f.make_poison()
	return f


func spawn_random(type: String) -> bool:
	if type == "":
		type = "cheese" if randf() < 0.3 else "crumb"
	var cheese := type == "cheese"
	var open := bool(night.get("openFood", false))
	var high := not high_surfaces.is_empty() and randf() < ((0.45 if open else 0.8) if cheese else 0.25)
	var poison := cheese and stars >= Nights.threat_star(night, "poison") and randf() < 0.45
	for tries in 60:
		var p: Vector3
		if high:
			var s: Node3D = high_surfaces.pick_random()
			var b := LevelBuilder.world_aabb(s)
			if b.size.x < 0.3 or b.size.z < 0.3:
				continue
			var o := Vector3(randf_range(b.position.x + 0.12, b.end.x - 0.12), b.end.y + 0.3, randf_range(b.position.z + 0.12, b.end.z - 0.12))
			var hit := ray(o, o + Vector3.DOWN * 2.0)
			if hit.is_empty() or hit.normal.y < 0.85 or hit.position.y > 1.2 or (hit.collider as Node).get_parent() != s:
				continue
			p = hit.position
		else:
			p = grid.random_free(1.2, hole)
			if not sphere_free(p + Vector3.UP * 0.08, 0.05):
				continue
		var clash := false
		for f in foods:
			if not f.carried and Vector2(f.global_position.x - p.x, f.global_position.z - p.z).length() < 0.24:
				clash = true
		for k in knockables:
			if Vector2(k.global_position.x - p.x, k.global_position.z - p.z).length() < 0.24:
				clash = true
		if clash:
			continue
		spawn_food(type, p, "", poison)
		return true
	return false


func add_trap(at: Vector3, hidden: bool) -> Trap:
	var t := Trap.new()
	t.hidden = hidden
	_builder.decor.add_child(t)
	t.global_position = at
	t.rotation.y = randf() * TAU
	var m := _builder.spawn("props/mousetrap", at, 0.0, t)
	if m:
		m.position = Vector3.ZERO
		m.rotation = Vector3.ZERO
	traps.append(t)
	return t


func place_traps(n: int) -> void:
	var placed := 0
	for t in 500:
		if placed >= n:
			break
		var p := grid.random_free(0.0, Vector3.ZERO)
		if p.distance_to(hole) < 1.5 or p.distance_to(rat.global_position) < 0.9 or p.distance_to(owner_ai.door) < 0.7:
			continue
		var near := false
		for q in traps:
			if q.global_position.distance_to(p) < 1.0: near = true
		if near:
			continue
		var by_furn := grid.blocked_at(p + Vector3.RIGHT * 0.45) or grid.blocked_at(p + Vector3.LEFT * 0.45) or grid.blocked_at(p + Vector3.FORWARD * 0.45) or grid.blocked_at(p + Vector3.BACK * 0.45)
		if not by_furn and randf() < 0.7:
			continue
		add_trap(p + Vector3(randf_range(-0.04, 0.04), 0, randf_range(-0.04, 0.04)), false)
		placed += 1


# ---------- states: cutscenes, pause, results ----------

func begin() -> void:
	if grid == null:
		return
	_cut_phase = ""
	cut_bars = false
	_fade_to = 0.0
	rat.scripted = false
	if is_instance_valid(_cut_cam):
		_cut_cam.queue_free()
	cam.cam.current = true
	var p := Nights.world(180, 640, 1)
	rat.teleport(p, PI)
	cam.snap(PI)
	for i in pups.size():
		pups[i].global_position = Nights.world(150 + i * 20, 660)
	state = "play"
	rat.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var st := str(night.get("startTitle", ""))
	if st != "":
		banner(Keys.text(st), Keys.text(str(night.get("startSub", ""))), 5.5)
	else:
		banner("Bring %d food before dawn" % int(night.goal), "", 4.5)


func _cut_camera() -> void:
	if not is_instance_valid(_cut_cam):
		_cut_cam = Camera3D.new()
		_cut_cam.fov = 55.0
		_cut_cam.near = 0.02
		add_child(_cut_cam)
	_cut_cam.current = true


## The nest scene before a night (and the prologue before night 1, the first time).
func _start_intro() -> void:
	state = "intro"
	cut_bars = true
	_cut_camera()
	rat.scripted = true
	rat.frozen = true
	rat.global_position = Nights.world(150, 700, 1)
	rat.rotation.y = Nights.yaw_to(Vector3(0.5, 0, 1))
	rat.anim.play("sleep")
	for i in pups.size():
		pups[i].global_position = Nights.world(120 + i * 22, 735)
	fade = 1.0
	_fade_to = 0.0
	Sfx.music_night(night.get("music", {}))
	if bool(night.get("prologue", false)) and not Progress.seen_prologue:
		Progress.seen_prologue = true
		Progress.save()
		_prologue()
		return
	_night_intro()


func _night_intro() -> void:
	_cut_phase = "nest"
	_cut_t = 0.0
	rat.global_position = Nights.world(150, 700, 1)
	for p in nest_pups: p.visible = nest_pups.find(p) < 4 - pups.size()
	var lines: Array = night.get("introPups", [])
	var talkers := _talkers()
	_cues = []
	for i in mini(lines.size(), 3):
		var who = talkers[i % talkers.size()] if not talkers.is_empty() else null
		_cues.append([0.7 + i * 0.8, func(): if who: bubble_on(str(lines[i]), who, 0.2, 1.8); Sfx.play("squeak", null, -6.0, randf_range(1.3, 1.5))])
	var mom := str(night.get("introMom", ""))
	_cues.append([3.4, func(): rat.anim.play("idle"); if mom != "": bubble_on(mom, rat, 0.3, 3.0)])
	_cues.append([6.4, func(): _cut_phase = "walk"; _walk = [Nights.world(170, 650, 1), Nights.world(180, 612, 1)]])
	banner("Night %d · %s" % [int(night.number), str(night.name)], "", 2.6)


func _talkers() -> Array:
	var out := []
	for p in nest_pups:
		if p.visible: out.append(p)
	for p in pups:
		out.append(p)
	return out


func _prologue() -> void:
	_cut_phase = "prologue"
	_cut_t = 0.0
	for p in nest_pups: p.visible = false
	for p in pups: p.visible = false
	rat.global_position = Nights.world(180, 612, 1)
	rat.anim.play("walk")
	_walk = [Nights.world(170, 660, 1), Nights.world(150, 700, 1)]
	Sfx.music_menu()
	_cues = [
		[0.2, func(): Sfx.play("thunder"); banner("A stormy night", "A mother rat slips into the house through a gap in the wall…", 3.4)],
		[3.9, func(): banner("", "She finds a warm spot behind the kitchen wall and builds a nest.", 3.0)],
		[7.2, func(): _fade_to = 1.0],
		[7.8, func(): _fade_to = 0.0; rat.anim.play("sleep"); for p in nest_pups: p.visible = true
			],
		[7.9, func(): banner("By morning, there were four.", "", 3.0); Sfx.play("squeak", null, -6.0, 1.7)],
		[9.2, func(): Sfx.play("squeak", null, -8.0, 1.8)],
		[11.2, func(): _fade_to = 1.0],
		[11.8, func(): _fade_to = 0.0; banner("A few days later", "Their eyes are open. And they are very hungry.", 3.2)],
		[15.2, func(): Sfx.music_night(night.get("music", {})); _night_intro()],
	]


func _skip_intro() -> void:
	if _cut_phase == "leave":
		return
	_cut_phase = "leave"
	_cut_t = 0.0
	_fade_to = 1.0


func _run_cues() -> void:
	while not _cues.is_empty() and _cut_t >= float(_cues[0][0]):
		var c: Callable = _cues.pop_front()[1]
		c.call()


## Walk the rat along _walk; true when she got there.
func _walk_rat(dt: float, spd: float) -> bool:
	if _walk.is_empty():
		return true
	var t: Vector3 = _walk[0]
	var d := t - rat.global_position
	d.y = 0.0
	if d.length() < 0.03:
		_walk.pop_front()
		return _walk.is_empty()
	rat.global_position += d.normalized() * minf(d.length(), spd * dt)
	rat.rotation.y = lerp_angle(rat.rotation.y, Nights.yaw_to(d), minf(1.0, dt * 8.0))
	rat.anim.play("walk")
	return false


func _orbit(dt: float, center: Vector3, a: float, r: float, h: float) -> void:
	var want := center + Vector3(cos(a) * r, h, sin(a) * r * 0.75)
	_cut_cam.global_position = _cut_cam.global_position.lerp(want, minf(1.0, dt * 3.0)) if _cut_t > 0.05 else want
	_cut_cam.look_at(center + Vector3.UP * 0.05)


func _tick_intro(dt: float) -> void:
	dt = minf(dt, 0.05)  # the first frame after loading can be seconds long
	_cut_t += dt
	_run_cues()
	var nest_c := Nights.world(140, 705, 2)
	match _cut_phase:
		"prologue":
			if _cut_t < 7.2: _walk_rat(dt, 0.3)
			_orbit(dt, nest_c, 0.8 + _cut_t * 0.05, 0.95, 0.45)
		"nest":
			_orbit(dt, nest_c, 0.5 + _cut_t * 0.09, lerpf(0.95, 0.7, clampf(_cut_t / 5.0, 0.0, 1.0)), lerpf(0.5, 0.32, clampf(_cut_t / 5.0, 0.0, 1.0)))
		"walk":
			_orbit(dt, rat.global_position, PI * 0.45, 0.7, 0.3)
			if _walk_rat(dt, 0.8):
				_skip_intro()
		"leave":
			if _cut_t > 0.4:
				begin()


## The nest scene after a won night: the pups eat and thank Mom.
func _start_outro() -> void:
	state = "outro"
	_cut_phase = "in"
	_cut_t = 0.0
	_fade_to = 1.0
	cut_bars = true
	rat.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.music_layers(0.0, false)


func _tick_outro(dt: float) -> void:
	dt = minf(dt, 0.05)
	_cut_t += dt
	if _cut_phase == "in" and _cut_t > 0.45:
		_cut_phase = "eat"
		_cut_t = 0.0
		_cut_camera()
		rat.scripted = true
		rat.global_position = Nights.world(165, 700, 1)
		rat.rotation.y = Nights.yaw_to(Vector3.LEFT)
		rat.anim.play("idle")
		for p in nest_pups: p.visible = true
		for i in pups.size():
			pups[i].global_position = Nights.world(110 + i * 25, 690)
			pups[i].mode = Pup.Mode.STAY
			pups[i].target = pups[i].global_position
		_fade_to = 0.0
		var lines := [["We’re free!", "Mom, we found food for YOU!", "Here, Mom!", "We love you!"]] if bool(night.get("finale", false)) else [["Nom!", "Thanks, Mom!", "Cheeese!", "I’m full!"]]
		var talkers := _talkers()
		_cues = []
		for i in 4:
			var who = talkers[i % talkers.size()]
			var line: String = lines[0][i]
			_cues.append([0.6 + i * 0.8, func(): bubble_on(line, who, 0.2, 1.8); Sfx.play("squeak", null, -6.0, randf_range(1.3, 1.6))])
	if _cut_phase == "eat":
		_run_cues()
		_orbit(dt, Nights.world(140, 705, 2), 0.4 + _cut_t * 0.12, 0.8, 0.36)
		if _cut_t > 4.6:
			_cut_phase = ""
			cut_bars = false
			_show_result(true)


func _set_paused(on: bool) -> void:
	state = "pause" if on else "play"
	Sfx.music_duck(on)
	get_tree().paused = false
	rat.frozen = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	if on:
		_pause_panel()


## Nights with "freeEnd": once the nest is full the player may finish right away, or keep playing for the
## other tasks and finish from the pause menu whenever they like.
func _free_end() -> bool:
	return bool(night.get("freeEnd", false))


func can_finish() -> bool:
	return _free_end() and fed >= int(night.goal) and (state == "play" or state == "pause")


func finish_now() -> void:
	_set_paused(false)
	_end(true, "The nest is full!", "The pups are fed. Next night: " + str(night.get("teaser", "")))


func _offer_finish() -> void:
	_set_paused(true)
	if is_instance_valid(_panel):
		_panel.queue_free()
	var sc := UI.screen(hud, 0.55, false, 480.0)
	_panel = sc[0]
	_panel.set_meta("pause", true)
	var box: VBoxContainer = sc[1]
	box.add_child(UI.label("The nest is full!", 32, UI.ACCENT, true))
	box.add_child(UI.label("You can finish the night now, or keep playing and do the other tasks. You can finish any time from the pause menu (%s)." % Keys.label("pause"), 16, UI.TEXT, true))
	box.add_child(UI.button("Finish the night", finish_now))
	box.add_child(UI.button("Keep playing", func(): _set_paused(false)))
	UI.focus_first(box)


func _pause_panel() -> void:
	var sc := UI.screen(hud, 0.55, false, 440.0)
	_panel = sc[0]
	_panel.set_meta("pause", true)
	var box: VBoxContainer = sc[1]
	box.add_child(UI.label("Paused", 32, UI.ACCENT, true))
	box.add_child(UI.label("Night %d · %s. The pups are waiting." % [int(night.number), str(night.name)], 16, UI.DIM, true))
	box.add_child(UI.button("Resume", func(): _set_paused(false)))
	if can_finish():
		box.add_child(UI.button("Finish the night", finish_now))
	box.add_child(UI.button("Settings", func(): _panel.hide(); UI.settings_panel(hud, func(): _apply_settings(); if is_instance_valid(_panel): _panel.show())))
	box.add_child(UI.button("Restart night", _restart))
	box.add_child(UI.button("Main menu", func(): Main.I.show_menu()))
	UI.focus_first(box)


## Forward+ effects by the Quality setting (the Compatibility renderer, used on old graphics cards, ignores them).
##   medium: ambient occlusion (soft dark in corners and under furniture), a little glow on lamps
##   high:   + bounced light (SSIL), global illumination (SDFGI) and volumetric fog in the moonlight
func apply_fx() -> void:
	if env == null:
		return
	var q := Settings.quality
	var on := q != "low"
	env.ssao_enabled = on
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.glow_enabled = on
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var hi := q == "high"
	env.ssil_enabled = hi
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	env.sdfgi_enabled = hi
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 3
	env.sdfgi_min_cell_size = 0.05
	env.sdfgi_energy = 0.7
	env.sdfgi_bounce_feedback = 0.4
	env.volumetric_fog_enabled = hi
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.75, 0.8, 1.0)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 12.0
	env.volumetric_fog_ambient_inject = 0.15
	env.fog_enabled = not hi  # the plain fog gives way to the volumetric one
	if moon:
		moon.light_volumetric_fog_energy = 1.6


func _apply_settings() -> void:
	apply_fx()
	cam.sensitivity = 0.25 * Settings.sens
	cam.invert_y = Settings.invert_y
	cam.fov = Settings.fov
	for l in find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or (l is OmniLight3D and l != tv_light):
			(l as Light3D).shadow_enabled = Settings.shadows()


func _end(won: bool, title: String, text: String) -> void:
	if state != "play":
		return
	if won:
		tasks.finish_night()
	end_title = title
	end_text = text
	rat.frozen = true
	Sfx.play("win" if won else "lose")
	Sfx.music_layers(0.0, false)
	ended.emit(won)
	if won:
		_start_outro()
	else:
		state = "lost"
		_show_result(false)


func goal_rows(won: bool) -> Array:
	var rows := []
	if tasks.has_tasks():
		rows.append(["Main tasks %d / %d" % [mini(tasks.step, tasks.chain.size()), tasks.chain.size()], won and tasks.chain_done()])
		for i in tasks.side.size():
			rows.append(["Side: " + str(tasks.side[i].text), won and tasks.side_done.has(i)])
		for i in tasks.secret.size():
			rows.append([("Secret: " + str(tasks.secret[i].text)) if tasks.secret_done.has(i) else "Secret: ???", tasks.secret_done.has(i)])
	else:
		rows.append(["Fill the nest", won])
	return rows


func _show_result(won: bool) -> void:
	state = "won" if won else "lost"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rows := goal_rows(won)
	var got := 0
	for r in rows:
		if r[1]: got += 1
	var last := int(night.number) >= Nights.last_playable()
	if won:
		Progress.record(night, night_time, hud.clock_text(), got, rows.size(), max_stars)
		Achievements.night_won(self)
	else:
		Progress.losses[night_id] = int(Progress.losses.get(night_id, 0)) + 1
	var sc := UI.screen(hud, 0.7, false, 620.0)
	_panel = sc[0]
	var box: VBoxContainer = sc[1]
	var title := end_title
	if won:
		title = "The End" if bool(night.get("finale", false)) else "Night %d complete" % int(night.number)
	box.add_child(UI.label(title, 34, UI.ACCENT if won else UI.BAD, true))
	var text := end_text
	if won and bool(night.get("finale", false)):
		text = "The family slipped out under the front door before dawn. Somewhere out there, four grown-up rats are bringing food home to their mom for the first time. Thank you for playing!"
	box.add_child(UI.label(text, 16, UI.TEXT, true))
	if won and Nights.demo() and last:
		box.add_child(UI.label("That’s the end of the demo. Wishlist Kitchen Rat on Steam to play all twenty nights.", 17, UI.ACCENT, true))
	for r in rows:
		box.add_child(UI.label(("✔  " if r[1] else "✖  ") + str(r[0]), 16, UI.GOOD if r[1] else UI.DIM))
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 28)
	box.add_child(stats)
	var st := [[hud.clock_text(), "Finished at" if won else "Time"], ["%d / %d" % [mini(fed, int(night.goal)), int(night.goal)], "Food"], [str(3 - maxi(lives, 0)), "Lives lost"]]
	if bool(night.get("wanted", false)):
		st.append([_star_text(max_stars), "Top wanted"])
	for s2 in st:
		var v := VBoxContainer.new()
		for k in 2:
			var l := UI.label(str(s2[k]), 22 if k == 0 else 13, UI.TEXT if k == 0 else UI.DIM, true)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			v.add_child(l)
		stats.add_child(v)
	if not won and int(Progress.losses.get(night_id, 0)) >= 2:
		var tip := Keys.text(str(tasks.current().get("hint", ""))) if tasks.current() != null else ""
		box.add_child(UI.label("Tip: " + (tip if tip != "" else "sneak (%s) near the cat and hide under furniture when it comes close." % Keys.label("sneak")) + ("" if Settings.calm else " You can also turn on Calm mode in Settings."), 15, UI.ACCENT, true))
	if won and not last:
		box.add_child(UI.button("Next night", func(): Main.I.start_number(int(night.number) + 1)))
	box.add_child(UI.button("Replay night" if won else "Try again", _restart))
	box.add_child(UI.button("Main menu", func(): Main.I.show_menu()))
	UI.focus_first(box)


func _restart() -> void:
	Main.I.start_night(night_id)


func _exit_tree() -> void:
	if nav:
		nav.dispose()
	if is_instance_valid(_rain):
		_rain.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play":
		_set_paused(true)


static func _star_text(n: int) -> String:
	return "none" if n == 0 else "★".repeat(n)


# ---------- messages ----------

func bubble_at(text: String, at: Vector3, dur: float, col := Color.WHITE) -> void:
	hud.bubble(text, at, null, 0.0, dur, col)


func bubble_on(text: String, follow: Node3D, height: float, dur: float) -> void:
	hud.bubble(text, Vector3.ZERO, follow, height, dur, Color.WHITE)


func toast(text: String) -> void:
	hud.toast(text)


func banner(title: String, sub: String, dur: float) -> void:
	hud.banner(title, sub, dur)


# ---------- scent trails ----------

func _make_trail() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _draw_trail(mi: MeshInstance3D, from: Vector3, to: Vector3, poison: bool, i: int) -> void:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var a := from + Vector3.UP * 0.05
	var b := to + Vector3.UP * 0.03
	var side := (b - a).cross(Vector3.UP).normalized()
	var alpha := clampf((_sniff_hold - 0.35) * 2.0, 0.0, 1.0) * (0.55 + 0.25 * sin(Time.get_ticks_msec() / 200.0)) * (1.0 if i == 0 else 0.55)
	var c := Settings.poison_color() if poison else Color(1, 0.85, 0.5)
	var t0 := Time.get_ticks_msec() / 1000.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var eye := get_viewport().get_camera_3d().global_position
	var pts: Array[Vector3] = []
	for k in 24:
		var t := k / 23.0
		pts.append(a.lerp(b, t) + Vector3.UP * sin(t * PI) * 0.15 + side * sin(t * 12.0 + t0 * 3.0 + i) * 0.02)
	for k in 24:
		var t := k / 23.0
		var p := pts[k]
		var tan := (pts[mini(k + 1, 23)] - pts[maxi(k - 1, 0)]).normalized()
		var off := tan.cross((eye - p).normalized()).normalized() * 0.007  # the ribbon faces the camera: seen from any side
		im.surface_set_color(Color(c.r, c.g, c.b, alpha * 0.45 * (1.0 - t * 0.6)))
		im.surface_add_vertex(p + off)
		im.surface_set_color(Color(c.r, c.g, c.b, alpha * 0.45 * (1.0 - t * 0.6)))
		im.surface_add_vertex(p - off)
	im.surface_end()
	# specks of smell drifting along it toward the food, brighter the closer the food is
	var near := clampf(1.0 - from.distance_to(to) / 4.0, 0.25, 1.0)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 14:
		var u := fmod(t0 * 0.35 + j / 14.0, 1.0)
		var fi := u * 23.0
		var k0 := int(floor(fi))
		var q := pts[k0].lerp(pts[mini(k0 + 1, 23)], fi - k0)
		var to_eye := (eye - q).normalized()
		var rx := to_eye.cross(Vector3.UP).normalized() * 0.008
		var ry := rx.cross(to_eye).normalized() * 0.008
		var col := Color(c.r, c.g, c.b, alpha * near * sin(u * PI) * 1.4)
		for v in [q - rx - ry, q + rx - ry, q + rx + ry, q - rx - ry, q + rx + ry, q - rx + ry]:
			im.surface_set_color(col)
			im.surface_add_vertex(v)
	im.surface_end()
