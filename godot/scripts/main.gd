class_name Main
extends Node
## The menu and the night that is running. Also sets up the controls (keyboard, mouse and gamepad) and test hooks:
##   godot --path godot -- --night=kitchen --auto --shot=out.png --frames=120

static var I: Main
var game: Game
var backdrop: Game  # the kitchen behind the menu (see Game.backdrop)
var menu: Control
var _args := {}
var _frames := 0
var _tester: Tester


func _init() -> void:
	I = self
	_setup_input()


func _ready() -> void:
	Sfx.setup(self)
	TextureLib.boot(self)  # round 6: CDN texture pack + background painter (never blocks)
	if "--pad" in OS.get_cmdline_user_args():
		Keys.pad = true
	Settings.load_all()
	Keys.apply_saved()
	Progress.load_all()
	Achievements.load_all()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Dof.watch = not _args.has("shot")
	if _args.has("quality"):  # dev: --quality=low|medium|high for screenshots (not saved)
		Settings.quality = str(_args.quality)
	if _args.has("night"):
		if _args.has("via_menu"):  # dev: go through the menu (and its live backdrop) first, like a player does
			show_menu()
			await get_tree().create_timer(1.5).timeout
			await enter_night(_args.night)
		else:
			start_night(_args.night)
	else:
		show_menu()
		if _args.get("screen", "") == "nights": show_nights()
		elif _args.get("screen", "") == "settings": UI.settings_panel(self, show_menu)
		elif _args.get("screen", "") == "controls": UI.controls_panel(self, show_menu)


func _exit_tree() -> void:
	TextureLib.shutdown()


var _fps: Label
var _fps_t := 0.0

## Frames per second in the top right corner (Settings → Show FPS).
func _tick_fps(dt: float) -> void:
	if not Settings.show_fps:
		if _fps:
			_fps.visible = false
		return
	if _fps == null:
		var layer := CanvasLayer.new()
		layer.layer = 60
		add_child(layer)
		_fps = Label.new()
		_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_fps.offset_right = -6
		_fps.offset_top = 2
		_fps.add_theme_font_size_override("font_size", 14)
		_fps.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
		_fps.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_fps.add_theme_constant_override("outline_size", 4)
		layer.add_child(_fps)
	_fps.visible = true
	_fps_t -= dt
	if _fps_t <= 0.0:
		_fps_t = 0.5
		_fps.text = "%d FPS" % int(Engine.get_frames_per_second())


## Round 16, a safety net: if a night runs under 24 frames a second for six seconds, the graphics step down one
## level for the rest of the session (high → medium → low) and say so once. The saved setting is left alone.
var _slow := 0.0

func _tick_perf(dt: float) -> void:
	if game == null or game.state != "play" or _args.has("shot") or DisplayServer.get_name() == "headless" or Settings.quality == "low":
		_slow = 0.0
		return
	var fps := Engine.get_frames_per_second()
	_slow = _slow + dt if fps > 1.0 and fps < 24.0 else maxf(_slow - dt * 2.0, 0.0)
	if _slow < 6.0:
		return
	_slow = 0.0
	Settings.quality = "medium" if Settings.quality == "high" else "low"
	Settings.apply()
	game._apply_light_shadows()
	if Settings.quality == "low":
		for n in game.find_children("Paper", "CanvasLayer", true, false):
			n.queue_free()
		for n in game.find_children("Dust motes", "", true, false):
			n.queue_free()
	game.toast("Graphics lowered to %s to keep the game smooth" % Settings.quality)


