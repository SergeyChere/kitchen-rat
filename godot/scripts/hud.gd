class_name Hud
extends CanvasLayer
## The night's HUD, like the prototype: night and clock, lives and wanted stars, nest progress, noise, tasks in the
## bottom-left corner, banners and toasts; speech bubbles float in the world (Label3D). Drawn in code, no UI assets.
## Ghibli storybook look: parchment cards with ink text and leaf-green accents; danger states stay red and loud.

var _canvas: Control
var _panel_box: StyleBoxFlat
var _toasts := []  # [text, time]
var _banner_t := ""
var _banner_s := ""
var _banner_time := 0.0
var _bubbles := []  # {label, follow, height, pos, t, rise}
var font: Font


var _last_counts := Vector2i(-1, -1)
var _punch_at := -10.0


func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_panel_box = StyleBoxFlat.new()
	_panel_box.bg_color = PANEL
	_panel_box.border_color = PANEL_BORDER
	_panel_box.set_border_width_all(1)
	_panel_box.set_corner_radius_all(12)
	_panel_box.shadow_color = Color(0, 0, 0, 0.25)
	_panel_box.shadow_size = 6
	_panel_box.shadow_offset = Vector2(0, 3)


func toast(text: String) -> void:
	for t in _toasts:
		if t[0] == text:
			_toasts.erase(t)
			break
	_toasts.append([text, 3.0])
	if _toasts.size() > 3:
		_toasts.pop_front()


func banner(title: String, sub: String, dur: float) -> void:
	_banner_t = title
	_banner_s = sub
	_banner_time = dur


