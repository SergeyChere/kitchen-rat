class_name WindowSky
extends Node3D
## Outside the north window (demo polish, round 3): the moon, clouds that drift past it and
## swallow its light, and tree branches swaying in the wind. The clouds write Game.moon_cloud and
## game.gd multiplies the moonlight by it, so the moon patch on the floor breathes as the sky
## moves. Built by LevelBuilder for every night that has a window; all materials are unshaded
## silhouettes/flat light, in the game's cel look — no new art assets.

var _game: Game
var _t := 0.0
var _moon_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _moon_x := 0.9
var _clouds: Array = []  # {node, speed, width}
var _shaft_mats: Array = []  # the moon shaft sheets inside the room: they fade with the moon


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _ball(r: float, mat: Material, squash := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 20
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat
	mi.scale.y = squash
	return mi


func build_sky(game: Game, seed_value: int, shaft_mats: Array = []) -> void:
	_game = game
	_shaft_mats = shaft_mats
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# the moon and its halo
	_moon_mat = _unshaded(Color(0.93, 0.96, 1.0))
	var moon := _ball(0.27, _moon_mat)
	moon.position = Vector3(_moon_x, 2.35, -2.7)
	add_child(moon)
	_halo_mat = _unshaded(Color(0.55, 0.65, 1.0, 0.16))
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var halo := _ball(0.46, _halo_mat)
	halo.position = moon.position
	add_child(halo)
	# clouds: dark puffs drifting across, each wide enough to swallow the moon for a few seconds
	var cloud_mat := _unshaded(Color(0.12, 0.14, 0.21, 0.94))
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 3:
		var cl := Node3D.new()
		var w := rng.randf_range(0.9, 1.5)
		for j in 3:
			var puff := _ball(rng.randf_range(0.22, 0.34) * w, cloud_mat, 0.38)
			puff.position = Vector3((float(j) - 1.0) * 0.34 * w, rng.randf_range(-0.03, 0.05), 0.0)
			cl.add_child(puff)
		cl.position = Vector3(-3.2 + float(i) * 2.6 + rng.randf_range(-0.4, 0.4), rng.randf_range(2.0, 2.6), -2.3)
		add_child(cl)
		_clouds.append({"node": cl, "speed": rng.randf_range(0.05, 0.085), "width": w})
	# a tree outside (asked for): trunk, boughs and leaf clumps in one mesh, swayed by a vertex shader. The
	# shadow pass runs the same vertex code, so its shadow — leaves with moonlight between them — sways across
	# the moon patch on the floor too.
	_tree = MeshInstance3D.new()
	_tree.name = "Tree"
	_tree.mesh = _tree_mesh(rng)
	var tm := ShaderMaterial.new()
	tm.shader = TREE_SHADER
	_tree.material_override = tm
	_tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# the rooms have no ceiling: a crown higher than the walls would show over the wall top from inside
	_tree.scale = Vector3.ONE * minf(1.0, 2.42 / maxf(_tree.mesh.get_aabb().end.y, 0.1))
	_tree.position = Vector3(0.15, 0.0, -0.75)
	add_child(_tree)


const TREE_SHADER := preload("res://shaders/tree_sway.gdshader")


var _tree: MeshInstance3D
var _vs := PackedVector3Array()
var _ns := PackedVector3Array()
var _cs := PackedColorArray()
var _ix := PackedInt32Array()


## Appends one primitive mesh, placed by `xf`; COLOR.b = 1 marks leaves, COLOR.g is the clump's phase.
func _put(m: PrimitiveMesh, xf: Transform3D, leaf: float, phase: float) -> void:
	var arr := m.get_mesh_arrays()
	var base := _vs.size()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		_vs.append(xf * v[i])
		_ns.append((xf.basis * n[i]).normalized())
		_cs.append(Color(0.0, phase, leaf, randf()))
	for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
		_ix.append(base + i)


func _bough(rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var to := from + dir * length
	var cy := CylinderMesh.new()
	cy.top_radius = radius * 0.62
	cy.bottom_radius = radius
	cy.height = length
	cy.radial_segments = 6
	cy.rings = 1
	cy.cap_top = false
	cy.cap_bottom = false
	var up := dir.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	_put(cy, Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), (from + to) / 2.0), 0.0, 0.0)
	if depth >= 3:
		# a clump of leaves at the tip: a few flattened blobs with gaps between them, for a dappled shadow
		var ph := rng.randf()
		for k in rng.randi_range(4, 6):
			var sp := SphereMesh.new()
			var r := rng.randf_range(0.1, 0.17)
			sp.radius = r
			sp.height = r * 1.3
			sp.radial_segments = 8
			sp.rings = 4
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.8), rng.randf_range(-1, 1)) * 0.2
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
			_put(sp, Transform3D(b, to + off), 1.0, ph)
		return
	var kids := 3 if depth < 2 else 2
	for k in kids:
		var spin := TAU * (float(k) + rng.randf_range(-0.2, 0.2)) / float(kids) + float(depth)
		var tilt := rng.randf_range(0.45, 0.85)
		var nd := (Basis(up.cross(Vector3(cos(spin), 0, sin(spin))).normalized() if absf(up.y) > 0.2 else Vector3.UP, tilt) * up).normalized()
		nd = (nd + Vector3.UP * 0.25).normalized()
		_bough(rng, to, nd, length * rng.randf_range(0.62, 0.78), radius * 0.6, depth + 1)


