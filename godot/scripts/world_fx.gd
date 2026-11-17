class_name WorldFx
extends Node3D
## Readability effects on the floor, like the prototype:
##  · hiding spots: a dashed green outline that brightens as the rat gets close (and glows while she's inside),
##  · the cat's view cone (pale), clipped by furniture,
##  · noise rings made of dust that spread from every sound (round 24: the torus is gone — a ring of
##    dust reads as a sound in the world, not as a UI circle).

var g: Game
var _steam_t := 0.0
var _marks: Array = []  # [MeshInstance3D, HideSpot]
var _cone: MeshInstance3D
var _rings: Array = []  # [GPUParticles3D, t, life, max_r, base alpha]
var _ring_pool: Array = []  # round 24: continuous ring emitters, reused — a ring lives up to a
	# second, so several can be alive at once (running steps come every 0.35 s)
var _glints: Array = []  # [Sprite3D, node it marks, phase]
var _puffs: Array = []  # round 23: a pool of one-shot dust emitters, reused round-robin —
	# a running step puffs dust, and creating a node per puff (up to ~13 a second)
	# would stutter the game
var _puff_i := 0
var _beacon: MeshInstance3D  # a green column of light over the nest hole while she carries food
var _beacon_in: MeshInstance3D  # round 24: the same green column INSIDE the burrow, over the hole —
	# from inside, the way out was invisible (the camera jams against the pocket walls)
var _hole_ring: MeshInstance3D  # round 24: a green ring on the burrow floor at the hole's mouth
static var _tex: ImageTexture
static var _star: ImageTexture
static var _dot: ImageTexture


func _init(game: Game) -> void:
	g = game


static func _dash_tex() -> ImageTexture:
	if _tex:
		return _tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.12))
	for i in n:
		for k in 8:
			var on := (i / 14) % 2 == 0
			var a := 1.0 if on else 0.0
			for p in [Vector2i(i, k), Vector2i(i, n - 1 - k), Vector2i(k, i), Vector2i(n - 1 - k, i)]:
				img.set_pixelv(p, Color(1, 1, 1, a) if on else Color(1, 1, 1, 0.12))
	_tex = ImageTexture.create_from_image(img)
	return _tex


## A soft round dot and a four-point star, drawn in code.
static func _make_dot() -> ImageTexture:
	if _dot:
		return _dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
	_dot = ImageTexture.create_from_image(img)
	return _dot


static func _make_star() -> ImageTexture:
	if _star:
		return _star
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5) / (n / 2.0)
			var a := maxf(0.0, 1.0 - absf(p.x) * 7.0 - absf(p.y)) + maxf(0.0, 1.0 - absf(p.y) * 7.0 - absf(p.x))
			a += clampf(1.0 - p.length() * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_star = ImageTexture.create_from_image(img)
	return _star


func _particles(at: Vector3, n: int, col: Color, size: float, speed: float, up: float, life: float, gravity := -0.6, layer := 0) -> void:
	# GPU particles (Forward+): the CPU ones never rendered on the player's machine.
	var p := GPUParticles3D.new()
	if layer != 0:
		p.layers = layer  # the warm-up camera alone sees it: shader compiles before play, not as a hitch
	p.one_shot = true
	p.emitting = false
	p.amount = n
	p.lifetime = life
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)  # sized on the mesh: particle scale isn't applied to billboards on every renderer
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _make_dot()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.draw_pass_1 = q
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = grad
	pm.color_ramp = ramp_tex
	add_child(p)
	p.global_position = at + Vector3.UP * up
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## A puff of dust where she lands (bigger from higher up).
func dust(at: Vector3, big: bool, layer := 0) -> void:
	_particles(at, 18 if big else 7, Color(0.75, 0.7, 0.62, 0.55), 0.05 if big else 0.035, 0.5 if big else 0.3, 0.02, 0.7, -0.4, layer)


## The puff pool: small one-shot dust emitters, made once and restarted where needed.
## (Same shader as the landing bursts, so the warm-up already compiled it.)
func _make_puff_pool() -> void:
	for i in 16:
		var e := GPUParticles3D.new()
		e.amount = 4
		e.lifetime = 0.6
		e.one_shot = true
		e.explosiveness = 0.95
		e.emitting = false
		e.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 60.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.15
		pm.gravity = Vector3(0, -0.1, 0)
		pm.damping_min = 0.5
		pm.damping_max = 0.9
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var c := Curve.new()
		c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(0.3, 1.0)); c.add_point(Vector2(1, 1.6))
		var scale_tex := CurveTexture.new()
		scale_tex.curve = c
		pm.scale_curve = scale_tex
		var grad := Gradient.new()
		grad.set_color(0, Color(0.78, 0.74, 0.68, 0.4))
		grad.set_color(1, Color(0.78, 0.74, 0.68, 0.0))
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = grad
		pm.color_ramp = ramp_tex
		e.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.03)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = _make_dot()
		m.vertex_color_use_as_albedo = true
		q.material = m
		e.draw_pass_1 = q
		add_child(e)
		_puffs.append(e)


