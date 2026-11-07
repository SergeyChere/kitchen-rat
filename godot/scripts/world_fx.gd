class_name WorldFx
extends Node3D
## Readability effects on the floor, like the prototype:
##  · hiding spots: a dashed green outline that brightens as the rat gets close (and glows while she's inside),
##  · the cat's view cone (pale), clipped by furniture,
##  · noise rings that spread from every sound.

var g: Game
var _marks: Array = []  # [MeshInstance3D, HideSpot]
var _cone: MeshInstance3D
var _rings: Array = []  # [MeshInstance3D, t, life, max_r]
static var _tex: ImageTexture


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


func _ready() -> void:
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


func _process(dt: float) -> void:
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
