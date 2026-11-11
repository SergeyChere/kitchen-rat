class_name GameFeel
extends Node
## The moments that should be felt, not read:
##  · slow motion for a beat when the cat (owner, dog) spots her, or a trap snaps next to her
##  · a heartbeat and a dark red edge on the screen while something is close or chasing her
##  · the room goes muffled while she hides (a low-pass on the sound effects)

var g: Game
var _vignette: ColorRect
var _mat: ShaderMaterial
var _threat := 0.0      # 0…1, eased
var _beat_t := 0.0
var _pulse := 0.0       # flashes with each heartbeat
var beats := 0          # heartbeat count (the tester reads it; the pulse is what the player sees)
var _was_chased := false
var _slow_until := 0.0
var _lp: AudioEffectLowPassFilter
var _lp_bus := -1

const VIGNETTE := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.32, 0.0, 0.03, 1.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.5, 1.0));
	float v = smoothstep(0.28, 0.92, d);
	COLOR = vec4(tint.rgb, v * amount);
}
"""

## Round 8: the film grade overlay — a soft vignette and a whisper of animated
## grain over the whole frame. Part of grading the game like a film (the user's
## It Takes Two ask); kept very subtle so the HUD stays crisp.
const GRADE := """
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.4, 1.0));
	float vig = smoothstep(0.52, 1.05, d);
	float gr = hash(UV * vec2(1831.0, 1013.0) + vec2(fract(TIME * 13.7), fract(TIME * 7.3)) * 91.7) - 0.5;
	vec3 col = mix(vec3(0.5 + gr * 0.9), vec3(0.0), vig);
	COLOR = vec4(col, max(0.045, vig * 0.13));
}
"""


func _init(game: Game) -> void:
	g = game
	name = "Game feel"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Settings.quality != "low":
		var grade := ColorRect.new()
		grade.set_anchors_preset(Control.PRESET_FULL_RECT)
		grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gsh := Shader.new()
		gsh.code = GRADE
		var gmat := ShaderMaterial.new()
		gmat.shader = gsh
		grade.material = gmat
		g.hud.add_child(grade)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_vignette.material = _mat
	g.hud.add_child(_vignette)
	g.hud.move_child(_vignette, 0)  # under the HUD text
	_lp_bus = AudioServer.get_bus_index("SFX")
	if _lp_bus >= 0:
		for i in AudioServer.get_bus_effect_count(_lp_bus):
			if AudioServer.get_bus_effect(_lp_bus, i) is AudioEffectLowPassFilter:
				_lp = AudioServer.get_bus_effect(_lp_bus, i)
		if _lp == null:
			_lp = AudioEffectLowPassFilter.new()
			_lp.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(_lp_bus, _lp)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if _lp:
		_lp.cutoff_hz = 20000.0


## Slow motion for a moment (real seconds), then back to normal.
func slowmo(scale := 0.3, secs := 0.35) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = scale
	_slow_until = Time.get_ticks_msec() / 1000.0 + secs


func _process(_dt: float) -> void:
	var real_dt := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	if _slow_until > 0.0 and Time.get_ticks_msec() / 1000.0 >= _slow_until:
		_slow_until = 0.0
		Engine.time_scale = 1.0
	if g.state != "play":
		_threat = move_toward(_threat, 0.0, real_dt * 2.0)
		_mat.set_shader_parameter("amount", _threat * 0.5)
		if g.state != "pause" and Engine.time_scale < 1.0:
			Engine.time_scale = 1.0
		return
	var chased := false
	var near := 0.0
	var chaser_near := 0.0
	for a in [g.cat, g.owner_ai, g.dog]:
		if a == null or not is_instance_valid(a) or not (a as Node3D).visible:
			continue
		# round 6: the owner waits INVISIBLE at the door while AWAY / COMING, but his
		# root node stays "visible" — the proximity term fired the heartbeat by the
		# door with nobody in the room. He only counts once he is actually IN.
		if a is OwnerAI and not (a as OwnerAI).in_room():
			continue
		var m: int = a.get("mode")
		var is_chase := (a is CatAI and m == CatAI.Mode.CHASE) or (a is OwnerAI and m == OwnerAI.Mode.CHASE) or (a is DogAI and m == DogAI.Mode.CHASE)
		if is_chase: chased = true
		var awake := not (a is CatAI) or (a as CatAI).awake()
		if awake:
			# demo polish: the danger is felt from farther out (3.4 m, was 2.2) and the curve is steeper,
			# so the last metre before a catch counts much more than a hunter across the room
			var nn := pow(clampf((3.4 - (a as Agent).dist_rat()) / 2.6, 0.0, 1.0), 1.5)
			near = maxf(near, nn)
			if is_chase: chaser_near = maxf(chaser_near, nn)
	if chased and not _was_chased:
		# round 3: no slow motion on being spotted (asked for) — the heartbeat throb below carries it
		g.cam.shake(0.25)
	_was_chased = chased
	# a chase is never mild, but how bad it feels now scales with how close the hunter actually is
	var want := clampf(0.72 + 0.38 * chaser_near, 0.0, 1.0) if chased else near * 0.85
	if g.rat.hidden():
		want *= 0.4
	_threat = move_toward(_threat, want, real_dt * (4.5 if want > _threat else 1.1))
	# heartbeat: faster and louder the closer the danger (demo polish: it starts earlier, beats faster
	# at the top end and plays louder — at full threat it is the loudest quiet sound in the game)
	if _threat > 0.08:
		_beat_t -= real_dt
		if _beat_t <= 0.0:
			_beat_t = lerpf(1.0, 0.34, _threat)
			Sfx.play("heartbeat", null, lerpf(-15.0, -0.5, _threat), 1.0, 0.0)
			_pulse = 1.0
			beats += 1
	else:
		_beat_t = 0.0
	_pulse = move_toward(_pulse, 0.0, real_dt * 3.2)
	# the red edge throbs with the heartbeat: every beat (_pulse = 1) swells it, then it ebbs away
	_mat.set_shader_parameter("amount", clampf(_threat * 0.68 + _pulse * _threat * 0.45, 0.0, 1.0))
	# hiding: the room sounds muffled
	if _lp:
		var target := 900.0 if g.rat.hidden() else 20000.0
		_lp.cutoff_hz = lerpf(_lp.cutoff_hz, target, clampf(real_dt * 5.0, 0.0, 1.0))
