class_name Achievements
## Achievements, saved with the progress (user://progress.cfg). When the game runs with the GodotSteam extension
## (Engine.has_singleton("Steam")), each unlock is also sent to Steam; the ids are the ones to create in Steamworks.

const LIST := [
	["ACT_1", "Silence", "Finish Act 1 (night 5)."],
	["ACT_2", "The Owner", "Finish Act 2 (night 10)."],
	["ACT_3", "Traps", "Finish Act 3 (night 15)."],
	["ACT_4", "Moving Day", "Lead the family out of the house (night 20)."],
	["FIRST_CHEESE", "Cheeese!", "Bring the first cheese home."],
	["LET_IT_SLEEP", "Let Sleeping Cats Lie", "Finish a night with a sleeping cat without waking it."],
	["GHOST", "Ghost", "Finish a night without anyone chasing you."],
	["UNTOUCHABLE", "Untouchable", "Finish a night without losing a life."],
	["COMPLETIONIST", "Every Last Crumb", "Finish a night with every side task and secret done."],
	["TUNNELER", "Through the Walls", "Crawl through 10 wall tunnels."],
	["RIDER", "Wheee!", "Ride the robot vacuum."],
	["RESCUER", "No Pup Left Behind", "Rescue a caught pup."],
	["TRAP_BREAKER", "Snap!", "Disarm 5 mousetraps by knocking things onto them."],
	["DOG_BALL", "Fetch!", "Distract the dog with the ball."],
	["ALL_NIGHTS", "Twenty Nights", "Finish every night."],
]

static var unlocked := {}  # id → true
static var counters := {}  # id → int
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(Progress.FILE) == OK:
		unlocked = c.get_value("achievements", "unlocked", {})
		counters = c.get_value("achievements", "counters", {})


static func _save() -> void:
	var c := ConfigFile.new()
	c.load(Progress.FILE)
	c.set_value("achievements", "unlocked", unlocked)
	c.set_value("achievements", "counters", counters)
	c.save(Progress.FILE)


static func reset() -> void:
	unlocked = {}
	counters = {}
	_save()


static func title(id: String) -> String:
	for a in LIST:
		if a[0] == id:
			return a[1]
	return id


static func unlock(id: String) -> void:
	load_all()
	if unlocked.has(id):
		return
	unlocked[id] = true
	_save()
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		steam.call("setAchievement", id)
		steam.call("storeStats")
	if Game.I and is_instance_valid(Game.I) and Game.I.hud:
		Game.I.hud.achievement(title(id))
	Sfx.play("star_up", null, -4.0, 1.3)


static func add(id: String, n: int, goal: int) -> void:
	load_all()
	counters[id] = int(counters.get(id, 0)) + n
	_save()
	if int(counters[id]) >= goal:
		unlock(id)


## Called when a night is won.
static func night_won(g: Game) -> void:
	var num := int(g.night.number)
	if num == 5: unlock("ACT_1")
	if num == 10: unlock("ACT_2")
	if num == 15: unlock("ACT_3")
	if num == 20: unlock("ACT_4")
	if str(g.night.get("cat", "")) == "sleep" and not g.run.catWoke: unlock("LET_IT_SLEEP")
	if not g.run.chased and not g.run.dogChased and not g.run.seenOwner: unlock("GHOST")
	if g.lives >= 3: unlock("UNTOUCHABLE")
	var all := true
	for r in g.goal_rows(true):
		if not r[1]: all = false
	if all and g.tasks.has_tasks(): unlock("COMPLETIONIST")
	if Progress.unlocked > Nights.files().size(): unlock("ALL_NIGHTS")
