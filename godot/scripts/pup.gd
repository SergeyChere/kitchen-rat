class_name Pup
extends Node3D
## A pup that comes along (acts 3 and 4), ported from the prototype's comps. It follows Mom's trail, hides with her,
## waits when told (Q), fetches food on request (R) and brings it home. Personalities:
## brave goes ahead for food when Mom stands still, greedy grabs anything (even green cheese), shy freezes at loud
## noises and warns about the cat, curious sniffs out hidden food and secrets.
## The cat, the dog or the owner catch an unhidden pup (it's dropped by the cat bed); traps and tape stick it.

enum Mode { FOLLOW, STAY, FETCH, CARRY, CAPTURED, STUCK }

const INFO := {
	"brave": {"name": "Brave", "speed": 1.15}, "greedy": {"name": "Greedy", "speed": 0.95},
	"shy": {"name": "Shy", "speed": 1.0}, "curious": {"name": "Curious", "speed": 1.05},
}

var kind := "brave"
var title := "Brave"
var spd_k := 1.0
var index := 0
var mode := Mode.FOLLOW
var target = null  # Vector3 (stay) or Food (fetch)
var item: Food
var freeze_t := 0.0
var anim: ClipPlayer
var _said := 0.0
var _stuck := 0.0

var G: Game:
	get: return Game.I


func setup(k: String, i: int, model: Node3D) -> void:
	kind = k
	index = i
	title = INFO.get(k, INFO.brave).name
	spd_k = INFO.get(k, INFO.brave).speed
	anim = ClipPlayer.new(model)


func say(t: String, d := 1.4) -> void:
	if _said > 0.0:
		return
	_said = 1.5
	G.bubble_on(t, self, 0.22, d)
	Sfx.play("squeak", global_position + Vector3.UP * 0.1, -4.0, randf_range(1.15, 1.35))


func force_say(t: String, d := 1.4) -> void:
	_said = 0.0
	say(t, d)


func lost() -> bool: return mode == Mode.CAPTURED or mode == Mode.STUCK


func hidden() -> bool:
	for z in G.zones:
		if z is HideSpot and z.contains_xz(global_position, 0.0):
			return true
	return global_position.distance_to(G.hole) < 0.3 or global_position.z > G.hole.z


func capture(by: String) -> void:
	if lost():
		return
	print_verbose("pup ", title, " caught by ", by)
	if item:
		_drop_item()
	if by == "trap" or by == "sticky":
		mode = Mode.STUCK
		force_say("Mom! I’m stuck!", 2.0)
	else:
		mode = Mode.CAPTURED
		global_position = G.cat.bed + Vector3(0.22, 0, 0.06)
		force_say("MOM! HELP!", 2.2)
		G.banner(title + " got caught!", "The owner dropped them by the cat bed. Rescue them!" if by == "owner" else "The cat dragged them to its bed. Distract it and rescue them!", 4.0)
	G.run.pupCaught = true


func _drop_item() -> void:
	var f := item
	item = null
	f.carried = false
	f.reparent(G._builder.foods, true)
	f.global_position = Vector3(global_position.x, 0.0, global_position.z)
	f.rotation = Vector3.ZERO
	G.foods.append(f)


## Walk toward t: through the mouse hole when one of us is in the nest, sliding along furniture, and catching up
## (a quick scurry) when stuck for a second. Returns true when there.
func step_to(t: Vector3, spd: float, dt: float) -> bool:
	var wall_z := G.hole.z + 0.15  # the south wall
	var in_nest := global_position.z > wall_z
	var t_nest := t.z > wall_z
	var via := t
	if in_nest != t_nest:
		var on_axis := absf(global_position.x - G.hole.x) < 0.05
		if in_nest:
			via = Vector3(G.hole.x, 0, G.hole.z) if on_axis else Vector3(G.hole.x, 0, wall_z + 0.25)
		else:
			via = Vector3(G.hole.x, 0, wall_z + 0.3) if (on_axis and global_position.z > G.hole.z - 0.05) else Vector3(G.hole.x, 0, G.hole.z)
	var before := global_position
	var there := _step(via, spd, dt) and via == t
	if not there and (global_position - before).length() < spd * dt * 0.2:
		_stuck += dt
		if _stuck > 1.0:
			_stuck = 0.0
			if _free(via):
				global_position = Vector3(via.x, 0, via.z)
	else:
		_stuck = 0.0
	return there


func _step(t: Vector3, spd: float, dt: float) -> bool:
	var p := global_position
	var d := Vector3(t.x - p.x, 0, t.z - p.z)
	var dist := d.length()
	if dist < 0.02:
		return true
	var m := minf(dist, spd * dt)
	var dir := d / dist
	var np := p + dir * m
	if not _free(np):
		var a := p + Vector3(dir.x * m, 0, 0)
		var b := p + Vector3(0, 0, dir.z * m)
		np = a if _free(a) else (b if _free(b) else p)
	global_position = np
	if (np - p).length() > 0.0005:
		rotation.y = lerp_angle(rotation.y, Nights.yaw_to(np - p), clampf(dt * 10.0, 0.0, 1.0))
	return false


func _free(p: Vector3) -> bool:
	return G.sphere_free(p + Vector3.UP * 0.07, 0.033)


