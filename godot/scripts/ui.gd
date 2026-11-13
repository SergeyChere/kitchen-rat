class_name UI
## Shared look for the menus (main menu, pause, results): a warm, dark theme drawn in code, and the settings panel
## the main menu and the pause menu both open.

const BG := Color(0.055, 0.07, 0.125)
const PANEL := Color(0.08, 0.09, 0.15, 0.94)
const ACCENT := Color(0.95, 0.72, 0.35)
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.72, 0.72, 0.78)
const GOOD := Color(0.6, 0.88, 0.48)
const BAD := Color(0.91, 0.4, 0.29)

static var _theme: Theme


## The game's typeface (round 14): Lora, a brush-cut serif (SIL Open Font License, assets/fonts/Lora-OFL.txt).
## `weight` 400 … 700; glyphs it lacks (the hearts in the HUD) come from the engine's own font.
static var _fonts := {}

static func font(weight := 500) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f: Font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/Lora.ttf"):
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Lora.ttf")
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		fv.fallbacks = [ThemeDB.fallback_font]
		f = fv
	_fonts[weight] = f
	return f


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	var normal := _box(Color(0.16, 0.15, 0.2), Color(0.3, 0.27, 0.32))
	var hover := _box(Color(0.26, 0.21, 0.18), ACCENT)
	var pressed := _box(Color(0.36, 0.26, 0.16), ACCENT)
	var disabled := _box(Color(0.1, 0.1, 0.13), Color(0.18, 0.18, 0.22))
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, hover)
		t.set_stylebox("disabled", cls, disabled)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.45, 0.5))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(26)
	panel.border_color = Color(0.25, 0.22, 0.28)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT
	grab.set_corner_radius_all(6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.22, 0.28)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	_theme = t
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func label(text: String, size := 18, col := TEXT, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if size >= 26:
		l.add_theme_font_override("font", font(700))  # headings: the bold cut
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, cb: Callable, width := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): Sfx.play("click"); cb.call())
	return b


## What a "solid" menu screen is painted with: the flat background, or — when the kitchen
## is alive behind the menu — a dark veil the room still shows through.
static func veil() -> Color:
	if Main.I and is_instance_valid(Main.I.backdrop):
		return Color(BG.r, BG.g, BG.b, 0.8)
	return BG


## A centred panel on a dimmed (or solid) full-screen background. Returns [root, vbox].
static func screen(parent: Node, dim := 0.6, solid := false, width := 560.0) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var bg := ColorRect.new()
	bg.color = (veil() if solid else Color(0, 0, 0.02, dim))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	center.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	pc.add_child(box)
	return [root, box]


static func focus_first(box: Node) -> void:
	for c in box.find_children("*", "Button", true, false):
		if not (c as Button).disabled and (c as Button).visible:
			(c as Button).call_deferred("grab_focus")
			return


# ---------- settings ----------

