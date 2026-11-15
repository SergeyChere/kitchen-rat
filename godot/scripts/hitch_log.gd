class_name HitchLog
extends Node
## Round 19 (asked: "the game freezes now and then — find out why"): a frame that takes much longer than the ones
## around it is written to user://hitches.txt with what the frame cost (scripts, physics, the renderer on the CPU
## and on the graphics card) and what had just happened in the game (the last sounds, words on screen, lights
## switched, things spawned, what the cat and the owner were doing). The player sends the file; it names the cause.
## On Windows the file is in %APPDATA%\Godot\app_userdata\Kitchen Rat\.

const PATH := "user://hitches.txt"
const MAX_LINES := 400

static var I: HitchLog
var _events: Array = []  # [msec, text], the newest last
var _avg := 0.0
var _file: FileAccess
var _lines := 0
var _vp := RID()


static func note(text: String) -> void:
	if I == null:
		return
	I._events.append([Time.get_ticks_msec(), text])
	if I._events.size() > 10:
		I._events.pop_front()


func _ready() -> void:
	I = self
	process_priority = 1000  # after everything else in the frame
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_file = FileAccess.open(PATH, FileAccess.WRITE)  # one session per file: the last session is what matters
	if _file:
		_file.store_line("Kitchen Rat · %s · %s (%s) · %s · quality %s · %dx%d" % [
			Time.get_datetime_string_from_system(),
			RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), OS.get_name(),
			Settings.quality, get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y])
		_file.flush()


func _process(dt: float) -> void:
	var ms := dt * 1000.0
	if _avg <= 0.0:
		_avg = ms
	var hitch := ms > 70.0 and ms > _avg * 2.5
	if not hitch:
		_avg = lerpf(_avg, ms, 0.05)
		return
	if _file == null or _lines >= MAX_LINES:
		return
	_lines += 1
	var now := Time.get_ticks_msec()
	var ev := []
	for e in _events:
		if now - int(e[0]) < 3000:
			ev.append("%s (-%.1fs)" % [e[1], (now - int(e[0])) / 1000.0])
	var who := ""
	var main := get_parent()
	var g = main.get("game") if main else null
	if g and is_instance_valid(g):
		who = " · state %s" % str(g.state)
		if g.get("cat") and is_instance_valid(g.cat): who += " · cat %s" % str(g.cat.Mode.keys()[g.cat.mode])
		if g.get("owner_ai") and is_instance_valid(g.owner_ai): who += " · owner %s" % str(g.owner_ai.Mode.keys()[g.owner_ai.mode])
	_file.store_line("%7.1fs HITCH %4.0f ms (usual %.0f) · scripts %.1f · physics %.1f · render cpu %.1f gpu %.1f · draw calls %d%s · just before: %s" % [
		now / 1000.0, ms, _avg, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(_vp),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), who,
		", ".join(ev) if not ev.is_empty() else "nothing"])
	_file.flush()


func _exit_tree() -> void:
	if I == self:
		I = null
	if _file:
		_file.close()
