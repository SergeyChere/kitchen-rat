class_name Settings
## Player settings, saved in user://settings.cfg (like the prototype's settings panel, plus what the plan adds:
## fullscreen, VSync and a calm difficulty).

const FILE := "user://settings.cfg"

static var sens := 1.0
static var invert_y := false
static var fov := 60.0
static var music := 0.7
static var sfx := 0.8
static var quality := "medium"  # low: no shadows · medium · high: soft shadows, MSAA 4×
static var hints := true
static var fullscreen := false
static var vsync := true
static var calm := false  # more time, the cat hears and sees less
static var resolution := "1280x720"  # windowed size
static var colorblind := false  # poison shows purple instead of green
static var keys := {}  # action → ["key", physical keycode] | ["mouse", button] (rebound keys only)
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(FILE) == OK:
		sens = float(c.get_value("controls", "sens", sens))
		invert_y = bool(c.get_value("controls", "invert_y", invert_y))
		fov = float(c.get_value("video", "fov", fov))
		quality = str(c.get_value("video", "quality", quality))
		fullscreen = bool(c.get_value("video", "fullscreen", fullscreen))
		vsync = bool(c.get_value("video", "vsync", vsync))
		music = float(c.get_value("audio", "music", music))
		sfx = float(c.get_value("audio", "sfx", sfx))
		hints = bool(c.get_value("game", "hints", hints))
		calm = bool(c.get_value("game", "calm", calm))
		colorblind = bool(c.get_value("game", "colorblind", colorblind))
		resolution = str(c.get_value("video", "resolution", resolution))
		keys = c.get_value("controls", "keys", {})
	apply()


static func save() -> void:
	var c := ConfigFile.new()
	c.set_value("controls", "sens", sens)
	c.set_value("controls", "invert_y", invert_y)
	c.set_value("video", "fov", fov)
	c.set_value("video", "quality", quality)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "vsync", vsync)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("game", "hints", hints)
	c.set_value("game", "calm", calm)
	c.set_value("game", "colorblind", colorblind)
	c.set_value("video", "resolution", resolution)
	c.set_value("controls", "keys", keys)
	c.save(FILE)
	apply()


static func apply() -> void:
	Sfx.music_volume = music
	Sfx.sfx_volume = sfx
	Sfx.apply_volumes()
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		if not fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			var r := resolution.split("x")
			var want_size := Vector2i(int(r[0]), int(r[1]))
			var screen := DisplayServer.screen_get_size()
			want_size = Vector2i(mini(want_size.x, screen.x), mini(want_size.y, screen.y))
			if DisplayServer.window_get_size() != want_size:
				DisplayServer.window_set_size(want_size)
				DisplayServer.window_set_position((screen - want_size) / 2)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.msaa_3d = Viewport.MSAA_4X if quality == "high" else (Viewport.MSAA_2X if quality == "medium" else Viewport.MSAA_DISABLED)


static func poison_color() -> Color:
	return Color(0.75, 0.4, 0.95) if colorblind else Color(0.45, 0.9, 0.3)


static func shadows() -> bool:
	return quality != "low"
