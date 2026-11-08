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


## Under a sofa or an armchair there's only room for a crouching rat: an invisible slab 10 cm up stops her unless she
## sneaks (crouched she is lower).
func low_roof(f: Dictionary, inset: float) -> void:
	var w := float(f.get("w", 32)); var d := float(f.get("h", 32))
	var slab := b.box("Low clearance", W(float(f.x) + w / 2.0, float(f.y) + d / 2.0, 11.5), Vector3((w - inset * 2.0) / 100.0, 0.03, (d - inset * 2.0) / 100.0), b.mat(Color.BLACK), b.furn)
	slab.visible = false


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
				low_roof(f, 4.0)
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
	var extras := ["furniture/plant", "furniture/floor_lamp"]
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
	var wood := b.mat(LevelBuilder.hex(0x8a5a34))
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
	return n != null