func _process(_dt: float) -> void:
	if _args.has("perf") and _frames % 120 == 60 and game:  # dev: frame rate and what the frame costs
		print("PERF fps %d · draw calls %d · objects %d · primitives %dk" % [Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	_frames += 1
	_tick_fps(_dt)
	_tick_perf(get_process_delta_time() / maxf(Engine.time_scale, 0.01))
	if _args.has("auto") and game and game.state == "intro" and game.grid != null:
		game.begin()
		if _args.has("at"):
			var p := str(_args.at).split(",")
			game.rat.teleport(Nights.world(float(p[0]), float(p[1]), float(p[3]) if p.size() > 3 else 1.0), deg_to_rad(float(p[2])) if p.size() > 2 else PI)
			game.cam.snap(game.rat.rotation.y)
		if OS.has_environment("HIDE"):  # dev: HIDE="Moon shaft,Lamp" hides nodes by name, to find what draws something
			for pat in OS.get_environment("HIDE").split(","):
				for hn in game.find_children("*" + pat + "*", "Node3D", true, false):
					(hn as Node3D).visible = false
		if _args.has("carry"):  # dev: start with a cheese in her teeth
			var f := game.spawn_food(str(_args.carry) if str(_args.carry) != "" else "cheese", game.rat.global_position, "", false)
			game.rat.carry(f)
		if _args.has("fp"):
			game.cam.first_person = true
		if _args.has("hold"):  # dev: keep an action pressed (sniff…)
			Input.action_press(str(_args.hold))
		if _args.get("screen", "") == "pause": game._set_paused(true)
		elif _args.get("screen", "") == "won": game.state = "play"; game._end(true, "", "")
		elif _args.get("screen", "") == "lost": game._end(false, "You got caught", "The pups got 3 of 12 and are waiting for Mom.")
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
	if _args.has("visit") and game and game.grid != null and game.state == "play" and not has_meta("visited") and _frames > 20:
		set_meta("visited", true)  # dev: the owner walks in now (for a portrait of him)
		if game.owner_ai and not game.owner_ai.in_room():
			game.owner_ai._start_visit()
			game.owner_ai._t = 0.05
	if _args.has("focus") and game and game.grid != null and game.state != "intro":
		_focus()
	if _args.has("shot") and _frames == int(_args.get("frames", "90")):
		get_viewport().get_texture().get_image().save_png(_args.shot)
		print("saved ", _args.shot)
		if not _args.has("keep"):
			get_tree().quit()


func _input(e: InputEvent) -> void:
	if not _args.has("pad"):
		Keys.seen(e)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("menu") and game and game.state in ["pause", "won", "lost"]:
		show_menu()
	elif e.is_action_pressed("pause") and menu and game == null and not menu.has_meta("main"):
		show_menu()


## From the menu into a night: the menu and its kitchen dip to black first (the night then fades in from
## black by itself), instead of the picture jumping while the room is built.
func enter_night(id: String) -> void:
	if not is_instance_valid(backdrop) or has_node("Dip"):
		if not has_node("Dip"):
			start_night(id)
		return
	Sfx.play("click")
	var layer := CanvasLayer.new()
	layer.name = "Dip"
	layer.layer = 50
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP  # no second click while it fades
	layer.add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.3)
	await tw.finished
	start_night(id)
	await get_tree().process_frame
	await get_tree().process_frame
	layer.queue_free()


func start_night(id: String) -> void:
	Sfx.play("click")
	_clear()
	if backdrop:
		backdrop.queue_free()
		backdrop = null
	game = Game.new(id)
	game.name = "Game"
	add_child(game)


const ACTS := ["Act 1 · Silence", "Act 2 · The Owner", "Act 3 · Traps", "Act 4 · Siege"]


func show_menu() -> void:
	_clear()
	Sfx.music_menu()
	Sfx.music_duck(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_make_backdrop()
	# the menu sits on the left over a soft shadow; the right of the screen is hers
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	menu = root
	menu.set_meta("main", true)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.03, 0.08, 0.62))
	grad.set_color(1, Color(0.03, 0.03, 0.08, 0.0))
	grad.add_point(0.55, Color(0.03, 0.03, 0.08, 0.32))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	# round 16 (asked: "make the menu beautiful — it looks worse now"), after the user's own mock-up: a big bold
	# gold title, two lines in cream, wide rounded buttons; Play stands out in gold
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	box.offset_left = 88
	box.offset_right = 88 + 420
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var title := UI.label("Kitchen Rat", 70, Color(0.99, 0.77, 0.32))
	title.add_theme_font_override("font", UI.font(700))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.03, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	box.add_child(title)
	var tag := UI.label("Demo · Act 1, nights 1–5" if Nights.demo() else "A mother rat. Twenty nights.\nOne hungry family.", 22, Color(0.97, 0.94, 0.86))
	tag.add_theme_constant_override("line_spacing", 4)
	tag.add_theme_constant_override("shadow_offset_y", 2)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	box.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	box.add_child(gap)
	var files := Nights.files()
	var next := clampi(Progress.unlocked, 1, Nights.last_playable())
	var play_text := "Play"
	if Progress.unlocked > Nights.last_playable():
		play_text = "Play again · Night 1"
		next = 1
	elif Progress.unlocked > 1:
		play_text = "Continue · Night %d" % next
	box.add_child(UI.button(play_text, start_number.bind(next)))
	box.add_child(UI.button("Nights", show_nights))
	box.add_child(UI.button("Achievements", show_achievements))
	box.add_child(UI.button("Settings", func(): menu.hide(); UI.settings_panel(self, func(): if is_instance_valid(menu): menu.show())))
	box.add_child(UI.button("Quit", get_tree().quit))
	var first := true
	for b in box.find_children("*", "Button", false, false):
		var bt := b as Button
		bt.size_flags_horizontal = Control.SIZE_FILL
		bt.custom_minimum_size = Vector2(420, 58)
		bt.add_theme_font_size_override("font_size", 24)
		var nb := UI._box(Color(0.13, 0.12, 0.15, 0.84), Color(0.32, 0.29, 0.33, 0.7))
		nb.set_corner_radius_all(14)
		var hb := UI._box(Color(0.24, 0.19, 0.14, 0.92), Color(0.99, 0.77, 0.32))
		hb.set_corner_radius_all(14)
		if first:  # Play: gold rim and a warm fill even before it is hovered
			nb = UI._box(Color(0.25, 0.2, 0.14, 0.9), Color(0.96, 0.74, 0.3))
			nb.set_corner_radius_all(14)
			first = false
		bt.add_theme_stylebox_override("normal", nb)
		bt.add_theme_stylebox_override("hover", hb)
		bt.add_theme_stylebox_override("focus", hb)
		bt.add_theme_stylebox_override("pressed", hb)
	UI.focus_first(box)


