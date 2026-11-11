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
	if _http != null:
		_http.queue_free()
		_http = null
