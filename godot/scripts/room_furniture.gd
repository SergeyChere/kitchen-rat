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
	var n := b.spawn(model, W(x + w / 2.0, y + d / 2.0), r, b.furn)
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
func _fire(at: Vector3, w_cm: float) -> void:
	var e := CPUParticles3D.new()
	e.name = "Fireplace fire"
	e.amount = 26
	e.lifetime = 0.75
	e.local_coords = false
	e.direction = Vector3.UP
	e.spread = 13.0
	e.gravity = Vector3(0, 0.32, 0)
	e.initial_velocity_min = 0.22
	e.initial_velocity_max = 0.42
	e.damping_min = 0.3
	e.damping_max = 0.6
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.15
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.25
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35)); sc.add_point(Vector2(0.3, 1.0)); sc.add_point(Vector2(1, 0.1))
	e.scale_amount_curve = sc
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.6, 0.14, 0.8))
	gr.set_color(1, Color(0.9, 0.2, 0.03, 0.0))
	e.color_ramp = gr
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_disc()
	q.material = m
	e.mesh = q
	b.furn.add_child(e)
	e.global_position = at
	e.scale = Vector3(maxf(w_cm, 60.0) / 90.0, 0.55, 0.75)


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
			"fridge":
				var fn2 := place("furniture/fridge", f, "fridge", 0.0, null, "metal_matte")
				_detail_for(t, f, fn2)
			"island": place("furniture/kitchen_island", f, "island", 0.0, 180.0)
			"box":
				var ht := float(f.get("ht", 44))
				place("furniture/cardboard_box_tall" if ht > 70.0 else "furniture/cardboard_box", f, "box", ht, null, "cardboard")
			"crate":
				var cr := place("furniture/crate", f, "crate", float(f.get("ht", 40)), null, "wood_dark")
				_detail_for(t, f, cr)
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
					if bool(f.get("dining", false)):
						_detail_dining(f, n)
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
						for mi in cloth.find_children("*", "MeshInstance3D", true, false):
							(mi as MeshInstance3D).material_override = clothmat
					if bool(f.get("dining", false)):
						light(W(cx, cy, ht + 60), Color8(0xff, 0xb0, 0x60), 0.7, 3.0)
				hide("table", f)
			"coffeeTable":
				var ctn := place("furniture/coffee_table", f, "table", 0.0, 0.0, "wood_dark")
				_detail_for(t, f, ctn)
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
				var sn := place("furniture/sofa" if t == "sofa" else "furniture/armchair", f, "sofa", 0.0, r, "fabric")
				_detail_for(t, f, sn)
				hide("sofa", f, 12.0)
				low_roof(f, 4.0)
			"wall":
				var wm := b.mat(LevelBuilder.hex(0x8a8a9a), "wall_" + str(g.night.get("pal", {}).get("wall", "stripes")))
				b.box("Inner wall", W(cx, cy, 115), Vector3(w / 100.0, 2.3, d / 100.0), wm, b.furn)
			"tvStand":
				var stand := place("furniture/tv_stand", f, "tv", 0.0, null, "wood_dark")
				_detail_for(t, f, stand)
				var tv := light(W(cx, y + d + 70, 90), Color(0.56, 0.7, 1.0), 1.6, 4.6, "tv")
				g.tv_light = tv
				tv.visible = not bool(g.night.get("tvOff", false))
			"bookcase":
				var bk := place("furniture/bookcase", f, "bookcase", 0.0, null, "wood_dark")
				_detail_for(t, f, bk)
			"fireplace":
				place("furniture/fireplace", f, "fireplace")
				var out := W(x + w + 30, cy, 40) if side(x, y, w, d) == "w" else W(cx, cy, 40)
				light(out, Color8(0xff, 0x8a, 0x3a), 2.2, 4.2)
				_fire(W(cx, cy, 16), w)
			"sideTable": place("furniture/side_table", f, "side", float(f.get("ht", 60)), null, "wood_dark")
			"lamp":
				b.collide(b.spawn("furniture/floor_lamp", W(cx, cy), 0.0, b.furn))
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
				var wn := place("furniture/dryer" if bool(f.get("dryer", false)) else "furniture/washer", f, "washer", 0.0, null, "plastic")
				_detail_for(t, f, wn)
				if not _lamp_done:
					_lamp_done = true
					_washer_wall_lamp(x - 160.0)
			"basket": place("furniture/laundry_basket", f, "basket", float(f.get("ht", 45)), null, "plastic")
			"cans": place("furniture/cans_stack", f, "cans", float(f.get("ht", 30)))
			"shelfUnit":
				var su := place("furniture/shelf_unit", f, "shelf", 0.0, null, "wood")
				_detail_for(t, f, su)
			"boiler":
				place("furniture/boiler", f, "boiler", 0.0, -90.0 if x > 480.0 else 90.0)
				light(W(cx - 50, cy, 40), Color8(0xff, 0x8a, 0x3a), 1.4, 3.0)
			"sideboard":
				var sb := place("furniture/sideboard", f, "sideboard", 0.0, null, "wood_dark")
				_detail_for(t, f, sb)
			"cabinetTall":
				# modelled long along its own Z, front toward +X: as is against the west wall
				var n := b.spawn("furniture/cabinet_tall", W(cx, cy), 0.0 if x < 480.0 else 180.0, b.furn)
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
	# details (ported from round 17): wall outlets on the south wall, a light
	# switch by the east wall — the door is always centred at y=300, so the
	# switch at y=200 never lands on it
	for ox in [300.0, 660.0]:
		b.box("Outlet " + str(int(ox)), W(ox, 595, 30), Vector3(0.09, 0.13, 0.014), b.mat(Color(0.92, 0.90, 0.86)), b.furn, false)
	b.box("Switch", W(953, 200, 115), Vector3(0.014, 0.13, 0.09), b.mat(Color(0.92, 0.90, 0.86)), b.furn, false)
	if kind == "living":
		# a radiator on the north wall's free stretch (x 110–280: the bookcase
		# ends at 60, the TV stand starts at 330, night 19's partition at 296)
		# and a slow ceiling fan. 0.45 m tall: a wall shelf hangs at 0.54 m
		# and must never cut through it.
		b.box("Radiator", W(195, 10, 24.5), Vector3(1.7, 0.45, 0.10), b.mat(Color(0.88, 0.86, 0.82)), b.furn, false)
		b.box("Radiator top", W(195, 10, 48.5), Vector3(1.76, 0.03, 0.13), b.mat(Color(0.80, 0.78, 0.74)), b.furn, false)
		var fan := Node3D.new()
		fan.name = "Ceiling fan"
		b.furn.add_child(fan)
		fan.global_position = W(480, 300, 240)
		var fm := b.mat(Color(0.25, 0.22, 0.20))
		var rod := MeshInstance3D.new()
		rod.name = "Fan rod"
		var rm := CylinderMesh.new()
		rm.top_radius = 0.014; rm.bottom_radius = 0.014; rm.height = 0.10
		rod.mesh = rm; rod.material_override = fm; rod.position = Vector3(0, 0.05, 0)
		fan.add_child(rod)
		var hub := MeshInstance3D.new()
		hub.name = "Fan hub"
		var hm := CylinderMesh.new()
		hm.top_radius = 0.055; hm.bottom_radius = 0.055; hm.height = 0.05
		hub.mesh = hm; hub.material_override = fm
		fan.add_child(hub)
		for k in 4:
			var piv := Node3D.new()
			piv.name = "Blade pivot " + str(k)
			piv.rotation.y = float(k) * PI / 2.0
			fan.add_child(piv)
			var bl := MeshInstance3D.new()
			bl.name = "Fan blade " + str(k)
			var bm := BoxMesh.new()
			bm.size = Vector3(0.62, 0.012, 0.13)
			bl.mesh = bm; bl.material_override = fm; bl.position = Vector3(0.38, 0, 0)
			piv.add_child(bl)
		g.spinners.append([fan, 2.4])
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
	var n := b.spawn(model, p, randf() * 360.0, b.furn)
	if n:
		b.collide(n)
		if model == "furniture/plant":
			g.plants.append([n, n.rotation, randf() * TAU])  # round 12: it sways
	return n != null


