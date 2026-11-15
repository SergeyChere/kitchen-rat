class_name ToyCar
extends AnimatableBody3D
## Round 20 (the player: "it's boring — make the missions like It Takes Two"): the kids' room's toy, a wind-up car
## big enough for a rat. F beside it: she hops in. W / S drive and brake, A / D steer, Space hops out. It is fast
## and the spring whirrs (the cat can hear it), it bounces off furniture with a bonk, and it knocks over whatever
## it drives into — a tower of toy blocks most of all.

const MAX_FWD := 1.8
const MAX_BACK := 0.6
const ACC := 2.6
const DRAG := 1.6
const TURN := 2.4
const LENGTH := 0.34

var speed := 0.0
var driver: Rat = null
var _half := Vector3(0.09, 0.05, 0.17)
var _hinted := false
var _click := 0.0
var _toppled := {}


func setup(b: LevelBuilder, at: Vector3, yaw_deg: float) -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	global_position = at
	rotation.y = 0.0  # (fitted unturned, so its own frame is the world's; turned at the end)
	var m := b.spawn("finds/toy_car", at, 0.0, self)
	if m == null:
		return
	var bb := b.world_aabb(m)
	if bb.size.x > bb.size.z * 1.15:  # (modelled lying along X: turned so it drives along its length)
		m.rotate_y(PI * 0.5)
		bb = b.world_aabb(m)
	var k := LENGTH / maxf(maxf(bb.size.x, bb.size.z), 0.001)
	m.scale *= k
	bb = b.world_aabb(m)
	m.global_position += Vector3(at.x - bb.get_center().x, at.y - bb.position.y, at.z - bb.get_center().z)
	bb = b.world_aabb(m)
	var lb := AABB(bb.position - at, bb.size)  # its size in its own frame
	_half = lb.size * 0.5
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = lb.size
	cs.shape = sh
	cs.position = lb.get_center()
	add_child(cs)
	rotation.y = deg_to_rad(yaw_deg)


func _physics_process(dt: float) -> void:
	var g := Game.I
	if g == null or not g.playing():
		return
	var rat: Rat = g.rat
	if driver != null and rat.carrier != self:  # (caught, teleported home…)
		driver = null
	if driver == null:
		if absf(speed) > 0.01:  # coasting on after she hopped out
			speed = move_toward(speed, 0.0, DRAG * 2.0 * dt)
			_move(dt)
		var near := rat.carrier == null and not rat.jumping and rat.balloon == null \
			and Vector2(rat.global_position.x - global_position.x, rat.global_position.z - global_position.z).length() < 0.3 \
			and absf(rat.global_position.y - global_position.y) < 0.15
		if near and not _hinted:
			_hinted = true
			g.toast("%s — hop into the toy car" % Keys.label("push"))
		if near and Input.is_action_just_pressed("push") and not rat.dragging():
			_mount(rat)
		return
	if Input.is_action_just_pressed("jump"):
		_dismount()
		return
	var thr := Input.get_action_strength("forward") - Input.get_action_strength("back")
	var steer := Input.get_action_strength("left") - Input.get_action_strength("right")
	if thr > 0.0:
		speed = move_toward(speed, MAX_FWD, ACC * dt)
	elif thr < 0.0:
		speed = move_toward(speed, -MAX_BACK, ACC * 1.5 * dt)
	else:
		speed = move_toward(speed, 0.0, DRAG * dt)
	rotation.y += steer * TURN * dt * clampf(speed / 0.5, -1.0, 1.0)
	_move(dt)
	rat.global_position = global_position + Vector3.UP * (_half.y * 1.2)
	rat.rotation.y = rotation.y
	if absf(speed) > 0.3:
		rat.add_noise(0.3 + absf(speed) * 0.2)  # the spring whirrs
	_click -= dt * absf(speed) * 8.0
	if _click <= 0.0 and absf(speed) > 0.05:
		_click = 1.0
		Sfx.play("click", global_position, -16.0, randf_range(1.5, 1.8))


func _move(dt: float) -> void:
	var g := Game.I
	var fw := global_basis.z
	var dir := signf(speed)
	var reach := absf(speed) * dt + 0.03
	for side: float in [-1.0, 0.0, 1.0]:
		var o := global_position + Vector3.UP * 0.035 + global_basis.x * side * _half.x * 0.85 + fw * _half.z * 0.9 * dir
		var hit := g.ray(o, o + fw * dir * (_half.z * 0.1 + reach))
		if hit.is_empty() or hit.collider == self or hit.collider is Rat:
			continue
		if hit.collider is Knockable:
			_knock(hit.collider as Knockable)
			continue
		_crash(hit.position)
		return
	global_position += fw * speed * dt
	if absf(speed) > 0.35:
		var front := global_position + fw * _half.z * dir
		for k in g.knockables:
			if not k.knocked and absf(k.global_position.y - global_position.y) < 0.2 \
					and Vector2(k.global_position.x - front.x, k.global_position.z - front.z).length() < 0.13:
				_knock(k)


func _knock(k: Knockable) -> void:
	var fw := global_basis.z * signf(speed)
	if k.has_meta("tower"):
		var t: int = k.get_meta("tower")
		if _toppled.has(t):
			return
		_toppled[t] = true
		var n := 0
		for o in Game.I.knockables:
			if o.has_meta("tower") and int(o.get_meta("tower")) == t and not o.knocked:
				n += 1
				var spread := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
				o.knock(fw + spread)
				o.apply_central_impulse(fw * absf(speed) * 0.25 * o.mass)
		Game.I.tasks.set_flag("tower")
		Game.I.cam.shake(0.35)
		Game.I.bubble_at("STRIKE!" if absf(speed) > 1.2 else "Crash!", k.global_position + Vector3.UP * 0.25, 1.4, Color(1.0, 0.85, 0.35))
		Sfx.play("crash", k.global_position)
		Game.I.noise(k.global_position, 2.2, "Crash!", true, 0.9)
		speed *= 0.6
	else:
		k.knock(fw)


func _crash(at: Vector3) -> void:
	if absf(speed) > 0.9:
		Sfx.play("thud", at)
		Game.I.cam.shake(0.22)
		Game.I.bubble_at("Bonk!", at + Vector3.UP * 0.18, 1.0)
		Game.I.noise(at, 1.2, "Bonk!", false, 0.5)
	speed = -speed * 0.25


func _mount(rat: Rat) -> void:
	driver = rat
	rat.carrier = self
	speed = 0.0
	Sfx.play("squeak", global_position, -6.0, 1.2)
	Game.I.tasks.set_flag("car")
	Game.I.toast("%s / %s drive · %s / %s steer · %s hop out" % [Keys.label("forward"), Keys.label("back"),
		Keys.label("left"), Keys.label("right"), Keys.label("jump")])


func _dismount() -> void:
	var rat := driver
	driver = null
	if rat == null or rat.carrier != self:
		return
	rat.carrier = null
	for side: float in [1.0, -1.0]:
		var p := global_position + global_basis.x * side * (_half.x + 0.09) + Vector3.UP * 0.02
		if Game.I.sphere_free(p + Vector3.UP * 0.05, 0.04):
			rat.teleport(p, rotation.y)
			return
	rat.teleport(global_position - global_basis.z * (_half.z + 0.1) + Vector3.UP * 0.02, rotation.y)
