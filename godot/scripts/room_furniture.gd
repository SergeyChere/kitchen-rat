class_name RoomFurniture
extends RefCounted
## Builds a room's furniture from the night's furn list (levels.js livingFurniture, pantryFurniture, diningFurniture…),
## like the prototype's builder B[t]: each entry is a rect (x, y = north-west corner, w along x, h along y, in cm).
## Pieces against a wall face into the room. Also the per-room decor (rugs, wall art) and the flickering lights.

var b: LevelBuilder
var g: Game


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
func place(model: String, f: Dictionary, surface: String, height := 0.0, rot = null) -> Node3D:
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


func light(at: Vector3, color: Color, energy: float, rng: float, kind := "fire") -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
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
			"fridge": place("furniture/fridge", f, "fridge")
			"island": place("furniture/kitchen_island", f, "island", 0.0, 180.0)
			"box":
				var ht := float(f.get("ht", 44))
				place("furniture/cardboard_box_tall" if ht > 70.0 else "furniture/cardboard_box", f, "box", ht)
			"crate": place("furniture/crate", f, "crate", float(f.get("ht", 40)))
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
					if bool(f.get("dining", false)):
						light(W(cx, cy, ht + 60), Color8(0xff, 0xb0, 0x60), 0.7, 3.0)
				hide("table", f)
			"coffeeTable":
				place("furniture/coffee_table", f, "table", 0.0, 0.0)
				hide("table", f)
			"bench":
				place("furniture/workbench", f, "table", 0.0, 0.0)
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
				place("furniture/sofa" if t == "sofa" else "furniture/armchair", f, "sofa", 0.0, r)
				hide("sofa", f, 12.0)
			"wall":
				var wm := b.mat(LevelBuilder.hex(0x8a8a9a), "wall_" + str(g.night.get("pal", {}).get("wall", "stripes")))
				b.box("Inner wall", W(cx, cy, 115), Vector3(w / 100.0, 2.3, d / 100.0), wm, b.furn)
			"tvStand":
				place("furniture/tv_stand", f, "tv")
				var tv := light(W(cx, y + d + 70, 90), Color(0.56, 0.7, 1.0), 1.6, 4.6, "tv")
				g.tv_light = tv
				tv.visible = not bool(g.night.get("tvOff", false))
			"bookcase": place("furniture/bookcase", f, "bookcase")
			"fireplace":
				place("furniture/fireplace", f, "fireplace")
				var out := W(x + w + 30, cy, 40) if side(x, y, w, d) == "w" else W(cx, cy, 40)
				light(out, Color8(0xff, 0x8a, 0x3a), 2.2, 4.2)
			"sideTable": place("furniture/side_table", f, "side", float(f.get("ht", 60)))
			"lamp":
				b.collide(b.spawn("furniture/floor_lamp", W(cx, cy), 0.0, b.furn))
				light(W(cx, cy, 138), Color8(0xff, 0xc2, 0x7a), 1.3, 3.8, "steady")
			"plant": b.collide(b.spawn("furniture/plant", W(cx, cy), randf() * 360.0, b.furn))
			"washer": place("furniture/dryer" if bool(f.get("dryer", false)) else "furniture/washer", f, "washer")
			"basket": place("furniture/laundry_basket", f, "basket", float(f.get("ht", 45)))
			"cans": place("furniture/cans_stack", f, "cans", float(f.get("ht", 30)))
			"shelfUnit": place("furniture/shelf_unit", f, "shelf")
			"boiler":
				place("furniture/boiler", f, "boiler", 0.0, -90.0 if x > 480.0 else 90.0)
				light(W(cx - 50, cy, 40), Color8(0xff, 0x8a, 0x3a), 1.4, 3.0)
			"sideboard": place("furniture/sideboard", f, "sideboard")
			"cabinetTall":
				# modelled long along its own Z, front toward +X: as is against the west wall
				var n := b.spawn("furniture/cabinet_tall", W(cx, cy), 0.0 if x < 480.0 else 180.0, b.furn)
				b.fit(n, w, d)
				b.collide(n)
			"ottoman": place("furniture/ottoman", f, "ottoman", 0.0, 0.0)
			"barCart": place("furniture/bar_cart", f, "cart", 0.0, 0.0)
			_:
				push_warning("Kitchen Rat: no builder for furniture " + t)


# ---------- decor ----------

func decor(kind: String) -> void:
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
