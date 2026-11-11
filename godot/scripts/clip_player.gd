class_name ClipPlayer
extends RefCounted
## Plays a model's animation clips by name ("walk", "run", "sleep"…) with cross-fades.

const ONE_SHOT := ["jump_up", "jump_down", "land", "wake_up", "pounce", "swat", "place_trap", "toss", "sit_up_scream",
	"sit_up", "yawn", "drink", "head_up", "meow", "bark", "squeak", "stand_up", "react_scared", "set_trap", "crouch_look"]

var ap: AnimationPlayer
var current := ""
var aliases: Dictionary = {}  # round 14b: game clip name -> the replacement model's own names


func _init(model: Node) -> void:
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		a.loop_mode = Animation.LOOP_NONE if ONE_SHOT.has(n) else Animation.LOOP_LINEAR


## Round 14b: a replacement model (the new cat) names its clips its own way.
## set_aliases() maps the game's names to candidates; resolution is exact
## match first, then the alias list, then a head-word substring match. A clip
## that resolves to nothing simply does not play — the game never breaks.
func set_aliases(map: Dictionary) -> void:
	aliases = map
	if ap == null:
		return
	for game_name in aliases:
		var real := _resolve(str(game_name))
		if real != "" and ap.has_animation(real):
			ap.get_animation(real).loop_mode = Animation.LOOP_NONE if ONE_SHOT.has(str(game_name)) else Animation.LOOP_LINEAR


func _resolve(clip: String) -> String:
	if ap == null:
		return ""
	if ap.has_animation(clip):
		return clip
	for cand in aliases.get(clip, []):
		if ap.has_animation(str(cand)):
			return str(cand)
	var head := clip.split("_")[0].to_lower()
	if head.length() >= 3:
		for n in ap.get_animation_list():
			if n.to_lower().contains(head):
				return n
	return ""


func has(clip: String) -> bool:
	return _resolve(clip) != ""


func play(clip: String, blend := 0.15, restart := false) -> void:
	var real := _resolve(clip)
	if real == "":
		return
	if clip == current and not restart:
		return
	current = clip
	ap.play(real, blend)
	if restart:
		ap.seek(0.0, true)


func set_speed(s: float) -> void:
	if ap:
		ap.speed_scale = s
