class_name ComicStory
extends CanvasLayer
## The prologue's opening as a painted comic (round 18, the player: "like Frostpunk did it — a comic, a picture
## that moves a little"): pages of panels on a dark page, each a painting (assets/story) that drifts slowly (a pan
## and a push in), with rain over it, lightning, cut-out figures that move within the panel, and caption boxes that
## type themselves in. It runs on the game's prologue clock (tick(t)), so skipping and STORY_AT work as before.
##
## A figure is a cut-out PNG in assets/story: for now the game's own rat and street cat as dark silhouettes
## (tools/blender/comic_cutouts.py). A painting that already has them drawn in can take a panel's place: put
## assets/story/<panel's own name>.jpg there (garden_chase.jpg…) and that panel shows it without the cut-outs.

const DIR := "res://assets/story/"
const FONT := "res://assets/fonts/Lora.ttf"

## Panels: name, page [from, to], rect on the screen (0..1), painting, view [centre from, width from, centre to,
## width to] (as parts of the painting), rain, figures, appears at.
## A figure: [cut-out, from (painting u, v of its feet), to, height (part of the painting's height), t from, t to,
## mirror, bob, eye (u, v in the cut-out, or null), gone at].
var PANELS := [
	# ---- page 1 · the garden in the rain
	{"name": "garden_chase", "page": [0.0, 9.6], "rect": Rect2(0.035, 0.05, 0.93, 0.56), "img": "garden",
		"view": [Vector2(0.45, 0.6), 1.0, Vector2(0.42, 0.62), 0.8], "rain": true, "at": 0.15,
		"figs": [["rat_run", Vector2(0.1, 0.97), Vector2(0.33, 0.8), 0.1, 1.4, 7.5, false, 0.006, null, -1.0]]},
	{"name": "cat_eyes", "page": [0.0, 9.6], "rect": Rect2(0.035, 0.645, 0.6, 0.305), "img": "garden",
		"view": [Vector2(0.17, 0.58), 0.34, Vector2(0.2, 0.6), 0.3], "rain": true, "at": 3.9,
		"figs": [["cat_run", Vector2(-0.08, 0.9), Vector2(0.17, 0.88), 0.34, 3.9, 9.6, false, 0.008, Vector2(0.935, 0.205), -1.0]]},
	{"name": "warm_windows", "page": [0.0, 9.6], "rect": Rect2(0.665, 0.645, 0.3, 0.305), "img": "garden",
		"view": [Vector2(0.7, 0.3), 0.4, Vector2(0.72, 0.28), 0.3], "rain": true, "at": 6.6, "figs": []},
	# ---- page 2 · the hole at the foot of the wall
	{"name": "hole_dash", "page": [9.6, 14.6], "rect": Rect2(0.035, 0.05, 0.93, 0.56), "img": "hole",
		"view": [Vector2(0.55, 0.5), 0.95, Vector2(0.68, 0.48), 0.7], "rain": true, "at": 9.7,
		"figs": [["rat_run", Vector2(0.18, 0.86), Vector2(0.8, 0.585), 0.11, 9.8, 12.3, false, 0.006, null, 12.25]]},
	{"name": "cat_pounce", "page": [9.6, 14.6], "rect": Rect2(0.035, 0.645, 0.6, 0.305), "img": "hole",
		"view": [Vector2(0.72, 0.45), 0.42, Vector2(0.76, 0.44), 0.36], "rain": true, "at": 12.4,
		"figs": [["cat_pounce", Vector2(0.5, 0.63), Vector2(0.6, 0.6), 0.2, 12.4, 13.4, false, 0.0, Vector2(0.935, 0.2), -1.0]]},
	{"name": "cat_waits", "page": [9.6, 14.6], "rect": Rect2(0.665, 0.645, 0.3, 0.305), "img": "garden",
		"view": [Vector2(0.1, 0.55), 0.22, Vector2(0.1, 0.55), 0.2], "rain": true, "at": 13.2,
		"figs": [["cat_sit", Vector2(0.115, 0.68), Vector2(0.115, 0.68), 0.15, 13.2, 14.6, true, 0.0, Vector2(0.94, 0.18), -1.0]]},
	# ---- page 3 · inside the wall
	{"name": "blocked", "page": [14.6, 21.6], "rect": Rect2(0.035, 0.05, 0.56, 0.9), "img": "passage",
		"view": [Vector2(0.32, 0.5), 0.6, Vector2(0.3, 0.55), 0.5], "rain": false, "at": 14.7,
		"figs": [["rat_run", Vector2(0.26, 0.97), Vector2(0.36, 0.92), 0.2, 14.7, 17.0, false, 0.004, null, -1.0]]},
	{"name": "warm_light", "page": [14.6, 21.6], "rect": Rect2(0.625, 0.05, 0.34, 0.9), "img": "passage",
		"view": [Vector2(0.73, 0.5), 0.3, Vector2(0.74, 0.5), 0.22], "rain": false, "at": 18.8, "figs": []},
	# ---- page 4 · the burrow behind the kitchen
	{"name": "too_big", "page": [21.6, 27.6], "rect": Rect2(0.035, 0.05, 0.93, 0.9), "img": "burrow",
		"view": [Vector2(0.5, 0.5), 1.0, Vector2(0.62, 0.55), 0.72], "rain": false, "at": 21.7,
		"figs": [["rat_run", Vector2(0.52, 0.93), Vector2(0.64, 0.86), 0.13, 21.7, 24.0, false, 0.004, null, -1.0]]},
]