## The settings panel; on_back is called after saving.
static func settings_panel(parent: Node, on_back: Callable) -> Control:
	var s := screen(parent, 0.75, false, 640.0)
	var root: Control = s[0]
	var box: VBoxContainer = s[1]
	box.add_child(label("Settings", 30, ACCENT, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	_scroll(box, 380).add_child(grid)
	_slider(grid, "Mouse sensitivity", 0.3, 2.5, 0.05, Settings.sens, func(v): Settings.sens = v, "%.2f×")
	_check(grid, "Invert mouse Y", Settings.invert_y, func(v): Settings.invert_y = v)
	_slider(grid, "Field of view", 50, 90, 1, Settings.fov, func(v): Settings.fov = v, "%d°")
	_slider(grid, "Music", 0, 1, 0.05, Settings.music, func(v): Settings.music = v; Settings.apply(), "%d%%", 100.0)
	_slider(grid, "Sound", 0, 1, 0.05, Settings.sfx, func(v): Settings.sfx = v; Settings.apply(); Sfx.play("squeak"), "%d%%", 100.0)
	var q := OptionButton.new()
	for o in ["Low (no shadows)", "Medium", "High"]:
		q.add_item(o)
	q.selected = ["low", "medium", "high"].find(Settings.quality)
	q.item_selected.connect(func(i): Settings.quality = ["low", "medium", "high"][i]; Settings.save())
	grid.add_child(_name("Quality"))
	grid.add_child(q)
	var res := OptionButton.new()
	var sizes := ["1280x720", "1600x900", "1920x1080", "2560x1440"]
	for o in sizes:
		res.add_item(o.replace("x", " × "))
	res.selected = maxi(0, sizes.find(Settings.resolution))
	res.item_selected.connect(func(i): Settings.resolution = sizes[i]; Settings.save())
	grid.add_child(_name("Window size"))
	grid.add_child(res)
	_check(grid, "Fullscreen", Settings.fullscreen, func(v): Settings.fullscreen = v; Settings.save())
	_check(grid, "VSync", Settings.vsync, func(v): Settings.vsync = v; Settings.save())
	_check(grid, "Depth of field (soft background)", Settings.dof, func(v): Settings.dof = v; Settings.save())
	_check(grid, "Show FPS", Settings.show_fps, func(v): Settings.show_fps = v; Settings.save())
	_check(grid, "Hints", Settings.hints, func(v): Settings.hints = v)
	_check(grid, "Calm mode (more time, quieter cat)", Settings.calm, func(v): Settings.calm = v)
	_check(grid, "Colour-blind scents (poison purple)", Settings.colorblind, func(v): Settings.colorblind = v)
	var ctl := Button.new()
	ctl.text = "Controls…"
	ctl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ctl.pressed.connect(func(): Sfx.play("click"); root.hide(); controls_panel(parent, func(): root.show()))
	box.add_child(ctl)
	var reset := Button.new()
	reset.text = "Reset progress"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var msg := label("", 15, DIM, true)
	reset.pressed.connect(func():
		if reset.has_meta("armed") and Time.get_ticks_msec() - int(reset.get_meta("armed")) < 4000:
			Progress.reset()
			reset.remove_meta("armed")
			reset.text = "Reset progress"
			msg.text = "Progress reset: the nights, the stars, the nest decorations and the achievements start over."
		else:
			reset.set_meta("armed", Time.get_ticks_msec())
			reset.text = "Click again to erase progress")
	box.add_child(reset)
	box.add_child(msg)
	var back := func(): Settings.save(); root.queue_free(); on_back.call()
	box.add_child(button("Back", back, 220))
	_esc_back(root, back)
	focus_first(box)
	return root


## Esc (or the gamepad's Start) on a sub-panel works like its Back button, and nothing behind it sees the key.
static func _esc_back(root: Control, back: Callable) -> void:
	var h := EscBack.new()
	h.back = back
	h.panel = root
	root.add_child(h)


class EscBack extends Node:
	var back: Callable
	var panel: Control

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(e: InputEvent) -> void:
		for c in panel.get_children():
			if c is Keys.Catcher:
				return  # waiting for a key to rebind: Esc cancels that instead
		if panel.visible and (e.is_action_pressed("pause") or e.is_action_pressed("ui_cancel")):
			get_viewport().set_input_as_handled()
			back.call()


## Rebind keys: click an action, press the new key (Esc cancels).
static func controls_panel(parent: Node, on_back: Callable) -> Control:
	var s := screen(parent, 0.8, false, 600.0)
	var root: Control = s[0]
	var box: VBoxContainer = s[1]
	box.add_child(label("Controls", 30, ACCENT, true))
	box.add_child(label("Click an action, then press a key or mouse button. Esc cancels. Gamepad buttons stay as they are.", 14, DIM, true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	_scroll(box, 400).add_child(grid)
	for a in Keys.ACTIONS:
		var action: String = a[0]
		grid.add_child(_name(a[1]))
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 36)
		b.text = Keys.keyboard_label(action)
		var pad := label(Keys.pad_label(action), 15, DIM)
		pad.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.pressed.connect(func():
			b.text = "Press a key…"
			var c := Keys.Catcher.new()
			c.done = func(e):
				if e != null:
					Keys.rebind(action, e)
				b.text = Keys.keyboard_label(action)
			root.add_child(c))
		grid.add_child(b)
		grid.add_child(pad)
	box.add_child(button("Reset to defaults", func(): Keys.reset(); root.queue_free(); controls_panel(parent, on_back), 260))
	var back := func(): root.queue_free(); on_back.call()
	box.add_child(button("Back", back, 220))
	_esc_back(root, back)
	focus_first(box)
	return root


## A scroll area of at most h pixels (the panels must fit a 720-pixel-high screen).
static func _scroll(box: Control, h: float) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	return sc


static func _name(text: String) -> Label:
	var l := label(text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(300, 0)
	return l


static func _slider(grid: GridContainer, name: String, lo: float, hi: float, step: float, value: float, cb: Callable, fmt: String, show_k := 1.0) -> void:
	grid.add_child(_name(name))
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var out := label(fmt % (value * show_k), 16, DIM)
	out.autowrap_mode = TextServer.AUTOWRAP_OFF
	out.custom_minimum_size = Vector2(64, 0)
	s.value_changed.connect(func(v): cb.call(v); out.text = fmt % (v * show_k))
	row.add_child(s)
	row.add_child(out)
	grid.add_child(row)


static func _check(grid: GridContainer, name: String, value: bool, cb: Callable) -> void:
	grid.add_child(_name(name))
	var c := CheckBox.new()
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.button_pressed = value
	c.toggled.connect(func(v): cb.call(v))
	grid.add_child(c)
