class_name RoomFurniture
extends RefCounted
## Builds a room's furniture from the night's furn list (levels.js livingFurniture, pantryFurniture, diningFurniture…),
## like the prototype's builder B[t]: each entry is a rect (x, y = north-west corner, w along x, h along y, in cm).
## Pieces against a wall face into the room. Also the per-room decor (rugs, wall art) and the flickering lights.

var b: LevelBuilder
var g: Game
var _lamp_done := false  # the pantry wall lamp goes up once, by the first washer


func _init(builder: LevelBuilder) -> void:
	b = builder
	g = builder.g


static func W(x: float, y: float, h := 0.0) -> Vector3:
	return Nights.world(x, y, h)


## Which wall a rect stands against: n, s, w, e or "" (free-standing).
static func side(x: float, y: float, w: float, h: float) -> String:
	var west := x <= 4.0
	var east := x + w >= 956.0
	var north := y <= 4.0
	var south := y + h >= 596.0
	if (west or east) and (h > w or not (north or south)):
		return "w" if west else "e"
	if north: return "n"
	if south: return "s"
	if west: return "w"
	if east: return "e"
	return ""


static func side_rot(s: String) -> float:
	match s:
		"s": return 180.0
		"w": return 90.0
		"e": return -90.0
	return 0.0


## A model fitted to the rect (its front toward the room), with collision and a surface id.
func place(model: String, f: Dictionary, surface: String, height := 0.0, rot = null, tex := "") -> Node3D:
	var x := float(f.x); var y := float(f.y)
	var w := float(f.get("w", 0)); var d := float(f.get("h", 0))
	var r: float = rot if rot != null else side_rot(side(x, y, w, d))
	var at := W(x + w / 2.0, y + d / 2.0)
	if surface in ["washer", "boiler"]:
		at += _gap_behind(x, y, w, d)
	var n := b.spawn(model, at, r, b.furn)
	if n == null:
		return null
	if absf(absf(r) - 90.0) < 1.0:
		b.fit(n, d, w)
	else:
		b.fit(n, w, d)
	if height > 0.0:
		_fit_height(n, height)
	b.collide(n, surface)
	if tex != "":
		# demo polish: a real surface for the model (fabric sofa, cardboard box, ...), tinted by the
		# night's own colour for the piece when it has one
		var tint := LevelBuilder.hex(int(f.get("color", 0xffffff))) if f.has("color") else Color.WHITE
		b.apply_texture(n, tex, tint)
	return n


## Round 16 (asked: "move the fridge, the washing machines and so on away from the wall, so the rat can hide
## behind them"): a big piece standing against a wall is pulled out until there is a 15 cm gap behind it — room
## for her, not for the cat — and the gap is a hiding place. Returns the shift (world metres).
const GAP := 24.0   # cm from the room's edge: the walls take the first 7, so this leaves her ~17 cm
const WALL := 7.0

func _gap_behind(x: float, y: float, w: float, d: float) -> Vector3:
	var shift := Vector3.ZERO
	var gx := x + w / 2.0
	var gy := y + d / 2.0
	var gw := w
	var gd := d
	match side(x, y, w, d) if side(x, y, w, d) != "" else _nearest_wall(x, y, w, d):
		"n":
			shift.z = maxf(GAP - y, 0.0) / 100.0
			gy = (GAP + WALL) / 2.0
			gd = GAP - WALL - 2.0
		"s":
			shift.z = -maxf(GAP - (600.0 - y - d), 0.0) / 100.0
			gy = 600.0 - (GAP + WALL) / 2.0
			gd = GAP - WALL - 2.0
		"w":
			shift.x = maxf(GAP - x, 0.0) / 100.0
			gx = (GAP + WALL) / 2.0
			gw = GAP - WALL - 2.0
		"e":
			shift.x = -maxf(GAP - (960.0 - x - w), 0.0) / 100.0
			gx = 960.0 - (GAP + WALL) / 2.0
			gw = GAP - WALL - 2.0
		_:
			return Vector3.ZERO
	b._hide("behind", gx, gy, gw, gd)
	return shift


func _nearest_wall(x: float, y: float, w: float, d: float) -> String:
	var dist := {"n": y, "s": 600.0 - y - d, "w": x, "e": 960.0 - x - w}
	var best := "n"
	for k in dist:
		if dist[k] < dist[best]:
			best = k
	return best if dist[best] < 40.0 else ""


func _fit_height(n: Node3D, h_cm: float) -> void:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if LevelBuilder._soft(m.name):
			continue
		var bb: AABB = (inv * m.global_transform) * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if box.size.y > 0.001:
		n.scale.y *= h_cm / 100.0 / box.size.y


func hide(kind: String, f: Dictionary, inset := 8.0) -> void:
	var w := float(f.get("w", 32)); var d := float(f.get("h", 32))
	b._hide(kind, float(f.x) + w / 2.0, float(f.y) + d / 2.0, maxf(16.0, w - inset * 2.0), maxf(16.0, d - inset * 2.0))


## Under a sofa or an armchair there's only room for a crouching rat: an invisible slab 10 cm up stops her unless she
## sneaks (crouched she is lower).
func low_roof(f: Dictionary, inset: float) -> void:
	var w := float(f.get("w", 32)); var d := float(f.get("h", 32))
	var slab := b.box("Low clearance", W(float(f.x) + w / 2.0, float(f.y) + d / 2.0, 11.5), Vector3((w - inset * 2.0) / 100.0, 0.03, (d - inset * 2.0) / 100.0), b.mat(Color.BLACK), b.furn)
	slab.visible = false


## Round 7 (asked): a small wall lamp on the north wall by the washing machines —
## the pantry had NO light sources of its own at all. Plate, enamel shade, warm bulb.
func _washer_wall_lamp(lx: float) -> void:
	b.box("Wall lamp plate", W(lx, 3, 168), Vector3(0.12, 0.2, 0.03), b.mat(LevelBuilder.hex(0x2e2a26)), b.furn, false)
	var shade := MeshInstance3D.new()
	shade.name = "Wall lamp shade"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.08
	cm.height = 0.09
	shade.mesh = cm
	shade.material_override = b.mat(LevelBuilder.hex(0x274435))
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.furn.add_child(shade)
	shade.global_position = W(lx, 10, 161)
	var bulb := MeshInstance3D.new()
	bulb.name = "Wall lamp bulb"
	var sm := SphereMesh.new()
	sm.radius = 0.02
	sm.height = 0.04
	bulb.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color8(0xff, 0xc2, 0x7a)
	bulb.material_override = bmat
	b.furn.add_child(bulb)
	bulb.global_position = W(lx, 10, 156)
	light(W(lx, 16, 148), Color8(0xff, 0xc2, 0x7a), 0.95, 3.4, "steady")