# ---------- details, ported from round 17 (muse/demo-polish) onto main ----------
## Small set dressing scattered over every placed piece, at Muse's discretion
## (Sergii reviews in game and vetoes). Everything is non-solid decor parented
## to b.furn; positions come from each model's measured world AABB, so a detail
## lands on the piece whatever wall it stands against.
## Port notes (details-ui): every detail node gets a unique name — Godot
## renames duplicate children to @ClassName@N, which broke node counts in
## probes and risks collisions. Names carry the piece tag (type + map position)
## and an index inside rows.

const DETAIL_INK := [Color(0.55, 0.25, 0.18), Color(0.32, 0.38, 0.22), Color(0.62, 0.48, 0.28), Color(0.36, 0.36, 0.44), Color(0.48, 0.28, 0.36), Color(0.55, 0.52, 0.42)]


## A short tag unique to one placed piece: its type + map position.
func _dtag(t: String, f: Dictionary) -> String:
	return t + "_" + str(int(float(f.x))) + "_" + str(int(float(f.y)))


func _aabb_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if LevelBuilder._soft(m.name):
			continue
		var bb: AABB = m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return box


func _dcyl(nm: String, center: Vector3, r: float, h: float, m: Material, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cm := CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	b.furn.add_child(mi)
	mi.global_position = center
	return mi


func _book_row(center: Vector3, along_x: bool, length: float, seedv: float, tag: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seedv * 1000.0) + 7
	var off := -length / 2.0
	var bi := 0
	while off < length / 2.0 - 0.04:
		var bw := rng.randf_range(0.022, 0.040)
		var bh := rng.randf_range(0.16, 0.24)
		var col: Color = DETAIL_INK[rng.randi() % DETAIL_INK.size()] * rng.randf_range(0.8, 1.15)
		var c := center + (Vector3(off + bw / 2.0, bh / 2.0, 0) if along_x else Vector3(0, bh / 2.0, off + bw / 2.0))
		var bk := b.box("Book " + tag + " " + str(bi), c, Vector3(bw, bh, 0.13) if along_x else Vector3(0.13, bh, bw), b.mat(col), b.furn, false)
		bk.rotation.y = rng.randf_range(-0.03, 0.03)
		off += bw + rng.randf_range(0.0, 0.012)
		bi += 1


func _jar_row(center: Vector3, along_x: bool, count: int, seedv: float, tag: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seedv * 777.0) + 3
	var glass := b.mat(Color(0.82, 0.78, 0.66))
	glass.roughness = 0.15
	for i in count:
		var k := (float(i) - float(count - 1) / 2.0) * 0.095
		var c := center + (Vector3(k, 0.05, 0) if along_x else Vector3(0, 0.05, k))
		_dcyl("Jar " + tag + " " + str(i), c, 0.034, 0.10, glass)
		var lid := _dcyl("Jar lid " + tag + " " + str(i), c + Vector3(0, 0.058, 0), 0.036, 0.016, b.mat(DETAIL_INK[rng.randi() % DETAIL_INK.size()]))
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _detail_for(t: String, f: Dictionary, n: Node3D) -> void:
	if n == null:
		return
	var ab := _aabb_of(n)
	if ab.size == Vector3.ZERO:
		return
	var c := ab.get_center()
	var top := ab.end.y
	var tag := _dtag(t, f)
	var sd := side(float(f.x), float(f.y), float(f.get("w", 0)), float(f.get("h", 0)))
	match t:
		"sofa", "armchair":
			var along_x := ab.size.x >= ab.size.z
			var cnt := 3 if t == "sofa" else 1
			var rng := RandomNumberGenerator.new()
			rng.seed = int(c.x * 91.0 + c.z * 57.0)
			for i in cnt:
				var k := (float(i) + 0.5) / float(cnt) - 0.5
				var pos := c + (Vector3(k * ab.size.x * 0.62, 0, -ab.size.z * 0.16) if along_x else Vector3(-ab.size.x * 0.16, 0, k * ab.size.z * 0.62))
				pos.y = ab.position.y + ab.size.y * 0.52
				var cu := b.box("Cushion " + tag + " " + str(i), pos, Vector3(0.34, 0.13, 0.30), b.mat(DETAIL_INK[rng.randi() % DETAIL_INK.size()]), b.furn, false)
				cu.rotation.y = rng.randf_range(-0.15, 0.15)
				cu.rotation.z = rng.randf_range(-0.08, 0.08)
			if t == "sofa":
				var tp := c + (Vector3(ab.size.x * 0.38, 0, 0) if along_x else Vector3(0, 0, ab.size.z * 0.38))
				tp.y = ab.position.y + ab.size.y * 0.68
				b.box("Throw " + tag, tp, Vector3(0.5, 0.05, ab.size.z * 0.8) if along_x else Vector3(ab.size.x * 0.8, 0.05, 0.5), b.mat_named("fabric", Color(0.75, 0.60, 0.45)), b.furn, false)
		"bookcase":
			var along_x := sd == "n" or sd == "s"
			for lvl in [0.20, 0.47, 0.74]:
				var ctr := c
				ctr.y = ab.position.y + ab.size.y * lvl
				if sd == "n": ctr.z = ab.end.z - 0.10
				elif sd == "s": ctr.z = ab.position.z + 0.10
				elif sd == "w": ctr.x = ab.end.x - 0.10
				else: ctr.x = ab.position.x + 0.10
				_book_row(ctr, along_x, (ab.size.x if along_x else ab.size.z) * 0.82, c.x + lvl * 10.0, tag + "_" + str(int(lvl * 100)))
		"shelfUnit":
			var along_x2 := sd == "n" or sd == "s"
			for lvl in [0.30, 0.62]:
				var ctr := c
				ctr.y = ab.position.y + ab.size.y * lvl
				if sd == "n": ctr.z = ab.end.z - 0.09
				elif sd == "s": ctr.z = ab.position.z + 0.09
				elif sd == "w": ctr.x = ab.end.x - 0.09
				else: ctr.x = ab.position.x + 0.09
				_jar_row(ctr, along_x2, 4, c.x + lvl * 10.0, tag + "_" + str(int(lvl * 100)))
		"washer":
			_dcyl("Detergent " + tag, c + Vector3(ab.size.x * 0.24, top + 0.08, 0), 0.045, 0.16, b.mat(Color(0.85, 0.45, 0.15)))
			_dcyl("Detergent cap " + tag, c + Vector3(ab.size.x * 0.24, top + 0.175, 0), 0.02, 0.03, b.mat(Color(0.2, 0.2, 0.22)))
			for i in 2:
				b.box("Folded towel " + tag + " " + str(i), c + Vector3(-ab.size.x * 0.22, top + 0.026 + float(i) * 0.052, 0), Vector3(0.30, 0.05, 0.24), b.mat(Color(0.88, 0.85, 0.78) if i == 0 else Color(0.62, 0.68, 0.60)), b.furn, false)
		"tvStand":
			b.box("Remote " + tag, c + Vector3(-ab.size.x * 0.2, top + 0.012, 0), Vector3(0.16, 0.02, 0.05), b.mat(Color(0.08, 0.08, 0.09)), b.furn, false)
			for i in 2:
				var gc := b.box("Game case " + tag + " " + str(i), c + Vector3(ab.size.x * (0.12 + 0.03 * float(i)), top + 0.09, 0), Vector3(0.135, 0.18, 0.014), b.mat(DETAIL_INK[i % DETAIL_INK.size()]), b.furn, false)
				gc.rotation.z = -0.10
		"sideboard":
			_dcyl("Vase " + tag, c + Vector3(-ab.size.x * 0.25, top + 0.11, 0), 0.045, 0.22, b.mat(Color(0.45, 0.52, 0.48)), 0.028)
			var ball := MeshInstance3D.new()
			ball.name = "Vase greens " + tag
			var sm := SphereMesh.new()
			sm.radius = 0.085; sm.height = 0.17
			ball.mesh = sm
			ball.material_override = b.mat(Color(0.25, 0.38, 0.18))
			b.furn.add_child(ball)
			ball.global_position = c + Vector3(-ab.size.x * 0.25, top + 0.28, 0)
			for i in 2:
				b.box("Book stack " + tag + " " + str(i), c + Vector3(ab.size.x * 0.22, top + 0.013 + float(i) * 0.027, 0), Vector3(0.24 - 0.03 * float(i), 0.026, 0.17), b.mat(DETAIL_INK[(i + 2) % DETAIL_INK.size()]), b.furn, false)
		"fridge":
			var dir := Vector3.ZERO
			match sd:
				"n": dir = Vector3(0, 0, 1)
				"s": dir = Vector3(0, 0, -1)
				"w": dir = Vector3(1, 0, 0)
				_: dir = Vector3(-1, 0, 0)
			var face := c + dir * (ab.size.z * 0.5 + 0.006 if dir.z != 0.0 else ab.size.x * 0.5 + 0.006)
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = int(c.x * 31.0 + c.z * 17.0)
			var nsz := Vector3(0.13, 0.17, 0.006) if dir.z != 0.0 else Vector3(0.006, 0.17, 0.13)
			b.box("Fridge note " + tag, Vector3(face.x, ab.position.y + ab.size.y * 0.68, face.z), nsz, b.mat(Color(0.94, 0.92, 0.85)), b.furn, false)
			for i in 5:
				var mp := Vector3(face.x, ab.position.y + ab.size.y * rng2.randf_range(0.45, 0.8), face.z)
				if dir.z != 0.0: mp.x += rng2.randf_range(-0.3, 0.3)
				else: mp.z += rng2.randf_range(-0.3, 0.3)
				b.box("Magnet " + tag + " " + str(i), mp, Vector3(0.028, 0.028, 0.008) if dir.z != 0.0 else Vector3(0.008, 0.028, 0.028), b.mat(DETAIL_INK[rng2.randi() % DETAIL_INK.size()]), b.furn, false)
		"crate":
			_jar_row(Vector3(c.x, top, c.z), true, 2, c.x, tag)
		"coffeeTable":
			for i in 2:
				b.box("Book stack " + tag + " " + str(i), c + Vector3(-ab.size.x * 0.18, top + 0.013 + float(i) * 0.027, 0), Vector3(0.24 - 0.03 * float(i), 0.026, 0.17), b.mat(DETAIL_INK[(i + 1) % DETAIL_INK.size()]), b.furn, false)
			_dcyl("Mug " + tag, c + Vector3(ab.size.x * 0.2, top + 0.04, ab.size.z * 0.15), 0.035, 0.08, b.mat(Color(0.75, 0.35, 0.25)))


func _detail_dining(f: Dictionary, n: Node3D) -> void:
	if n == null:
		return
	var ab := _aabb_of(n)
	if ab.size == Vector3.ZERO:
		return
	var c := ab.get_center()
	var top := ab.end.y
	var tag := _dtag("dining", f)
	var along_x := ab.size.x >= ab.size.z
	var pm := b.mat_named("fabric", Color(0.55, 0.48, 0.40))
	var pi := 0
	for sx in [-0.30, 0.30]:
		for sz in [-0.30, 0.30]:
			var pos := c + (Vector3(sx * ab.size.x, 0, sz * ab.size.z) if along_x else Vector3(sz * ab.size.x, 0, sx * ab.size.z))
			pos.y = top + 0.004
			b.box("Placemat " + tag + " " + str(pi), pos, Vector3(0.40, 0.006, 0.28), pm, b.furn, false)
			pi += 1
	_dcyl("Centerpiece " + tag, c + Vector3(0, top + 0.07, 0), 0.05, 0.14, b.mat(Color(0.50, 0.42, 0.30)), 0.032)
	_dcyl("Candle " + tag + " 0", c + Vector3(0.16, top + 0.05, 0.1), 0.018, 0.10, b.mat(Color(0.93, 0.90, 0.82)))
	_dcyl("Candle " + tag + " 1", c + Vector3(-0.16, top + 0.035, -0.1), 0.018, 0.07, b.mat(Color(0.93, 0.90, 0.82)))