## The panels' own paintings (the figures drawn in, made for the panel): how each drifts — [centre from, width
## from, centre to, width to]. A panel not named here shows all of its painting with a slow push in.
const OWN_VIEW := {
	"garden_chase": [Vector2(0.45, 0.5), 1.0, Vector2(0.55, 0.55), 0.82],
	"cat_eyes": [Vector2(0.45, 0.52), 1.0, Vector2(0.55, 0.5), 0.85],
	"hole_dash": [Vector2(0.45, 0.55), 1.0, Vector2(0.62, 0.58), 0.8],
	"cat_pounce": [Vector2(0.5, 0.5), 1.0, Vector2(0.62, 0.52), 0.82],
	"cat_waits": [Vector2(0.5, 0.5), 1.0, Vector2(0.45, 0.5), 0.88],
	"blocked": [Vector2(0.35, 0.55), 1.0, Vector2(0.42, 0.55), 0.85],
	"too_big": [Vector2(0.5, 0.5), 1.0, Vector2(0.5, 0.42), 0.82],
}

## Captions: text, panel, where in it (0..1 of the panel, the box's top left), width (part of the panel), at.
var CAPTIONS := [
	["Night. Rain.", "garden_chase", Vector2(0.025, 0.05), 0.2, 0.4],
	["A rat runs for her life through the wet grass.", "garden_chase", Vector2(0.6, 0.05), 0.37, 2.0],
	["A street cat is right behind her.", "cat_eyes", Vector2(0.62, 0.07), 0.36, 4.5],
	["Ahead: a house, its windows warm with light.", "warm_windows", Vector2(0.05, 0.6), 0.9, 7.0],
	["A hole at the foot of the wall…", "hole_dash", Vector2(0.025, 0.05), 0.3, 10.0],
	["She slips through. Just in time.", "cat_pounce", Vector2(0.6, 0.07), 0.36, 12.8],
	["Out of the rain. Safe from the cat…", "blocked", Vector2(0.05, 0.04), 0.6, 15.0],
	["…but the way on is blocked.", "blocked", Vector2(0.35, 0.86), 0.6, 16.6],
	["From the other side comes a faint, warm light.", "warm_light", Vector2(0.08, 0.05), 0.84, 19.2],
	["A hole into a huge, bright kitchen.", "too_big", Vector2(0.025, 0.04), 0.36, 22.1],
	["Too big. Too frightening.", "too_big", Vector2(0.6, 0.86), 0.36, 24.3],
]

