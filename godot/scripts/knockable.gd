class_name Knockable
extends RigidBody3D
## A cup, jar, apple… the rat can push off a surface with F. A "trap" one falls by itself when the rat walks past
## without sneaking. The crash is a big noise: it lures the cat and can disarm a mousetrap it lands on.

var kind := "cup"
var trap := false
var push_dir := Vector3.FORWARD
var spawn := ""
var group := ""
var knocked := false
var _landed := false
var _speed := 0.0
var _slide := Vector3.ZERO  # pushed: it slides along the surface until it goes over the edge, then falls
var _slid := 0.0


func _ready() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func sound() -> String:
	match kind:
		"cup", "glass": return "Clink!"
		"vase": return "Crash!"
		"jar", "bottle": return "Bang!"
		"can", "spoon": return "Clang!"
		"carton": return "Thump!"
		"ball": return "Bonk!"
	return "Thud!"


func knock(d: Vector3) -> void:
	if knocked:
		return
	knocked = true
	d.y = 0.0
	_slide = d.normalized() if d.length() > 0.001 else push_dir
	Game.I.tasks.knocked[kind] = true
	if group != "":
		Game.I.knock_group(self)


func _physics_process(dt: float) -> void:
	if knocked and _slide != Vector3.ZERO:
		global_position += _slide * 0.7 * dt
		_slid += 0.7 * dt
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.05, global_position + Vector3.DOWN * 0.04, 1, [get_rid()])
		var supported := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		if not supported or _slid > 1.0:  # over the edge: let it fall
			freeze = false
			apply_central_impulse((_slide * 0.6 + Vector3.UP * 0.1) * mass)
			apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.01)
			_slide = Vector3.ZERO
		return
	if knocked:
		_speed = maxf(_speed * 0.9, linear_velocity.length())


func _on_body_entered(_b: Node) -> void:
	if not knocked or _landed or _speed < 1.2:
		return
	_landed = true
	Game.I.knock_landed(self, global_position)
