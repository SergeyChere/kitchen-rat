class_name StorySet
extends Node3D
## Round 17: the places of the prologue that are not in the house (asked: "night, a street, rain, lightning; the
## rat runs through the grass with a street cat after her; she sees a house with lit windows and turns to it; at
## the last moment she slips into a hole in the wall"; then "the way on is blocked, she crawls the other way,
## toward a light"). Built far off to the side of the room (x = 40 m) only while the prologue plays, and freed
## after it. Everything is simple shapes in the game's painted look; the points the story needs are exposed.

const O := Vector3(40.0, 0.0, 0.0)        # the garden
const T := Vector3(40.0, 0.0, 24.0)       # the passage inside the wall

var start := O + Vector3(0.0, 0.0, -7.0)  # where she comes running from, through the grass
var turn := O + Vector3(0.0, 0.0, -0.6)   # where she sees the house and turns to it
var hole := O + Vector3(5.86, 0.0, 0.6)   # the hole at the foot of the house wall
var house_look := O + Vector3(6.0, 1.4, 0.6)
var tunnel_in := T + Vector3(0.0, 0.0, 0.0)
var tunnel_block := T + Vector3(0.0, 0.0, 0.85)  # the fallen bricks
var tunnel_out := T + Vector3(-0.9, 0.0, 0.25)   # round the bend, toward the light
var rain: CPUParticles3D

var _b: LevelBuilder


func build(b: LevelBuilder) -> void:
	_b = b
	name = "Story set"
	_garden()
	_passage()


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _box(at: Vector3, size: Vector3, m: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = at
	return mi


func _garden() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# the ground: wet grass, and the street along the far side with a lamp
	_box(O + Vector3(0, -0.05, 0), Vector3(30, 0.1, 22), _flat(Color(0.13, 0.2, 0.15)))
	_box(O + Vector3(-4.0, -0.04, 0), Vector3(3.0, 0.1, 22), _flat(Color(0.12, 0.12, 0.15)))  # the street
	_box(O + Vector3(-2.35, 0.02, 0), Vector3(0.2, 0.08, 22), _flat(Color(0.3, 0.3, 0.32)))   # the kerb
	var post := _box(O + Vector3(-2.7, 1.6, -3.0), Vector3(0.08, 3.2, 0.08), _flat(Color(0.1, 0.1, 0.12)))
	_box(O + Vector3(-2.5, 3.2, -3.0), Vector3(0.5, 0.06, 0.12), _flat(Color(0.1, 0.1, 0.12)))
	_box(O + Vector3(-2.3, 3.12, -3.0), Vector3(0.22, 0.08, 0.16), _glow(Color(1.0, 0.86, 0.55)))
	var lamp := OmniLight3D.new()
	add_child(lamp)
	lamp.global_position = O + Vector3(-2.3, 2.9, -3.0)
	lamp.light_color = Color(1.0, 0.8, 0.5)
	lamp.light_energy = 2.2
	lamp.omni_range = 7.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# tall grass: blades in tufts along her way and around it
	var blade := BoxMesh.new()
	blade.size = Vector3(0.005, 1.0, 0.002)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade
	mm.instance_count = 4200
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-1.6, 5.6), 0.0, rng.randf_range(-8.5, 4.0))
		if absf(p.x) < 0.3 and p.z < -0.3:
			p.x += 0.45 * signf(p.x + 0.001)  # a parting where she runs (and the camera runs beside her)
		if p.z > -1.2 and p.z < 1.6 and p.x > 0.0 and absf(p.z - 0.6 * p.x / 5.86 + 0.1) < 0.35:
			p.z += 0.6  # and along her dash to the hole
		var h := rng.randf_range(0.12, 0.34)
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		mm.set_instance_transform(i, Transform3D(bs.scaled(Vector3(1.0, h, 1.0)), O + p + Vector3.UP * h * 0.5))
		mm.set_instance_color(i, Color(0.16, 0.3, 0.2).lerp(Color(0.3, 0.42, 0.26), rng.randf()))
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = mm
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass.material_override = gm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass)
	# the house: a long wall with lit windows, a roof, and the hole at its foot
	var wall := _flat(Color(0.55, 0.47, 0.42))
	_box(O + Vector3(8.0, 1.9, 0.0), Vector3(4.0, 3.8, 14.0), wall)
	_box(O + Vector3(8.0, 4.25, 0.0), Vector3(4.6, 0.9, 14.6), _flat(Color(0.25, 0.16, 0.14)))
	_box(O + Vector3(5.98, 0.15, 0.0), Vector3(0.06, 0.3, 14.0), _flat(Color(0.35, 0.3, 0.28)))  # the plinth
	var warm := _glow(Color(1.0, 0.8, 0.45))
	var frame := _flat(Color(0.92, 0.9, 0.84))
	for z in [-4.5, -1.5, 1.8, 4.6]:
		_box(O + Vector3(5.97, 1.9, z), Vector3(0.05, 1.3, 1.0), frame)
		_box(O + Vector3(5.95, 1.9, z), Vector3(0.04, 1.16, 0.86), warm)
		var wl := OmniLight3D.new()
		add_child(wl)
		wl.global_position = O + Vector3(5.6, 1.7, z)
		wl.light_color = Color(1.0, 0.75, 0.45)
		wl.light_energy = 1.1
		wl.omni_range = 3.2
	var dark := _glow(Color(0.02, 0.015, 0.02))
	_box(hole + Vector3(0.075, 0.045, 0.0), Vector3(0.012, 0.09, 0.11), dark)  # flush with the plinth's face
	rain = CPUParticles3D.new()
	rain.amount = 700
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(3.5, 0.2, 3.5)
	rain.direction = Vector3(0.15, -1, 0.05)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -9.8, 0)
	rain.initial_velocity_min = 6.0
	rain.initial_velocity_max = 7.5
	var streak := QuadMesh.new()
	streak.size = Vector2(0.006, 0.16)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.75, 0.82, 1.0, 0.35)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = sm
	rain.mesh = streak
	rain.local_coords = false
	add_child(rain)


