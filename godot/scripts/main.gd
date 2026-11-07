class_name Main
extends Node
## The menu and the night that is running. Also sets up the controls (keyboard, mouse and gamepad) and test hooks:
##   godot --path godot -- --night=kitchen --auto --shot=out.png --frames=120

static var I: Main
var game: Game
var menu: Control
var _args := {}
var _frames := 0
var _tester: Tester


func _init() -> void:
	I = self
	_setup_input()


func _ready() -> void:
	Sfx.setup(self)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("night"):
		start_night(_args.night)
	else:
		show_menu()


func _process(_dt: float) -> void:
	_frames += 1
	if _args.has("auto") and game and game.state == "intro" and game.grid != null:
		game.begin()
		if _args.has("test"):
			_tester = Tester.new(game, _args.test)
			_tester.start(self)
	if _args.has("cam") and game and game.grid != null and not has_meta("cam_done"):
		set_meta("cam_done", true)
		var v := str(_args.cam).split(",")  # x,y,h,lookx,looky,lookh in room cm
		var c := Camera3D.new()
		game.add_child(c)
		c.global_position = Nights.world(float(v[0]), float(v[1]), float(v[2]))
		c.look_at(Nights.world(float(v[3]), float(v[4]), float(v[5])))
		c.fov = 70.0
		c.current = true
	if _args.has("shot") and _frames == int(_args.get("frames", "90")):
		get_viewport().get_texture().get_image().save_png(_args.shot)
		print("saved ", _args.shot)
		if not _args.has("keep"):
			get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("menu") and game and game.state in ["pause", "won", "lost"]:
		show_menu()


func start_night(id: String) -> void:
	Sfx.play("click")
	_clear()
	game = Game.new(id)
	game.name = "Game"
	add_child(game)


func show_menu() -> void:
	_clear()
	Sfx.music_menu()
	Sfx.music_duck(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.07, 0.125)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(760, 0)
	box.position = Vector2(-380, -300)
	box.add_theme_constant_override("separation", 14)
	menu.add_child(box)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.png")
	logo.custom_minimum_size = Vector2(120, 120)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(logo)
	var title := Label.new()
	title.text = "Kitchen Rat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Twenty nights. One hungry family. Choose a night:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for f in Nights.files():
		var num := int(f.get_slice("_", 0))
		var id := f.substr(f.find("_") + 1)
		var d := Nights.load_night(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(184, 44)
		b.text = "%d · %s" % [num, str(d.get("name", id))]
		b.clip_text = true
		if Nights.BUILT.has(id):
			b.pressed.connect(start_night.bind(id))
		else:
			b.disabled = true
			b.tooltip_text = "This room is not built in Godot yet"
		grid.add_child(b)
	var vol := HBoxContainer.new()
	vol.alignment = BoxContainer.ALIGNMENT_CENTER
	vol.add_theme_constant_override("separation", 12)
	box.add_child(vol)
	for which in ["Music", "Sound"]:
		var l := Label.new()
		l.text = which
		vol.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(200, 24)
		sl.value = Sfx.music_volume if which == "Music" else Sfx.sfx_volume
		sl.value_changed.connect(_on_volume.bind(which))
		vol.add_child(sl)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(160, 40)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)


func _on_volume(v: float, which: String) -> void:
	if which == "Music":
		Sfx.set_volumes(v, Sfx.sfx_volume)
	else:
		Sfx.set_volumes(Sfx.music_volume, v)
		Sfx.play("squeak")


func _clear() -> void:
	if game:
		game.queue_free()
		game = null
	if menu:
		menu.queue_free()
		menu = null


static func _key(action: String, keys: Array, mouse := -1, joy_buttons: Array = [], joy_axis := -1, axis_dir := 0.0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse >= 0:
		var m := InputEventMouseButton.new()
		m.button_index = mouse
		InputMap.action_add_event(action, m)
	for b in joy_buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	if joy_axis >= 0:
		var a := InputEventJoypadMotion.new()
		a.axis = joy_axis
		a.axis_value = axis_dir
		InputMap.action_add_event(action, a)


static func _setup_input() -> void:
	_key("forward", [KEY_W, KEY_UP], -1, [], JOY_AXIS_LEFT_Y, -1.0)
	_key("back", [KEY_S, KEY_DOWN], -1, [], JOY_AXIS_LEFT_Y, 1.0)
	_key("left", [KEY_A, KEY_LEFT], -1, [], JOY_AXIS_LEFT_X, -1.0)
	_key("right", [KEY_D, KEY_RIGHT], -1, [], JOY_AXIS_LEFT_X, 1.0)
	_key("run", [KEY_SHIFT], -1, [JOY_BUTTON_LEFT_STICK], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key("sneak", [KEY_CTRL], -1, [JOY_BUTTON_LEFT_SHOULDER])
	_key("sneak_toggle", [KEY_C])
	_key("jump", [KEY_SPACE], -1, [JOY_BUTTON_A])
	_key("sniff", [KEY_E], MOUSE_BUTTON_RIGHT, [JOY_BUTTON_Y])
	_key("push", [KEY_F], -1, [JOY_BUTTON_X])
	_key("pause", [KEY_ESCAPE], -1, [JOY_BUTTON_START])
	_key("restart", [KEY_R])
	_key("menu", [KEY_M], -1, [JOY_BUTTON_BACK])
	_key("pups", [KEY_Q], -1, [JOY_BUTTON_RIGHT_SHOULDER])
	_key("fetch", [KEY_R], -1, [JOY_BUTTON_DPAD_UP])
	_key("look_left", [], -1, [], JOY_AXIS_RIGHT_X, -1.0)
	_key("look_right", [], -1, [], JOY_AXIS_RIGHT_X, 1.0)
	_key("look_up", [], -1, [], JOY_AXIS_RIGHT_Y, -1.0)
	_key("look_down", [], -1, [], JOY_AXIS_RIGHT_Y, 1.0)