const APPEAR := 0.45
const PAGE_FADE := 0.5
const TYPE_CPS := 38.0

var _root: Control
var _bg: ColorRect
var _flash_rect: ColorRect
var _panels: Array = []  # {def, box, world, img, figs: [[def, node, eye]], rain, frame, own}
var _caps: Array = []  # {def, box, label, panel}
var _size := Vector2.ZERO
var _rain_shader: Shader
var _vig_shader: Shader
var _t := 0.0


func build() -> void:
	layer = 40
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bg = ColorRect.new()
	_bg.color = Color(0.055, 0.06, 0.075)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	_rain_shader = Shader.new()
	_rain_shader.code = RAIN
	_vig_shader = Shader.new()
	_vig_shader.code = VIGNETTE
	for d in PANELS:
		_panels.append(_make_panel(d))
	var font: Font = load(FONT) if ResourceLoader.exists(FONT) else null
	for c in CAPTIONS:
		var p: Dictionary = {}
		for q in _panels:
			if q.def.name == c[1]:
				p = q
		if p.is_empty():
			continue
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.94, 0.9, 0.8)
		sb.border_color = Color(0.13, 0.1, 0.08)
		sb.set_border_width_all(2)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 7
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(3, 3)
		box.add_theme_stylebox_override("panel", sb)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.text = c[0]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.15, 0.11, 0.09))
		if font:
			l.add_theme_font_override("font", font)
		l.visible_ratio = 0.0
		box.add_child(l)
		box.visible = false
		(p.holder as Control).add_child(box)
		_caps.append({"def": c, "box": box, "label": l, "panel": p})
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.85, 0.9, 1.0, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash_rect.material = add
	_root.add_child(_flash_rect)


func _make_panel(d: Dictionary) -> Dictionary:
	# a painting of the panel's own (the figures drawn in) beats the stage painting with cut-outs
	var own_path: String = DIR + str(d.name) + ".jpg"
	var own := ResourceLoader.exists(own_path)
	var tex: Texture2D = load(own_path if own else DIR + str(d.img) + ".jpg")
	var holder := Control.new()  # the panel with its frame and captions; moves as one
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	_root.add_child(holder)
	var shadow := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0.0)
	ss.shadow_color = Color(0, 0, 0, 0.6)
	ss.shadow_size = 14
	ss.shadow_offset = Vector2(5, 7)
	shadow.add_theme_stylebox_override("panel", ss)
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shadow)
	var clip := Control.new()
	clip.clip_contents = true
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var world := Control.new()  # the painting's own space: 1 unit = 1 texel
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(world)
	var img := TextureRect.new()
	img.texture = tex
	img.size = tex.get_size()
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(img)
	var figs: Array = []
	if not own:
		for f in d.figs:
			var fp: String = DIR + "cut_" + str(f[0]) + ".png"
			if not ResourceLoader.exists(fp):
				continue
			var ft: Texture2D = load(fp)
			var fr := TextureRect.new()
			fr.texture = ft
			fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fr.stretch_mode = TextureRect.STRETCH_SCALE
			fr.flip_h = bool(f[6])
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			world.add_child(fr)
			var eye: TextureRect = null
			if f[8] != null:  # a glint of the eye in the dark
				eye = TextureRect.new()
				var g := GradientTexture2D.new()
				g.fill = GradientTexture2D.FILL_RADIAL
				g.fill_from = Vector2(0.5, 0.5)
				g.fill_to = Vector2(1.0, 0.5)
				var gr := Gradient.new()
				gr.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
				gr.set_color(1, Color(0.9, 0.85, 0.2, 0.0))
				gr.add_point(0.25, Color(0.95, 0.85, 0.3, 0.85))
				g.gradient = gr
				g.width = 64
				g.height = 64
				eye.texture = g
				eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var am := CanvasItemMaterial.new()
				am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				eye.material = am
				world.add_child(eye)
			figs.append([f, fr, eye, ft.get_size()])
	var rain: ColorRect = null
	if bool(d.rain):
		rain = ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = _rain_shader
		rain.material = m
		rain.set_anchors_preset(Control.PRESET_FULL_RECT)
		rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(rain)
	var vig := ColorRect.new()
	var vm := ShaderMaterial.new()
	vm.shader = _vig_shader
	vig.material = vm
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(vig)
	var frame := Panel.new()
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.border_color = Color(0.93, 0.89, 0.8)
	fs.set_border_width_all(4)
	frame.add_theme_stylebox_override("panel", fs)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	return {"def": d, "holder": holder, "world": world, "tex": tex, "figs": figs, "rain": rain, "own": own}


