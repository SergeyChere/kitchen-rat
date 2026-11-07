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
var _start_y := 0.0


func _ready() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	var pm := PhysicsMaterial.new()  # slides off a table, bounces a little on the floor
	pm.friction = 0.25
	pm.bounce = 0.25
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


## Round things roll (Game gives them a sphere to collide with).
func is_round() -> bool:
	return kind in ["apple", "ball", "orange"]


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
	_start_y = global_position.y
	var dir := d.normalized() if d.length() > 0.001 else push_dir
	var push := 1.5 + (Game.I.rat.move_speed * 0.4 if Game.I and Game.I.rat else 0.0)  # a running rat shoves harder
	freeze = false
	apply_central_impulse((dir * push + Vector3.UP * 0.25) * mass)
	apply_torque_impulse(dir.cross(Vector3.UP) * -0.004 * mass * (3.0 if is_round() else 1.0))
	Game.I.tasks.knocked[kind] = true
	if group != "":
		Game.I.knock_group(self)


func _physics_process(_dt: float) -> void:
	if knocked:
		_speed = maxf(_speed * 0.9, linear_velocity.length())


func _on_body_entered(_b: Node) -> void:
	if not knocked or _landed or _speed < 1.2 or global_position.y > _start_y - 0.1:  # only once it has fallen
		return
	_landed = true
	Game.I.knock_landed(self, global_position)
