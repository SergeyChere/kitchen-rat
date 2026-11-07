class_name Sfx
extends Node
## Sound and music. The files are rendered by tools/make_audio.py from the prototype's synth recipes (audio.js).
##   Sfx.play("snap", position)       a one-shot in the room (heard from where it happens), or 2D without a position
##   Sfx.loop("hum_loop", node)       a looping sound that follows a node (the robot vacuum); returns the player
##   Sfx.music_night(def) / music_menu() and Sfx.music_layers(tension, chase): three synced layers per night —
##   base, the "wanted" layer (ticking hats, pulsing bass) and the chase drums — blended like Music.set().
## Volumes (0…1) live in Settings (user://settings.cfg).

const SND := "res://assets/sounds/"
const MUS := "res://assets/music/"
const SETTINGS := "user://settings.cfg"

## How loud each sound was in the prototype (peak, before the master compressor); the files are normalized, so this
## sets their level relative to each other, with the range squeezed like a compressor would.
const PEAK := {
	"bang": 0.55, "bark": 0.45, "beep": 0.12, "bell": 0.1, "buzz": 0.1, "caught": 0.29, "cheese": 0.19, "click": 0.12,
	"clink": 0.5, "crackle": 0.06, "crash": 0.55, "creak": 0.1, "crinkle": 0.2, "crunch": 0.12, "deliver": 0.37,
	"door": 0.25, "fail": 0.13, "gnaw": 0.13, "jump": 0.04, "land": 0.11, "land_big": 0.37, "light_switch": 0.3,
	"lose": 0.25, "meow": 0.3, "meow_angry": 0.5, "meow_q": 0.32, "musicbox": 0.12, "pickup": 0.18, "poison": 0.12,
	"purr": 0.05, "scrape": 0.08, "scratch": 0.12, "snap": 0.79, "sniff": 0.12, "snore": 0.09, "splash": 0.17,
	"squeak": 0.22, "squeaky": 0.12, "star_up": 0.5, "step": 0.035, "stomp": 0.3, "task": 0.19, "thud": 0.47,
	"thunder": 0.6, "tv": 0.28, "whack": 0.72, "win": 0.31, "hum_loop": 0.12, "rain_loop": 0.14,
}

static var I: Sfx
static var music_volume := 0.7
static var sfx_volume := 0.8

var _cache := {}
var _variants := {}
var _pool3: Array[AudioStreamPlayer3D] = []
var _pool2: Array[AudioStreamPlayer] = []
var _next3 := 0
var _next2 := 0
var _layers: Array[AudioStreamPlayer] = []
var _music_key := ""
var _tension := 0.0
var _chase := 0.0
var _want_t := 0.0
var _want_c := 0.0
var _duck := 1.0
var _want_duck := 1.0
var _base := 1.0


static func setup(parent: Node) -> void:
	if I:
		return
	I = Sfx.new()
	I.name = "Sfx"
	parent.add_child(I)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	lim.threshold_db = -6.0
	AudioServer.add_bus_effect(0, lim)
	_load_settings()
	for i in 28:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 2.5
		p.max_distance = 16.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		add_child(p)
		_pool3.append(p)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2.append(p)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_layers.append(p)


func _exit_tree() -> void:
	for c in find_children("*", "", true, false):
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
			c.stream = null
	_cache.clear()
	if I == self:
		I = null


# ---------- settings ----------

func _load_settings() -> void:
	Settings.load_all()
	apply_volumes()


static func set_volumes(music: float, sfx: float) -> void:
	Settings.music = clampf(music, 0.0, 1.0)
	Settings.sfx = clampf(sfx, 0.0, 1.0)
	Settings.save()


static func apply_volumes() -> void:
	var m := AudioServer.get_bus_index("Music")
	var s := AudioServer.get_bus_index("SFX")
	if m >= 0:
		AudioServer.set_bus_volume_db(m, linear_to_db(maxf(0.0001, pow(music_volume, 1.6) * 0.8)))
		AudioServer.set_bus_mute(m, music_volume <= 0.001)
	if s >= 0:
		AudioServer.set_bus_volume_db(s, linear_to_db(maxf(0.0001, pow(sfx_volume, 1.4))))
		AudioServer.set_bus_mute(s, sfx_volume <= 0.001)


# ---------- effects ----------

func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStream = null
	if ResourceLoader.exists(SND + name + ".wav"):
		s = load(SND + name + ".wav")
	_cache[name] = s
	return s