func _puff_at(p: Vector3) -> void:
	if _puffs.is_empty():
		return
	var e: GPUParticles3D = _puffs[_puff_i]
	_puff_i = (_puff_i + 1) % _puffs.size()
	e.global_position = p
	e.restart()


## A running step kicks up a little dust at her feet.
func step_dust(at: Vector3) -> void:
	_puff_at(at + Vector3.UP * 0.02)


## The noise rings, round 24: each is a pool emitter whose emission ring grows while the ring
## lives — dust appears at the moving edge and hangs a moment behind it, so the ring reads as a
## circle of stirred dust. The emitter's AABB is set by hand: particles spawn up to 6 m from the
## emitter's origin, and the default bounds would cull the ring whenever its centre left the view.
func _make_ring_pool() -> void:
	for i in 6:
		var e := GPUParticles3D.new()
		e.amount = 256  # a 3 m ring is 19 m round: fewer than this reads as stray specks, not a ring
		e.lifetime = 0.6  # the trail behind the edge stays a moment, so the ring has a body
		e.one_shot = false
		e.explosiveness = 0.0
		e.emitting = false
		e.custom_aabb = AABB(Vector3(-6.5, -0.5, -6.5), Vector3(13, 2.5, 13))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_height = 0.02
		pm.emission_ring_radius = 0.05
		pm.emission_ring_inner_radius = 0.0
		pm.direction = Vector3.UP
		pm.spread = 60.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.2
		pm.gravity = Vector3(0, -0.15, 0)
		pm.damping_min = 0.6
		pm.damping_max = 1.0
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var c := Curve.new()
		c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(0.3, 1.0)); c.add_point(Vector2(1, 1.8))
		var scale_tex := CurveTexture.new()
		scale_tex.curve = c
		pm.scale_curve = scale_tex
		var grad := Gradient.new()
		grad.set_color(0, Color(0.8, 0.76, 0.7, 0.8))
		grad.set_color(1, Color(0.8, 0.76, 0.7, 0.0))
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = grad
		pm.color_ramp = ramp_tex
		e.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.07, 0.07)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = _make_dot()
		m.vertex_color_use_as_albedo = true
		q.material = m
		e.draw_pass_1 = q
		add_child(e)
		_ring_pool.append(e)


func _free_ring() -> GPUParticles3D:
	for e in _ring_pool:
		if not (e as GPUParticles3D).emitting:
			return e
	# all six alive (a loud crash mid-sprint): steal the oldest ring rather than drop the new sound
	if not _rings.is_empty():
		var old: GPUParticles3D = _rings[0][0]
		_rings.remove_at(0)
		return old
	return _ring_pool[0] if not _ring_pool.is_empty() else null


func _start_ring(e: GPUParticles3D, at: Vector3, radius: float, life: float, alpha: float, tint: Color) -> void:
	var pm := e.process_material as ParticleProcessMaterial
	pm.emission_ring_radius = 0.05
	pm.emission_ring_inner_radius = 0.0
	pm.color = Color(tint.r, tint.g, tint.b, alpha)
	e.global_position = Vector3(at.x, maxf(at.y, 0.0) + 0.01, at.z)
	e.restart()
	e.emitting = true
	_rings.append([e, 0.0, life, clampf(radius, 0.5, 6.0), alpha])


func ring(at: Vector3, radius: float, big: bool) -> void:
	var e := _free_ring()
	if e == null:
		return
	# loud sounds keep their golden tint (the old torus was gold for loud, pale for quiet)
	var tint := Color(0.95, 0.76, 0.3) if big else Color(0.93, 0.9, 0.85)
	_start_ring(e, at, radius, 1.0 if big else 0.6, 1.0, tint)
	if big:  # a loud sound: a fainter echo ring trails a beat behind the first
		var e2 := _free_ring()
		if e2 != null and e2 != e:
			_start_ring(e2, at, radius * 0.7, 1.0, 0.5, tint)
			_rings[_rings.size() - 1][1] = -0.15  # starts a beat late
			e2.emitting = false  # …and stays dark until its beat


## One ring where only the warm-up camera looks, so the ring shader (a different variant from the
## point bursts: ring emission) compiles before play, not as a hitch on the first sound.
func warm_ring(at: Vector3) -> void:
	var e := _free_ring()
	if e == null:
		return
	e.layers = Game.WARM_LAYER
	_start_ring(e, at, 1.5, 0.6, 1.0, Color(0.93, 0.9, 0.85))