func _passage() -> void:
	# inside the wall: a narrow passage of old boards and brick, fallen bricks blocking the way on, and round a bend
	# a warm light (the burrow behind the kitchen wall)
	var board := _flat(Color(0.2, 0.14, 0.1))
	var brick := _flat(Color(0.28, 0.16, 0.13))
	_box(T + Vector3(0, -0.02, 0.3), Vector3(0.4, 0.04, 1.6), board)                 # floor
	_box(T + Vector3(0.18, 0.15, 0.3), Vector3(0.04, 0.34, 1.6), brick)              # right wall
	_box(T + Vector3(-0.18, 0.15, 0.75), Vector3(0.04, 0.34, 0.7), brick)            # left wall, beyond the bend
	_box(T + Vector3(-0.18, 0.15, -0.3), Vector3(0.04, 0.34, 0.3), brick)            # left wall, before it
	_box(T + Vector3(0, 0.33, 0.3), Vector3(0.4, 0.04, 1.6), board)                  # ceiling
	_box(T + Vector3(0, 0.15, -0.5), Vector3(0.4, 0.34, 0.04), board)                # behind her
	_box(T + Vector3(-0.6, -0.02, 0.25), Vector3(0.8, 0.04, 0.3), board)             # the side way, floor
	_box(T + Vector3(-0.6, 0.33, 0.25), Vector3(0.8, 0.04, 0.3), board)              # its ceiling
	_box(T + Vector3(-0.6, 0.15, 0.42), Vector3(0.8, 0.34, 0.04), brick)
	_box(T + Vector3(-0.6, 0.15, 0.08), Vector3(0.8, 0.34, 0.04), brick)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 9:  # the fall of bricks
		var bk := _box(tunnel_block + Vector3(rng.randf_range(-0.12, 0.12), 0.03 + (i / 3) * 0.06, rng.randf_range(-0.05, 0.08)),
				Vector3(0.11, 0.055, 0.06), brick)
		bk.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3))
	var light := OmniLight3D.new()
	add_child(light)
	light.global_position = T + Vector3(-1.05, 0.12, 0.25)
	light.light_color = Color(1.0, 0.78, 0.48)
	light.light_energy = 1.6
	light.omni_range = 1.4
	_box(T + Vector3(-1.02, 0.12, 0.25), Vector3(0.02, 0.2, 0.22), _glow(Color(1.0, 0.85, 0.6)))
	var dim := OmniLight3D.new()
	add_child(dim)
	dim.global_position = T + Vector3(0, 0.25, 0.1)
	dim.light_color = Color(0.5, 0.55, 0.8)
	dim.light_energy = 0.2
	dim.omni_range = 1.2
	for n in find_children("*", "GeometryInstance3D", true, false):
		if n != rain:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
