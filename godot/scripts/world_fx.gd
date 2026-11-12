class_name WorldFx
extends Node3D
## Readability effects on the floor, like the prototype:
##  · hiding spots: a dashed green outline that brightens as the rat gets close (and glows while she's inside),
##  · the cat's view cone (pale), clipped by furniture,
##  · noise rings that spread from every sound.

var g: Game
var _steam_t := 0.0
var _marks: Array = []  # [MeshInstance3D, HideSpot]
var _cone: MeshInstance3D
var _rings: Array = []  # [MeshInstance3D, t, life, max_r]
var _glints: Array = []  # [Sprite3D, node it marks, phase]
var _beacon: MeshInstance3D  # a green column of light over the nest hole while she carries food
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


func _particles(at: Vector3, n: int, col: Color, size: float, speed: float, up: float, life: float, gravity := -0.6) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = n
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)  # sized on the mesh: particle scale isn't applied to billboards on every renderer
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _make_dot()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = grad
	add_child(p)
	p.global_position = at + Vector3.UP * up
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## A puff of dust where she lands (bigger from higher up).
func dust(at: Vector3, big: bool) -> void:
	_particles(at, 14 if big else 7, Color(0.75, 0.7, 0.62, 0.55), 0.05 if big else 0.035, 0.5 if big else 0.3, 0.02, 0.7, -0.4)


## Sparkles when she picks something up.
func sparkle(at: Vector3, cheese: bool) -> void:
	_particles(at, 10, Color(1.0, 0.85, 0.35, 0.95) if cheese else Color(0.95, 0.85, 0.6, 0.8), 0.025, 0.6, 0.04, 0.6, -1.2)


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
	_make_glints()
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


func ring(at: Vector3, radius: float, big: bool) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.93
	t.outer_radius = 1.0
	t.rings = 48
	t.ring_segments = 3
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.76, 0.3, 0.6) if big else Color(0.93, 0.9, 0.85, 0.45)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(at.x, maxf(at.y, 0.0) + 0.01, at.z)
	mi.scale = Vector3(0.05, 0.02, 0.05)
	_rings.append([mi, 0.0, 1.0 if big else 0.6, clampf(radius, 0.5, 6.0)])


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
		var mi: MeshInstance3D = r[0]
		if k >= 1.0:
			mi.queue_free()
			_rings.remove_at(i)
			continue
		var rad: float = lerpf(0.05, r[3], 1.0 - pow(1.0 - k, 2.0))
		mi.scale = Vector3(rad, 0.02, rad)
		(mi.material_override as StandardMaterial3D).albedo_color.a = (1.0 - k) * 0.55


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