func _layout() -> void:
	_size = _root.size
	var fsz := int(clampf(_size.y * 0.03, 13.0, 40.0))
	for p in _panels:
		var r: Rect2 = p.def.rect
		var h := p.holder as Control
		h.position = r.position * _size
		h.size = r.size * _size
		h.pivot_offset = h.size * 0.5
	for c in _caps:
		var ps: Vector2 = (c.panel.holder as Control).size
		var box := c.box as PanelContainer
		box.position = (c.def[2] as Vector2) * ps
		(c.label as Label).custom_minimum_size.x = float(c.def[3]) * ps.x - 24.0
		(c.label as Label).add_theme_font_size_override("font_size", fsz)
		box.reset_size()


## t: the prologue's clock; flash: the lightning, 0..1.
func tick(t: float, flash: float) -> void:
	if _root == null:
		return
	if _root.size != _size:
		_layout()
	var dt := clampf(t - _t, 0.0, 0.1)
	_t = t
	for p in _panels:
		var d: Dictionary = p.def
		var page: Array = d.page
		var h := p.holder as Control
		var on := t >= float(d.at) and t < float(page[1])
		h.visible = on
		if not on:
			continue
		# in: a little drop and settle; out: the whole page fades together
		var a := clampf((t - float(d.at)) / APPEAR, 0.0, 1.0)
		var out := clampf((float(page[1]) - t) / PAGE_FADE, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - a, 3.0)
		h.modulate.a = minf(e, out)
		h.scale = Vector2.ONE * lerpf(1.04, 1.0, e)
		h.position = (d.rect as Rect2).position * _size + Vector2(0, lerpf(-14.0, 0.0, e))
		# the painting drifts: centre and width, eased over the panel's life
		var life := clampf((t - float(d.at)) / maxf(float(page[1]) - float(d.at), 0.1), 0.0, 1.0)
		var k := smoothstep(0.0, 1.0, life)
		var v: Array = d.view if not p.own else OWN_VIEW.get(d.name, [Vector2(0.5, 0.5), 1.0, Vector2(0.5, 0.48), 0.9])
		var c: Vector2 = (v[0] as Vector2).lerp(v[2], k)
		var wpart := lerpf(float(v[1]), float(v[3]), k)
		var ts: Vector2 = (p.tex as Texture2D).get_size()
		var ps := h.size
		var vis_w := wpart * ts.x
		var vis_h := vis_w * ps.y / maxf(ps.x, 1.0)
		if vis_h > ts.y:  # (a tall panel: fit the height instead)
			vis_h = ts.y
			vis_w = vis_h * ps.x / maxf(ps.y, 1.0)
		var s := ps.x / vis_w
		var tl := c * ts - Vector2(vis_w, vis_h) * 0.5
		tl.x = clampf(tl.x, 0.0, ts.x - vis_w)
		tl.y = clampf(tl.y, 0.0, ts.y - vis_h)
		var w := p.world as Control
		w.scale = Vector2.ONE * s
		w.position = -tl * s
		# lightning: the painting itself flares a little (the figures stay black against it)
		var img := w.get_child(0) as TextureRect
		img.modulate = Color(1, 1, 1).lerp(Color(1.7, 1.75, 1.9), flash * (1.0 if p.rain else 0.0))
		for fg in p.figs:
			var f: Array = fg[0]
			var node := fg[1] as TextureRect
			var eye := fg[2] as TextureRect
			var fsz: Vector2 = fg[3]
			var fon := t >= float(f[4]) and (float(f[9]) < 0.0 or t < float(f[9]))
			node.visible = fon
			if eye: eye.visible = fon
			if not fon:
				continue
			var fk := clampf((t - float(f[4])) / maxf(float(f[5]) - float(f[4]), 0.1), 0.0, 1.0)
			var at: Vector2 = (f[1] as Vector2).lerp(f[2], fk) * ts
			var hh := float(f[3]) * ts.y
			# going toward the back of the picture (up it), smaller
			hh *= lerpf(1.0, 0.55, clampf(((f[1] as Vector2).y - (f[2] as Vector2).y) * 3.0 * fk, 0.0, 1.0))
			var ww := hh * fsz.x / fsz.y
			var bob := float(f[7]) * ts.y * absf(sin(t * 11.0)) if fk < 1.0 else 0.0
			node.size = Vector2(ww, hh)
			node.position = at - Vector2(ww * 0.5, hh + bob)
			if eye:
				var ev: Vector2 = f[8]
				if bool(f[6]): ev.x = 1.0 - ev.x
				var er := hh * 0.09 * (1.0 + flash * 0.6 + 0.12 * sin(t * 5.0))
				eye.size = Vector2(er, er)
				eye.position = node.position + ev * Vector2(ww, hh) - eye.size * 0.5
		if p.rain:
			var m := (p.rain as ColorRect).material as ShaderMaterial
			m.set_shader_parameter("t", t)
			m.set_shader_parameter("aspect", ps.x / maxf(ps.y, 1.0))
	for cp in _caps:
		var cd: Array = cp.def
		var box := cp.box as PanelContainer
		var on: bool = (cp.panel.holder as Control).visible and t >= float(cd[4])
		box.visible = on
		if on:
			var l := cp.label as Label
			l.visible_ratio = clampf((t - float(cd[4])) * TYPE_CPS / maxf(float(l.text.length()), 1.0), 0.0, 1.0)
			box.modulate.a = clampf((t - float(cd[4])) / 0.2, 0.0, 1.0)
	_flash_rect.color.a = flash * flash * 0.35
	var _unused := dt


