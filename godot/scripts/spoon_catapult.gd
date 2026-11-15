class_name SpoonCatapult
extends Node3D
## Round 21 (the player: "it's boring — make the missions like It Takes Two"): a serving spoon lying across a cork at
## the corner of the dining table, its handle in the air. G beside the bowl drops what she carries into it; F at the
## handle stomps it down and the bowl flings the load off the table in a high arc, down by the mouse hole — the
## chicken leg she could only have dragged the long way round. It lands with a thump that carries across the room.

const LEN := 0.26
const REST := -12.0  # the spoon's tilt at rest (handle up), degrees
const FIRED := 14.0  # stomped: handle down, bowl up
const FLIGHT := 0.9  # s in the air

var target := Vector3.ZERO
var loaded: Food = null
var _pivot: Node3D
var _bowl := Vector3.ZERO    # in the pivot's frame
var _handle := Vector3.ZERO
var _loaded_t := 0.0
var _flip := 0.0             # the stomp: 1 → 0
var _hint_drop := false
var _hint_fire := false


func setup(b: LevelBuilder, at: Vector3, to: Vector3) -> void:
	global_position = at
	target = to
	var d := to - at
	d.y = 0.0
	rotation.y = Nights.yaw_to(d.normalized())
	var cork := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.015
	cm.height = 0.04
	cm.radial_segments = 10
	cork.mesh = cm
	cork.material_override = b.mat(Color(0.74, 0.56, 0.36))
	cork.rotation.z = PI * 0.5  # lying across the spoon
	cork.position = Vector3(0.0, 0.015, 0.0)
	add_child(cork)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 0.032, 0.0)
	add_child(_pivot)
	var m := b.spawn("props/spoon", at, 0.0, _pivot)
	if m:
		m.rotation = Vector3(0.0, PI * 0.5, 0.0)  # its bowl (+X) to the back, the handle toward the target
		var bb := LevelBuilder.aabb_of(m)
		var k := LEN / maxf(maxf(bb.size.x, bb.size.z), 0.001)
		m.scale = Vector3.ONE * k
		m.position = -(m.basis * (bb.get_center()))
		_bowl = Vector3(0.0, 0.006, -bb.size.x * k * 0.36)
		_handle = Vector3(0.0, 0.0, bb.size.x * k * 0.47)
	_pivot.rotation.x = deg_to_rad(REST)


func bowl_point() -> Vector3:
	return _pivot.global_transform * _bowl


func handle_point() -> Vector3:
	return _pivot.global_transform * _handle


## G pressed: does the food she carries go into this spoon's bowl?
func takes(rat: Rat) -> bool:
	if loaded != null or rat.carried.is_empty():
		return false
	var p := bowl_point()
	return Vector2(rat.global_position.x - p.x, rat.global_position.z - p.z).length() < 0.2 and absf(rat.global_position.y - p.y) < 0.12


func load_food(f: Food) -> void:
	loaded = f
	_loaded_t = 0.0
	Sfx.play("clink", bowl_point(), -6.0, 1.3)


func _physics_process(dt: float) -> void:
	var g := Game.I
	if g == null:
		return
	if _flip > 0.0:
		_flip = maxf(_flip - dt, 0.0)
		var k := 1.0 if _flip > 0.5 else _flip / 0.5  # snaps down, holds, eases back up
		_pivot.rotation.x = deg_to_rad(lerpf(REST, FIRED, k))
	if not g.playing():
		return
	var rat: Rat = g.rat
	if loaded != null:
		_loaded_t += dt
		if not is_instance_valid(loaded) or loaded.carried:  # she took it back out
			loaded = null
		elif _loaded_t > 0.55:
			loaded.global_position = bowl_point()
	var on_top := absf(rat.global_position.y - global_position.y) < 0.12 and not rat.jumping
	if not on_top:
		return
	var hp := handle_point()
	var near_handle := Vector2(rat.global_position.x - hp.x, rat.global_position.z - hp.z).length() < 0.15
	if loaded == null:
		if not _hint_drop and not rat.carried.is_empty() and rat.global_position.distance_to(bowl_point()) < 0.45:
			_hint_drop = true
			g.toast("%s by the bowl — drop it in the spoon" % Keys.label("drop"))
		return
	if near_handle and not _hint_fire:
		_hint_fire = true
		g.toast("%s — stomp on the handle" % Keys.label("push"))
	if near_handle and _loaded_t > 0.6 and Input.is_action_just_pressed("push"):
		_fire()


func _fire() -> void:
	var g := Game.I
	var f := loaded
	loaded = null
	_flip = 1.0
	Sfx.play("whack", handle_point(), -2.0, 1.2)
	g.cam.shake(0.15)
	g.tasks.set_flag("catapult")
	var from := f.global_position
	var to := target
	var tw := f.create_tween()
	tw.tween_method(func(t: float):
		f.global_position = from.lerp(to, t) + Vector3.UP * (0.55 * 4.0 * t * (1.0 - t))
		f.rotation = Vector3(t * 9.0, t * 3.0, 0.0), 0.0, 1.0, FLIGHT)
	tw.tween_callback(func():
		f.rotation = Vector3.ZERO
		f.global_position = to
		if f.has_meta("dropped_at"):
			f.remove_meta("dropped_at")
		Sfx.play("land_big", to)
		g.cam.shake(0.12)
		g.noise(to, 2.0, "Thump!", true, 0.8))
	g.bubble_at("Wheee!", from + Vector3.UP * 0.2, 1.0, Color(1.0, 0.9, 0.5))