## Round 8 (asked): a MOVING fire in the fireplace — the flickering light alone
## read as a lamp behind glass. CPU flame particles: they rise, shrink and die,
## orange to ember-red, additively blended over the logs.
## A fire in the grate (round 16, asked: "add a moving fire to the fireplace"): three crossed logs on a bed of
## glowing embers, five tongues of flame that lick and flicker (each its own phase and height), and sparks.
const FLAME := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;
uniform float seed = 0.0;
uniform float hot = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	// stands upright and turns to face the camera (a billboard around the vertical)
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = normalize(cross(side, vec3(0.0, 1.0, 0.0)));
	mat4 bb = mat4(vec4(side * length(MODEL_MATRIX[0].xyz), 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(fwd * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}
void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);  // 0 at the base, 1 at the tip
	float t = TIME * 1.7 + seed * 7.3;
	float n = noise(vec2(uv.x * 3.0 + seed * 5.0, uv.y * 3.5 - t * 2.3));
	float n2 = noise(vec2(uv.x * 7.0 - seed * 3.0, uv.y * 8.0 - t * 3.4));
	float x = uv.x - 0.5 + (n - 0.5) * 0.42 * uv.y + (n2 - 0.5) * 0.1;
	float w = 0.5 * pow(clamp(uv.y, 0.0, 1.0), 0.28) * (1.0 - uv.y * 0.92);
	float d = abs(x) / max(w, 0.001);
	float tip = uv.y + (n - 0.5) * 0.3 + (n2 - 0.5) * 0.12;
	float body = smoothstep(1.0, 0.5, d) * smoothstep(0.98, 0.62, tip);
	float core = smoothstep(0.6, 0.05, d) * smoothstep(0.58, 0.12, tip);
	vec3 col = mix(vec3(0.9, 0.24, 0.04), vec3(1.0, 0.55, 0.1), smoothstep(0.0, 0.7, body));
	col = mix(col, vec3(1.0, 0.92, 0.62), core);
	ALBEDO = col * body * hot * 1.35;
}
"""
static var _flame_shader: Shader


func _fire(at: Vector3, len_cm: float, wall := "n") -> void:
	var grp := Node3D.new()
	grp.name = "Fireplace fire"
	b.furn.add_child(grp)
	grp.global_position = at
	# local +z points out of the fireplace into the room
	grp.rotation.y = {"w": PI / 2.0, "e": -PI / 2.0, "s": PI}.get(wall, 0.0)
	var span := clampf(len_cm / 100.0 * 0.45, 0.28, 0.6)
	# embers: a low glowing mound
	var em := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 6
	em.mesh = sm
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(1.0, 0.42, 0.1)
	em.material_override = emat
	grp.add_child(em)
	em.scale = Vector3(span, 0.035, 0.2)
	em.position = Vector3(0, -0.02, 0)
	# logs: two side by side and one across them, bark outside, charred ends
	var bark := b._paint(Color(0.3, 0.18, 0.11))
	var char_m := b._paint(Color(0.12, 0.08, 0.07))
	var logs := [[Vector3(0, 0.01, -0.045), Vector3(0, 0, 90), span * 0.9], [Vector3(0.02, 0.01, 0.05), Vector3(0, 8, 90), span * 0.85],
			[Vector3(-0.03, 0.06, 0.0), Vector3(0, 70, 90), span * 0.6]]
	for lg in logs:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.038
		cm.height = lg[2]
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = bark
		grp.add_child(mi)
		mi.position = lg[0]
		mi.rotation_degrees = lg[1]
		for e in [-1.0, 1.0]:
			var cap := MeshInstance3D.new()
			var ccm := CylinderMesh.new()
			ccm.top_radius = 0.036
			ccm.bottom_radius = 0.036
			ccm.height = 0.012
			ccm.radial_segments = 10
			cap.mesh = ccm
			cap.material_override = char_m
			mi.add_child(cap)
			cap.position = Vector3(0, e * float(lg[2]) * 0.5, 0)
	# flames
	if _flame_shader == null:
		_flame_shader = Shader.new()
		_flame_shader.code = FLAME
	var flames := [[-0.42, 0.75, 0.13], [-0.18, 1.0, 0.71], [0.05, 1.18, 0.37], [0.26, 0.95, 0.93], [0.45, 0.7, 0.52]]
	for fl in flames:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.24, 0.32)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = _flame_shader
		m.set_shader_parameter("seed", fl[2])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grp.add_child(mi)
		var hgt: float = fl[1]
		mi.scale = Vector3(0.9 + hgt * 0.2, hgt, 1.0)
		mi.position = Vector3(float(fl[0]) * span * 0.85, 0.02 + 0.15 * hgt, 0.045 + (float(fl[2]) - 0.5) * 0.03)
	for mi in grp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# sparks rising out of it now and then
	var e := CPUParticles3D.new()
	e.name = "Sparks"
	e.amount = 10
	e.lifetime = 1.3
	e.local_coords = false
	e.direction = Vector3.UP
	e.spread = 18.0
	e.gravity = Vector3(0, 0.15, 0)
	e.initial_velocity_min = 0.25
	e.initial_velocity_max = 0.5
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(span * 0.4, 0.02, 0.05)
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	gr.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	e.color_ramp = gr
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.012, 0.012)
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m2.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m2.vertex_color_use_as_albedo = true
	m2.albedo_texture = _soft_disc()
	q2.material = m2
	e.mesh = q2
	grp.add_child(e)
	e.position = Vector3(0, 0.1, 0)


func _soft_disc() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) ** 1.5))
	return ImageTexture.create_from_image(img)


func light(at: Vector3, color: Color, energy: float, rng: float, kind := "fire") -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	# round 10 (the lighting pass): every practical falls off into a pool — the
	# fire tightest, the TV softest — so rooms read as islands of motivated light
	l.omni_attenuation = {"fire": 1.35, "tv": 1.15, "garland": 1.25}.get(kind, 1.3)
	l.shadow_enabled = kind != "tv"
	b.root.add_child(l)
	l.global_position = at
	g.flickers.append([l, energy, kind])
	return l


func _kid_bed(f: Dictionary) -> bool:
	for z in g.night.get("sleepers", []):
		if str(z.get("kind", "")) == "kid" and float(z.x) >= float(f.x) and float(z.x) <= float(f.x) + float(f.w) and float(z.y) >= float(f.y) and float(z.y) <= float(f.y) + float(f.h):
			return true
	return false


# ---------- furniture ----------

func build(list: Array) -> void:
	for f in list:
		var t := str(f.t)
		var x := float(f.x); var y := float(f.y)
		var w := float(f.get("w", 0)); var d := float(f.get("h", 0))
		var cx := x + w / 2.0; var cy := y + d / 2.0
		match t:
			"counter":
				var n := maxi(1, roundi(w / 63.0))
				for i in n:
					var seg := {"x": x + w / n * i, "y": y, "w": w / n, "h": d}
					place("furniture/counter_section", seg, "counter", 0.0, 0.0)
			"fridge": place("furniture/fridge", f, "fridge", 0.0, null, "metal_matte")
			"island": place("furniture/kitchen_island", f, "island", 0.0, 180.0)
			"box":
				var ht := float(f.get("ht", 44))
				place("furniture/cardboard_box_tall" if ht > 70.0 else "furniture/cardboard_box", f, "box", ht, null, "cardboard")
			"crate": place("furniture/crate", f, "crate", float(f.get("ht", 40)), null, "wood_dark")
			"table":
				var ht := float(f.get("ht", 79))
				var model := "furniture/table_dining" if bool(f.get("dining", false)) else "furniture/table_kitchen"
				if _kid_bed(f):
					place("furniture/bed_kid", f, "bed", 0.0, 0.0)
					continue  # the bed sits on the floor: nothing to hide under
				elif absf(ht - 75.0) < 1.0:
					place("furniture/desk", f, "table", 0.0, 0.0)
				else:
					var n := place(model, f, "table", 0.0, 0.0)
					var cloth := n.find_child("tablecloth*", true, false) as Node3D if n else null
					if cloth and int(f.get("cloth", 0)) == 0:
						cloth.queue_free()
					elif cloth and bool(f.get("dining", false)):
						# round 11 (asked, night 8): the model's pale cloth threw the
						# ceiling light back like a mirror. A deep wine cloth, fully
						# matte — the glare is gone and the dining room gains a colour.
						var clothmat := StandardMaterial3D.new()
						clothmat.albedo_color = Color(0.4, 0.12, 0.15)
						clothmat.albedo_texture = TextureLib.get_texture("fabric")
						if clothmat.albedo_texture:
							clothmat.uv1_scale = Vector3(4, 4, 4)
						clothmat.roughness = 0.96
						clothmat.metallic_specular = 0.08
						clothmat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
						# (the model's "tablecloth" node IS the mesh: looking only among its children found nothing,
						# and the cloth stayed glaring white)
						var meshes := cloth.find_children("*", "MeshInstance3D", true, false)
						if cloth is MeshInstance3D:
							meshes.append(cloth)
						for mi in meshes:
							(mi as MeshInstance3D).material_override = clothmat
					if bool(f.get("dining", false)):
						light(W(cx, cy, ht + 60), Color8(0xff, 0xb0, 0x60), 0.7, 3.0)
				hide("table", f)
			"coffeeTable":
				place("furniture/coffee_table", f, "table", 0.0, 0.0, "wood_dark")
				hide("table", f)
				# round 5: something to hide AMONG under the coffee table, not bare floor
				# (at the zone's edge — the middle stays clear for her)
				b.collide(b.spawn("props/small_box", W(float(f.x) + 26.0, float(f.y) + float(f.h) / 2.0), 12.0, b.furn))
			"bench":
				place("furniture/workbench", f, "table", 0.0, 0.0, "wood_dark")
				hide("table", f)
			"chair":
				var cf := {"x": x, "y": y, "w": 32, "h": 32}
				var back := str(f.get("back", "n"))
				var r := 0.0
				match back:
					"s": r = 180.0
					"w": r = 90.0
					"e": r = -90.0
				var n := b.spawn("furniture/chair", W(x + 16, y + 16), r, b.furn)
				b.collide(n, "chair")
				hide("chair", cf, 2.0)
			"stool":
				b.collide(b.spawn("furniture/stool", W(x + 18, y + 18), 0.0, b.furn), "stool")
				hide("stool", {"x": x, "y": y, "w": 36, "h": 36}, 3.0)
			"lowShelf":
				place("furniture/low_shelf", f, "lowShelf")
				hide("shelf", f, 4.0)
			"sofa", "armchair":
				var face := str(f.get("face", "s"))
				var r := 180.0 if face == "n" else (90.0 if face == "e" else (-90.0 if face == "w" else 0.0))
				place("furniture/sofa" if t == "sofa" else "furniture/armchair", f, "sofa", 0.0, r, "fabric")
				hide("sofa", f, 12.0)
				low_roof(f, 4.0)
			"wall":
				var wm := b.mat(LevelBuilder.hex(0x8a8a9a), "wall_" + str(g.night.get("pal", {}).get("wall", "stripes")))
				b.box("Inner wall", W(cx, cy, 115), Vector3(w / 100.0, 2.3, d / 100.0), wm, b.furn)
			"tvStand":
				place("furniture/tv_stand", f, "tv", 0.0, null, "wood_dark")
				var tv := light(W(cx, y + d + 70, 90), Color(0.56, 0.7, 1.0), 1.6, 4.6, "tv")
				g.tv_light = tv
				tv.visible = not bool(g.night.get("tvOff", false))
			"bookcase": place("furniture/bookcase", f, "bookcase", 0.0, null, "wood_dark")
			"fireplace":
				place("furniture/fireplace", f, "fireplace")
				var out := W(x + w + 30, cy, 40) if side(x, y, w, d) == "w" else W(cx, cy, 40)
				light(out, Color8(0xff, 0x8a, 0x3a), 2.2, 4.2)
				var fside := side(x, y, w, d)
				# at the front of the firebox, not in the middle of the model's footprint (it was inside the brickwork)
				var fat := W(cx, cy, 6)
				match fside:
					"w": fat = W(x + w - 8.0, cy, 6)
					"e": fat = W(x + 8.0, cy, 6)
					"n": fat = W(cx, y + d - 8.0, 6)
					"s": fat = W(cx, y + 8.0, 6)
				_fire(fat, d if fside in ["w", "e"] else w, fside)
			"sideTable": place("furniture/side_table", f, "side", float(f.get("ht", 60)), null, "wood_dark")
			"lamp":
				b.floor_lamp(W(cx, cy), true)
				# round 8 (asked): in the living room the floor lamp sits by the garland
				# and out-shouts it — dimmed there, untouched elsewhere
				if str(g.night.get("decor", "")) == "living":
					light(W(cx, cy, 138), Color8(0xff, 0xc2, 0x7a), 0.7, 3.0, "steady")
				else:
					light(W(cx, cy, 138), Color8(0xff, 0xc2, 0x7a), 1.3, 3.8, "steady")
			"plant":
				var pn := b.spawn("furniture/plant", W(cx, cy), randf() * 360.0, b.furn)
				b.collide(pn)
				if pn:
					g.plants.append([pn, pn.rotation, randf() * TAU])  # round 12: it sways
			"washer":
				place("furniture/dryer" if bool(f.get("dryer", false)) else "furniture/washer", f, "washer", 0.0, null, "plastic")
				if not _lamp_done:
					_lamp_done = true
					_washer_wall_lamp(x - 160.0)
			"basket": place("furniture/laundry_basket", f, "basket", float(f.get("ht", 45)), null, "plastic")
			"cans": place("furniture/cans_stack", f, "cans", float(f.get("ht", 30)))
			"shelfUnit": place("furniture/shelf_unit", f, "shelf", 0.0, null, "wood")
			"boiler":
				place("furniture/boiler", f, "boiler", 0.0, -90.0 if x > 480.0 else 90.0)
				light(W(cx - 50, cy, 40), Color8(0xff, 0x8a, 0x3a), 1.4, 3.0)
			"sideboard": place("furniture/sideboard", f, "sideboard", 0.0, null, "wood_dark")
			"cabinetTall":
				# modelled long along its own Z, front toward +X: as is against the west wall
				var n := b.spawn("furniture/cabinet_tall", W(cx, cy) + _gap_behind(x, y, w, d), 0.0 if x < 480.0 else 180.0, b.furn)
				b.fit(n, w, d)
				b.collide(n)
			"ottoman": place("furniture/ottoman", f, "ottoman", 0.0, 0.0, "fabric")
			"barCart": place("furniture/bar_cart", f, "cart", 0.0, 0.0)
			_:
				push_warning("Kitchen Rat: no builder for furniture " + t)
	# round 3: a plug-in night light in the living rooms — a small warm source you can actually see
	# by the wall, so the room's light reads: moon from the window, this amber glow below
	var living := false
	var anchor: Dictionary = {}
	for f2 in list:
		if str(f2.t) in ["sofa", "tvStand", "armchair"]:
			living = true
		if str(f2.t) == "tvStand":
			anchor = f2
	if living:
		var af: Dictionary = anchor if not anchor.is_empty() else list[0]
		var ax := float(af.x) + float(af.get("w", 40)) / 2.0
		var ay := float(af.y) + float(af.get("h", 40)) + 6.0
		var nl_mat := StandardMaterial3D.new()
		nl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nl_mat.albedo_color = Color(1.0, 0.62, 0.3)
		var nl := MeshInstance3D.new()
		nl.name = "Night light"
		var nm := BoxMesh.new()
		nm.size = Vector3(0.07, 0.1, 0.04)
		nl.mesh = nm
		nl.material_override = nl_mat
		b.furn.add_child(nl)
		nl.global_position = W(ax, ay, 16)
		light(W(ax, ay, 30), Color(1.0, 0.58, 0.28), 0.65, 2.6, "steady")
		# rounds 5-6: a garland along the south wall in TWO SAGGING SWAGS (a dead-straight
		# wire at the ceiling read as decoration in a shop window) — coloured bulbs on
		# little drops, pulsing in a slow travelling wave (game.gd pulses the emission
		# and the one real light among them, kind "garland")
		var bulb_cols := [Color(1, 0.3, 0.2), Color(1, 0.75, 0.25), Color(0.35, 1, 0.45), Color(0.35, 0.55, 1)]
		var pts: Array = []
		var SEG := 28
		for i in SEG + 1:
			var fx := lerpf(120.0, 840.0, float(i) / SEG)
			var hang := 0.5 - 0.5 * cos(TAU * 2.0 * float(i) / SEG)  # 0 at the pins, 1 at a swag's bottom
			pts.append(Vector2(fx, 234.0 - hang * 34.0))
		var wire_mat := b.mat(Color(0.05, 0.05, 0.06))
		for i in SEG:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var seg := MeshInstance3D.new()
			seg.name = "Garland wire"
			var bm := BoxMesh.new()
			bm.size = Vector3(p0.distance_to(p1) / 100.0 + 0.01, 0.008, 0.008)
			seg.mesh = bm
			seg.material_override = wire_mat
			b.furn.add_child(seg)
			seg.global_position = W((p0.x + p1.x) / 2.0, 588, (p0.y + p1.y) / 2.0)
			seg.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)
		var bi := 0
		for i in range(0, SEG + 1, 2):
			var p: Vector2 = pts[i]
			var sock := MeshInstance3D.new()
			sock.name = "Garland socket"
			var cm := CylinderMesh.new()
			cm.top_radius = 0.008
			cm.bottom_radius = 0.01
			cm.height = 0.05
			sock.mesh = cm
			sock.material_override = wire_mat
			b.furn.add_child(sock)
			sock.global_position = W(p.x, 588, p.y - 2.5)
			var bmat := StandardMaterial3D.new()
			var bc: Color = bulb_cols[bi % bulb_cols.size()]
			bmat.albedo_color = bc
			bmat.emission_enabled = true
			bmat.emission = bc
			bmat.emission_energy_multiplier = 1.2
			var bulb := MeshInstance3D.new()
			bulb.name = "Garland bulb"
			var sm := SphereMesh.new()
			sm.radius = 0.026
			sm.height = 0.052
			bulb.mesh = sm
			bulb.material_override = bmat
			b.furn.add_child(bulb)
			bulb.global_position = W(p.x, 588, p.y - 7.5)
			g.garland.append([bmat, float(bi % 4) * (TAU / 4.0)])  # round 7: four switching groups, not a phase smear
			bi += 1
		light(W(480, 585, 205), Color(1.0, 0.8, 0.55), 1.05, 5.2, "garland")


# ---------- decor ----------

func decor(kind: String) -> void:
	dress(kind)
	match kind:
		"living":
			_rug("rooms/rug_diamond", 480, 280, 440, 250)
			_hang(["rooms/wall_art_landscape", "rooms/wall_clock"])
		"dining":
			_rug("rooms/rug_stripes", 480, 280, 420, 260)
			_hang(["rooms/wall_art_portrait", "rooms/wall_art_flowers"])
		"pantry":
			for p in [[20, 300], [30, 450]]:
				b.collide(b.spawn("props/grain_sack", W(p[0] + 4, p[1]), randf() * 360.0, b.decor))
			b.collide(b.spawn("props/bucket_mop", W(600, 560), 20.0, b.decor))


## Hang pictures on the north wall where there's no window and nothing tall in front.
func _hang(models: Array) -> void:
	var win: Dictionary = g.night.get("window", {})
	var wx := float(win.get("x", -999)); var ww := float(win.get("w", 0))
	var i := 0
	for x in [190.0, 470.0, 760.0, 920.0, 330.0]:
		if i >= models.size():
			return
		if ww > 0.0 and x > wx - 60.0 and x < wx + ww + 60.0:
			continue
		var tall := false
		for f in g.night.get("furn", []):
			if float(f.y) < 60.0 and x > float(f.x) - 40.0 and x < float(f.x) + float(f.get("w", 40)) + 40.0 and str(f.t) in ["bookcase", "shelfUnit", "tvStand", "cabinetTall", "plant", "wall"]:
				tall = true
		if tall:
			continue
		if models[i] == "rooms/wall_clock":
			b.add_working_clock(W(x, 4, 175), 0.0)  # round 5: working hands, the night's real time
		else:
			_art(models[i], x, 175.0)
		i += 1


func _rug(model: String, x: float, y: float, w: float, d: float) -> void:
	var n := b.spawn(model, W(x, y, 0.2), 0.0, b.decor)
	b.fit(n, w, d)


## Wall art on the north wall at x (cm), its centre h cm up.
func _art(model: String, x: float, h: float) -> void:
	var n := b.spawn(model, W(x, 2, h), 0.0, b.decor)
	if n:
		var bb := LevelBuilder.aabb_of(n)
		n.global_position.y = h / 100.0 - bb.size.y / 2.0


# ---------- dressing a room (like night 1): a second level on the walls, pictures, plants ----------

## Shelf props by room: what stands on the wall shelves.
const SHELF_PROPS := {
	"living": ["props/small_box", "props/jar", "rooms/kettle"],
	"dining": ["props/mug", "props/glass", "props/bottle"],
	"pantry": ["props/can", "props/jar", "props/bottle"],
	"kids": ["props/ball", "props/squeaky_toy", "props/lego_bricks"],
}
const ART := ["rooms/wall_art_landscape", "rooms/wall_art_flowers", "rooms/wall_art_portrait", "rooms/wall_clock"]

var _inner := {}  # wall → its inside face, in cm from the room edge


## Two climbable wall shelves (floor → 55 cm → 100 cm), pictures on free walls and a plant / lamp in free corners.
## Everything goes only where there's room and away from the door, the mouse hole, cracks, food and traps.
func dress(kind: String) -> void:
	if bool(g.night.get("kitchenUpper", false)) or kind == "kitchen":
		return
	var props: Array = SHELF_PROPS.get("kids" if int(g.night.number) == 13 else kind, SHELF_PROPS.living)
	for wall in ["n", "s", "w", "e"]:
		_inner[wall] = _probe_inner(wall)
	var placed := 0
	for wall in ["w", "e", "n", "s"]:
		if placed < 2 and _shelf_pair(wall, props):
			placed += 1
	var arts := ART.duplicate()
	if kind == "living":
		arts.erase("rooms/wall_clock")  # it already has one
	var ai := 0
	for wall in ["s", "w", "e", "n"]:
		for along in range(120, 900, 150):
			if ai >= 3:
				break
			if _art_at(wall, float(along), arts[ai % arts.size()]):
				ai += 1
	var extras := ["furniture/plant", "furniture/plant", "furniture/floor_lamp"]  # round 12 (asked): more houseplants — two per dressed room, not one
	var ei := 0
	for c in [[60, 60], [900, 60], [60, 540], [900, 540], [480, 560], [60, 300]]:
		if ei >= extras.size():
			break
		if _floor_item(extras[ei], float(c[0]), float(c[1])):
			ei += 1


## How far the wall's inside face is from the room's edge (cm). Several rays along the wall, from near it, and the
## nearest hit wins: one ray from the middle of the room can hit a tall bookcase instead, and the shelves then
## hung in mid-air in the middle of the room (night 4).
func _probe_inner(wall: String) -> float:
	var best := INF
	var length := 600.0 if wall in ["w", "e"] else 960.0
	for k in 7:
		var along := length * (k + 1) / 8.0
		var from: Vector3; var to: Vector3
		match wall:
			"n": from = W(along, 60, 150); to = W(along, -60, 150)
			"s": from = W(along, 540, 150); to = W(along, 660, 150)
			"w": from = W(60, along, 150); to = W(-60, along, 150)
			_: from = W(900, along, 150); to = W(1020, along, 150)
		var hit := g.ray(from, to)
		if hit.is_empty():
			continue
		var p: Vector3 = hit.position
		var d: float
		match wall:
			"n": d = (p.z + 3.0) * 100.0
			"s": d = 600.0 - (p.z + 3.0) * 100.0
			"w": d = (p.x + 4.8) * 100.0
			_: d = 960.0 - (p.x + 4.8) * 100.0
		best = minf(best, d)
	return clampf(best, 0.0, 20.0) if best < INF else 0.0


## A point on a wall: `along` cm along it, `out` cm into the room from its inside face, h cm up. And the rotation
## that faces into the room.
func _wall_pt(wall: String, along: float, out: float, h: float) -> Vector3:
	var i: float = _inner.get(wall, 0.0) + out
	match wall:
		"n": return W(along, i, h)
		"s": return W(along, 600.0 - i, h)
		"w": return W(i, along, h)
		_: return W(960.0 - i, along, h)


func _wall_rot(wall: String) -> float:
	return {"n": 0.0, "s": 180.0, "w": 90.0, "e": -90.0}[wall]


## Too close to something the night needs (cm): the door, the mouse hole, cracks, food, traps, things to knock over.
func _busy(p: Vector3, r_cm: float) -> bool:
	var x := (p.x + 4.8) * 100.0
	var y := (p.z + 3.0) * 100.0
	var door := float(g.night.get("door", 300))
	if x > 860.0 and absf(y - door) < 80.0 + r_cm:
		return true
	if y > 500.0 and absf(x - 180.0) < 70.0 + r_cm:
		return true
	var win: Dictionary = g.night.get("window", {})
	if y < 60.0 and float(win.get("w", 0)) > 0.0 and x > float(win.x) - 40.0 - r_cm and x < float(win.x) + float(win.w) + 40.0 + r_cm:
		return true
	for c in g.cracks:
		if Vector2(c.x - p.x, c.z - p.z).length() * 100.0 < 50.0 + r_cm:
			return true
	var spots: Array = (g.night.get("food", {}) as Dictionary).get("spots", [])
	for lst in [spots, g.night.get("knocks", []), g.night.get("trapSpots", []), g.night.get("props", [])]:
		for s in lst:
			if s is Dictionary and s.has("x") and Vector2(float(s.x) - x, float(s.y) - y).length() < 45.0 + r_cm:
				return true
	return false


func _free_box(center: Vector3, size_cm: Vector3) -> bool:
	return g.box_free(center, size_cm / 200.0)


## Two shelves on a wall, the low one reachable from the floor and the high one from the low one.
func _shelf_pair(wall: String, props: Array) -> bool:
	var length := 540.0 if wall in ["w", "e"] else 880.0
	var along := 60.0
	while along + 125.0 < length:
		var a := _wall_pt(wall, along + 35.0, 12.0, 54.0)
		var bb := _wall_pt(wall, along + 85.0, 12.0, 99.0)
		var front := _wall_pt(wall, along + 35.0, 40.0, 25.0)
		var side := wall in ["w", "e"]
		var sz := Vector3(22, 30, 72) if side else Vector3(72, 30, 22)
		if not _busy(a, 50.0) and not _busy(bb, 50.0) and _free_box(a + Vector3.UP * 0.12, sz) and _free_box(bb + Vector3.UP * 0.12, sz) \
				and _free_box(front, Vector3(40, 40, 40)):
			_shelf(wall, along + 35.0, 54.0, props)
			_shelf(wall, along + 85.0, 99.0, props)
			return true
		along += 20.0
	return false


func _shelf(wall: String, along: float, top_cm: float, props: Array) -> void:
	var side := wall in ["w", "e"]
	var c := _wall_pt(wall, along, 12.0, top_cm - 1.5)
	var size := Vector3(0.24, 0.03, 0.7) if side else Vector3(0.7, 0.03, 0.24)
	var wood := b.mat_named("wood", LevelBuilder.hex(0x8a5a34))
	var sh := b.box("Wall shelf", c, size, wood, b.furn)
	sh.get_child(0).set_meta("surface", "shelf")
	for br in [-0.25, 0.25]:  # brackets
		var bp := _wall_pt(wall, along + br * 100.0, 3.0, top_cm - 8.0)
		b.box("Bracket", bp, Vector3(0.02, 0.12, 0.02), wood, b.furn, false)
	for j in 2:  # a couple of things at the back, leaving room to walk
		var pp := _wall_pt(wall, along - 22.0 + j * 40.0, 4.0, top_cm)
		var n := b.spawn(str(props[(j + int(top_cm)) % props.size()]), pp, _wall_rot(wall), b.decor)
		if n:
			var ab := LevelBuilder.world_aabb(n)
			if ab.size.y > 0.2:
				n.scale *= 0.2 / ab.size.y
			b.collide(n)


func _art_at(wall: String, along: float, model: String) -> bool:
	var p := _wall_pt(wall, along, 3.0, 165.0)
	if _busy(p, 10.0) or not _free_box(_wall_pt(wall, along, 4.0, 165.0), Vector3(60, 60, 4) if wall in ["n", "s"] else Vector3(4, 60, 60)):
		return false
	b._wall_art(model, ((p.x + 4.8) * 100.0), ((p.z + 3.0) * 100.0), 165.0, _wall_rot(wall))
	return true


func _floor_item(model: String, x: float, y: float) -> bool:
	var p := W(x, y)
	if _busy(p, 30.0) or not _free_box(p + Vector3.UP * 0.6, Vector3(44, 110, 44)):
		return false
	if model == "furniture/floor_lamp":
		b.floor_lamp(p)
		return true
	var n := b.spawn(model, p, randf() * 360.0, b.furn)
	if n:
		b.collide(n)
		if model == "furniture/plant":
			g.plants.append([n, n.rotation, randf() * TAU])  # round 12: it sways
	return n != null


## ---------------------------------------------------------------------------------------------------------
## Round 15 (asked: "make the other rooms lived-in too"). Small things people leave about, hung on the night's own
## furniture list so every layout gets its share: magazines and a remote on the coffee table, a throw over the
## sofa's arm, a photo on the side table, candlesticks and a clock on the mantelpiece, firewood, a globe on the
## bookcase; a runner and a vase on the dining table, plates and candles on the sideboard, a suitcase on the tall
## cabinet; detergent and folded towels on the washers, laundry spilling out of the basket, a washing line across
## the corner, paint cans, boots, a pegboard of tools. All scenery: nothing is a task or a noise, nothing goes
## where the night keeps food, traps or things to knock over (_busy), nothing looks like something to pick up.
var _life: Node3D
var _lrng := RandomNumberGenerator.new()
var _pm := {}


func _c(color: Color) -> StandardMaterial3D:
	var k := color.to_html()
	if not _pm.has(k):
		_pm[k] = b._paint(color)
	return _pm[k]


## A spot on top of a piece of furniture (cm), or null when the night needs that spot or nothing stands there.
func _on(x: float, y: float, r_cm := 9.0):
	var p := b.on_top(x, y)
	if p.y < 0.1 or _busy(p, r_cm):
		return null
	return p


## A free patch of floor (cm)?
func _clear_spot(x: float, y: float, r_cm: float) -> bool:
	if x < 30.0 or x > 930.0 or y < 30.0 or y > 570.0:
		return false
	var p := W(x, y)
	return not _busy(p, r_cm) and _free_box(p + Vector3.UP * 0.2, Vector3(r_cm * 2.0, 32, r_cm * 2.0))


func _ball(at: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	_life.add_child(mi)
	mi.global_position = at
	return mi


## A block inside another one's frame (a picture in its frame, a face on a clock).
func _inset(parent: Node3D, local: Vector3, size: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = local


func _solid(at: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	body.add_child(cs)
	_life.add_child(body)
	body.global_position = at + Vector3.UP * height * 0.5


func life(kind: String) -> void:
	if kind == "kitchen" or bool(g.night.get("kitchenUpper", false)) or OS.get_environment("HIDE").contains("life"):
		return
	_life = b.group("Room life")
	_lrng.seed = hash(kind) + int(g.night.number) / 100
	for wall in ["n", "s", "w", "e"]:
		_inner[wall] = _probe_inner(wall)
	var kids := int(g.night.number) == 13
	var seen := {}
	var sofa = null
	var table = null
	for f in g.night.get("furn", []):
		if f.get("w") == null or f.get("h") == null:
			continue
		var x := float(f.x)
		var y := float(f.y)
		var w := float(f.w)
		var h := float(f.h)
		var cx := x + w / 2.0
		var cy := y + h / 2.0
		var t := str(f.t)
		var nth: int = seen.get(t, 0)
		seen[t] = nth + 1
		match t:
			"coffeeTable":
				table = f
				_magazines(cx - w * 0.22, cy - 4.0)
				_remote(cx + w * 0.2, cy + h * 0.12)
			"sofa":
				sofa = f
				_throw(x + 26.0, cy, h)
			"armchair":
				if not _yarn_basket(x + w + 24.0, cy + 12.0):
					_yarn_basket(x - 24.0, cy + 12.0)
			"sideTable":
				_photo(cx, cy, side(x, y, w, h))
			"fireplace":
				_mantel(f)
			"tvStand":
				_console(x + 36.0, cy)
				_cases(x + w - 30.0, cy)
			"bookcase":
				_globe(cx, cy)
			"table":
				if kind == "pantry":
					_towels(cx - w * 0.22, cy)
				else:
					_runner(f, not kids)
			"sideboard":
				_candle(cx - w * 0.36, cy)
				_candle(cx - w * 0.36 + 13.0, cy + 3.0)
				_plates(cx + w * 0.3, cy)
				_photo(cx, cy - 6.0, side(x, y, w, h))
			"cabinetTall":
				_suitcase(cx, cy, w > h)
			"washer":
				if nth == 0:
					_detergent(cx, cy)
				else:
					_towels(cx, cy)
			"basket":
				_laundry(cx, cy)
			"boiler":
				if not _paint_cans(x - 36.0, cy + 18.0):
					_paint_cans(x - 36.0, y - 30.0)
			"bench":
				_toolbox(x + 34.0, cy)
			"box", "crate":
				if nth == 0:
					_tarp(cx, cy)
			"barCart":
				_bottles(cx, cy)
	match kind:
		"living":
			if kids:
				_kid_wall()
			else:
				_slippers(sofa, table)
				_newspapers()
		"pantry":
			_washing_line()
			_boots()
			_pegboard()
	for mi in _life.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _magazines(x: float, y: float) -> void:
	var p = _on(x, y, 16.0)
	if p == null:
		return
	var cols := [Color(0.78, 0.26, 0.22), Color(0.2, 0.5, 0.56), Color(0.93, 0.89, 0.78)]
	for i in 3:
		b._bit(_life, (p as Vector3) + Vector3(_lrng.randf_range(-0.012, 0.012), 0.007 + i * 0.013, _lrng.randf_range(-0.012, 0.012)),
				Vector3(0.21, 0.012, 0.28), _c(cols[i]), 0.0, _lrng.randf_range(-28.0, 28.0))


func _remote(x: float, y: float) -> void:
	var p = _on(x, y, 8.0)
	if p == null:
		return
	var yaw := _lrng.randf_range(-40.0, 40.0)
	var r := b._bit(_life, (p as Vector3) + Vector3.UP * 0.009, Vector3(0.045, 0.018, 0.15), _c(Color(0.16, 0.16, 0.19)), 0.0, yaw)
	_inset(r, Vector3(0, 0.01, -0.05), Vector3(0.014, 0.004, 0.014), _c(Color(0.85, 0.2, 0.18)))


## A woollen throw over one arm of the sofa: across the top, hanging down in front and behind.
func _throw(x: float, cy: float, depth: float) -> void:
	var p := b.on_top(x, cy)
	if p.y < 0.25:
		return
	var d := depth / 100.0 + 0.05
	var wool := _c(Color(0.86, 0.66, 0.24))
	var stripe := _c(Color(0.62, 0.3, 0.2))
	b._bit(_life, p + Vector3.UP * 0.012, Vector3(0.4, 0.022, d), wool)
	for s in [-1.0, 1.0]:
		b._bit(_life, p + Vector3(0, -0.11, s * d * 0.5), Vector3(0.4, 0.26, 0.022), wool)
		b._bit(_life, p + Vector3(0, -0.2, s * (d * 0.5 + 0.002)), Vector3(0.4, 0.035, 0.024), stripe)
	for sx in [-0.12, 0.12]:
		b._bit(_life, p + Vector3(sx, 0.014, 0), Vector3(0.035, 0.024, d + 0.002), stripe)


func _yarn_basket(x: float, y: float) -> bool:
	if not _clear_spot(x, y, 16.0):
		return false
	var p := W(x, y)
	b._round(_life, p + Vector3.UP * 0.07, 0.115, 0.14, _c(Color(0.7, 0.52, 0.3)))
	b._round(_life, p + Vector3.UP * 0.142, 0.122, 0.014, _c(Color(0.56, 0.4, 0.22)))
	var cols := [Color(0.8, 0.26, 0.3), Color(0.25, 0.48, 0.72), Color(0.93, 0.88, 0.76)]
	for i in 3:
		var a := i * TAU / 3.0 + 0.4
		_ball(p + Vector3(cos(a) * 0.045, 0.16, sin(a) * 0.045), 0.048, _c(cols[i]))
	_solid(p, 0.12, 0.15)
	return true


## A framed photograph, leaning back a little, facing into the room.
func _photo(x: float, y: float, wall: String) -> void:
	var p = _on(x, y, 8.0)
	if p == null:
		return
	var yaw := side_rot(wall) + _lrng.randf_range(-14.0, 14.0)
	var fr := b._bit(_life, (p as Vector3) + Vector3.UP * 0.073, Vector3(0.115, 0.145, 0.014), _c(Color(0.5, 0.32, 0.18)))
	fr.rotation_degrees = Vector3(-11.0, yaw, 0.0)
	_inset(fr, Vector3(0, 0, 0.0055), Vector3(0.085, 0.115, 0.006), _c(Color(0.9, 0.86, 0.74)))
	_inset(fr, Vector3(0, -0.02, 0.0075), Vector3(0.085, 0.05, 0.004), _c(Color(0.42, 0.6, 0.44)))


func _candle(x: float, y: float) -> void:
	var p = _on(x, y, 6.0)
	if p == null:
		return
	var q: Vector3 = p
	var brass := _c(Color(0.78, 0.6, 0.24))
	b._round(_life, q + Vector3.UP * 0.006, 0.032, 0.012, brass)
	b._round(_life, q + Vector3.UP * 0.06, 0.009, 0.1, brass)
	b._round(_life, q + Vector3.UP * 0.113, 0.018, 0.008, brass)
	b._round(_life, q + Vector3.UP * 0.16, 0.012, 0.09, _c(Color(0.94, 0.9, 0.8)))


func _mantel(f: Dictionary) -> void:
	var x := float(f.x)
	var y := float(f.y)
	var w := float(f.w)
	var h := float(f.h)
	var wall := side(x, y, w, h)
	var along_y := wall in ["w", "e"]  # the mantel runs along y on a side wall
	var cx := x + w / 2.0
	var cy := y + h / 2.0
	var half := (h if along_y else w) * 0.33
	for s in [-1.0, 1.0]:
		_candle(cx + (0.0 if along_y else s * half), cy + (s * half if along_y else 0.0))
	var p = _on(cx, cy, 8.0)
	if p != null:
		var clock := b._bit(_life, (p as Vector3) + Vector3.UP * 0.075, Vector3(0.17, 0.15, 0.075), _c(Color(0.42, 0.25, 0.14)), 0.0, side_rot(wall))
		_inset(clock, Vector3(0, 0.01, 0.038), Vector3(0.1, 0.1, 0.004), _c(Color(0.95, 0.92, 0.82)))
		_inset(clock, Vector3(0.012, 0.022, 0.041), Vector3(0.006, 0.045, 0.003), _c(Color(0.15, 0.13, 0.13)))
		_inset(clock, Vector3(-0.012, 0.004, 0.041), Vector3(0.035, 0.006, 0.003), _c(Color(0.15, 0.13, 0.13)))
	# a few logs beside it
	for c in [[x + w + 34.0, y + h + 6.0], [x + w + 34.0, y - 6.0], [x + 24.0, y + h + 30.0], [x + 24.0, y - 30.0]]:
		if _clear_spot(c[0], c[1], 22.0):
			var lp := W(c[0], c[1])
			var bark := _c(Color(0.46, 0.3, 0.18))
			for k in 3:
				var at := lp + (Vector3(0, 0.05, -0.05 + k * 0.1) if k < 2 else Vector3(0, 0.135, 0))
				var lg := b._round(_life, at, 0.05, 0.34, bark)
				lg.rotation_degrees = Vector3(0, _lrng.randf_range(-8.0, 8.0), 90.0)
				_inset(lg, Vector3(0, 0.171, 0), Vector3(0.07, 0.002, 0.07), _c(Color(0.85, 0.72, 0.5)))
			_solid(lp, 0.16, 0.18)
			break


func _console(x: float, y: float) -> void:
	var p = _on(x, y, 10.0)
	if p == null:
		return
	var c := b._bit(_life, (p as Vector3) + Vector3.UP * 0.026, Vector3(0.27, 0.05, 0.18), _c(Color(0.2, 0.2, 0.24)))
	_inset(c, Vector3(0.1, 0.005, 0.091), Vector3(0.016, 0.008, 0.004), _c(Color(0.3, 0.9, 0.45)))


func _cases(x: float, y: float) -> void:
	var p = _on(x, y, 10.0)
	if p == null:
		return
	var cols := [Color(0.24, 0.42, 0.8), Color(0.82, 0.3, 0.24), Color(0.3, 0.6, 0.36), Color(0.9, 0.75, 0.25), Color(0.5, 0.36, 0.6)]
	for i in 5:
		b._bit(_life, (p as Vector3) + Vector3(0, 0.008 + i * 0.015, 0), Vector3(0.14, 0.014, 0.19), _c(cols[i]), 0.0, _lrng.randf_range(-9.0, 9.0))


func _globe(x: float, y: float) -> void:
	var p = _on(x, y, 10.0)
	if p == null:
		return
	var q: Vector3 = p
	var wood := _c(Color(0.5, 0.32, 0.18))
	b._round(_life, q + Vector3.UP * 0.008, 0.065, 0.016, wood)
	b._round(_life, q + Vector3.UP * 0.05, 0.009, 0.07, wood)
	_ball(q + Vector3.UP * 0.17, 0.095, _c(Color(0.24, 0.5, 0.62)))
	var land := b._bit(_life, q + Vector3(0.04, 0.2, 0.06), Vector3(0.07, 0.06, 0.06), _c(Color(0.46, 0.62, 0.36)), 20.0, 30.0)
	land.scale = Vector3(1, 1, 0.7)


## A runner down the middle of a table and, on a dining table, a vase of flowers.
func _runner(f: Dictionary, vase: bool) -> void:
	var w := float(f.w)
	var h := float(f.h)
	var cx := float(f.x) + w / 2.0
	var cy := float(f.y) + h / 2.0
	var p := b.on_top(cx, cy)
	if p.y < 0.3 or p.y > 1.1:
		return
	p.y += 0.012  # over the tablecloth, which lies a little above the table's collision top
	var long_x := w >= h
	var len := (w if long_x else h) / 100.0 * 0.86
	var size := Vector3(len, 0.006, 0.3) if long_x else Vector3(0.3, 0.006, len)
	b._bit(_life, p + Vector3.UP * 0.004, size, _c(Color(0.5, 0.62, 0.48)))
	for s in [-1.0, 1.0]:
		var off := Vector3(0, 0.005, s * 0.12) if long_x else Vector3(s * 0.12, 0.005, 0)
		b._bit(_life, p + off, Vector3(len, 0.006, 0.02) if long_x else Vector3(0.02, 0.006, len), _c(Color(0.93, 0.89, 0.78)))
	if not vase:
		return
	if _busy(p, 16.0):  # the middle is taken (food): a third of the way along instead
		var found := false
		for s in [-1.0, 1.0]:
			var q := p + (Vector3(s * len * 0.3, 0, 0) if long_x else Vector3(0, 0, s * len * 0.3))
			if not _busy(q, 12.0):
				p = q
				found = true
				break
		if not found:
			return
	b._round(_life, p + Vector3.UP * 0.085, 0.05, 0.16, _c(Color(0.3, 0.48, 0.7)))
	b._round(_life, p + Vector3.UP * 0.17, 0.036, 0.02, _c(Color(0.26, 0.42, 0.62)))
	var petals := [Color(0.9, 0.3, 0.3), Color(0.96, 0.8, 0.26), Color(0.95, 0.92, 0.86), Color(0.86, 0.46, 0.66), Color(0.9, 0.3, 0.3)]
	for i in 5:
		var a := i * TAU / 5.0
		var lean := Vector3(cos(a), 0, sin(a)) * 0.07
		var stem := b._round(_life, p + Vector3.UP * 0.25 + lean * 0.5, 0.005, 0.18, _c(Color(0.3, 0.5, 0.26)))
		stem.look_at(stem.global_position + Vector3.UP + lean * 5.5, Vector3.RIGHT)
		stem.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		_ball(p + Vector3.UP * 0.345 + lean * 1.05, 0.032, _c(petals[i]))
	_solid(p, 0.055, 0.2)


func _towels(x: float, y: float) -> void:
	var p = _on(x, y, 14.0)
	if p == null:
		return
	var cols := [Color(0.93, 0.9, 0.82), Color(0.36, 0.56, 0.78), Color(0.93, 0.9, 0.82), Color(0.84, 0.44, 0.36)]
	for i in 4:
		b._bit(_life, (p as Vector3) + Vector3(0, 0.02 + i * 0.038, 0), Vector3(0.3 - i * 0.01, 0.036, 0.2), _c(cols[i]), 0.0, _lrng.randf_range(-5.0, 5.0))


func _plates(x: float, y: float) -> void:
	var p = _on(x, y, 10.0)
	if p == null:
		return
	for i in 5:
		b._round(_life, (p as Vector3) + Vector3(0, 0.007 + i * 0.013, 0), 0.1 - (i % 2) * 0.004, 0.012, _c(Color(0.94, 0.92, 0.86) if i % 2 == 0 else Color(0.78, 0.84, 0.92)))


func _suitcase(x: float, y: float, long_x: bool) -> void:
	var p = _on(x, y, 10.0)
	if p == null:
		return
	var yaw := 0.0 if long_x else 90.0
	var s := b._bit(_life, (p as Vector3) + Vector3.UP * 0.085, Vector3(0.44, 0.17, 0.3), _c(Color(0.56, 0.36, 0.2)), 0.0, yaw)
	for sx in [-0.13, 0.13]:
		_inset(s, Vector3(sx, 0, 0), Vector3(0.035, 0.176, 0.306), _c(Color(0.34, 0.2, 0.12)))
	_inset(s, Vector3(0, 0.02, 0.158), Vector3(0.1, 0.02, 0.016), _c(Color(0.24, 0.16, 0.1)))


func _detergent(x: float, y: float) -> void:
	var p = _on(x - 12.0, y, 8.0)
	if p != null:
		var box := b._bit(_life, (p as Vector3) + Vector3.UP * 0.11, Vector3(0.16, 0.22, 0.09), _c(Color(0.92, 0.52, 0.16)), 0.0, _lrng.randf_range(-12.0, 12.0))
		_inset(box, Vector3(0, 0.01, 0.046), Vector3(0.11, 0.1, 0.004), _c(Color(0.24, 0.42, 0.8)))
		_inset(box, Vector3(0, 0.01, 0.048), Vector3(0.06, 0.05, 0.004), _c(Color(0.95, 0.93, 0.86)))
	var q = _on(x + 14.0, y + 4.0, 6.0)
	if q != null:
		b._round(_life, (q as Vector3) + Vector3.UP * 0.09, 0.04, 0.18, _c(Color(0.3, 0.56, 0.8)))
		b._round(_life, (q as Vector3) + Vector3.UP * 0.195, 0.02, 0.03, _c(Color(0.94, 0.92, 0.88)))


func _laundry(x: float, y: float) -> void:
	var p := b.on_top(x, y)
	if p.y < 0.12:
		return
	var cols := [Color(0.93, 0.9, 0.84), Color(0.8, 0.28, 0.26), Color(0.3, 0.5, 0.76), Color(0.94, 0.8, 0.3)]
	for i in 4:
		var cl := b._bit(_life, p + Vector3(_lrng.randf_range(-0.07, 0.07), 0.02 + i * 0.022, _lrng.randf_range(-0.06, 0.06)), Vector3(0.2, 0.045, 0.16), _c(cols[i]))
		cl.rotation_degrees = Vector3(_lrng.randf_range(-14.0, 14.0), _lrng.randf_range(0.0, 180.0), _lrng.randf_range(-14.0, 14.0))
	b._bit(_life, p + Vector3(0.0, -0.05, 0.225), Vector3(0.055, 0.17, 0.014), _c(Color(0.3, 0.5, 0.76)), 6.0)


func _paint_cans(x: float, y: float) -> bool:
	if not _clear_spot(x, y, 22.0):
		return false
	var p := W(x, y)
	var lids := [Color(0.82, 0.3, 0.24), Color(0.3, 0.56, 0.8), Color(0.94, 0.8, 0.3)]
	var spots := [Vector3(-0.085, 0.0, 0.0), Vector3(0.085, 0.0, 0.02), Vector3(0.0, 0.16, 0.01)]
	for i in 3:
		var at: Vector3 = p + spots[i]
		b._round(_life, at + Vector3.UP * 0.075, 0.078, 0.15, _c(Color(0.86, 0.86, 0.84)))
		b._round(_life, at + Vector3.UP * 0.155, 0.08, 0.012, _c(lids[i]))
		b._bit(_life, at + Vector3(0.03, 0.115, 0.074), Vector3(0.03, 0.07, 0.006), _c(lids[i]), 0.0, 22.0)
	_solid(p, 0.17, 0.3)
	return true


func _toolbox(x: float, y: float) -> void:
	var p = _on(x, y, 16.0)
	if p == null:
		return
	var tb := b._bit(_life, (p as Vector3) + Vector3.UP * 0.07, Vector3(0.36, 0.14, 0.17), _c(Color(0.8, 0.24, 0.2)), 0.0, _lrng.randf_range(-10.0, 10.0))
	_inset(tb, Vector3(0, 0.05, 0), Vector3(0.366, 0.02, 0.176), _c(Color(0.56, 0.16, 0.14)))
	_inset(tb, Vector3(0, 0.1, 0), Vector3(0.16, 0.014, 0.02), _c(Color(0.2, 0.2, 0.23)))
	for sx in [-0.075, 0.075]:
		_inset(tb, Vector3(sx, 0.085, 0), Vector3(0.014, 0.03, 0.02), _c(Color(0.2, 0.2, 0.23)))


func _tarp(x: float, y: float) -> void:
	var p = _on(x, y, 14.0)
	if p == null:
		return
	b._bit(_life, (p as Vector3) + Vector3.UP * 0.028, Vector3(0.4, 0.055, 0.3), _c(Color(0.42, 0.52, 0.42)), 0.0, _lrng.randf_range(-12.0, 12.0))
	b._bit(_life, (p as Vector3) + Vector3.UP * 0.075, Vector3(0.36, 0.04, 0.26), _c(Color(0.5, 0.6, 0.5)), 0.0, _lrng.randf_range(-12.0, 12.0))


func _bottles(x: float, y: float) -> void:
	for i in 3:
		var p = _on(x - 14.0 + i * 14.0, y + (i % 2) * 6.0 - 3.0, 5.0)
		if p != null:
			b.spawn("props/bottle", p, _lrng.randf_range(0.0, 360.0), _life)


## Slippers left between the sofa and the coffee table.
func _slippers(sofa, table) -> void:
	if sofa == null or table == null:
		return
	var sx := float(sofa.x) + float(sofa.w) * 0.72
	var gap_y := (float(table.y) + float(table.h) + float(sofa.y)) / 2.0
	if float(table.y) > float(sofa.y):
		gap_y = (float(sofa.y) + float(sofa.h) + float(table.y)) / 2.0
	if not _clear_spot(sx, gap_y, 14.0):
		return
	var p := W(sx, gap_y)
	for s in [-1.0, 1.0]:
		var yaw: float = 8.0 * s + _lrng.randf_range(-10.0, 10.0)
		var sl := b._bit(_life, p + Vector3(s * 0.065, 0.016, s * 0.02), Vector3(0.085, 0.03, 0.21), _c(Color(0.72, 0.26, 0.24)), 0.0, yaw)
		_inset(sl, Vector3(0, 0.022, -0.045), Vector3(0.09, 0.03, 0.11), _c(Color(0.9, 0.84, 0.7)))


func _newspapers() -> void:
	for c in [[130.0, 450.0], [700.0, 480.0], [250.0, 90.0], [620.0, 540.0], [800.0, 120.0]]:
		if _clear_spot(c[0], c[1], 24.0):
			var p := W(c[0], c[1])
			var yaw := _lrng.randf_range(0.0, 90.0)
			var st := b._bit(_life, p + Vector3.UP * 0.05, Vector3(0.3, 0.1, 0.4), _c(Color(0.9, 0.87, 0.78)), 0.0, yaw)
			_inset(st, Vector3(0, 0, 0), Vector3(0.306, 0.104, 0.016), _c(Color(0.5, 0.36, 0.22)))
			_inset(st, Vector3(0, 0, 0), Vector3(0.016, 0.104, 0.406), _c(Color(0.5, 0.36, 0.22)))
			_inset(st, Vector3(0.04, 0.052, 0.06), Vector3(0.16, 0.003, 0.05), _c(Color(0.3, 0.3, 0.34)))
			return


## Children's drawings taped to the wall at a child's height.
func _kid_wall() -> void:
	for wall in ["s", "w", "e", "n"]:
		var ok := true
		for along in [345.0, 495.0, 645.0]:
			var c := _wall_pt(wall, along, 3.0, 105.0)
			if _busy(c, 20.0) or not _free_box(_wall_pt(wall, along, 5.0, 105.0), Vector3(36, 30, 6) if wall in ["n", "s"] else Vector3(6, 30, 36)):
				ok = false
		if not ok:
			continue
		var crayons := [Color(0.86, 0.26, 0.24), Color(0.95, 0.78, 0.2), Color(0.3, 0.6, 0.34), Color(0.26, 0.44, 0.8), Color(0.86, 0.46, 0.66)]
		var k := 0
		for along in [345.0, 495.0, 645.0]:
			var sheet := b._bit(_life, _wall_pt(wall, along, 0.6, 105.0 + _lrng.randf_range(-8.0, 8.0)), Vector3(0.3, 0.22, 0.004), _c(Color(0.94, 0.92, 0.86)), _lrng.randf_range(-6.0, 6.0), _wall_rot(wall))
			for i in 4:
				_inset(sheet, Vector3(_lrng.randf_range(-0.1, 0.1), _lrng.randf_range(-0.07, 0.07), 0.003), Vector3(_lrng.randf_range(0.04, 0.1), _lrng.randf_range(0.03, 0.08), 0.003), _c(crayons[(k + i) % crayons.size()]))
			for sx in [-0.13, 0.13]:
				_inset(sheet, Vector3(sx, 0.1, 0.004), Vector3(0.03, 0.016, 0.003), _c(Color(0.8, 0.76, 0.6)))
			k += 2
		return


## A washing line across the corner above the washers, with the wash on it.
func _washing_line() -> void:
	var wx := -1.0
	for f in g.night.get("furn", []):
		if str(f.t) == "washer":
			wx = float(f.x)
			break
	if wx < 0.0:
		return
	var east := wx > 480.0
	var a := W(700.0 if east else 260.0, 5.0, 172.0)
	var c := W(955.0 if east else 5.0, 215.0, 172.0)
	var dir := c - a
	var yaw := rad_to_deg(atan2(-dir.z, dir.x))
	b._bit(_life, (a + c) / 2.0, Vector3(dir.length(), 0.008, 0.008), _c(Color(0.9, 0.88, 0.8)), 0.0, yaw)
	var items := [[0.14, Vector3(0.07, 0.2, 0.01), Color(0.9, 0.3, 0.3)], [0.24, Vector3(0.07, 0.2, 0.01), Color(0.9, 0.3, 0.3)],
			[0.42, Vector3(0.34, 0.3, 0.012), Color(0.93, 0.9, 0.82)], [0.64, Vector3(0.26, 0.26, 0.012), Color(0.3, 0.52, 0.78)],
			[0.84, Vector3(0.22, 0.32, 0.012), Color(0.94, 0.8, 0.32)]]
	for it in items:
		var size: Vector3 = it[1]
		var at: Vector3 = a + dir * float(it[0]) - Vector3.UP * (size.y / 2.0)
		var cloth := b._bit(_life, at, size, _c(it[2]), _lrng.randf_range(-4.0, 4.0), yaw)
		if size.x > 0.3:  # the towel has a stripe
			_inset(cloth, Vector3(0, -0.08, 0), Vector3(size.x + 0.002, 0.04, 0.014), _c(Color(0.3, 0.52, 0.78)))
		elif size.x > 0.24:  # the shirt has sleeves
			for sx in [-1.0, 1.0]:
				_inset(cloth, Vector3(sx * 0.17, 0.08, 0), Vector3(0.1, 0.09, 0.012), _c(it[2]))
		for sx in [-1.0, 1.0]:  # pegs
			_inset(cloth, Vector3(sx * size.x * 0.32, size.y / 2.0, 0), Vector3(0.012, 0.035, 0.018), _c(Color(0.72, 0.56, 0.34)))


func _boots() -> void:
	for c in [[810.0, 410.0], [800.0, 190.0], [560.0, 560.0], [330.0, 560.0], [420.0, 60.0]]:
		if _clear_spot(c[0], c[1], 18.0):
			var p := W(c[0], c[1])
			var rubber := _c(Color(0.26, 0.42, 0.3))
			for s in [-1.0, 1.0]:
				var q := p + Vector3(s * 0.07, 0, 0)
				b._round(_life, q + Vector3.UP * 0.15, 0.048, 0.24, rubber)
				b._bit(_life, q + Vector3(0, 0.035, 0.05), Vector3(0.095, 0.07, 0.2), rubber)
				b._round(_life, q + Vector3.UP * 0.273, 0.052, 0.012, _c(Color(0.9, 0.8, 0.4)))
			_solid(p, 0.13, 0.26)
			return


## A board of tools on a free piece of wall.
func _pegboard() -> void:
	for wall in ["s", "w", "e", "n"]:
		for along in [495.0, 345.0, 645.0]:
			var c := _wall_pt(wall, along, 3.0, 150.0)
			if _busy(c, 30.0) or not _free_box(_wall_pt(wall, along, 6.0, 150.0), Vector3(70, 52, 8) if wall in ["n", "s"] else Vector3(8, 52, 70)):
				continue
			var board := b._bit(_life, _wall_pt(wall, along, 1.0, 150.0), Vector3(0.66, 0.48, 0.016), _c(Color(0.62, 0.48, 0.32)), 0.0, _wall_rot(wall))
			var steel := _c(Color(0.66, 0.68, 0.72))
			var grip := _c(Color(0.8, 0.26, 0.2))
			var wood := _c(Color(0.5, 0.32, 0.18))
			# hammer
			_inset(board, Vector3(-0.24, -0.02, 0.014), Vector3(0.022, 0.24, 0.016), wood)
			_inset(board, Vector3(-0.24, 0.11, 0.016), Vector3(0.1, 0.035, 0.03), steel)
			# saw
			_inset(board, Vector3(-0.05, 0.02, 0.012), Vector3(0.06, 0.26, 0.006), steel)
			_inset(board, Vector3(-0.05, 0.16, 0.014), Vector3(0.09, 0.06, 0.018), wood)
			# screwdrivers
			for i in 3:
				_inset(board, Vector3(0.1 + i * 0.05, 0.1, 0.014), Vector3(0.02, 0.07, 0.02), grip if i != 1 else _c(Color(0.94, 0.8, 0.3)))
				_inset(board, Vector3(0.1 + i * 0.05, 0.02, 0.012), Vector3(0.007, 0.1, 0.007), steel)
			# wrench and a roll of tape
			_inset(board, Vector3(0.27, 0.02, 0.012), Vector3(0.024, 0.22, 0.008), steel)
			_inset(board, Vector3(0.27, 0.14, 0.012), Vector3(0.05, 0.04, 0.008), steel)
			var tape := b._round(_life, _wall_pt(wall, along + 14.0, 3.0, 133.0), 0.045, 0.03, _c(Color(0.3, 0.3, 0.34)))
			tape.rotation_degrees = Vector3(90.0, _wall_rot(wall), 0.0)
			return
