class_name LevelBuilder
extends RefCounted
## Builds a night's room at run time from the generated models (res://assets/models, made by tools/blender) and the
## night data. So far: the kitchen layout, used by nights 1, 5, 6, 14 and 16. Positions use the prototype's room
## coordinates in cm (x east, y south). Models face +Z; walls face into the room.

const MODELS := "res://assets/models/"
const WALL_HEX := "ce8dcc6"  # the plain wall colour in the models: replaced by the night's wallpaper

var g: Game
var night: Dictionary
var root: Node3D
var furn: Node3D
var decor: Node3D
var foods: Node3D
var _toon := {}
static var _outline: StandardMaterial3D


func _init(game: Game, n: Dictionary) -> void:
	g = game
	night = n


static func W(x: float, y: float, h := 0.0) -> Vector3:
	return Nights.world(x, y, h)


# ---------- helpers ----------

func group(name: String, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = name
	(parent if parent else root).add_child(n)
	return n


func spawn(path: String, pos: Vector3, rot_deg := 0.0, parent: Node3D = null) -> Node3D:
	var ps := load(MODELS + path + ".glb") as PackedScene
	if ps == null:
		push_warning("Kitchen Rat: missing model " + path)
		return null
	var n := ps.instantiate() as Node3D
	(parent if parent else root).add_child(n)
	n.global_position = pos
	n.rotation.y = deg_to_rad(rot_deg)
	toonify(n)
	return n


## Flat banded shading with dark outlines, like the prototype's MeshToonMaterial.
func toonify(n: Node) -> void:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.08, 0.07, 0.09)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.004
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if not (mat is BaseMaterial3D):
				continue
			var key := mat.get_instance_id()
			if not _toon.has(key):
				var t := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				t.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				t.specular_mode = BaseMaterial3D.SPECULAR_TOON
				t.metallic = 0.0
				t.roughness = 0.9
				if t.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					t.next_pass = _outline
				_toon[key] = t
			m.set_surface_override_material(i, _toon[key])


static func aabb_of(n: Node3D) -> AABB:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = (inv * m.global_transform) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## World-space bounds.
static func world_aabb(n: Node3D) -> AABB:
	return n.global_transform * aabb_of(n)


## Scale to a footprint (cm) along the model's own X (width) and Z (depth); h scales the height. 0 keeps a size.
func fit(n: Node3D, w: float, d: float, h := 0.0) -> void:
	if n == null:
		return
	var b := aabb_of(n)
	var s := n.scale
	if w > 0.0 and b.size.x > 0.0001: s.x *= w / 100.0 / b.size.x
	if d > 0.0 and b.size.z > 0.0001: s.z *= d / 100.0 / b.size.z
	if h > 0.0 and b.size.y > 0.0001: s.y *= h / 100.0 / b.size.y
	n.scale = s


## Static collision from the meshes, plus an optional surface id ("chair", "table"…) the rat can stand on.
func collide(n: Node3D, surface := "") -> void:
	if n == null:
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = m.mesh.create_trimesh_shape()
		body.add_child(cs)
		m.add_child(body)
		if surface != "":
			body.set_meta("surface", surface)


func furn_piece(path: String, x: float, y: float, rot: float, surface: String, w := 0.0, d := 0.0, h := 0.0) -> Node3D:
	var n := spawn(path, W(x, y), rot, furn)
	if n == null:
		return null
	fit(n, w, d, h)
	collide(n, surface)
	return n


## The top of whatever is at (x, y): floor, counter, table…
func on_top(x: float, y: float) -> Vector3:
	var o := W(x, y, 240)
	var hit := g.ray(o, o + Vector3.DOWN * 3.0)
	return hit.position if not hit.is_empty() else W(x, y)