func tick(dt: float, trail: Array, idle_t: float) -> void:
	_said -= dt
	freeze_t -= dt
	var rat := G.rat
	var spd := 1.5 * spd_k * (0.5 if rat.sneaking else 1.0)
	var moved := global_position
	if lost():
		if randf() < dt * 0.4:
			say("Mom…")
		if rat.surface_id == "floor" and not rat.jumping and rat.global_position.y < 0.05 and rat.global_position.distance_to(global_position) < 0.22:
			mode = Mode.FOLLOW
			force_say("Thanks, Mom!")
			G.tasks.set_flag("pupRescued")
			Achievements.unlock("RESCUER")
		anim.play("freeze" if mode == Mode.STUCK else "idle")
		return
	if freeze_t > 0.0:
		anim.play("freeze")
		return
	match kind:
		"greedy":
			if mode == Mode.FOLLOW:
				var f := G.nearest_floor_food(global_position, 1.0, true)
				if f:
					mode = Mode.FETCH
					target = f
					say("Ooh, green cheese!" if f.poison else "Food!")
		"brave":
			if mode == Mode.FOLLOW and idle_t > 4.0 and G.night_time > 20.0:
				var f := G.nearest_floor_food(global_position, 2.4, false)
				if f:
					mode = Mode.FETCH
					target = f
					say("I’ll go first!")
		"shy":
			if G.pup_warn_t <= 0.0 and G.cat.awake() and G.cat.global_position.distance_to(global_position) < 2.2:
				G.pup_warn_t = 6.0
				force_say("!! The cat!", 1.6)
		"curious":
			for f in G.foods:
				if not f.carried and f.global_position.distance_to(global_position) < 1.1:
					f.reveal_t = maxf(f.reveal_t, 2.0)
					if f.is_find and not f.has_meta("pointed") and f.global_position.distance_to(global_position) < 1.4:
						f.set_meta("pointed", true)
						f.hidden = false
						force_say("Mom, look! Something shiny!", 2.0)
	match mode:
		Mode.FOLLOW:
			var hid := rat.hidden()
			var tp := rat.global_position
			var gap := 0.22 + index * 0.16
			if hid and rat.global_position.z > G.hole.z - 0.05:
				# in the burrow there is room: they lie round her instead of piling up under her (four grown pups
				# in one spot read as one rat with five tails)
				var a := 0.9 + index * 1.45
				tp = rat.global_position + Vector3(cos(a), 0, sin(a)) * (0.17 + (index % 2) * 0.05)
			elif hid:
				tp = rat.global_position + Vector3((index - 0.5) * 0.08, 0, 0.06)
			elif not trail.is_empty():
				var acc := 0.0
				var k := trail.size() - 1
				tp = trail[k]
				while k > 0 and acc < gap:
					acc += (trail[k] as Vector3).distance_to(trail[k - 1])
					k -= 1
					tp = trail[k]
				if acc < gap * 0.5:  # she has hardly moved yet: a place behind her, not on top of her
					var back := -rat.global_basis.z
					back.y = 0.0
					tp = rat.global_position + back.normalized() * gap + rat.global_basis.x * ((index % 2) - 0.5) * 0.1
			tp.y = 0.0
			var dd := Vector2(tp.x - global_position.x, tp.z - global_position.z).length()
			if dd > (0.02 if hid else 0.06):
				step_to(tp, spd * 1.4 if dd > 1.2 else spd, dt)
		Mode.STAY:
			if target is Vector3:
				step_to(target, spd, dt)
		Mode.FETCH:
			var f = target
			if not (f is Food) or not is_instance_valid(f) or f.carried or not G.foods.has(f):
				mode = Mode.FOLLOW
			elif step_to(f.global_position, spd, dt) or Vector2(f.global_position.x - global_position.x, f.global_position.z - global_position.z).length() < 0.08:
				G.foods.erase(f)
				item = f
				f.carried = true
				f.reparent(self, false)
				f.position = Vector3(0, 0.03, 0.12)
				mode = Mode.CARRY
		Mode.CARRY:
			var home := G.hole + Vector3(0, 0, 0.1)
			if step_to(home, spd, dt) or global_position.distance_to(home) < 0.14:
				var f := item
				item = null
				if f.poison:
					G.fed = maxi(0, G.fed - 4)
					G.run.poisonDelivered = true
					force_say("Oops… it was green", 2.0)
				else:
					G.fed += f.value()
					force_say("+%d for the nest!" % f.value(), 1.6)
				G.tasks.flag("pupFetch")
				f.queue_free()
				mode = Mode.FOLLOW
	var mv := (global_position - moved).length() / maxf(dt, 0.0001)
	anim.play(("carry_walk" if item else ("run" if mv > 1.2 else "walk")) if mv > 0.05 else "idle")

	# dangers: the cat, the dog, the owner, traps, sticky tape
	if not hidden():
		var c := G.cat
		if c.visible and c.awake() and c.mode != CatAI.Mode.EAT and c.global_position.distance_to(global_position) < 0.22:
			capture("cat")
		elif G.dog and G.dog.awake() and G.dog.mode != DogAI.Mode.PLAY and G.dog.global_position.distance_to(global_position) < 0.26:
			capture("cat")
		elif G.owner_ai.in_room() and G.owner_ai.global_position.distance_to(global_position) < 0.3:
			capture("owner")
	for t in G.traps:
		if not t.sprung and not t.found and Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length() < 0.1:
			t.spring()
			G.noise(t.global_position, 3.0, "SNAP!", true, 0.6)
			capture("trap")
	for z in G.zones:
		if z is StickyZone and z.on_floor() and (z.kind == "sticky" or z.kind == "cage") and z.contains_xz(global_position, 0.0):
			capture("sticky")
