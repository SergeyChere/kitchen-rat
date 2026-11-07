class_name ClipPlayer
extends RefCounted
## Plays a model's animation clips by name ("walk", "run", "sleep"…) with cross-fades.

const ONE_SHOT := ["jump_up", "jump_down", "land", "wake_up", "pounce", "swat", "place_trap", "toss", "sit_up_scream",
	"sit_up", "yawn", "drink", "head_up", "meow", "bark", "squeak", "stand_up", "react_scared", "set_trap", "crouch_look"]

var ap: AnimationPlayer
var current := ""


func _init(model: Node) -> void:
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		a.loop_mode = Animation.LOOP_NONE if ONE_SHOT.has(n) else Animation.LOOP_LINEAR


func has(clip: String) -> bool:
	return ap != null and ap.has_animation(clip)


func play(clip: String, blend := 0.15, restart := false) -> void:
	if ap == null or not ap.has_animation(clip):
		return
	if clip == current and not restart:
		return
	current = clip
	ap.play(clip, blend)
	if restart:
		ap.seek(0.0, true)


func set_speed(s: float) -> void:
	if ap:
		ap.speed_scale = s
