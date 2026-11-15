class_name HeliumBalloon
extends Node3D
## Round 20 (the player: "it's boring — make the missions like It Takes Two"): the party night's gadget. A helium
## balloon tied to a chair leg: she walks into its string and holds on. Holding Space she floats up (the cake is on
## top of the fridge, out of reach of any jump); letting go of Space she sinks gently — a parachute, slow enough to
## carry even the cake down. G lets go when her mouth is empty; at the mouse hole it slips away by itself (it would
## never fit). A balloon let go drifts up to the ceiling and stays there.

enum State { TIED, HELD, FREE }

const LIFT_H := 0.62     # how far above her it floats
const STRING_H := 1.0    # tied: how high over the knot it floats
const REACH := 0.2       # she takes the string this close to the knot

var state := State.TIED
var knot := Vector3.ZERO
var _ball: Node3D
var _string: MeshInstance3D
var _t := 0.0
var _vel := Vector3.ZERO


func setup(at: Vector3, color: String) -> void:
	knot = at + Vector3.UP * 0.03
	global_position = knot + Vector3.UP * STRING_H
	var path := LevelBuilder.MODELS + "props/balloon_%s.glb" % color
	if ResourceLoader.exists(path):
		_ball = (load(path) as PackedScene).instantiate()
		add_child(_ball)
		var bb := _aabb(_ball)
		var k := 0.26 / maxf(bb.size.y, 0.001)
		_ball.scale = Vector3.ONE * k
		_ball.position = -bb.get_center() * k
	_string = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0025
	cm.bottom_radius = 0.0025
	cm.height = 1.0
	cm.radial_segments = 5
	cm.rings = 1
	_string.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.92, 0.9, 0.84)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_string.material_override = sm
	_string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_string.top_level = true
	add_child(_string)
	_t = randf() * 10.0


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := (m.transform * m.get_aabb()) if m.get_parent() == n else (_rel(n, m) * m.get_aabb())
		out = b if first else out.merge(b)
		first = false
	return out


func _rel(root: Node, m: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = m
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _process(dt: float) -> void:
	_t += dt
	var g := Game.I
	if g == null:
		return
	var rat: Rat = g.rat
	var bob := Vector3(sin(_t * 1.3) * 0.02, sin(_t * 1.7) * 0.03, cos(_t * 1.1) * 0.02)
	var low := knot
	match state:
		State.TIED:
			global_position = knot + Vector3.UP * STRING_H + bob
			if g.playing() and rat.balloon == null and not rat.dragging() and not rat.jumping:
				var d := Vector2(rat.global_position.x - knot.x, rat.global_position.z - knot.z).length()
				if d < REACH and absf(rat.global_position.y - knot.y) < 0.15:
					take(rat)
		State.HELD:
			if not is_instance_valid(rat) or rat.balloon != self:
				release()
			else:
				var want := rat.global_position + Vector3.UP * LIFT_H + bob
				global_position = global_position.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
				low = rat.global_position + Vector3.UP * 0.07 + rat.global_basis.z * -0.03
		State.FREE:
			_vel.y = move_toward(_vel.y, 0.35 if global_position.y < 2.25 else 0.0, dt)
			global_position += (_vel + bob * 0.3) * dt
			low = global_position + Vector3.DOWN * 0.55 + bob * 2.0
	_lay_string(low, global_position + Vector3.DOWN * 0.13)


func _lay_string(a: Vector3, b: Vector3) -> void:
	if _string == null:
		return
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	_string.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d / l)).scaled(Vector3(1, l, 1)), (a + b) * 0.5)


func take(rat: Rat) -> void:
	state = State.HELD
	rat.balloon = self
	Sfx.play("squeak", rat.global_position, -6.0, 1.3)
	Game.I.tasks.set_flag("balloon")
	Game.I.toast("Hold %s to float up · %s lets go" % [Keys.label("jump"), Keys.label("drop")])


func release() -> void:
	if state == State.FREE:
		return
	var g := Game.I
	if g and is_instance_valid(g.rat) and g.rat.balloon == self:
		g.rat.balloon = null
	state = State.FREE
	_vel = Vector3.ZERO
