class_name Hud
extends CanvasLayer
## The night's HUD, like the prototype: night and clock, lives and wanted stars, nest progress, noise, tasks in the
## bottom-left corner, banners and toasts; speech bubbles float in the world (Label3D). Drawn in code, no UI assets.

var _canvas: Control
var _toasts := []  # [text, time]
var _banner_t := ""
var _banner_s := ""
var _banner_time := 0.0
var _bubbles := []  # {label, follow, height, pos, t, rise}
var font: Font


func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


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

const PANEL := Color(0.05, 0.06, 0.1, 0.72)
const BAR_BG := Color(1, 1, 1, 0.15)
const BAR := Color(1, 0.72, 0.35, 0.95)
const NOISE := Color(1, 0.35, 0.3, 0.9)
const SLEEP := Color(0.55, 0.65, 1.0, 0.9)
const HINT := Color(0.85, 0.85, 0.75)


func _text(p: Vector2, s: String, size := 15, col := Color.WHITE, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_canvas.draw_string(font, p, s, align, width, size, col)


func _wrap(p: Vector2, s: String, width: float, size := 14, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	_canvas.draw_multiline_string(font, p, s, align, width, size, -1, col)
	var lines := font.get_multiline_string_size(s, align, width, size).y
	return lines


func _clock(g: Game) -> String:
	var h := 23.0 + 7.0 * clampf(g.night_time / float(g.night.get("seconds", 900)), 0.0, 1.0)
	return "%02d:%02d" % [int(h) % 24, int((h - floorf(h)) * 60.0)]


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

	if g.state == "intro":
		_canvas.draw_rect(Rect2(0, 0, W, H), PANEL)
		_text(Vector2(0, H * 0.3), "Night %d · %s" % [int(n.number), str(n.name)], 36, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(0, H * 0.3 + 46), str(n.get("startTitle", "")), 18, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
		_wrap(Vector2(W / 2 - 320, H * 0.3 + 80), str(n.get("startSub", "")), 640, 16, HINT, HORIZONTAL_ALIGNMENT_CENTER)
		var mom := str(n.get("introMom", ""))
		if mom != "":
			_wrap(Vector2(W / 2 - 320, H * 0.3 + 140), "Mom: “" + mom + "”", 640, 15, HINT, HORIZONTAL_ALIGNMENT_CENTER)
		_wrap(Vector2(W / 2 - 400, H * 0.66), "WASD move · Mouse look · Shift run · Ctrl or C sneak · Space jump (aim at the yellow ring) · E or right mouse sniff · F push · Esc pause", 800, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(0, H * 0.8), "Loading…" if g.grid == null else "Click to start", 30, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
		return

	# the sleeping cat's Zzz bar
	var cam := g.get_viewport().get_camera_3d()
	if cam and g.cat and g.cat.visible and g.cat.mode == CatAI.Mode.SLEEP and g.cat.global_position.distance_to(g.rat.global_position) < 4.0:
		var wp := g.cat.global_position + Vector3.UP * 0.5
		if not cam.is_position_behind(wp):
			var sp := cam.unproject_position(wp) / s
			_text(sp + Vector2(-40, -10), "Zzz", 14, Color.WHITE, 80, HORIZONTAL_ALIGNMENT_CENTER)
			_canvas.draw_rect(Rect2(sp.x - 30, sp.y - 4, 60, 6), BAR_BG)
			_canvas.draw_rect(Rect2(sp.x - 30, sp.y - 4, 60 * g.cat.sleep, 6), SLEEP)

	# top-left: night, clock, lives, wanted
	_canvas.draw_rect(Rect2(12, 12, 270, 80), PANEL)
	_text(Vector2(22, 34), "Night %d · %s" % [int(n.number), str(n.name)], 17)
	_text(Vector2(22, 58), _clock(g) + "  ·  dawn at 06:00", 14)
	var lives := "♥".repeat(maxi(0, g.lives)) + "♡".repeat(maxi(0, 3 - g.lives))
	_text(Vector2(22, 82), "Lives " + lives + (("   Wanted " + ("★".repeat(g.stars) if g.stars > 0 else "—")) if bool(n.get("wanted", false)) else ""), 14)

	# top-centre: nest progress
	var bw := 320.0
	var bx := (W - bw) / 2.0
	_canvas.draw_rect(Rect2(bx - 10, 12, bw + 20, 52), PANEL)
	_text(Vector2(bx, 32), "Nest  %d / %d     Carrying  %d / %d" % [g.fed, goal, g.rat.carry_weight(), g.rat.capacity], 14)
	_canvas.draw_rect(Rect2(bx, 42, bw, 12), BAR_BG)
	_canvas.draw_rect(Rect2(bx, 42, bw * clampf(float(g.fed) / maxf(1.0, goal), 0.0, 1.0), 12), BAR)

	# top-right: noise and stance
	if g.rat.noise_level > 0.05 or g.rat.sneaking or g.rat.hidden():
		_canvas.draw_rect(Rect2(W - 182, 12, 170, 50), PANEL)
		_text(Vector2(W - 172, 32), "Hidden" if g.rat.hidden() else ("Sneaking" if g.rat.sneaking else "Noise"), 14)
		_canvas.draw_rect(Rect2(W - 172, 42, 150, 10), BAR_BG)
		_canvas.draw_rect(Rect2(W - 172, 42, 150 * g.rat.noise_level, 10), NOISE)

	if _banner_time > 0.0:
		var a := clampf(_banner_time, 0.0, 1.0)
		_canvas.draw_rect(Rect2(W / 2 - 340, 86, 680, 76), Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * a))
		_text(Vector2(0, 116), _banner_t, 22, Color(1, 1, 1, a), W, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(0, 146), _banner_s, 15, Color(1, 1, 1, a), W, HORIZONTAL_ALIGNMENT_CENTER)
	for i in _toasts.size():
		_text(Vector2(0, 190 + i * 26), _toasts[i][0], 16, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)

	_draw_tasks(g, H)
	if g.rat.has_jump_target() and g.state == "play":
		_text(Vector2(0, H - 50), "Space — jump", 16, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)

	if g.state == "pause":
		_canvas.draw_rect(Rect2(0, 0, W, H), PANEL)
		_text(Vector2(0, H * 0.42), "Paused", 36, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(0, H * 0.42 + 44), "The pups are waiting. Click or Esc to continue · R restart · M menu", 16, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
	elif g.state == "won" or g.state == "lost":
		_canvas.draw_rect(Rect2(0, 0, W, H), PANEL)
		_text(Vector2(0, H * 0.3), g.end_title, 36, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)
		_wrap(Vector2(W / 2 - 340, H * 0.3 + 30), g.end_text, 680, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		var y := H * 0.3 + 110
		var t := g.tasks
		if t.has_tasks():
			_text(Vector2(0, y), "Main tasks %d / %d" % [mini(t.step, t.chain.size()), t.chain.size()], 15, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER); y += 26
			for i in t.side.size():
				_text(Vector2(0, y), ("✓ " if (t.side_done.has(i) and g.state == "won") else "○ ") + "Side: " + str(t.side[i].text), 15, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER); y += 24
			for i in t.secret.size():
				_text(Vector2(0, y), ("★ Secret: " + str(t.secret[i].text)) if t.secret_done.has(i) else "Secret: ???", 15, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER); y += 24
		_text(Vector2(0, H * 0.84), "Click or R to play again · M menu", 16, Color.WHITE, W, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_tasks(g: Game, H: float) -> void:
	var w := 380.0
	var t := g.tasks
	var goal := int(g.night.get("goal", 10))
	var lines := []  # [text, size, color, height]
	lines.append([t.goal_text + "  %d/%d" % [mini(g.fed, goal), goal], 17, Color.WHITE, 26.0])
	var cur = t.current()
	if cur != null:
		var s1 := "Step %d of %d:  %s" % [t.step + 1, t.chain.size(), str(cur.text)]
		lines.append([s1, 14, Color.WHITE, font.get_multiline_string_size(s1, HORIZONTAL_ALIGNMENT_LEFT, w - 20, 14).y + 4])
		var hint := str(cur.get("hint", ""))
		if hint != "":
			lines.append([hint, 13, HINT, font.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, w - 20, 13).y + 4])
	elif g.fed < goal:
		lines.append(["Every task is done. Bring %d more food home." % (goal - g.fed), 14, Color.WHITE, 22.0])
	for i in t.side.size():
		if not t.side_visible(i):
			continue
		var mark := "✓ " if t.side_done.has(i) else ("✗ " if t.side_failed.has(i) else "○ ")
		lines.append([mark + "Side: " + str(t.side[i].text), 14, Color.WHITE, 22.0])
	for i in t.secret.size():
		if t.secret_done.has(i):
			lines.append(["★ Secret: " + str(t.secret[i].text), 14, Color.WHITE, 22.0])
	var total := 16.0
	for l in lines:
		total += l[3]
	var y := H - 12 - total
	_canvas.draw_rect(Rect2(12, y, w, total), PANEL)
	y += 8
	for l in lines:
		_canvas.draw_multiline_string(font, Vector2(22, y + l[1]), l[0], HORIZONTAL_ALIGNMENT_LEFT, w - 20, l[1], -1, l[2])
		y += l[3]
