class_name Blink
extends Node
## Eyelids. She blinks every few seconds (now and then twice in a row), and whoever sleeps, sleeps with
## their eyes shut. The lids are small coat-coloured balls over the eyes, on the Head bone; a blink shows them
## for a tenth of a second and hides the glints.

var lids: Array[Node3D] = []
var glints: Array[Node3D] = []
var _t := 1.5
var _closed := 0.0
var _shut := false
var _ap: AnimationPlayer
var _looked := false
var _force := OS.get_environment("BLINK") == "shut"  # dev: eyes always shut, to look at the lids


func _ready() -> void:
	_t = randf_range(0.8, 4.0)
	_apply(false)


func _process(dt: float) -> void:
	if not _looked:  # the model's animation player: a few levels up from the skeleton, never past the model
		_looked = true
		var n := get_parent()
		for i in 4:
			if n == null or _ap != null:
				break
			_ap = n.find_child("AnimationPlayer", true, false) as AnimationPlayer
			n = n.get_parent()
	_t -= dt
	if _t <= 0.0:
		_closed = 0.11
		_t = 0.3 if randf() < 0.18 else randf_range(2.2, 6.0)
	_closed -= dt
	var asleep := _ap != null and String(_ap.current_animation).begins_with("sleep")
	var shut := asleep or _closed > 0.0 or _force
	if shut != _shut:
		_apply(shut)


func _apply(shut: bool) -> void:
	_shut = shut
	for l in lids:
		l.visible = shut
	for g in glints:
		g.visible = not shut