## Sparkles when she picks something up.
func sparkle(at: Vector3, cheese: bool, layer := 0) -> void:
	_particles(at, 10, Color(1.0, 0.85, 0.35, 0.95) if cheese else Color(0.95, 0.85, 0.6, 0.8), 0.025, 0.6, 0.04, 0.6, -1.2, layer)


## Noisy things and wobbly cups glint when she comes close, so every trap can be seen in advance.
func _make_glints() -> void:
	var marks := []
	for z in g.noisy:
		if z.kind in ["sofa", "board", "foil", "confetti", "puddle", "grain"]:
			continue  # big floor areas: the noise warning covers them
		marks.append(z)
	for k in g.knockables:
		if k.trap:
			marks.append(k)
	for n in marks:
		var s := Sprite3D.new()
		s.texture = _make_star()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.pixel_size = 0.0024
		s.modulate = Color(1.0, 0.92, 0.6, 0.0)
		s.no_depth_test = false
		add_child(s)
		s.global_position = (n as Node3D).global_position + Vector3.UP * 0.1
		_glints.append([s, n, randf() * TAU])


func _make_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 2.4
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beacon.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _fade_tex()
	m.albedo_color = Color(0.35, 1.0, 0.45, 0.55)
	_beacon.material_override = m
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	add_child(_beacon)
	_beacon.global_position = g.hole + Vector3(0, 1.2, -0.05)


## The way out, seen from inside the burrow: a green column over the hole's mouth (the pocket's
## roof is 0.95 m, so this one is short) and a green ring on the floor where the hole is.
func _make_beacon_in() -> void:
	_beacon_in = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 0.9
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beacon_in.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _fade_tex()
	m.albedo_color = Color(0.35, 1.0, 0.45, 0.5)
	_beacon_in.material_override = m
	_beacon_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon_in.visible = false
	add_child(_beacon_in)
	_beacon_in.global_position = g.hole + Vector3(0, 0.45, 0.32)
	_hole_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.14
	tm.rings = 32
	_hole_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.55, 1.0, 0.4, 0.6)
	_hole_ring.material_override = rm
	_hole_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hole_ring.visible = false
	_hole_ring.scale = Vector3(1, 0.05, 1)
	add_child(_hole_ring)
	_hole_ring.global_position = g.hole + Vector3(0, 0.01, 0.3)


## Bright at the bottom, fading out upward (the cylinder's V runs top to bottom).
static func _fade_tex() -> ImageTexture:
	var img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var a := pow(y / 63.0, 1.6)
		for x in 4:
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	_make_beacon()  # (the dust in the moonlight lives in LevelBuilder._dust_motes now: along the whole shaft)
	_make_beacon_in()
	_make_glints()
	_make_puff_pool()
	_make_ring_pool()
	for z in g.zones:
		if z is HideSpot:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(z.size.x + 0.08, z.size.z + 0.08)
			q.orientation = PlaneMesh.FACE_Y
			mi.mesh = q
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_texture = _dash_tex()
			m.albedo_color = Color(0.55, 1.0, 0.4, 0.0)
			m.no_depth_test = false
			m.render_priority = 2
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_transform = Transform3D(z.global_transform.basis, z.global_position + Vector3.UP * 0.006)
			_marks.append([mi, z])
	_cone = MeshInstance3D.new()
	_cone.mesh = ImmediateMesh.new()
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_color = Color(0.86, 0.86, 0.92, 0.13)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone.material_override = cm
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cone)


## A small glowing mark over food she has sniffed out, for a few seconds.
func _scent_marks(dt: float) -> void:
	for f in g.foods:
		if not is_instance_valid(f) or not f.has_meta("scent_mark"):
			continue
		var t: float = f.get_meta("scent_mark") - dt
		var mark := f.get_node_or_null("ScentMark") as Label3D
		if t <= 0.0 or f.carried:
			f.remove_meta("scent_mark")
			if mark: mark.queue_free()
			continue
		f.set_meta("scent_mark", t)
		if mark == null:
			mark = Label3D.new()
			mark.name = "ScentMark"
			mark.text = "◆"
			mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			mark.no_depth_test = true
			mark.fixed_size = true
			mark.pixel_size = 0.0025
			mark.font_size = 22
			mark.outline_size = 6
			mark.modulate = Color(1.0, 0.85, 0.4)
			f.add_child(mark)
			mark.position = Vector3.UP * 0.1
		mark.modulate.a = clampf(t, 0.0, 1.0) * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 160.0))
		mark.position.y = 0.1 + 0.01 * sin(Time.get_ticks_msec() / 300.0)


