class_name ZipLine
extends Node3D
## Round 21 (the player: "it's boring — make the missions like It Takes Two"): a string stretched from a stick on top
## of the crate stairs down to a stake near the mouse hole, with a clothes peg on it. F under the peg: she grabs it and
## zips down, with whatever she carries — the salami too, which she could never carry back up. Space lets go early,
## and from up there that is a long drop. After a ride the peg springs back up the line.

const HANG := 0.17    # her feet hang this far below the line
const REST := 0.14    # the peg rests this far down the line from the top stick
const GRAB := 0.17    # she takes the peg standing this close under it
const MAX_V := 2.6

var a := Vector3.ZERO  # the line's top end
var b := Vector3.ZERO  # its bottom end
var t := 0.0           # where the peg is along the line (0 = top, 1 = bottom)
var v := 0.0
var rider: Rat = null
var rest_t := 0.0
var _len := 1.0
var _dir := Vector3.FORWARD
var _peg: Node3D
var _hinted := false
var _whizz := 0.0
var _hop := 1.0
var _hop_from := Vector3.ZERO


func setup(bld: LevelBuilder, top: Vector3, top_base: float, bottom: Vector3, bottom_base: float) -> void:
	a = top
	b = bottom
	_len = maxf(a.distance_to(b), 0.1)
	_dir = (b - a) / _len
	rest_t = REST / _len
	t = rest_t
	set_meta("ride_clip", "jump_up")
	set_meta("ride_tilt", 48.0)
	var wood := bld.mat(Color(0.6, 0.43, 0.27))
	_stick(a, top_base, wood)
	_stick(b, bottom_base, wood)
	var line := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.003
	cm.bottom_radius = 0.003
	cm.height = _len
	cm.radial_segments = 5
	cm.rings = 1
	line.mesh = cm
	line.material_override = bld.mat(Color(0.93, 0.9, 0.82))
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	line.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, _dir)), (a + b) * 0.5)
	# the clothes peg: two wooden prongs and a steel spring, hanging under the line
	_peg = Node3D.new()
	add_child(_peg)
	for s in [-1.0, 1.0]:
		var prong := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.009, 0.085, 0.018)
		prong.mesh = bm
		prong.material_override = wood
		prong.position = Vector3(s * 0.006, -0.04, 0.0)
		_peg.add_child(prong)
	var spring := MeshInstance3D.new()
	var sp := CylinderMesh.new()
	sp.top_radius = 0.006
	sp.bottom_radius = 0.006
	sp.height = 0.02
	spring.mesh = sp
	spring.material_override = bld.mat(Color(0.72, 0.74, 0.78))
	spring.rotation.z = PI * 0.5
	spring.position = Vector3(0.0, -0.03, 0.0)
	_peg.add_child(spring)
	_place_peg()


func _stick(top: Vector3, base_y: float, m: Material) -> void:
	var h := top.y - base_y + 0.035
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.007
	cm.bottom_radius = 0.009
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	add_child(mi)
	mi.global_position = Vector3(top.x, base_y + h * 0.5, top.z)


func peg_point() -> Vector3:
	return a.lerp(b, t)


func _place_peg() -> void:
	_peg.global_position = peg_point()
	_peg.rotation = Vector3(0.0, Nights.yaw_to(Vector3(_dir.x, 0.0, _dir.z)), 0.0)


func _physics_process(dt: float) -> void:
	var g := Game.I
	if g == null or not g.playing():
		return
	var rat: Rat = g.rat
	if rider != null and rat.carrier != self:  # caught, teleported home…
		rider = null
	if rider == null:
		if t > rest_t:  # the spring pulls the peg back up the line
			t = maxf(rest_t, t - dt * 0.3)
			_place_peg()
			return
		var hand := peg_point() + Vector3.DOWN * HANG
		var near := rat.carrier == null and not rat.jumping and rat.is_on_floor() and rat.balloon == null \
			and Vector2(rat.global_position.x - hand.x, rat.global_position.z - hand.z).length() < GRAB \
			and rat.global_position.y < hand.y + 0.05 and rat.global_position.y > hand.y - 0.26  # (she hops up to it)
		if near and not _hinted:
			_hinted = true
			g.toast("%s — grab the clothes peg and zip down" % Keys.label("push"))
		if near and Input.is_action_just_pressed("push"):
			_grab(rat)
		return
	if _hop < 1.0:  # the little hop up to the peg
		_hop = minf(_hop + dt / 0.14, 1.0)
		rat.global_position = _hop_from.lerp(peg_point() + Vector3.DOWN * HANG, _hop) + Vector3.UP * sin(_hop * PI) * 0.03
		return
	if Input.is_action_just_pressed("jump"):
		_let_go(_dir * v)
		return
	v = minf(v + (9.8 * -_dir.y * 0.7 - 0.25) * dt, MAX_V)
	var nt := minf(t + v * dt / _len, 1.0)
	var to := a.lerp(b, nt) + Vector3.DOWN * HANG
	var flat := Vector3(_dir.x, 0.0, _dir.z).normalized()
	# something in the way (a line strung badly): she stops dead and drops
	var hit := g.ray(rat.global_position + Vector3.UP * 0.07, to + Vector3.UP * 0.07 + flat * 0.07)
	if not hit.is_empty() and not (hit.collider is Rat) and not (hit.collider is Food):
		Sfx.play("thud", rat.global_position)
		_let_go(Vector3.ZERO)
		return
	t = nt
	_place_peg()
	rat.global_position = to
	rat.rotation.y = Nights.yaw_to(flat)
	rat.add_noise(0.25)
	_whizz -= dt
	if _whizz <= 0.0:
		_whizz = 0.1
		Sfx.play("scrape", rat.global_position, -14.0, 1.8 + v * 0.35, 0.08)
	if t >= 0.985:
		g.tasks.set_flag("zip")
		g.bubble_at("Wheee!", rat.global_position + Vector3.UP * 0.3, 1.2, Color(1.0, 0.9, 0.5))
		_let_go(flat * minf(v, 1.2))


func _grab(rat: Rat) -> void:
	rider = rat
	rat.carrier = self
	v = 0.5
	_hop = 0.0
	_hop_from = rat.global_position
	Sfx.play("squeak", rat.global_position, -6.0, 1.3)


func _let_go(vel: Vector3) -> void:
	var rat := rider
	rider = null
	v = 0.0
	if rat != null and rat.carrier == self:
		rat.ride_off(vel)
