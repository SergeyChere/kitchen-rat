class_name Progress
## Which nights are open and the best result on each, saved in user://progress.cfg (the prototype's progress:
## finish a night to open the next one).

const FILE := "user://progress.cfg"

static var unlocked := 1  # nights 1…unlocked are open
static var best := {}  # id → {time, clock, goals, of, stars}
static var seen_prologue := false
static var _loaded := false
static var losses := {}  # id → losses in a row this session


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(FILE) == OK:
		unlocked = int(c.get_value("progress", "unlocked", 1))
		best = c.get_value("progress", "best", {})
		seen_prologue = bool(c.get_value("progress", "seen_prologue", false))


static func save() -> void:
	var c := ConfigFile.new()
	c.load(FILE)  # keep the achievements stored in the same file
	c.set_value("progress", "unlocked", unlocked)
	c.set_value("progress", "best", best)
	c.set_value("progress", "seen_prologue", seen_prologue)
	c.save(FILE)


static func is_open(number: int) -> bool:
	return number <= unlocked


## A night was won: open the next one and keep the best result.
static func record(night: Dictionary, seconds: float, clock: String, goals: int, of: int, stars: int) -> void:
	losses.erase(str(night.id))
	unlocked = maxi(unlocked, int(night.number) + 1)
	var id := str(night.id)
	var prev: Dictionary = best.get(id, {})
	var rec := {"time": int(seconds), "clock": clock, "goals": goals, "of": of, "stars": stars}
	if not prev.is_empty():
		rec.goals = maxi(goals, int(prev.get("goals", 0)))
		rec.stars = mini(stars, int(prev.get("stars", 5)))
		if int(prev.get("time", 99999)) <= int(seconds):
			rec.time = prev.time
			rec.clock = prev.clock
	best[id] = rec
	save()


static func reset() -> void:
	unlocked = 1
	best = {}
	seen_prologue = false
	save()
