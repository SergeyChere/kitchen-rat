class_name YarnBall
extends RigidBody3D
## Round 21 (the player: "it's boring — make the missions like It Takes Two"): a ball of yarn on the living room
## floor. Run into it and it rolls; a cat that sees it rolling forgets everything else and plays with it — trots after
## it, crouches, swipes it away and goes after it again — and while it plays it sees only what is right under its
## nose. A sleeping cat, or one already chasing her, doesn't care.

const R := 0.05
const SEES := 3.2  # a cat this close notices it rolling

var _cd := 0.0
var _rolled := false


func setup(b: LevelBuilder, at: Vector3, color: Color) -> void:
	mass = 0.06
	collision_layer = 1
	collision_mask = 1
	linear_damp = 0.45
	angular_damp = 0.6
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.25
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = R
	cs.shape = sh
	add_child(cs)
	# the look: a ball wound from strands, in two shades
	var light := b.mat(color)
	var dark := b.mat(color.darkened(0.28))
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R * 0.96
	sm.height = R * 1.92
	sm.radial_segments = 16
	sm.rings = 8
	core.mesh = sm
	core.material_override = dark
	add_child(core)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 10:
		var t := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = R * 0.9
		tm.outer_radius = R * 1.02
		tm.rings = 20
		tm.ring_segments = 4
		t.mesh = tm
		t.material_override = light if i % 3 else dark
		t.rotation = Vector3(rng.randf_range(0.0, PI), rng.randf_range(0.0, PI), rng.randf_range(0.0, PI))
		add_child(t)
	var tail := MeshInstance3D.new()  # the loose end lying on the floor
	var tb := BoxMesh.new()
	tb.size = Vector3(0.006, 0.004, 0.09)
	tail.mesh = tb
	tail.material_override = light
	tail.position = Vector3(0.012, -R + 0.002, -R - 0.04)
	add_child(tail)
	global_position = at + Vector3.UP * R


func _physics_process(dt: float) -> void:
	var g := Game.I
	if g == null or not g.playing():
		return
	_cd = maxf(_cd - dt, 0.0)
	if _cd > 0.0 or linear_velocity.length() < 0.25 or g.cat == null or not g.cat.visible:
		return
	if g.cat.global_position.distance_to(global_position) < SEES and g.cat.play_with(self):
		_cd = 1.0
		if not _rolled:
			_rolled = true
			g.tasks.set_flag("yarn")


## The cat's swipe: off it rolls again, roughly away from the paw.
func bat(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	away = away.rotated(Vector3.UP, randf_range(-0.9, 0.9))
	apply_central_impulse((away * randf_range(0.6, 1.0) + Vector3.UP * 0.2) * mass)
	Sfx.play("scratch", global_position, -12.0, 1.5)