func _tree_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	_vs.clear(); _ns.clear(); _cs.clear(); _ix.clear()
	seed(rng.randi())
	# a trunk leaning toward the window, then boughs; the crown fills the top of the window from the left
	_bough(rng, Vector3.ZERO, Vector3(0.12, 1.0, 0.05).normalized(), 1.2, 0.13, 0)
	# sway weight: nothing at the root, most at the crown's rim
	for i in _vs.size():
		var p := _vs[i]
		var w := clampf((p.y - 0.8) / 2.4, 0.0, 1.0) * clampf(0.5 + Vector2(p.x, p.z).length() * 0.6, 0.0, 1.3)
		_cs[i].r = w
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _vs
	arr[Mesh.ARRAY_NORMAL] = _ns
	arr[Mesh.ARRAY_COLOR] = _cs
	arr[Mesh.ARRAY_INDEX] = _ix
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _process(dt: float) -> void:
	_t += dt
	var cover := 0.0
	for c in _clouds:
		var n := c.node as Node3D
		n.position.x += float(c.speed) * dt
		if n.position.x > 3.4:
			n.position.x = -3.4
		var d := absf(n.position.x - _moon_x)
		cover = maxf(cover, clampf(1.15 - d / (0.75 * float(c.width)), 0.0, 1.0))
	if _game:
		var target := 1.0 - 0.78 * cover
		_game.moon_cloud = lerpf(_game.moon_cloud, target, clampf(dt * 0.9, 0.0, 1.0))
		var f := _game.moon_cloud
		_moon_mat.albedo_color = Color(lerpf(0.32, 0.93, f), lerpf(0.36, 0.96, f), lerpf(0.44, 1.0, f))
		_halo_mat.albedo_color = Color(0.55, 0.65, 1.0, 0.16 * f)
		for sm in _shaft_mats:
			if sm is ShaderMaterial:  # the moon patch on the floor
				(sm as ShaderMaterial).set_shader_parameter("cloud", f)
			else:
				(sm as StandardMaterial3D).albedo_color.a = 0.26 * f  # round 6: softer shaft
	if _tree:
		# gusts: the wind rises and falls every half-minute or so
		var gust := 0.75 + 0.45 * maxf(0.0, sin(_t * 0.21)) * (0.6 + 0.4 * sin(_t * 0.53 + 1.1))
		(_tree.material_override as ShaderMaterial).set_shader_parameter("wind", gust)
		for sm in _shaft_mats:
			if sm is ShaderMaterial:
				(sm as ShaderMaterial).set_shader_parameter("wind", gust)
