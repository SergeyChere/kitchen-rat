class_name TaskTracker
extends RefCounted
## The night's tasks: the main list (all shown; each step counts the moment it's done, in any order, and the first
## one not done yet is the current one with its hint), side tasks revealed after N main steps ("keep" ones fail when
## broken), secrets shown once found.
## The game records what happened (picked tags, deliveries, knocks, flags); the tracker polls it every frame.

signal completed(text: String)
signal failed(text: String)
signal revealed(text: String)  # a NEW side task opened — the HUD announces it (round 5)

## Round 5: side tasks used to appear by an invisible "reveal after N steps" rule, in random
## counts, silently. Now exactly TWO are open at any time; when one finishes or fails the next
## opens at once and is announced. If a night ships too few, this pool tops it up.
const POOL := [
	{"text": "Sneak past the cat", "type": "flag", "arg": "passCat"},
	{"text": "Hide while the cat watches", "type": "flag", "arg": "hidNearCat"},
	{"text": "Slip through a wall path", "type": "count", "arg": "tunnel", "n": 1},
	{"text": "Sniff out hidden food", "type": "flag", "arg": "sniffed"},
	{"text": "Collect 5 pieces of food", "type": "count", "arg": "collected", "n": 5},
	{"text": "Disarm a mousetrap", "type": "flag", "arg": "disarm"},
]
var _open := {}  # side index → true: revealed and available

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
	side = tasks.get("side", []).duplicate()
	var texts := {}
	for t in side:
		texts[str(t.get("text", ""))] = true
	for t in POOL:
		if side.size() >= 6:
			break
		if not texts.has(str(t.text)):
			side.append(t)
	_open_more(false)
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
	return _open.has(i) or side_done.has(i) or side_failed.has(i)


## Keep exactly two side tasks open; announce ones opened after the night started.
func _open_more(announce := true) -> void:
	var active := 0
	for i in side.size():
		if _open.has(i) and not side_done.has(i) and not side_failed.has(i):
			active += 1
	for i in side.size():
		if active >= 2:
			break
		if not _open.has(i):
			_open[i] = true
			active += 1
			if announce:
				revealed.emit(str(side[i].text))


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
	_open_more()


func finish_night() -> void:
	for i in side.size():
		if side[i].type == "keep" and not side_failed.has(i):
			side_done[i] = true
