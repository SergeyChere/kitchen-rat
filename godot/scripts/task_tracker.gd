class_name TaskTracker
extends RefCounted
## The night's tasks: the main list (all shown; each step counts the moment it's done, in any order, and the first
## one not done yet is the current one with its hint), side tasks revealed after N main steps ("keep" ones fail when
## broken), secrets shown once found.
## The game records what happened (picked tags, deliveries, knocks, flags); the tracker polls it every frame.

signal completed(text: String)
signal failed(text: String)

var chain: Array = []
var side: Array = []
var secret: Array = []
var goal_text := "Fill the nest"
var step := 0  # how many main steps are done
var chain_done_at := {}  # index → true
var picked := {}
var delivered := {}
var knocked := {}
var delivered_any := false
var flags := {}
var side_done := {}
var side_failed := {}
var secret_done := {}
## Live checks the game answers.
var on_surface: Callable = func(_a): return false
var hidden_in: Callable = func(_a): return false
var keep_broken: Callable = func(_a): return false


func _init(tasks: Dictionary) -> void:
	chain = tasks.get("chain", [])
	side = tasks.get("side", [])
	secret = tasks.get("secret", [])
	goal_text = tasks.get("goal", "Fill the nest")


func has_tasks() -> bool: return not chain.is_empty()
func chain_done() -> bool: return step >= chain.size()
func step_done(i: int) -> bool: return chain_done_at.has(i)
func current_index() -> int:
	for i in chain.size():
		if not chain_done_at.has(i):
			return i
	return -1
func current(): return chain[current_index()] if current_index() >= 0 else null
func side_visible(i: int) -> bool:
	var r := int(side[i].get("reveal", -1))
	return r < 0 or step >= r or side_done.has(i)


func flag(n: String, add := 1) -> void:
	flags[n] = int(flags.get(n, 0)) + add


func set_flag(n: String) -> void:
	if not flags.has(n):
		flags[n] = 1


func flag_value(n: String) -> int:
	return int(flags.get(n, 0))


func _check(t: Dictionary) -> bool:
	var arg: String = str(t.get("arg", ""))
	match str(t.get("type", "")):
		"pick": return picked.has(arg)
		"deliver": return delivered_any if arg == "" else delivered.has(arg)
		"surf": return on_surface.call(arg)
		"hide": return hidden_in.call(arg)
		"knock": return knocked.has(arg)
		"flag": return flag_value(arg) > 0
		"count": return flag_value(arg) >= int(t.get("n", 0))
		"pickN":
			var k := 0
			for p in picked.keys():
				if str(p).begins_with(arg):
					k += 1
			return k >= int(t.get("n", 0))
	return false


func tick() -> void:
	for i in chain.size():
		if not chain_done_at.has(i) and _check(chain[i]):
			chain_done_at[i] = true
			step += 1
			completed.emit(str(chain[i].text))
	for i in side.size():
		var t: Dictionary = side[i]
		if side_done.has(i) or side_failed.has(i) or not side_visible(i):
			continue
		if t.type == "keep":
			if keep_broken.call(str(t.arg)):
				side_failed[i] = true
				failed.emit(str(t.text))
		elif _check(t):
			side_done[i] = true
			completed.emit(str(t.text))
	for i in secret.size():
		if not secret_done.has(i) and _check(secret[i]):
			secret_done[i] = true
			completed.emit("Secret: " + str(secret[i].text))


func finish_night() -> void:
	for i in side.size():
		if side[i].type == "keep" and not side_failed.has(i):
			side_done[i] = true