## "step" → step0, step1, step2 (whichever exist), picked at random.
func _pick(name: String) -> AudioStream:
	if not _variants.has(name):
		var list := []
		if _stream(name):
			list.append(name)
		for k in 4:
			if _stream(name + str(k)):
				list.append(name + str(k))
		_variants[name] = list
	var l: Array = _variants[name]
	return _stream(l.pick_random()) if not l.is_empty() else null


static func level_db(name: String) -> float:
	return 0.55 * linear_to_db(float(PEAK.get(name, 0.3)) / 0.8)


## A one-shot: at a position in the room (Vector3), or 2D (null). vol_db adds to the sound's own level.
static func play(name: String, at = null, vol_db := 0.0, pitch := 1.0, pitch_jitter := 0.04) -> void:
	if I == null:
		return
	var s := I._pick(name)
	if s == null:
		return
	var db := level_db(name) + vol_db
	var ps := pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	if at is Vector3:
		var p := I._pool3[I._next3]
		I._next3 = (I._next3 + 1) % I._pool3.size()
		p.stream = s
		p.volume_db = db + 6.0
		p.pitch_scale = ps
		p.global_position = at
		p.play()
	else:
		var p := I._pool2[I._next2]
		I._next2 = (I._next2 + 1) % I._pool2.size()
		p.stream = s
		p.volume_db = db
		p.pitch_scale = ps
		p.play()


## A looping sound that follows a node (or 2D when follow is null). Stop it with .stop() or by freeing the node.
static func loop(name: String, follow: Node3D = null, vol_db := 0.0) -> Node:
	if I == null:
		return null
	var s := I._stream(name)
	if s is AudioStreamWAV:
		s = s.duplicate()
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	var p: Node
	if follow:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 2.0
		p3.max_distance = 12.0
		p3.volume_db = level_db(name) + 6.0 + vol_db
		p3.stream = s
		p3.bus = "SFX"
		follow.add_child(p3)
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.volume_db = level_db(name) + vol_db
		p2.stream = s
		p2.bus = "SFX"
		I.add_child(p2)
		p2.play()
		p = p2
	return p


# ---------- music ----------

static func music_key(d: Dictionary) -> String:
	var prog := ""
	for c in d.get("prog", []):
		var o := int(c[0])
		prog += ("p" if o >= 0 else "n") + str(absi(o)) + str(c[1])
	return "r%d%s%d_%s" % [int(d.root), "m" if bool(d.minor) else "M", int(d.bpm), prog]


func _ogg(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStreamOggVorbis
	if s:
		s.loop = true
	return s


static func music_night(d: Dictionary) -> void:
	if I == null or d.is_empty():
		return
	var key := music_key(d)
	if key == I._music_key:
		return
	I._music_key = key
	I._base = 1.0
	var names := ["base", "tension", "chase"]
	for i in 3:
		var p := I._layers[i]
		p.stop()
		p.stream = I._ogg(MUS + key + "_" + names[i] + ".ogg")
	for p in I._layers:
		if p.stream:
			p.play()
	I._tension = 0.0
	I._chase = 0.0
	music_layers(0.0, false)
	I._apply_music()


static func music_menu() -> void:
	if I == null or I._music_key == "menu":
		return
	I._music_key = "menu"
	I._base = 0.8
	for p in I._layers:
		p.stop()
		p.stream = null
	I._layers[0].stream = I._ogg(MUS + "menu.ogg")
	I._layers[0].play()
	I._tension = 0.0
	I._chase = 0.0
	I._want_t = 0.0
	I._want_c = 0.0
	I._apply_music()


## tension 0…1 (the wanted level), chase: someone is after her.
static func music_layers(tension: float, chase: bool) -> void:
	if I == null:
		return
	I._want_t = clampf(tension, 0.0, 1.0) * 0.9
	I._want_c = 1.0 if chase else 0.0


static func music_duck(on: bool) -> void:
	if I:
		I._want_duck = 0.35 if on else 1.0


func _process(dt: float) -> void:
	_tension = move_toward(_tension, _want_t, dt / 1.2)
	_chase = move_toward(_chase, _want_c, dt / (0.3 if _want_c > _chase else 2.4))
	_duck = move_toward(_duck, _want_duck, dt * 2.0)
	_apply_music()


func _apply_music() -> void:
	var g := [_base, _tension * 2.0, _chase]
	for i in 3:
		_layers[i].volume_db = linear_to_db(maxf(0.0001, float(g[i]) * _duck))