const RAIN := """
shader_type canvas_item;
uniform float t = 0.0;
uniform float aspect = 1.7;
float h(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float layer(vec2 uv, float cols, float speed, float len, float seed) {
	uv.x += uv.y * 0.16;
	float c = floor(uv.x * cols);
	float r = h(c + seed);
	float x = fract(uv.x * cols);
	float y = fract(uv.y * 0.9 - t * speed * (0.8 + 0.4 * r) - r * 9.0);
	float line = smoothstep(0.5 - 0.06, 0.5, x) * smoothstep(0.5 + 0.06, 0.5, x);
	float drop = smoothstep(0.0, len * 0.3, y) * smoothstep(len, len * 0.6, y);
	return line * drop * step(0.45, h(c * 1.7 + seed));
}
void fragment() {
	vec2 uv = vec2(UV.x * aspect, UV.y);
	float a = layer(uv, 70.0, 1.9, 0.09, 1.0) * 0.55 + layer(uv, 130.0, 1.4, 0.05, 7.0) * 0.35;
	COLOR = vec4(0.82, 0.87, 0.97, a * 0.55);
}
"""

const VIGNETTE := """
shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.32, 0.75, length(d * vec2(1.0, 1.25)));
	float grain = (h(floor(FRAGCOORD.xy * 0.5)) - 0.5) * 0.06;
	COLOR = vec4(0.04, 0.03, 0.05, clamp(v * 0.55 + grain, 0.0, 1.0));
}
"""
