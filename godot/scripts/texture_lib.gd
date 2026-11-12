class_name TextureLib
extends RefCounted
## Round 6: where a material's texture comes from, in order:
##   1. user://textures/   — the CDN pack, downloaded once in the background (below)
##   2. res://assets/textures/ — a file committed to the repo or dropped in by hand
##   3. user://gen_textures/ — painted by TextureGen on an earlier launch
##   4. TextureGen, painted now and cached to (3)
## The user has no Python, so this replaces "run the generator script" entirely; and
## good PBR sets are far too heavy for the git repo, so they live on a CDN instead:
## godot/cdn.json holds one zip URL (a GitHub Release asset on this very repo);
## boot() fetches it once while the player is in the menu. Any failure — offline,
## no pack published yet — silently falls back to the painted textures. The game
## never waits for the network.

const USER_DIR := "user://textures"
const GEN_DIR := "user://gen_textures"

static var _cache: Dictionary = {}
static var _booted := false
static var _http: HTTPRequest = null
static var _thread: Thread = null


static func get_texture(tex_name: String, generate := true) -> Texture2D:
	if _cache.has(tex_name):
		return _cache[tex_name]
	var t: Texture2D = null
	# the CDN pack may carry .jpg files (that's what the texture libraries ship) —
	# the names are what matter, not the container
	for ext in [".png", ".jpg"]:
		var up: String = USER_DIR + "/" + tex_name + ext
		if FileAccess.file_exists(up):
			t = _load_file(up)
			if t != null:
				break
	if t == null and ResourceLoader.exists("res://assets/textures/" + tex_name + ".png"):
		t = load("res://assets/textures/" + tex_name + ".png") as Texture2D
	if t == null:
		var gp := GEN_DIR + "/" + tex_name + ".png"
		if FileAccess.file_exists(gp):
			t = _load_file(gp)
		elif generate:
			t = TextureGen.make(tex_name)
			if t != null:
				DirAccess.make_dir_recursive_absolute(GEN_DIR)
				(t as ImageTexture).get_image().save_png(gp + ".tmp")
				DirAccess.rename_absolute(gp + ".tmp", gp)
	if t != null:
		_cache[tex_name] = t
	return t


## The texture as SURFACE DETAIL only: grayscale, levelled to a mid brightness, with the factor that brings a
## colour multiplied by it back to that colour on average. A material is then  designed colour × detail:
## the grain, weave or scratches of the texture, the palette of the model — whatever pack is installed
## (a pale oak and a near-black walnut give the same brown shelf, each with its own grain).
## Returns [texture, gain] or [] when the texture doesn't exist.
static var _detail := {}


static func get_detail(tex_name: String) -> Array:
	if _detail.has(tex_name):
		return _detail[tex_name]
	var out := []
	var t := get_texture(tex_name)
	if t != null:
		var img := t.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.convert(Image.FORMAT_RGB8)
			var small := img.duplicate() as Image
			small.resize(32, 32, Image.INTERPOLATE_BILINEAR)
			var m := 0.0
			for y in 32:
				for x in 32:
					var c := small.get_pixel(x, y)
					m += (c.r + c.g + c.b) / 3.0
			m /= 1024.0
			img.adjust_bcs(0.72 / maxf(m, 0.02), 1.0, 0.0)  # gray, mean ~0.72 (sRGB)
			small = img.duplicate() as Image
			small.resize(32, 32, Image.INTERPOLATE_BILINEAR)
			var lin := 0.0
			for y in 32:
				for x in 32:
					lin += small.get_pixel(x, y).srgb_to_linear().r
			lin /= 1024.0
			img.generate_mipmaps()
			out = [ImageTexture.create_from_image(img), 1.0 / maxf(lin, 0.05)]
	_detail[tex_name] = out
	return out


## `colour` (as designed, sRGB) pre-multiplied so that colour × detail texture averages back to `colour`.
static func detail_colour(colour: Color, gain: float) -> Color:
	var l := colour.srgb_to_linear()
	var o := Color(l.r * gain, l.g * gain, l.b * gain, 1.0).linear_to_srgb()
	o.a = colour.a
	return o


## Join the painter thread before exit (Main._exit_tree) — it normally finished
## long before the player quits; files are written via .tmp + rename regardless.
static func shutdown() -> void:
	if _thread != null:
		if _thread.is_alive():
			_thread.wait_to_finish()
		_thread = null


static func _load_file(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Called once from Main._ready: start the CDN download and the background painter.
static func boot(parent: Node) -> void:
	if _booted:
		return
	_booted = true
	_thread = Thread.new()
	_thread.start(TextureGen.make_all_files.bind(GEN_DIR))
	if FileAccess.file_exists(USER_DIR + "/.cdn_done"):
		return
	var url := ""
	if FileAccess.file_exists("res://cdn.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://cdn.json"))
		if parsed is Dictionary:
			url = str((parsed as Dictionary).get("base", ""))
	if url == "":
		return
	_http = HTTPRequest.new()
	_http.download_file = "user://textures_pack.zip"
	_http.timeout = 60.0
	parent.add_child(_http)
	_http.request_completed.connect(_on_downloaded)
	_http.request(url)


static func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var z := ZIPReader.new()
		if z.open("user://textures_pack.zip") == OK:
			DirAccess.make_dir_recursive_absolute(USER_DIR)
			for f in z.get_files():
				if f.ends_with(".png") or f.ends_with(".jpg"):
					var fa := FileAccess.open(USER_DIR + "/" + f.get_file(), FileAccess.WRITE)
					if fa != null:
						fa.store_buffer(z.read_file(f))
			z.close()
			var m := FileAccess.open(USER_DIR + "/.cdn_done", FileAccess.WRITE)
			if m != null:
				m.store_string("1")
			_cache.clear()  # the next level build picks the real pack up
			_detail.clear()
	if _http != null:
		_http.queue_free()
		_http = null
