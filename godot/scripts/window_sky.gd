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
var _branches: Node3D
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
	# branches in the top corner: near-black silhouettes that sway; they cast shadows, so when the
	# moon is out their movement can ghost across the light patch, like the real thing
	_branches = Node3D.new()
	_branches.position = Vector3(-1.35, 2.5, -0.75)
	add_child(_branches)
	var bark := _unshaded(Color(0.04, 0.04, 0.07))
	for i in 5:
		var br := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var len := rng.randf_range(0.7, 1.25)
		bm.size = Vector3(len, 0.022, 0.022)
		br.mesh = bm
		br.material_override = bark
		br.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		br.position = Vector3(len / 2.0 - 0.1, -0.07 * float(i), 0.0)
		br.rotation.z = rng.randf_range(-0.5, -0.08)
		br.rotation.y = rng.randf_range(-0.15, 0.15)
		_branches.add_child(br)
		var leaves := _ball(rng.randf_range(0.09, 0.15), bark, 0.7)
		leaves.position = br.position + Vector3(cos(br.rotation.z), sin(br.rotation.z), 0.0) * len * 0.92
		leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_branches.add_child(leaves)


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
			(sm as StandardMaterial3D).albedo_color.a = 0.5 * f
	if _branches:
		_branches.rotation.z = 0.035 * sin(_t * 0.6) + 0.015 * sin(_t * 1.63 + 1.7)
		_branches.rotation.x = 0.012 * sin(_t * 0.83 + 0.4)
