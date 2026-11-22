class_name PlaytestLog
extends RefCounted
## Round 22 (the plan's milestone M1: "a playtest journal: time, detections, catches, retries, pauses with no
## progress"): what happens in a night, one JSON object per line, for the blind playtests. Only the playtest build
## (export feature "playtest") or a run with --playtest writes it: next to the game's .exe in playtest_logs/, or in
## user://playtest_logs when run from the editor. The game and the Steam demo never write anything.

const IDLE := 60.0  # this long without progress is worth a look in the recording (not proof she is lost)

static var force := false  # the tests switch it on
static var path := ""
static var clock := 0.0    # seconds of play in this night (pauses and menus don't count)
static var _idle := 0.0
static var _idle_logged := false
static var _night := ""
static var _file: FileAccess = null


static func on() -> bool:
	return force or OS.has_feature("playtest") or OS.get_cmdline_user_args().has("--playtest")


static func dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("playtest_logs")
	return "user://playtest_logs"


static func _open() -> bool:
	if _file:
		return true
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	for d in [dir(), "user://playtest_logs"]:  # (a read-only folder next to the .exe: the user folder instead)
		DirAccess.make_dir_recursive_absolute(d)
		path = d.path_join("kitchen_rat_%s.jsonl" % stamp)
		_file = FileAccess.open(path, FileAccess.WRITE)
		if _file:
			return true
	return false


## A night begins: its clock starts at 0.
static func start(night: String, data := {}) -> void:
	_night = night
	clock = 0.0
	_idle = 0.0
	_idle_logged = false
	event("night_start", data)


static func event(ev: String, data := {}) -> void:
	if not on() or not _open():
		return
	var row := {"ev": ev, "night": _night, "t": snappedf(clock, 0.1)}
	row.merge(data, true)
	_file.store_line(JSON.stringify(row))
	_file.flush()


## Something moved her on (food picked up or delivered, a task done, a thing knocked down).
static func progress(ev := "", data := {}) -> void:
	_idle = 0.0
	_idle_logged = false
	if ev != "":
		event(ev, data)


## Every frame of play: a minute with no progress is noted once, with where she is, until the next progress.
static func tick(dt: float, at: Vector3) -> void:
	clock += dt
	_idle += dt
	if _idle >= IDLE and not _idle_logged:
		_idle_logged = true
		event("no_progress", {"at": xz(at)})


static func xz(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]