func mat(color: Color, texture := "", tiling := Vector2.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if texture != "":
		m.albedo_texture = load("res://assets/textures/" + texture + ".png")
		m.uv1_scale = Vector3(tiling.x, tiling.y, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func box(name: String, center: Vector3, size: Vector3, m: Material, parent: Node3D, solid := true) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = center
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	return mi


func add_zone(script: GDScript, name: String, pos: Vector3, size: Vector3, rot_deg := 0.0) -> Zone:
	var z: Zone = script.new()
	z.name = name
	z.size = size
	root.add_child(z)
	z.global_position = pos
	z.rotation.y = deg_to_rad(rot_deg)
	return z


static func hex(c) -> Color:
	var i := int(c)
	return Color8((i >> 16) & 255, (i >> 8) & 255, i & 255)


# ---------- build ----------

func build() -> void:
	root = group("Room", g)
	furn = group("Furniture")
	decor = group("Decor")
	foods = group("Food")
	_lighting()
	_room()
	_furniture()


## The second half runs after the physics engine knows the furniture (things are placed on top of it).
func build_contents() -> void:
	_decor()
	_nest()
	_knockables()
	_food()
	_traps()


func _lighting() -> void:
	var pal: Dictionary = night.get("pal", {})
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = hex(pal.get("fog", 0x0e1220))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.27, 0.42) * float(pal.get("hemi", 0.8))
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = hex(pal.get("fog", 0x0e1220))
	env.fog_density = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.62, 0.7, 1.0)
	moon.light_energy = 0.5 * float(pal.get("moon", 0.9))
	moon.shadow_enabled = true
	root.add_child(moon)
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(165.0), 0)  # from the window in the north wall

	for l in night.get("lights", []):
		var pl := OmniLight3D.new()
		pl.light_color = hex(l.get("c", 0xffa860))
		pl.light_energy = float(l.get("i", 1.0)) * 1.6
		pl.omni_range = float(l.get("r", 500)) / 100.0
		pl.shadow_enabled = true
		root.add_child(pl)
		pl.global_position = W(float(l.x), float(l.y), float(l.get("h", 60)))

	var room := OmniLight3D.new()  # the ceiling light: off at night, the owner switches it on
	room.name = "Ceiling light"
	room.light_color = Color(1.0, 0.93, 0.8)
	room.light_energy = 2.0
	room.omni_range = 9.0
	room.shadow_enabled = true
	room.visible = false
	root.add_child(room)
	room.global_position = W(480, 300, 200)
	g.room_light = room


static func _section(p: float) -> int:
	return clampi(floori(p / 120.0), 0, 7)


