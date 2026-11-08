class_name Trap
extends Node3D
## A mousetrap on the floor. Sniffing reveals it; stepping on it snaps (a life); something falling on it disarms it.

var hidden := false
var sprung := false
var found := false
var _bar: Node3D
var _angle := 0.0


func _ready() -> void:
	_bar = find_child("bar*", true, false) as Node3D
	visible = not hidden


func reveal() -> void:
	hidden = false
	found = true
	visible = true


func spring() -> void:
	if sprung:
		return
	sprung = true
	visible = true
	Sfx.play("snap", global_position)
	var gm := Game.I
	if gm and gm.rat and gm.feel and gm.rat.global_position.distance_to(global_position) < 0.5:
		gm.feel.slowmo(0.3, 0.35)  # snapped right next to her
		gm.cam.shake(0.45)


func _process(dt: float) -> void:
	if not sprung or _bar == null or _angle >= 170.0:
		return
	var step := minf(170.0 - _angle, 1400.0 * dt)
	_angle += step
	_bar.rotate_object_local(Vector3.RIGHT, deg_to_rad(-step))