func _process(dt: float) -> void:
	_scent_marks(dt)
	# round 5: the kettle on the stove steams — small white puffs, always rising
	_steam_t -= dt
	if g.kettle_pos != null and _steam_t <= 0.0:
		_steam_t = 0.33
		_particles(g.kettle_pos, 2, Color(0.95, 0.97, 1.0, 0.3), 0.045, 0.03, 0.22, 1.3, -0.12)
	if _beacon:
		_beacon.visible = not g.rat.carried.is_empty() and not g.rat.in_nest
		if _beacon.visible:
			(_beacon.material_override as StandardMaterial3D).albedo_color.a = 0.45 + 0.15 * sin(Time.get_ticks_msec() / 250.0)
	if _beacon_in:
		_beacon_in.visible = g.rat.in_nest
		if _beacon_in.visible:
			(_beacon_in.material_override as StandardMaterial3D).albedo_color.a = 0.4 + 0.12 * sin(Time.get_ticks_msec() / 250.0)
	if _hole_ring:
		_hole_ring.visible = g.rat.in_nest
	var rp := g.rat.global_position
	var playing := g.state == "play" or g.state == "pause"
	for e in _marks:
		var mi: MeshInstance3D = e[0]
		var z: HideSpot = e[1]
		var d := Vector2(z.global_position.x - rp.x, z.global_position.z - rp.z).length()
		var inside := g.rat.hide_spot == z and g.rat.hidden()
		var a := 0.0
		if playing and rp.y < 0.3:
			a = 1.0 if inside else clampf(1.1 - (d - 0.4) / 2.6, 0.0, 0.85)
		var m := mi.material_override as StandardMaterial3D
		m.albedo_color.a = lerpf(m.albedo_color.a, a, minf(1.0, dt * 6.0))
	_draw_cone()
	var t := Time.get_ticks_msec() / 1000.0
	for e in _glints:
		var s: Sprite3D = e[0]
		var n: Node3D = e[1]
		if not is_instance_valid(n) or (n is NoisyZone and n.once and n.used) or (n is Knockable and n.knocked):
			s.visible = false
			continue
		var d := n.global_position.distance_to(rp)
		var near := clampf(1.0 - (d - 0.5) / 2.0, 0.0, 1.0) if playing else 0.0
		var tw := 0.5 + 0.5 * sin(t * 2.4 + float(e[2]))
		s.modulate.a = near * (0.35 + 0.65 * tw)
		s.scale = Vector3.ONE * (0.8 + 0.4 * tw)
	for i in range(_rings.size() - 1, -1, -1):
		var r: Array = _rings[i]
		r[1] += dt
		var k: float = r[1] / r[2]
		var e: GPUParticles3D = r[0]
		if k >= 1.0:
			e.emitting = false  # already-spawned dust finishes its own life and fades
			e.layers = 1  # a warm-up ring goes back to the world's layers
			_rings.remove_at(i)
			continue
		if k <= 0.0:  # an echo ring waiting its beat: dark until it starts
			continue
		if not e.emitting:
			e.emitting = true  # the echo's beat has arrived
		var rad: float = lerpf(0.05, r[3], 1.0 - pow(1.0 - k, 2.0))
		var pm := e.process_material as ParticleProcessMaterial
		pm.emission_ring_radius = rad
		pm.emission_ring_inner_radius = maxf(0.0, rad - 0.07)
		var c := pm.color
		pm.color = Color(c.r, c.g, c.b, (1.0 - k * 0.5) * float(r[4]))  # the per-particle ramp already
			# fades each mote; fading the whole ring to nothing as well left only the first instants visible


func _draw_cone() -> void:
	var im := _cone.mesh as ImmediateMesh
	im.clear_surfaces()
	var c := g.cat
	if not (g.state == "play") or not c.visible or not c.awake() or c.mode == CatAI.Mode.EAT:
		return
	var half := deg_to_rad(35.5)
	var rng := c._range()
	var o := c.global_position + Vector3.UP * 0.012
	var fwd := c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var n := 24
	var pts := []
	for i in n + 1:
		var dir := fwd.rotated(Vector3.UP, -half + 2.0 * half * i / n)
		var r := rng
		var hit := g.ray(o + Vector3.UP * 0.15, o + Vector3.UP * 0.15 + dir * rng)
		if not hit.is_empty():
			r = (hit.position - (o + Vector3.UP * 0.15)).length()
		pts.append(o + dir * r)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		im.surface_add_vertex(o)
		im.surface_add_vertex(pts[i])
		im.surface_add_vertex(pts[i + 1])
	im.surface_end()
