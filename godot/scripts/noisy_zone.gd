class_name NoisyZone
extends Zone
## Things that make noise under the paws (the prototype's NOISY table): foil, floorboards, bags, puddles, glasses,
## balloons… mode: walk (any non-sneaking step), step (any step, even sneaking), run (only running),
## land (landing on it after a jump), landrun (landing or running). Foil also sets a flag when crossed sneaking.

## The prototype's NOISY[kind].snd.
const SOUNDS := {
	"foil": "crinkle", "plate": "clink", "sofa": "scratch", "remote": "tv", "squeaky": "squeaky", "board": "creak",
	"bag": "crinkle", "grain": "crunch", "puddle": "splash", "cord": "buzz", "washer": "buzz", "hanger": "clink",
	"balloon": "bang", "confetti": "crinkle", "glasses": "clink", "litter": "crunch", "dock": "beep", "pipe": "bang",
	"lego": "crunch", "musicbox": "musicbox", "nightlight": "light_switch", "bottles": "clink", "popper": "bang",
}

var kind := "foil"
var mode := "walk"
var sound := "Crinkle!"
var radius := 1.5
var amount := 0.4
var big := false
var cooldown := 0.45
var once := false
var hide_when_used: Node3D
var sneak_flag := ""
var pass_distance := 0.4
var used := false
var _cd := 0.0
var _sneaked := 0.0
var _hint := 0.0
var _loud := false


func _on_it(rat: Rat) -> bool:
	return not rat.jumping and absf(rat.global_position.y - global_position.y) < 0.06


func enter(_rat: Rat) -> void:
	_sneaked = 0.0
	_loud = false


func stay(rat: Rat, dt: float) -> void:
	_cd -= dt
	_hint -= dt
	if not _on_it(rat) or not rat.moving():
		return
	var trig := mode == "step" or (rat.running if (mode == "run" or mode == "landrun") else (mode == "walk" and not rat.sneaking))
	if not trig:
		if rat.sneaking:
			_sneaked += rat.move_speed * dt
		return
	_loud = true
	_trigger(rat)


func on_landed(rat: Rat) -> void:
	if (mode == "land" or mode == "landrun") and _on_it(rat):
		_trigger(rat)


func _trigger(rat: Rat) -> void:
	if _cd > 0.0 or (once and used):
		return
	_cd = cooldown
	used = true
	Game.I.noise(rat.global_position, radius, sound, big, amount)
	Sfx.play(SOUNDS.get(kind, "crinkle"), rat.global_position + Vector3.UP * 0.05)
	Game.I.noisy_effect(kind, self)
	if hide_when_used:
		hide_when_used.visible = false
	if sneak_flag != "" and _hint <= 0.0 and Game.I.tasks.flag_value(sneak_flag) == 0:
		_hint = 6.0
		Game.I.toast(Keys.text("Too loud! Hold Ctrl (or press C) and sneak across."))


func exit(_rat: Rat) -> void:
	if not _loud and _sneaked >= pass_distance and sneak_flag != "":
		Game.I.tasks.set_flag(sneak_flag)


func configure(k: String) -> void:
	kind = k
	match k:
		"foil": _cfg("walk", "Crinkle!", 1.5, 0.4, 0.45); sneak_flag = "foilSneak"
		"plate": _cfg("landrun", "Clink!", 2.3, 0.6, 1.2)
		"sofa": _cfg("land", "Scritch!", 1.9, 0.45, 1.0)
		"remote": _cfg("step", "The TV turned on!", 6.5, 1.0, 1.0, true, true)
		"squeaky": _cfg("step", "Squeak!", 2.5, 0.7, 2.5)
		"board": _cfg("walk", "Creak…", 1.8, 0.35, 0.9)
		"bag": _cfg("walk", "Rustle!", 1.6, 0.35, 0.45)
		"grain": _cfg("walk", "Crunch", 1.4, 0.3, 0.5)
		"puddle": _cfg("walk", "Splash!", 1.6, 0.35, 0.6)
		"cord": _cfg("step", "Bzzt!", 2.1, 0.5, 3.0)
		"washer": _cfg("step", "The washing machine started!", 3.2, 0.3, 1.0, false, true)
		"hanger": _cfg("walk", "Clink clink", 1.8, 0.35, 0.8)
		"balloon": _cfg("step", "POP!", 4.2, 0.8, 1.0, true, true)
		"confetti": _cfg("walk", "Rustle", 1.4, 0.3, 0.5)
		"glasses": _cfg("walk", "Clink!", 2.2, 0.5, 0.9)
		"litter": _cfg("walk", "Scratch scratch", 1.2, 0.2, 0.8)
		"dock": _cfg("step", "Beep! Charging…", 2.6, 0.4, 3.0)
		"pipe": _cfg("run", "Bwonng!", 3.6, 0.5, 1.0)
		"lego": _cfg("walk", "Ouch! Lego!", 1.9, 0.45, 0.8)
		"musicbox": _cfg("step", "♪ Twinkle twinkle… ♪", 3.0, 0.6, 5.0)
		"nightlight": _cfg("walk", "Click! The night light is on", 1.6, 0.25, 6.0)
		"bottles": _cfg("walk", "Clatter!", 2.4, 0.5, 0.8)
		"popper": _cfg("step", "BANG! A party popper!", 4.5, 0.85, 1.0, true, true)


func _cfg(m: String, s: String, r: float, a: float, c: float, b := false, o := false) -> void:
	mode = m; sound = s; radius = r; amount = a; cooldown = c; big = b; once = o