func _room() -> void:
	var pal: Dictionary = night.get("pal", {})
	var floor_tex := "floor_" + str(pal.get("floor", "tile"))
	var wall_tex := "wall_" + str(pal.get("wall", "stripes"))
	if not ResourceLoader.exists("res://assets/textures/" + floor_tex + ".png"): floor_tex = "floor_tile"
	if not ResourceLoader.exists("res://assets/textures/" + wall_tex + ".png"): wall_tex = "wall_stripes"
	var floor_mat := mat(Color.WHITE, floor_tex, Vector2(6, 3.75))
	var wall_mat := mat(Color.WHITE, wall_tex)
	var trim := mat(hex(0x7a4a2a))

	# floor (a thin solid slab) and ceiling (no collision, casts no shadow)
	var fl := box("Floor", Vector3(0, -0.05, 0), Vector3(9.6, 0.1, 6.0), floor_mat, root)
	var fm := (fl as MeshInstance3D).mesh as BoxMesh
	fm.size = Vector3(9.6, 0.1, 6.0)
	var ceil := box("Ceiling", Vector3(0, 2.55, 0), Vector3(9.6, 0.1, 6.0), mat(hex(pal.get("ceil", 0x22263a))), root, false)
	(ceil as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var north := []; var south := []; var west := []; var east := []
	north.resize(8); south.resize(8); west.resize(5); east.resize(5)
	var win: Dictionary = night.get("window", {})
	if float(win.get("w", 0)) > 0.0:
		north[_section(float(win.x) + float(win.w) / 2.0)] = "wall_window"
	south[1] = "wall_mousehole"
	east[clampi(floori(float(night.get("door", 300)) / 120.0), 0, 4)] = "wall_door"
	for c in night.get("cracks", []):
		var cx := float(c.get("x", 0)); var cy := float(c.get("y", 0))
		match str(c.wall):
			"s":
				if south[_section(cx)] == null: south[_section(cx)] = "wall_crack"
				_hide("crack", cx, 590, 44, 18)
			"n":
				if north[_section(cx)] == null: north[_section(cx)] = "wall_crack"
				_hide("crack", cx, 10, 44, 18)
			"w":
				var j := clampi(floori(cy / 120.0), 0, 4)
				if west[j] == null: west[j] = "wall_crack"
				_hide("crack", 10, cy, 18, 44)
			_:
				var j := clampi(floori(cy / 120.0), 0, 4)
				if east[j] == null: east[j] = "wall_crack"
				_hide("crack", 950, cy, 18, 44)
	var walls := group("Walls")
	for i in 8: _wall(north[i] if north[i] else "wall_section", 60 + 120 * i, -5, 0.0, walls, wall_mat)
	for i in 8: _wall(south[i] if south[i] else "wall_section", 60 + 120 * i, 605, 180.0, walls, wall_mat)
	for j in 5: _wall(west[j] if west[j] else "wall_section", -5, 60 + 120 * j, 90.0, walls, wall_mat)
	for j in 5: _wall(east[j] if east[j] else "wall_section", 965, 60 + 120 * j, -90.0, walls, wall_mat)
	for p in [Vector2(-5, -5), Vector2(965, -5), Vector2(-5, 605), Vector2(965, 605)]:
		box("Corner", W(p.x, p.y, 125), Vector3(0.1, 2.5, 0.1), trim, walls)

	var shade := spawn("rooms/chandelier" if str(night.get("lamp", "")) == "chandelier" else "rooms/lamp_shade", W(480, 300), 0.0, decor)
	if shade:
		shade.global_position.y = 2.5 - world_aabb(shade).size.y


func _wall(model: String, x: float, y: float, rot: float, parent: Node3D, wall_mat: Material) -> void:
	var n := spawn("rooms/" + model, W(x, y), rot, parent)
	if n == null:
		return
	collide(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with(WALL_HEX):
				m.set_surface_override_material(i, wall_mat)


func _hide(kind: String, x: float, y: float, w: float, d: float, rot := 0.0) -> void:
	var z := add_zone(HideSpot, "Hide: " + kind, W(x, y), Vector3(w / 100.0, 0.2, d / 100.0), rot) as HideSpot
	z.id = kind


func _furniture() -> void:
	# levels.js kitchenFurniture: counters along the north and west walls, fridge, island, a box as a step,
	# the table with chairs, a low shelf and a stool. Fronts face into the room.
	furn_piece("furniture/counter_corner", 36, 36, 0.0, "counter", 72, 72)
	var n := 12
	var w := (830.0 - 72.0) / n
	for i in n:
		furn_piece("furniture/counter_sink" if i == 6 else "furniture/counter_section", 72 + w * (i + 0.5), 36, 0.0, "counter", w, 72)
	for j in 4:
		furn_piece("furniture/counter_section", 36, 72 + 60 * (j + 0.5), 90.0, "counter", 60, 72)
	furn_piece("furniture/fridge", 895, 56, 0.0, "fridge", 130, 110)
	add_zone(HumZone, "Fridge hum", W(895, 140), Vector3(1.8, 1.2, 1.2))
	furn_piece("furniture/kitchen_island", 480, 295, 180.0, "island", 200, 90)
	furn_piece("furniture/cardboard_box", 608, 284, 0.0, "box", 44, 44, 44)
	var table := furn_piece("furniture/table_kitchen", 720, 445, 0.0, "table", 200, 130)
	if table:
		var cloth := table.find_child("tablecloth*", true, false) as Node3D
		var spec := {}
		for f in night.get("furn", []):
			if str(f.t) == "table": spec = f
		if cloth and int(spec.get("cloth", 0)) == 0:
			cloth.queue_free()
	_hide("table", 720, 445, 184, 114)
	for c in [[596, 420, 90], [596, 472, 90], [846, 446, -90]]:
		furn_piece("furniture/chair", c[0], c[1], c[2], "chair")
		_hide("chair", c[0], c[1], 28, 28)
	furn_piece("furniture/low_shelf", 231, 325, 0.0, "lowShelf", 62, 50)
	_hide("shelf", 231, 325, 54, 42)
	furn_piece("furniture/stool", 100, 252, 0.0, "stool")


func _decor() -> void:
	for p in night.get("props", []):
		match str(p.t):
			"foil":
				var c := W(float(p.x) + float(p.w) / 2.0, float(p.y) + float(p.h) / 2.0)
				fit(spawn("props/foil", c, 0.0, decor), float(p.w), float(p.h))
				(add_zone(NoisyZone, "Foil", c, Vector3(float(p.w) / 100.0, 0.2, float(p.h) / 100.0)) as NoisyZone).configure("foil")
			"breadbox":
				collide(spawn("props/bread_box", on_top(float(p.x) + float(p.w) / 2.0, float(p.y) + float(p.h) / 2.0), 0.0, decor))
			"noisy":
				_noisy(p)
			_:
				pass  # other props (TV, washer, sticky traps…) come with their rooms
	for f in night.get("furn", []):
		if bool(f.get("plate", false)):
			collide(spawn("food/plate", on_top(680, 432), 0.0, decor))
	spawn("props/cat_bed", Nights.pos(night.get("catBed")), 0.0, decor)  # no collision: the cat lies in it
	if (night.get("bowl", []) as Array).size() >= 2:
		collide(spawn("props/cat_bowl", Nights.pos(night.bowl), 0.0, decor))
	if (night.get("dock", []) as Array).size() >= 2:
		collide(spawn("props/vacuum_dock", Nights.pos(night.dock), -90.0, decor))


static func _noisy_model(kind: String) -> String:
	match kind:
		"puddle": return "props/puddle"
		"board": return "props/floorboard_worn"
		"bag": return "props/plastic_bag"
		"glasses": return "props/glass"
		"bottles": return "props/bottle"
		"popper": return "props/party_popper"
		"balloon": return "props/balloon_red" if randf() < 0.5 else "props/balloon_blue"
		"confetti": return "props/confetti"
		"squeaky": return "props/squeaky_toy"
		"remote": return "props/tv_remote"
		"grain": return "props/grain_spill"
		"cord": return "props/lamp_cord"
		"hanger": return "props/hangers"
		"litter": return "props/litter_box"
		"pipe": return "props/pipe"
		"lego": return "props/lego_bricks"
		"musicbox": return "props/music_box"
		"nightlight": return "props/night_light"
	return ""


func _noisy(p: Dictionary) -> void:
	var kind := str(p.get("kind", ""))
	var rect := float(p.get("w", 0)) > 0.0 and float(p.get("h", 0)) > 0.0
	var cx := float(p.x) + (float(p.w) / 2.0 if rect else 0.0)
	var cy := float(p.y) + (float(p.h) / 2.0 if rect else 0.0)
	var r := float(p.get("r", 0))
	if r <= 0.0: r = 16.0 if kind == "plate" else (10.0 if kind == "remote" else (11.0 if kind == "squeaky" else 20.0))
	var at := W(cx, cy) if bool(p.get("floor", false)) else on_top(cx, cy)
	var model := _noisy_model(kind)
	var n := spawn(model, at, randf() * 360.0, decor) if model != "" else null
	if n and rect and (kind == "board" or kind == "confetti"):
		n.rotation.y = 0.0
		fit(n, float(p.w), float(p.h))
	var size := Vector3(float(p.w) / 100.0, 0.2, float(p.h) / 100.0) if rect else Vector3(r / 50.0, 0.2, r / 50.0)
	var z := add_zone(NoisyZone, "Noisy: " + kind, at, size) as NoisyZone
	z.configure(kind)
	if kind == "balloon" and n:
		z.hide_when_used = n


static func _knock_model(kind: String) -> String:
	match kind:
		"cup": return "props/mug"
		"carton", "book": return "props/small_box"
		"vase": return "props/jar"
	return "props/" + kind


func _knockables() -> void:
	for k in night.get("knocks", []):
		var path := _knock_model(str(k.kind))
		if not ResourceLoader.exists(MODELS + path + ".glb"):
			continue
		var body := Knockable.new()
		body.kind = str(k.kind)
		body.trap = bool(k.get("trap", false))
		body.spawn = str(k.get("spawn", ""))
		body.push_dir = (W(float(k.toX), float(k.toY)) - W(float(k.x), float(k.y))).normalized()
		body.mass = 0.25
		body.collision_layer = 1
		body.collision_mask = 1
		decor.add_child(body)
		body.global_position = on_top(float(k.x), float(k.y))
		var model := spawn(path, body.global_position, 0.0, body)
		var b := aabb_of(model)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b.size
		cs.shape = sh
		cs.position = b.get_center()
		body.add_child(cs)
		g.knockables.append(body)


const FIND_LABELS := {
	"button": "A shiny button! The pups will love it.", "sock": "A soft sock for the nest!",
	"photo": "An old photo of the owner as a kid.", "toy": "A tiny toy mouse for the pups!",
	"thimble": "A thimble! A perfect cup for the pups.", "ring": "A gold ring. The owner lost it long ago.",
	"drawing": "A kid’s drawing… of a rat. It’s you!", "letter": "A letter: “Exterminator, Saturday morning.” Uh-oh.",
	"candle": "A birthday candle for the nest.", "marble": "A glass marble! The pups can roll it around.",
	"battery": "The spare battery! His flashlight will die soon.",
}


func _food() -> void:
	var fd: Dictionary = night.get("food", {})
	for s in fd.get("spots", []):
		var at := W(float(s.x), float(s.y)) if bool(s.get("floor", false)) else on_top(float(s.x), float(s.y))
		var f := g.spawn_food(str(s.type), at, str(s.get("tag", "")), false)
		if f:
			f.hidden = bool(s.get("hidden", false))
	for sc in night.get("secrets", []):
		var kind := str(sc.kind)
		var model := "finds/toy_mouse" if kind == "toy" else "finds/" + kind
		if not ResourceLoader.exists(MODELS + model + ".glb"):
			model = "finds/button"
		var at := W(float(sc.x), float(sc.y)) if bool(sc.get("floor", false)) else on_top(float(sc.x), float(sc.y))
		var f := g.spawn_model_food(model, at)
		f.type = kind
		f.is_find = true
		var lbl := str(sc.get("label", ""))
		f.label = lbl if lbl != "" else FIND_LABELS.get(kind, "A find for the nest!")


func _traps() -> void:
	for t in night.get("trapSpots", []):
		g.add_trap(W(float(t.x), float(t.y)), bool(t.get("hidden", false)))


# ---------- the nest behind the mouse hole ----------

func _nest() -> void:
	var nest := group("Nest")
	var soil := mat(hex(0x4a3628))
	var earth := mat(hex(0x3a2a20))
	# x 10…250, y 600…780 behind the south wall (the mouse hole is at x = 180)
	box("Nest floor", W(130, 690, -5), Vector3(2.4, 0.1, 1.8), soil, nest)
	box("Back", W(130, 785, 50), Vector3(2.6, 1.0, 0.1), earth, nest)
	box("Side", W(5, 690, 50), Vector3(0.1, 1.0, 1.9), earth, nest)
	box("Side", W(255, 690, 50), Vector3(0.1, 1.0, 1.9), earth, nest)
	var roof := box("Roof", W(130, 690, 95), Vector3(2.6, 0.1, 1.9), earth, nest)
	collide(spawn("rooms/nest", W(90, 725), 0.0, nest))
	var light := OmniLight3D.new()
	light.light_color = Color8(0xff, 0xd0, 0xa0)
	light.light_energy = 0.7
	light.omni_range = 3.0
	nest.add_child(light)
	light.global_position = W(140, 690, 45)
	for p in [[70, 715, 20, "sleep"], [105, 735, -60, "sleep"], [80, 745, 150, "idle"], [125, 705, 200, "sniff"]]:
		var pup := spawn("characters/rat_pup", W(p[0], p[1], 2), p[2], nest)
		if pup:
			var cp := ClipPlayer.new(pup)
			cp.play(p[3], 0.0)
	add_zone(NestZone, "Nest", W(130, 692), Vector3(2.4, 0.9, 1.75))
	g.hole = W(180, 585)