func bubble(text: String, at: Vector3, follow: Node3D, height: float, dur: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = 30
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	l.modulate = col
	l.render_priority = 10
	l.outline_render_priority = 9
	Game.I.add_child(l)
	l.global_position = (follow.global_position + Vector3.UP * height) if follow else at
	_bubbles.append({"label": l, "follow": follow, "height": height, "pos": at, "t": dur, "rise": 0.0, "col": col})


func _process(dt: float) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		_toasts[i][1] -= dt
		if _toasts[i][1] <= 0.0:
			_toasts.remove_at(i)
	_banner_time -= dt
	for i in range(_ach.size() - 1, -1, -1):
		_ach[i][1] -= dt
		if _ach[i][1] <= 0.0:
			_ach.remove_at(i)
	for i in range(_recent.size() - 1, -1, -1):
		_recent[i][1] -= dt
		if _recent[i][1] <= 0.0:
			_recent.remove_at(i)
	for i in range(_bubbles.size() - 1, -1, -1):
		var b: Dictionary = _bubbles[i]
		b.t -= dt
		b.rise += dt * 0.08
		var l: Label3D = b.label
		if b.t <= 0.0:
			l.queue_free()
			_bubbles.remove_at(i)
			continue
		var base: Vector3 = (b.follow.global_position + Vector3.UP * b.height) if is_instance_valid(b.follow) else b.pos
		l.global_position = base + Vector3.UP * b.rise
		l.modulate = Color(b.col.r, b.col.g, b.col.b, clampf(b.t * 2.0, 0.0, 1.0))
	_canvas.queue_redraw()


# ---------- drawing ----------

const PANEL := Color(0.96, 0.90, 0.77, 0.88)
const PANEL_BORDER := Color(0.55, 0.42, 0.28, 0.85)
const BAR_BG := Color(0.45, 0.38, 0.28, 0.28)
const BAR := Color(0.35, 0.58, 0.30, 0.95)
const NOISE := Color(0.85, 0.25, 0.20, 0.9)
const SLEEP := Color(0.55, 0.65, 1.0, 0.9)
const HINT := Color(0.45, 0.38, 0.30)
const BAD := Color(0.82, 0.22, 0.15)
const CREAM := Color(0.98, 0.94, 0.82)  # text floating over the 3D view, not on a card
const CHEESE := Color(0.78, 0.55, 0.16)  # deep amber, readable on parchment
const SAFE := Color(0.30, 0.52, 0.26)
const INK := Color(0.25, 0.19, 0.13)
const MUTED := Color(0.50, 0.44, 0.36)


func _text(p: Vector2, s: String, size := 15, col := INK, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_canvas.draw_string(font, p, s, align, width, size, col)


## One parchment card; alpha fades the whole card (banners, achievements).
func _panel(r: Rect2, alpha := 1.0) -> void:
	_panel_box.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * alpha)
	_panel_box.border_color = Color(PANEL_BORDER.r, PANEL_BORDER.g, PANEL_BORDER.b, PANEL_BORDER.a * alpha)
	_panel_box.shadow_color = Color(0, 0, 0, 0.25 * alpha)
	_canvas.draw_style_box(_panel_box, r)


func _wrap(p: Vector2, s: String, width: float, size := 14, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	_canvas.draw_multiline_string(font, p, s, align, width, size, -1, col)
	var lines := font.get_multiline_string_size(s, align, width, size).y
	return lines


func clock_text() -> String:
	return _clock(Game.I)


func _clock(g: Game) -> String:
	var h := 23.0 + 7.0 * clampf(g.night_time / float(g.night.get("seconds", 900)), 0.0, 1.0)
	return "%02d:%02d" % [int(h) % 24, int((h - floorf(h)) * 60.0)]


var _ach := []  # [title, time]
var _recent := []  # [text, time, ok] tasks just completed or failed, shown at the top of the list


func achievement(title: String) -> void:
	_ach.append([title, 4.5])


func task_done(text: String, ok: bool) -> void:
	_recent.append([text, 2.6, ok])
	if _recent.size() > 3:
		_recent.pop_front()


## A new side task opened (round 5): announced in green at the top of the panel, so a task
## never just silently appears in the list any more.
func task_new(text: String) -> void:
	_recent.append(["+" + text, 4.0, true])
	if _recent.size() > 4:
		_recent.pop_front()


func _tag(cam: Camera3D, s: float, at: Vector3, text: String, size: int, col: Color) -> void:
	if cam.is_position_behind(at):
		return
	var sp := cam.unproject_position(at) / s
	_text(sp + Vector2(-60, 0), text, size, col, 120, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_hud() -> void:
	var g := Game.I
	if g == null or g.rat == null:
		return
	var vs := _canvas.get_viewport_rect().size
	var s := vs.y / 720.0
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var W := vs.x / s
	var H := 720.0
	var n := g.night
	var goal := int(n.get("goal", 10))
	var cam := g.get_viewport().get_camera_3d()

	if g.state == "intro" or g.state == "outro":
		_draw_banner_and_bubbles(W)
		if g.cut_bars:
			_canvas.draw_rect(Rect2(0, 0, W, 64), Color.BLACK)
			_canvas.draw_rect(Rect2(0, H - 64, W, 64), Color.BLACK)
			if g.state == "intro":
				_text(Vector2(W - 260, H - 26), Keys.label("jump") + " — skip", 15, Color(1, 1, 1, 0.75), 240, HORIZONTAL_ALIGNMENT_RIGHT)
		if g.grid == null:
			_text(Vector2(0, H / 2), "Loading…", 28, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
		_canvas.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, g.fade))
		return

	# state tags over the cat, the owner and the dog: Zzz bar, ? (suspicious), ! (sees you)
	if cam and g.state == "play":
		var c := g.cat
		if c.visible and c.global_position.distance_to(g.rat.global_position) < 6.0:
			var at := c.global_position + Vector3.UP * 0.5
			if c.mode == CatAI.Mode.SLEEP:
				var stg := 0 if c.sleep > 0.6 else (1 if c.sleep > 0.3 else 2)
				_tag(cam, s, at, ["Zzz", "zz…", "?!"][stg], 15, [Color(0.62, 0.7, 1.0), Color(0.95, 0.76, 0.3), BAD][stg])
				if not cam.is_position_behind(at):
					var sp := cam.unproject_position(at) / s
					_canvas.draw_rect(Rect2(sp.x - 30, sp.y + 6, 60, 6), BAR_BG)
					_canvas.draw_rect(Rect2(sp.x - 30, sp.y + 6, 60 * c.sleep, 6), SLEEP)
			elif c.mode == CatAI.Mode.CHASE or c.mode == CatAI.Mode.WATCH:
				_tag(cam, s, at, "!", 34, BAD)
			elif c.mode == CatAI.Mode.INVESTIGATE or c.mode == CatAI.Mode.SEARCH:
				_tag(cam, s, at, "?", 30, Color(0.95, 0.76, 0.3))
			elif c.alert > 0.05:
				_tag(cam, s, at, "•".repeat(ceili(c.alert * 5.0)), 20, Color(0.95, 0.76, 0.3))
		var o := g.owner_ai
		if o.in_room():
			var at2 := o.global_position + Vector3.UP * 2.05
			if o.mode == OwnerAI.Mode.CHASE: _tag(cam, s, at2, "!", 34, BAD)
			elif o.sees: _tag(cam, s, at2, "?", 30, Color(0.95, 0.76, 0.3))
		if g.dog and g.dog.awake():
			var at3 := g.dog.global_position + Vector3.UP * 0.8
			if g.dog.mode == DogAI.Mode.CHASE: _tag(cam, s, at3, "!", 34, BAD)
			elif g.dog.mode == DogAI.Mode.TRACK: _tag(cam, s, at3, "?", 26, Color(0.95, 0.76, 0.3))
		var sl := []
		if g.dog and g.dog.mode == DogAI.Mode.SLEEP: sl.append([g.dog, g.dog.sleep, "Dog · Zzz", 0.8])
		for z in g.sleepers:
			sl.append([z, 0.0 if z.awake_t > 0.0 else z.sleep, "AWAKE!" if z.awake_t > 0.0 else ("Kid · Zzz" if z.kind == "kid" else "Guest · Zzz"), 1.0])
		for e in sl:
			var nd: Node3D = e[0]
			if nd.global_position.distance_to(g.rat.global_position) > 5.0:
				continue
			var wp: Vector3 = nd.global_position + Vector3.UP * float(e[3])
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp) / s
			_text(sp + Vector2(-50, -10), str(e[2]), 14, BAD if str(e[2]) == "AWAKE!" else Color(0.62, 0.7, 1.0), 100, HORIZONTAL_ALIGNMENT_CENTER)
			_canvas.draw_rect(Rect2(sp.x - 30, sp.y - 4, 60, 6), BAR_BG)
			_canvas.draw_rect(Rect2(sp.x - 30, sp.y - 4, 60 * float(e[1]), 6), SLEEP)

	# top-left: night, clock, lives, wanted level and what's going on in the house
	var wanted := bool(n.get("wanted", false))
	_panel(Rect2(12, 12, 300, 104 if wanted else 80))
	_text(Vector2(22, 34), "Night %d · %s" % [int(n.number), str(n.name)], 17)
	_text(Vector2(22, 58), _clock(g) + "  ·  dawn at 06:00", 14, HINT)
	var lives := "♥".repeat(maxi(0, g.lives)) + "♡".repeat(maxi(0, 3 - g.lives))
	var lx := 22.0
	_text(Vector2(lx, 82), "Lives ", 15)
	lx += font.get_string_size("Lives ", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_text(Vector2(lx, 82), lives, 15, Color(0.82, 0.30, 0.22))
	lx += font.get_string_size(lives, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	if wanted:
		var stars := "★".repeat(g.stars) + "☆".repeat(5 - g.stars)
		_text(Vector2(lx, 82), "    Wanted ", 15)
		lx += font.get_string_size("    Wanted ", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_text(Vector2(lx, 82), stars, 15, CHEESE)
	if wanted:
		_text(Vector2(22, 104), _house_text(g), 13, HINT, 280)

	# top-centre: nest progress
	var bw := 320.0
	var bx := (W - bw) / 2.0
	# the counters punch (grow and flash gold) when food is picked up or brought home
	var now := Time.get_ticks_msec() / 1000.0
	var key := Vector2i(g.fed, g.rat.carry_weight())
	if key != _last_counts:
		if _last_counts.x >= 0 and (key.x > _last_counts.x or key.y > _last_counts.y):
			_punch_at = now
		_last_counts = key
	var pk := clampf(1.0 - (now - _punch_at) / 0.45, 0.0, 1.0)
	pk = pk * pk
	_panel(Rect2(bx - 10, 12, bw + 20, 52))
	_text(Vector2(bx, 32 + pk * 2.0), "Nest  %d / %d     Carrying  %d / %d" % [g.fed, goal, g.rat.carry_weight(), g.rat.capacity], 14 + int(round(pk * 5.0)), INK.lerp(Color(0.85, 0.62, 0.20), pk))
	_canvas.draw_rect(Rect2(bx, 42, bw, 12), BAR_BG)
	_canvas.draw_rect(Rect2(bx, 42, bw * clampf(float(g.fed) / maxf(1.0, goal), 0.0, 1.0), 12), BAR.lerp(Color(1.0, 0.9, 0.5), pk * 0.7))

	# top-right: are you seen, and how loud are you
	var chip := _chip(g)
	# the box grows to the left for the long lines ("Up high, but the owner can reach you" was cut off)
	var cw := maxf(240.0, font.get_string_size(str(chip[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 22.0)
	_panel(Rect2(W - 12 - cw, 12, cw, 58))
	_text(Vector2(W - 2 - cw, 33), chip[0], 15, chip[1])
	var lvl := 3 if g.rat.running and g.rat.moving() else (1 if g.rat.moving() and not g.rat.sneaking else 0)
	if g.rat.jumping: lvl = 1
	var ntext := "Loud: running" if lvl == 3 else ("Quiet: walking" if lvl == 1 else ("Silent: sneaking" if g.rat.sneaking else "Silent"))
	var warn := g.noisy_near != ""
	for i in 3:
		_canvas.draw_rect(Rect2(W - 2 - cw + i * 18, 46, 14, 12), NOISE if i < lvl else (Color(0.85, 0.45, 0.10, 0.55 + 0.35 * sin(Time.get_ticks_msec() / 150.0)) if warn else BAR_BG))
	_text(Vector2(W + 58 - cw, 57), ("Careful: " + g.noisy_near.trim_suffix("!").trim_suffix("…")) if warn else ntext, 13, Color(0.80, 0.42, 0.08) if warn else HINT)

	_draw_banner_and_bubbles(W)

	# the pups that came along
	if not g.pups.is_empty():
		var py := 78.0
		_panel(Rect2(W - 252, py, 240, 26 + 20 * g.pups.size()))
		_text(Vector2(W - 242, py + 18), "Pups  ·  %s wait/follow  ·  %s fetch" % [Keys.label("pups"), Keys.label("fetch")], 12, HINT)
		for i in g.pups.size():
			var pp: Pup = g.pups[i]
			var st: String = ["following", "waiting", "fetching", "bringing food", "CAUGHT! Rescue!", "STUCK! Help!"][pp.mode]
			_text(Vector2(W - 242, py + 40 + 20 * i), "%s · %s" % [pp.title, st], 14, BAD if pp.lost() else INK)

	_draw_tasks(g, H)

	# bottom centre: the action you can do right now, or the way home
	if g.state == "play":
		if g.prompt != "":
			_key_prompt(W, H, g.prompt)
		elif g.rat.has_jump_target():
			_key_prompt(W, H, Keys.label("jump") + " — jump")
		elif not g.rat.carried.is_empty() and cam:
			var to := g.hole - g.rat.global_position
			to.y = 0.0
			if to.length() > 0.6:
				var ang := Vector3(sin(g.cam.yaw), 0, cos(g.cam.yaw)).signed_angle_to(to, Vector3.UP)
				var c2 := Vector2(W / 2 - 110, H - 46)
				var pts := PackedVector2Array([Vector2(0, -12), Vector2(9, 9), Vector2(0, 4), Vector2(-9, 9)])
				var rot := PackedVector2Array()
				for p in pts:
					rot.append(c2 + p.rotated(-ang))
				_panel(Rect2(W / 2 - 132, H - 70, 264, 44))
				_canvas.draw_colored_polygon(rot, BAR)
				_text(Vector2(W / 2 - 92, H - 41), "to the pups · %.1f m%s" % [to.length(), " · jump down" if g.rat.global_position.y > 0.3 else ""], 15)
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_text(Vector2(0, H / 2), "Click to look around", 18, Color(CREAM.r, CREAM.g, CREAM.b, 0.85), W, HORIZONTAL_ALIGNMENT_CENTER)

	for i in _ach.size():
		var a := clampf(float(_ach[i][1]), 0.0, 1.0)
		var r := Rect2(W - 332, H - 150 - i * 74, 320, 64)
		_panel(r, a)
		_canvas.draw_rect(Rect2(r.position + Vector2(0, 12), Vector2(6, r.size.y - 24)), Color(BAR.r, BAR.g, BAR.b, a))
		_text(r.position + Vector2(18, 24), "ACHIEVEMENT UNLOCKED", 12, Color(BAR.r, BAR.g, BAR.b, a))
		_text(r.position + Vector2(18, 48), "★ " + str(_ach[i][0]), 18, Color(INK.r, INK.g, INK.b, a))
	_canvas.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, g.fade))


func _key_prompt(W: float, H: float, t: String) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 32
	_panel(Rect2(W / 2 - w / 2, H - 70, w, 40))
	_text(Vector2(0, H - 44), t, 16, INK, W, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_banner_and_bubbles(W: float) -> void:
	if _banner_time > 0.0:
		var a := clampf(_banner_time, 0.0, 1.0)
		_panel(Rect2(W / 2 - 360, 86, 720, 80), a)
		if _banner_t != "":
			_text(Vector2(0, 118), _banner_t, 24, Color(0.28, 0.48, 0.26, a), W, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(0, 150 if _banner_t != "" else 132), _banner_s, 16, Color(INK.r, INK.g, INK.b, a), W, HORIZONTAL_ALIGNMENT_CENTER)
	for i in _toasts.size():
		_text(Vector2(0, 196 + i * 26), _toasts[i][0], 16, CREAM, W, HORIZONTAL_ALIGNMENT_CENTER)


func _chip(g: Game) -> Array:
	var r := g.rat
	if r.hidden() or r.in_nest: return ["Hidden", SAFE]
	if g.owner_ai.sees: return ["The owner sees you!", BAD]
	if g.cat.sees and g.cat.mode == CatAI.Mode.WATCH: return ["The cat is waiting below", BAD]
	if g.cat.sees: return ["The cat sees you!", BAD]
	if g.dog and g.dog.sees: return ["The dog sees you!", BAD]
	for z in g.sleepers:
		if z.sees_rat(): return ["Spotted!", BAD]
	if r.global_position.y >= 0.3:
		if g.owner_ai.in_room(): return ["Up high, but the owner can reach you", CHEESE]
		return ["Up high: the cat can’t reach you", INK]
	return ["Unseen", INK]


func _house_text(g: Game) -> String:
	var o := g.owner_ai
	if o.mode == OwnerAI.Mode.CHASE: return "The owner is chasing you!"
	if g.cat.mode == CatAI.Mode.CHASE: return "The cat is chasing you!"
	if g.dog and g.dog.mode == DogAI.Mode.CHASE: return "The dog is chasing you!"
	if o.mode == OwnerAI.Mode.COMING: return "Footsteps in the hall…"
	if o.mode == OwnerAI.Mode.LEAVING: return "The owner is going back to bed…"
	if o.in_room(): return "The owner is in the room"
	var c := g.cat
	match c.mode:
		CatAI.Mode.SLEEP: return ["The cat is fast asleep", "The cat is stirring…", "The cat is half awake!"][0 if c.sleep > 0.6 else (1 if c.sleep > 0.3 else 2)]
		CatAI.Mode.AWAY: return "All quiet" if g.stars == 0 else "The house is restless"
		CatAI.Mode.EAT: return "The cat is eating"
		CatAI.Mode.INVESTIGATE, CatAI.Mode.SEARCH: return "The cat heard something"
	return "The cat is prowling"


## The task panel, as in the prototype: small and quiet — now a field-journal page. The goal with its bar, tasks just done (yellow ✔, fading),
## ONE current main task (yellow badge with its number, and its hint), then the side tasks in green.
func _draw_tasks(g: Game, H: float) -> void:
	var w := 330.0
	var tw := w - 24.0 - 29.0  # text width right of the badge
	var t := g.tasks
	var goal := int(g.night.get("goal", 10))
	var rows := []  # [badge text, badge fill, badge ring, small label, text, text colour, alpha, kind]
	var none := Color(0, 0, 0, 0)
	var gdone := g.fed >= goal
	rows.append(["✔" if gdone else "", CHEESE if gdone else none, CHEESE, "", t.goal_text + " · %d / %d" % [mini(g.fed, goal), goal], INK, 1.0, "bar"])
	for r in _recent:
		if str(r[0]).begins_with("+"):
			rows.append(["+", SAFE, SAFE, "New side task", str(r[0]).substr(1), SAFE, clampf(float(r[1]) / 4.0, 0.0, 1.0), ""])
		elif r[2]:
			rows.append(["✔", CHEESE, CHEESE, "", str(r[0]), CHEESE, clampf(float(r[1]), 0.0, 1.0), ""])
	if t.has_tasks():
		var ci := t.current_index()
		if ci >= 0:
			rows.append([str(t.step + 1), CHEESE, CHEESE, "Step %d of %d" % [t.step + 1, t.chain.size()], Keys.text(str(t.chain[ci].text)), INK, 1.0, "cur"])
			var hint := Keys.text(str(t.chain[ci].get("hint", "")))
			if Settings.hints and hint != "":
				rows.append(["", none, none, "", hint, Color(CHEESE.r, CHEESE.g, CHEESE.b, 0.8), 1.0, "hint"])
		elif not gdone:
			var rescue := false
			for pp in g.pups:
				if pp.lost(): rescue = true
			var m := "Rescue your pup first: walk up to them." if rescue else "All tasks done. Bring the rest of the food home!"
			rows.append(["✔", CHEESE, CHEESE, "", m, INK, 1.0, "cur"])
	for i in t.side.size():
		if not t.side_visible(i):
			continue
		if t.side_done.has(i) or t.side_failed.has(i):
			continue  # done/failed side tasks flash in the announcements above, then leave the list
		elif t.side[i].type == "keep":
			# a rule for the whole night: nothing to wait for, it counts when the night ends
			rows.append(["…", none, SAFE, "Side · counts when you finish the night", Keys.text(str(t.side[i].text)) + " (so far, so good)", Color(0.78, 0.92, 0.7), 1.0, ""])
		else:
			rows.append(["", none, SAFE, "Side", Keys.text(str(t.side[i].text)), Color(0.78, 0.92, 0.7), 1.0, ""])
	for i in t.secret.size():
		if t.secret_done.has(i):
			rows.append(["★", Color(0.91, 0.72, 0.29), Color(0.91, 0.72, 0.29), "Secret", str(t.secret[i].text), INK, 1.0, ""])
	var heights := []
	var total := 30.0 + 6.0
	for r in rows:
		var size := 12 if r[7] == "hint" else 14
		var h := font.get_multiline_string_size(r[4], HORIZONTAL_ALIGNMENT_LEFT, tw, size).y
		if r[3] != "": h += 13.0
		if r[7] == "bar": h += 10.0
		h = maxf(h, 20.0) + 7.0
		heights.append(h)
		total += h
	var x := 12.0
	var y := H - 14.0 - total
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = PANEL_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(16)
	box.shadow_color = Color(0, 0, 0, 0.25)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	_canvas.draw_style_box(box, Rect2(x, y, w, total))
	_canvas.draw_string(font, Vector2(x + 12, y + 20), "TONIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CHEESE)
	var yy := y + 30.0
	for k in rows.size():
		var r: Array = rows[k]
		var a: float = r[6]
		var size := 12 if r[7] == "hint" else 14
		var bc := Vector2(x + 22, yy + 11)
		if r[7] != "hint":
			var fill: Color = r[1]
			var ring: Color = r[2]
			if fill.a > 0.0:
				_canvas.draw_circle(bc, 10.0, Color(fill.r, fill.g, fill.b, a))
			_canvas.draw_arc(bc, 9.5, 0, TAU, 24, Color(ring.r, ring.g, ring.b, a), 1.5, true)
			if r[0] != "":
				var tc := Color(0.1, 0.09, 0.07, a) if fill.a > 0.0 else Color(ring.r, ring.g, ring.b, a)
				_canvas.draw_string(font, bc + Vector2(-10, 4), r[0], HORIZONTAL_ALIGNMENT_CENTER, 20, 11, tc)
		var tx := x + 41.0
		var ty := yy
		if r[3] != "":
			_canvas.draw_string(font, Vector2(tx, ty + 10), str(r[3]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(MUTED.r, MUTED.g, MUTED.b, a))
			ty += 13.0
		var col: Color = r[5]
		col.a *= a
		_canvas.draw_multiline_string(font, Vector2(tx, ty + size + 1), r[4], HORIZONTAL_ALIGNMENT_LEFT, tw, size, -1, col)
		if r[7] == "bar":
			var by := ty + size + 7
			_canvas.draw_rect(Rect2(tx, by, tw, 4), BAR_BG)
			_canvas.draw_rect(Rect2(tx, by, tw * clampf(float(g.fed) / maxf(1.0, goal), 0.0, 1.0), 4), CHEESE)
		yy += heights[k]
		if r[7] == "bar":
			_canvas.draw_line(Vector2(x + 12, yy - 3), Vector2(x + w - 12, yy - 3), Color(0.55, 0.42, 0.28, 0.6), 1.0)
