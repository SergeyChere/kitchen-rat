class_name Keys
## Controls: names for the prompts (the keyboard key, or the gamepad button when the player last used a gamepad),
## rebinding (saved in Settings), and rewriting the key names in the nights' texts ("Hold E" → "Hold Y").

## Actions the player can rebind, with names for the settings panel.
const ACTIONS := [
	["forward", "Move forward"], ["back", "Move back"], ["left", "Move left"], ["right", "Move right"],
	["run", "Run"], ["sneak", "Sneak (hold)"], ["sneak_toggle", "Sneak (toggle)"], ["jump", "Jump"],
	["sniff", "Sniff"], ["push", "Push / gnaw"], ["pups", "Pups: wait / follow"], ["fetch", "Pup: fetch food"],
	["drop", "Drop food"], ["view", "Rat's-eye view"], ["pause", "Pause"],
]
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓", JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
}
const DEFAULT_KEYS := {
	"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "run": KEY_SHIFT, "sneak": KEY_CTRL,
	"sneak_toggle": KEY_C, "jump": KEY_SPACE, "sniff": KEY_E, "push": KEY_F, "pups": KEY_Q, "fetch": KEY_R,
	"drop": KEY_G, "view": KEY_V, "pause": KEY_ESCAPE,
}

static var pad := false  # the last input came from a gamepad


## Note which device the player is using (Main calls this for every input event).
static func seen(e: InputEvent) -> void:
	if e is InputEventJoypadButton and e.pressed:
		pad = true
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.5:
		pad = true
	elif (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed):
		pad = false


static func _key_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		var n := OS.get_keycode_string(k)
		return {"Control": "Ctrl", "Escape": "Esc"}.get(n, n)
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse"}.get(e.button_index, "Mouse %d" % e.button_index)
	return ""


static func _pad_name(e: InputEvent) -> String:
	if e is InputEventJoypadButton:
		return PAD_NAMES.get(e.button_index, "Button %d" % e.button_index)
	if e is InputEventJoypadMotion:
		match e.axis:
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "Left stick"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "Right stick"
	return ""


## The key (or gamepad button) for an action, for prompts.
static func label(action: String, for_pad := pad) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		var n := _pad_name(e) if for_pad else _key_name(e)
		if n != "":
			return n
	if for_pad:
		return label(action, false)
	return "?"


## The gamepad button for an action, or a dash when it has none.
static func pad_label(action: String) -> String:
	for e in InputMap.action_get_events(action):
		var n := _pad_name(e)
		if n != "":
			return n
	return "—"


static func keyboard_label(action: String) -> String:
	return label(action, false)


## Rewrite the key names written into the nights' texts for the current keys and device.
static func text(s: String) -> String:
	if s == "":
		return s
	var map := {"E": "sniff", "F": "push", "Q": "pups", "R": "fetch", "C": "sneak_toggle", "Ctrl": "sneak", "Space": "jump"}
	var re := RegEx.new()
	re.compile("(?<=\\b(?:Hold|hold|press|Press|with|With) )(Ctrl|Space|[EFQRC])\\b|\\((Ctrl|[EFQR])\\)")
	var out := ""
	var last := 0
	for m in re.search_all(s):
		var k := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
		var name := label(map[k])
		out += s.substr(last, m.get_start() - last)
		out += ("(" + name + ")") if m.get_string(0).begins_with("(") else name
		last = m.get_end()
	out += s.substr(last)
	if pad:
		out = out.replace(" (or press " + label("sneak_toggle") + ")", "").replace(" or press " + label("sneak_toggle"), "")
		out = out.replace("Move with WASD, look around with the mouse", "Move with the left stick, look around with the right stick")
		out = out.replace(" or the right mouse button", "").replace(" or right mouse", "")
	else:
		out = out.replace("WASD", label("forward") + label("left") + label("back") + label("right"))
	return out


# ---------- rebinding ----------

## Bind an action's keyboard/mouse input to e (its gamepad buttons stay).
static func rebind(action: String, e: InputEvent) -> void:
	for old in InputMap.action_get_events(action):
		if old is InputEventKey or old is InputEventMouseButton:
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, e)
	if e is InputEventKey:
		Settings.keys[action] = ["key", e.physical_keycode if e.physical_keycode != 0 else e.keycode]
	elif e is InputEventMouseButton:
		Settings.keys[action] = ["mouse", e.button_index]
	Settings.save()


## Put the saved bindings into the input map (after Main has set up the defaults).
static func apply_saved() -> void:
	for action in Settings.keys:
		var v: Array = Settings.keys[action]
		if not InputMap.has_action(action) or v.size() < 2:
			continue
		var e: InputEvent
		if v[0] == "key":
			e = InputEventKey.new()
			e.physical_keycode = int(v[1])
		else:
			e = InputEventMouseButton.new()
			e.button_index = int(v[1])
		for old in InputMap.action_get_events(action):
			if old is InputEventKey or old is InputEventMouseButton:
				InputMap.action_erase_event(action, old)
		InputMap.action_add_event(action, e)
		if action == "sniff" and v[0] == "key":
			var rm := InputEventMouseButton.new()
			rm.button_index = MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, rm)


static func reset() -> void:
	Settings.keys = {}
	Settings.save()
	for a in DEFAULT_KEYS:
		var e := InputEventKey.new()
		e.physical_keycode = DEFAULT_KEYS[a]
		for old in InputMap.action_get_events(a):
			if old is InputEventKey or old is InputEventMouseButton:
				InputMap.action_erase_event(a, old)
		InputMap.action_add_event(a, e)
	var rm := InputEventMouseButton.new()
	rm.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("sniff", rm)


## Waits for the next key or mouse button, then calls done(event) (Esc cancels with null).
class Catcher extends Node:
	var done: Callable

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(e: InputEvent) -> void:
		var got: InputEvent = null
		if e is InputEventKey and e.pressed and not e.echo:
			got = e if e.physical_keycode != KEY_ESCAPE else null
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			got = e
		else:
			return
		get_viewport().set_input_as_handled()
		var cb := done
		queue_free()
		cb.call(got)
