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
	freeze = false
	d.y = 0.0
	apply_central_impulse((d.normalized() * 0.9 + Vector3.UP * 0.5) * mass)
	apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.01)
	Game.I.tasks.knocked[kind] = true
	if group != "":
		Game.I.knock_group(self)


func _physics_process(_dt: float) -> void:
	if knocked:
		_speed = maxf(_speed * 0.9, linear_velocity.length())


func _on_body_entered(_b: Node) -> void:
	if not knocked or _landed or _speed < 1.2:
		return
	_landed = true
	Game.I.knock_landed(self, global_position)