## The kitchen behind the menu: built once, kept while the player browses nights and settings,
## dropped when a night starts.
func _make_backdrop() -> void:
	if is_instance_valid(backdrop) or _args.has("no_backdrop"):
		return
	backdrop = Game.new("kitchen")
	backdrop.backdrop = true
	backdrop.name = "Backdrop"
	add_child(backdrop)
	move_child(backdrop, 0)


## Night number (1…20) → start it.
func start_number(n: int) -> void:
	var files := Nights.files()
	if n < 1 or n > Nights.last_playable():
		show_menu()
		return
	var f: String = files[n - 1]
	enter_night(f.substr(f.find("_") + 1))


func show_achievements() -> void:
	_clear()
	var s := UI.screen(self, 0.0, true, 640.0)
	menu = s[0]
	var box: VBoxContainer = s[1]
	box.add_child(UI.label("Achievements  %d / %d" % [Achievements.unlocked.size(), Achievements.LIST.size()], 30, UI.ACCENT, true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 470)
	box.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for a in Achievements.LIST:
		var got := Achievements.unlocked.has(a[0])
		list.add_child(UI.label(("★  " if got else "☆  ") + str(a[1]), 18, UI.ACCENT if got else UI.TEXT))
		list.add_child(UI.label("     " + str(a[2]), 14, UI.DIM))
	box.add_child(UI.button("Back", show_menu, 220))
	UI.focus_first(box)


func show_nights() -> void:
	_clear()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	add_child(root)
	menu = root
	var bg := ColorRect.new()
	bg.color = UI.veil()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 40
	outer.offset_right = -40
	outer.offset_top = 24
	outer.offset_bottom = -24
	outer.add_theme_constant_override("separation", 10)
	root.add_child(outer)
	outer.add_child(UI.label("Choose a night", 34, UI.ACCENT, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var grid: GridContainer
	var files := Nights.files()
	for i in files.size():
		if i % 5 == 0:
			list.add_child(UI.label(ACTS[i / 5], 22, UI.ACCENT))
			grid = GridContainer.new()
			grid.columns = 5
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			list.add_child(grid)
		var id: String = files[i].substr(files[i].find("_") + 1)
		var d := Nights.load_night(id)
		var open := Progress.is_open(i + 1) and i + 1 <= Nights.last_playable()
		var b := Button.new()
		b.custom_minimum_size = Vector2(228, 118)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var best: Dictionary = Progress.best.get(id, {})
		var txt := "Night %d\n%s\n" % [i + 1, str(d.get("name", id))]
		if i + 1 > Nights.last_playable():
			txt += "In the full game"
		elif not open:
			txt += "🔒 Finish night %d to unlock" % i
		elif not best.is_empty():
			txt += "✓ Tasks %d / %d · %s" % [int(best.get("goals", 0)), int(best.get("of", 0)), str(best.get("clock", ""))]
		else:
			txt += "Bring %d food" % int(d.get("goal", 10))
		b.text = txt
		b.disabled = not open
		b.tooltip_text = str(d.get("blurb", ""))
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): enter_night(id))
		grid.add_child(b)
	outer.add_child(UI.button("Back", show_menu, 220))
	UI.focus_first(list)


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
	_key("drop", [KEY_G], -1, [JOY_BUTTON_B])
	_key("view", [KEY_V], -1, [JOY_BUTTON_RIGHT_STICK])
	_key("look_left", [], -1, [], JOY_AXIS_RIGHT_X, -1.0)
	_key("look_right", [], -1, [], JOY_AXIS_RIGHT_X, 1.0)
	_key("look_up", [], -1, [], JOY_AXIS_RIGHT_Y, -1.0)
	_key("look_down", [], -1, [], JOY_AXIS_RIGHT_Y, 1.0)


## --focus=cat|owner|dog|rat|pup|sleeper[,anim]: a close-up camera that follows one character (screenshots of the models);
## with an anim name that character plays only that clip.
func _focus() -> void:
	var f := str(_args.focus).split(",")
	var t: Node3D = {"cat": game.cat, "owner": game.owner_ai, "dog": game.dog, "rat": game.rat,
		"pup": game.pups[0] if not game.pups.is_empty() else null,
		"sleeper": game.sleepers[0] if not game.sleepers.is_empty() else null}.get(f[0])
	if t == null:
		return
	var d: float = {"cat": 1.1, "owner": 2.8, "dog": 1.5, "rat": 0.55, "pup": 0.4, "sleeper": 2.2}[f[0]]
	var c := get_meta("focus_cam") as Camera3D if has_meta("focus_cam") else null
	if c == null:
		c = Camera3D.new()
		game.add_child(c)
		c.fov = 50.0
		c.current = true
		set_meta("focus_cam", c)
	if f.size() > 1 and f[1] != "":
		t.process_mode = Node.PROCESS_MODE_DISABLED
		var ap := t.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.current_animation != f[1]:
			ap.process_mode = Node.PROCESS_MODE_ALWAYS
			ap.play(f[1])
	var fwd := t.global_transform.basis.z
	var side := t.global_transform.basis.x
	if f.size() > 2 and f[2] == "wide":  # from a fixed spot up in the room, turning to follow (to see how they walk)
		var at := Vector3(clampf(t.global_position.x, -2.5, 2.5) * 0.5, 2.35, 2.75)
		c.global_position = c.global_position.lerp(at, 0.05) if c.global_position.y > 1.0 else at
		c.look_at(t.global_position + Vector3.UP * d * 0.15)
		return
	var low := f.size() > 2 and f[2] == "low"  # at floor level, from the side
	var to := t.global_position + (side if low else (fwd * 0.8 + side * 0.6).normalized()) * d + Vector3.UP * (0.03 if low else d * 0.45)
	c.global_position = to
	c.look_at(t.global_position + Vector3.UP * (0.03 if low else d * 0.18))

