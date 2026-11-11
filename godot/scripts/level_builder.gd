class_name LevelBuilder
extends RefCounted
## Builds a night's room at run time from the generated models (res://assets/models, made by tools/blender) and the
## night data. The kitchen (decor "kitchen") is laid out by hand like levels.js kitchenFurniture; every other room is
## built from the night's furn list, the way the prototype's builder B[t] does it. Positions use the prototype's room
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
const OUTLINE := 0.0055  # outline width (m): bold, cartoon


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


## Flat banded shading with dark outlines, like the prototype's MeshToonMaterial. The outline grows in the mesh's
## own units, so models scaled on a root node (the imported characters) get it sized back to ~4 mm.
func toonify(n: Node) -> void:
	if _outline == null:
		_outline = _outline_mat(OUTLINE)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var ref: Node3D = m
		var sk := m.get_node_or_null(m.skeleton) as Skeleton3D if m.skin else null
		if sk:
			ref = sk
		var sc := ref.global_transform.basis.get_scale().x
		var grow := snappedf(OUTLINE / maxf(sc, 0.0001), 0.0001) if absf(sc - 1.0) > 0.01 else OUTLINE
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if not (mat is BaseMaterial3D):
				continue
			var key := str(mat.get_instance_id()) + ":" + str(grow)
			if not _toon.has(key):
				var t := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				_cel(t)
				if m.skin:
					t.roughness = 0.5  # characters are faceted low-poly: a crisp step would chequer every face
				var fine := mat.resource_name.begins_with("Whisker") or mat.resource_name.begins_with("Eye")  # too thin for an outline
				if t.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not fine:
					t.next_pass = _outline if grow == OUTLINE else _outline_mat(grow)
				_toon[key] = t
			m.set_surface_override_material(i, _toon[key])


## The game's look: bright cel shading (not realistic). Two clean steps of light and shadow, no glossy highlights,
## a soft coloured rim on the edges facing away from the light, like a cartoon.
static func _cel(t: BaseMaterial3D) -> void:
	t.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	t.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	t.metallic = 0.0
	t.roughness = 0.12  # in toon mode this is how soft the light/shadow edge is: a crisp line
	t.rim_enabled = true
	t.rim = 0.35
	t.rim_tint = 0.6
	if t.albedo_texture == null:
		var c := t.albedo_color
		t.albedo_color = Color.from_hsv(c.h, minf(c.s * 1.18, 1.0), minf(c.v * 1.06, 1.0), c.a)  # a little more vivid


static func _outline_mat(grow: float) -> StandardMaterial3D:
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = Color(0.08, 0.07, 0.09)
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = grow
	return o


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
## Furniture and props (under furn / decor) are split into their parts (legs, top, seat…): every part that is
## box-like (fills at least 65% of its bounding box) gets a solid box, the rest (bowls, curved things) a two-sided
## triangle mesh. Boxes have no gaps to slip into and no hollow inside to end up in.
func collide(n: Node3D, surface := "") -> void:
	if n == null:
		return
	var parts := n.get_parent() == furn or n.get_parent() == decor or (n.get_parent() != null and n.get_parent().get_parent() == decor)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if _soft(m.name):
			continue
		var rest := []
		if parts:
			# boxes: one unscaled body at the mesh, boxes placed in it (shapes can't take a non-uniform scale)
			var gt := m.global_transform
			var sc := gt.basis.get_scale()
			var bx := StaticBody3D.new()
			bx.collision_layer = 1
			bx.collision_mask = 0
			bx.top_level = true
			m.add_child(bx)
			bx.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
			if surface != "":
				bx.set_meta("surface", surface)
			for isl in _islands(m.mesh):
				if isl[2] >= 0.65:
					var bb: AABB = isl[0]
					var cs := CollisionShape3D.new()
					var sh := BoxShape3D.new()
					sh.size = Vector3(maxf(bb.size.x * sc.x, 0.004), maxf(bb.size.y * sc.y, 0.004), maxf(bb.size.z * sc.z, 0.004))
					cs.shape = sh
					cs.position = bx.global_transform.affine_inverse() * (gt * bb.get_center())
					bx.add_child(cs)
				else:
					rest.append_array(isl[1])
		if not parts or not rest.is_empty():
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			m.add_child(body)
			if surface != "":
				body.set_meta("surface", surface)
			var cs := CollisionShape3D.new()
			var tri := ConcavePolygonShape3D.new()
			tri.set_faces(PackedVector3Array(rest) if parts else m.mesh.get_faces())
			tri.backface_collision = true
			cs.shape = tri
			body.add_child(cs)


## The mesh's connected parts: [local AABB, triangle vertices, how much of the AABB it fills (0…1)].
static func _islands(mesh: Mesh) -> Array:
	var faces := mesh.get_faces()  # 3 vertices per triangle
	var key := {}  # snapped position → vertex id
	var parent := PackedInt32Array()
	var ids := PackedInt32Array()
	ids.resize(faces.size())
	for i in faces.size():
		var p := faces[i]
		var k := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
		if not key.has(k):
			key[k] = parent.size()
			parent.append(parent.size())
		ids[i] = key[k]
	var find := func(a: int) -> int:
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	for t in range(0, faces.size(), 3):
		var a: int = find.call(ids[t])
		for j in [1, 2]:
			var b: int = find.call(ids[t + j])
			if a != b:
				parent[b] = a
	var groups := {}  # root → [verts]
	for t in range(0, faces.size(), 3):
		var r: int = find.call(ids[t])
		if not groups.has(r):
			groups[r] = []
		groups[r].append_array([faces[t], faces[t + 1], faces[t + 2]])
	var out := []
	for r in groups:
		var vs: Array = groups[r]
		var bb := AABB(vs[0], Vector3.ZERO)
		var vol := 0.0
		for t in range(0, vs.size(), 3):
			bb = bb.expand(vs[t]).expand(vs[t + 1]).expand(vs[t + 2])
			vol += (vs[t] as Vector3).dot((vs[t + 1] as Vector3).cross(vs[t + 2])) / 6.0
		var bv := maxf(bb.size.x, 0.0001) * maxf(bb.size.y, 0.0001) * maxf(bb.size.z, 0.0001)
		out.append([bb, vs, absf(vol) / bv])
	return out


## Cloth, blankets and screens: no collision, and they don't count for sizing.
static func _soft(n: String) -> bool:
	var l := n.to_lower()
	return l.contains("cloth") or l.contains("blanket") or l.contains("pillow") or l.contains("teddy") or l.contains("screen")


## Water in the sink's basin (the model's bowl: 40 × 36 cm inside, bottom at 74 cm, water up to 84 cm).
func _sink_water(n: Node3D) -> void:
	var bottom := n.to_global(Vector3(0, 0.74, 0))
	var surface := n.to_global(Vector3(0, 0.84, 0))
	var sz := Vector3(0.40 * n.scale.x, 0.14, 0.36 * n.scale.z)
	var z := add_zone(SinkWater, "Sink water", bottom, sz, rad_to_deg(n.rotation.y)) as SinkWater
	z.setup(surface.y)


func furn_piece(path: String, x: float, y: float, rot: float, surface: String, w := 0.0, d := 0.0, h := 0.0) -> Node3D:
	var n := spawn(path, W(x, y), rot, furn)
	if n == null:
		return null
	fit(n, w, d, h)
	if surface in ["fridge", "cabinet"]:
		collide_box(n, surface)  # closed boxes: no way inside, a flat top to walk on
	else:
		collide(n, surface)
	if path in ["furniture/counter_section", "furniture/counter_sink", "furniture/counter_corner", "furniture/kitchen_island"]:
		apply_countertop(n)  # round 12d: the stone finally reaches the counters
	return n


## One solid box over the whole model.
func collide_box(n: Node3D, surface := "") -> void:
	var bb := world_aabb(n)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bb.size
	cs.shape = sh
	body.add_child(cs)
	furn.add_child(body)
	body.global_position = bb.get_center()
	if surface != "":
		body.set_meta("surface", surface)
	n.set_meta("box_body", body)


## The top of whatever is at (x, y): floor, counter, table…
func on_top(x: float, y: float) -> Vector3:
	var o := W(x, y, 240)
	var hit := g.ray(o, o + Vector3.DOWN * 3.0)
	return hit.position if not hit.is_empty() else W(x, y)


## A named demo material (demo polish, plan point 2): the procedural texture from tools/make_textures.py
## when it has been generated into assets/textures/, the flat colour until then — so the game never breaks
## on a missing texture. Names: wood, wood_dark, fabric, leather, ceramic_tile, metal_matte, cardboard,
## plastic, counter_stone.
## How each named surface behaves as a material: [roughness, metallic]. Round 3: every surface is
## finished on its own instead of sharing the toon defaults — tile and stone are smooth enough to
## catch the moon patch, metal conducts, fabric and cardboard drink the light.
const SURFACE_PROPS := {
	"wood": [0.72, 0.0], "wood_dark": [0.78, 0.0], "fabric": [0.96, 0.0], "leather": [0.55, 0.0],
	"ceramic_tile": [0.3, 0.0], "metal_matte": [0.38, 0.65], "cardboard": [0.92, 0.0],
	"plastic": [0.5, 0.0], "counter_stone": [0.27, 0.0],
}


static func surface_props(tex_name: String) -> Array:
	return SURFACE_PROPS.get(tex_name, [0.85, 0.0])


func mat_named(tex_name: String, color: Color, tiling := Vector2.ONE) -> StandardMaterial3D:
	# round 6: the texture comes from TextureLib (CDN pack → repo file → painted
	# in-engine by TextureGen) — no Python step and no heavy binaries in the repo
	var tex := TextureLib.get_texture(tex_name)
	if tex != null:
		var m := mat(color)
		m.albedo_texture = tex
		m.uv1_scale = Vector3(tiling.x, tiling.y, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.set_meta("tile_m", 0.5)  # one texture tile ~ 0.5 m: box() scales the UV by the box size
		var p := surface_props(tex_name)
		m.roughness = float(p[0])
		m.metallic = float(p[1])
		_add_normal(m, tex_name)
		_add_rough(m, tex_name)
		return m
	return mat(color)


## A <name>_normal.png (e.g. the normal map from a CC0 PBR set) is picked up
## automatically wherever TextureLib finds the colour map — CDN pack or repo file.
static func _add_normal(m: StandardMaterial3D, tex_name: String) -> void:
	var n := TextureLib.get_texture(tex_name + "_normal", false)
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n


## Round 16: a <name>_rough map from the pack (ambientCG Roughness / Poly Haven
## Rough) replaces the flat roughness constant — the map carries the values, so
## the scalar goes to 1.0 and the surface stops shining uniformly.
static func _add_rough(m: StandardMaterial3D, tex_name: String) -> void:
	var r := TextureLib.get_texture(tex_name + "_rough", false)
	if r != null:
		m.roughness = 1.0
		m.roughness_texture = r


## Give a placed model a real surface (demo polish, plan point 2): the generated texture laid over its
## toon materials, tinted by `tint` (the furniture's own colour from the night data, white = as authored).
## The tint is divided by the textures' average brightness (~0.45), so the result lands near the
## requested colour instead of going twice as dark. No texture file -> no change at all.
## Round 12c (asked: "check ALL the other items"): should this surface take the
## furniture texture? The models bake their props into the same mesh — the
## bookcase's books, the shelf unit's jars, the workbench's steel tools — and
## the blanket pass turned them ALL into the furniture's material (the wooden
## TV screen was just the loudest casualty). Rules, by texture:
## - wood lands only on wood-toned surfaces: orange-brown hue, clearly
##   saturated, neither near-black trim nor pale pages/paper;
## - plastic and metal skip near-black surfaces (a washer's glass door);
## - everything else (fabric, cardboard) takes the blanket as before.
static func _takes_texture(tex_name: String, src: BaseMaterial3D) -> bool:
	var c := src.albedo_color
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	if tex_name == "plastic" or tex_name == "metal_matte":
		return mx > 0.08
	if tex_name != "wood" and tex_name != "wood_dark":
		return true
	if mx < 0.05 or mx > 0.8 or mx - mn < 0.001:
		return false
	if (mx - mn) / mx < 0.3:
		return false  # greys and pales: steel, stone, paper
	var hue := 0.0
	if mx == c.r:
		hue = fmod((c.g - c.b) / (mx - mn), 6.0)
	elif mx == c.g:
		hue = (c.b - c.r) / (mx - mn) + 2.0
	else:
		hue = (c.r - c.g) / (mx - mn) + 4.0
	hue *= 60.0
	if hue < 0.0:
		hue += 360.0
	return hue >= 10.0 and hue <= 52.0


## Round 12d: the countertop. The counter models (section / sink / corner /
## island) wear their stock materials, so the stone texture — painted or
## downloaded — never reached a single counter. The top is found by GEOMETRY,
## not colour: among the thin slabs in the model's upper band, the one whose
## top is highest. Fruit bowls, soap bottles and cabinet fronts sit elsewhere
## (or are thicker than a slab) and keep the materials they were made with.
## Round 14 (asked: "a stick with a bulb"): a floor lamp gets its shade, and
## the bulb inside actually glows.
func shade_lamp(n: Node3D) -> void:
	if n == null:
		return
	var bulb: MeshInstance3D = null
	for c in n.find_children("*", "MeshInstance3D", true, false):
		if "bulb" in (c as MeshInstance3D).name.to_lower():
			bulb = c as MeshInstance3D
	if bulb == null:
		return
	for i in bulb.mesh.get_surface_count():
		var d := StandardMaterial3D.new()
		d.albedo_color = Color(1.0, 0.85, 0.55)
		d.emission_enabled = true
		d.emission = Color(1.0, 0.72, 0.35)
		d.emission_energy_multiplier = 1.4
		bulb.set_surface_override_material(i, d)
	var bc := world_aabb(bulb).get_center()
	var shade := spawn("rooms/lamp_shade", bc, 0.0, n.get_parent())
	if shade:
		var sb := world_aabb(shade)
		shade.global_position += bc + Vector3(0, 0.04, 0) - sb.get_center()


## A plain mesh box with no body — dressing that must never snag her feet.
func _mesh_box(size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Round 15 (asked): a gas hob on the counter — black glass, four burners
## under iron grates, and an oven front with knobs on the face below.
## Mesh-only: her footing stays the counter's own, exactly as before.
func _stove(piece: Node3D) -> void:
	var bb := world_aabb(piece)
	var top := bb.end.y
	var cx := bb.get_center().x
	var cz := bb.get_center().z
	var glass := mat(Color(0.05, 0.05, 0.06))
	glass.roughness = 0.25
	glass.metallic = 0.2
	var iron := mat(Color(0.08, 0.08, 0.09))
	iron.roughness = 0.6
	iron.metallic = 0.5
	var plate := _mesh_box(Vector3(0.56, 0.008, 0.62), glass)
	plate.name = "Cooktop"
	decor.add_child(plate)
	plate.global_position = Vector3(cx, top + 0.004, cz)
	for off in [[-0.14, -0.16], [0.14, -0.16], [-0.14, 0.16], [0.14, 0.16]]:
		var burn := MeshInstance3D.new()
		burn.name = "Burner"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.055
		cm.bottom_radius = 0.065
		cm.height = 0.010
		burn.mesh = cm
		burn.material_override = iron
		burn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		decor.add_child(burn)
		burn.global_position = Vector3(cx + float(off[0]), top + 0.012, cz + float(off[1]))
		var g1 := _mesh_box(Vector3(0.20, 0.007, 0.028), iron)
		g1.name = "Grate"
		decor.add_child(g1)
		g1.global_position = Vector3(cx + float(off[0]), top + 0.020, cz + float(off[1]))
		var g2 := _mesh_box(Vector3(0.028, 0.007, 0.20), iron)
		g2.name = "Grate"
		decor.add_child(g2)
		g2.global_position = Vector3(cx + float(off[0]), top + 0.020, cz + float(off[1]))
	var front := bb.end.z
	var door := _mesh_box(Vector3(0.52, 0.52, 0.012), glass)
	door.name = "Oven door"
	decor.add_child(door)
	door.global_position = Vector3(cx, 0.50, front + 0.004)
	var steel := mat(Color(0.55, 0.57, 0.60))
	steel.metallic = 0.85
	steel.roughness = 0.3
	var handle := MeshInstance3D.new()
	handle.name = "Oven handle"
	var hm := CylinderMesh.new()
	hm.top_radius = 0.011
	hm.bottom_radius = 0.011
	hm.height = 0.46
	handle.mesh = hm
	handle.material_override = steel
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decor.add_child(handle)
	handle.rotation.z = PI / 2.0
	handle.global_position = Vector3(cx, 0.80, front + 0.028)
	for k in 4:
		var knob := MeshInstance3D.new()
		knob.name = "Stove knob"
		var km := CylinderMesh.new()
		km.top_radius = 0.013
		km.bottom_radius = 0.016
		km.height = 0.022
		knob.mesh = km
		knob.material_override = iron
		knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		decor.add_child(knob)
		knob.rotation.x = PI / 2.0
		knob.global_position = Vector3(cx - 0.21 + k * 0.14, 0.845, front + 0.012)


## Round 15: a standing lamp for a tall JSON light — a weighted base, a
## real pole, and a fabric shade with the bulb glowing inside it. The
## omni sits at the bulb, so the light and its source are one point.
func _lamp_stand(x: float, y: float, h_cm: float, col: Color) -> void:
	var dark := mat(hex(0x2a2320))
	var base := MeshInstance3D.new()
	base.name = "Lamp base"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.10
	bm.bottom_radius = 0.12
	bm.height = 0.025
	base.mesh = bm
	base.material_override = dark
	root.add_child(base)
	base.global_position = W(x, y, 1.2)
	var pole := MeshInstance3D.new()
	pole.name = "Lamp pole"
	var pm := CylinderMesh.new()
	pm.top_radius = 0.013
	pm.bottom_radius = 0.016
	pm.height = (h_cm - 10.0) / 100.0
	pole.mesh = pm
	pole.material_override = dark
	root.add_child(pole)
	pole.global_position = W(x, y, (h_cm - 10.0) / 2.0 + 1.0)
	var shade := MeshInstance3D.new()
	shade.name = "Lamp shade"
	var sm := CylinderMesh.new()
	sm.top_radius = 0.075
	sm.bottom_radius = 0.115
	sm.height = 0.17
	sm.cap_top = false
	sm.cap_bottom = false
	shade.mesh = sm
	var shmat := StandardMaterial3D.new()
	shmat.albedo_color = Color(0.93, 0.84, 0.64)
	shmat.emission_enabled = true
	shmat.emission = Color(1.0, 0.76, 0.44)
	shmat.emission_energy_multiplier = 0.5
	shmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.material_override = shmat
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shade)
	shade.global_position = W(x, y, h_cm - 2.0)
	var bulb := MeshInstance3D.new()
	bulb.name = "Lamp bulb"
	var km := SphereMesh.new()
	km.radius = 0.030
	km.height = 0.06
	bulb.mesh = km
	var kmat := StandardMaterial3D.new()
	kmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kmat.albedo_color = col
	bulb.material_override = kmat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	bulb.global_position = W(x, y, h_cm - 2.0)


## Round 15 (asked: the nest entrance looks bad): over the model's flat
## arch plate goes a real hole — a ragged dark opening with a rim of
## chipped plaster, and crumbs of plaster on the floor beneath it.
func _mouse_hole() -> void:
	var grp := Node3D.new()
	grp.name = "Mouse hole"
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var radii: Array = []
	for i in 10:
		radii.append(0.15 * rng.randf_range(0.7, 1.14))
	var rim := MeshInstance3D.new()
	rim.mesh = _blob_mesh(radii, 1.22)
	rim.material_override = mat(Color(0.72, 0.64, 0.52))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.position.z = -0.004
	grp.add_child(rim)
	var dark := MeshInstance3D.new()
	dark.mesh = _blob_mesh(radii, 1.0)
	dark.material_override = mat(hex(0x050506))
	dark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grp.add_child(dark)
	grp.scale = Vector3(1.12, 0.92, 1)
	grp.rotation.y = PI
	root.add_child(grp)
	grp.global_position = W(180, 597, 13.5)
	var plaster := mat(Color(0.72, 0.64, 0.52))
	for c in [[168, 590], [186, 588], [176, 592], [193, 591]]:
		var crumb := _mesh_box(Vector3(0.028, 0.014, 0.022), plaster)
		root.add_child(crumb)
		crumb.global_position = W(float(c[0]), float(c[1]), 0.7)
		crumb.rotation.y = rng.randf() * TAU


## Round 15: a tablecloth wears the woven gingham (TextureGen
## "tablecloth"), tinted by the night's cloth colour — never a flat fill.
func dress_tablecloth(n: Node3D, tint: Color) -> void:
	var tex := TextureLib.get_texture("tablecloth")
	if n == null or tex == null:
		return
	var cm := StandardMaterial3D.new()
	cm.albedo_color = tint
	cm.albedo_texture = tex
	cm.uv1_scale = Vector3(2.5, 2.5, 1)
	cm.roughness = 0.94
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if "tablecloth" in m.name.to_lower():
			for i in m.mesh.get_surface_count():
				m.set_surface_override_material(i, cm)


## Round 14 (asked: the foil reads as plain white scraps): crinkle facets,
## real metal — foil must flash under the moon patch, not sit there as paper.
func dress_foil(n: Node3D) -> void:
	if n == null:
		return
	var tex := TextureLib.get_texture("crinkle")
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var s := m.get_active_material(i) as BaseMaterial3D
			if s == null:
				continue
			var d := s.duplicate() as StandardMaterial3D
			d.metallic = 0.85
			d.roughness = 0.42
			if tex != null:
				d.albedo_texture = tex
				d.albedo_color = Color(0.92, 0.95, 1.02)
				_add_normal(d, "crinkle")
			m.set_surface_override_material(i, d)


## Round 14 (asked: the plate is just a white circle): porcelain — warm white,
## glossy enough to catch a rim of light.
func dress_plate(n: Node3D) -> void:
	if n == null:
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var s := m.get_active_material(i) as BaseMaterial3D
			if s == null:
				continue
			var d := s.duplicate() as StandardMaterial3D
			d.albedo_color = Color(0.93, 0.90, 0.84)
			d.roughness = 0.16
			m.set_surface_override_material(i, d)


func apply_countertop(n: Node3D) -> void:
	var tex := TextureLib.get_texture("counter_stone")
	if n == null or tex == null:
		return
	var inv := n.global_transform.affine_inverse()
	var all := AABB()
	var first := true
	var mis: Array[MeshInstance3D] = []
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mis.append(mi)
		var bb: AABB = (inv * mi.global_transform) * mi.get_aabb()
		all = bb if first else all.merge(bb)
		first = false
	if first:
		return
	var cands: Array = []  # [mesh, surface, box, uv_span]
	var top_end := -1.0e9
	for mi in mis:
		var to_local := inv * mi.global_transform
		for i in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var sb := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				sb = sb.expand(v)
			sb = to_local * sb
			if sb.size.y <= 0.08:  # round 15: any thin slab — the old upper-band test measured from the model's tallest prop (faucet, plant) and the corner and sink tops fell below it
				var span := Vector2(1, 1)
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				if not uvs.is_empty():
					var mn := Vector2(1.0e9, 1.0e9)
					var mx := Vector2(-1.0e9, -1.0e9)
					for t2 in uvs:
						mn = mn.min(t2)
						mx = mx.max(t2)
					span = Vector2(maxf(mx.x - mn.x, 0.05), maxf(mx.y - mn.y, 0.05))
				cands.append([mi, i, sb, span])
				top_end = maxf(top_end, sb.end.y)
	if cands.is_empty():
		return
	# round 15 (playtest: the kitchen CORNER and the SINK stayed bare):
	# group the thin surfaces by their top height and dress the group that
	# reads as the worktop — the most area up there, ties toward the higher
	# top. The floor plinth is thin too, and the bits standing ON the slab
	# are thinner still; neither out-areas the slab itself.
	var groups := {}
	for cd0 in cands:
		var cb0 := cd0[2] as AABB
		var gk := int(round(cb0.end.y * 50.0))
		if not groups.has(gk):
			groups[gk] = [0.0, cb0.end.y]
		groups[gk][0] = float(groups[gk][0]) + cb0.size.x * cb0.size.z
	var best_key := -1
	var best_score := -1.0
	for gk2 in groups:
		var gscore := float(groups[gk2][0]) * (0.45 + float(groups[gk2][1]))
		if gscore > best_score:
			best_score = gscore
			best_key = gk2
	if best_key < 0:
		return
	top_end = float(groups[best_key][1])
	# round 14 (asked: the stone read as a ROAD — one giant slab per counter):
	# repeat the sheet ~3.2 times across the slab's own UV span, so the slate
	# pieces land at ~20 cm whatever the model's UVs do. One material per piece.
	var ref := -1
	var ref_area := -1.0
	for ci in cands.size():
		var cb2 := cands[ci][2] as AABB
		if int(round(cb2.end.y * 50.0)) != best_key:
			continue
		var ar := cb2.size.x * cb2.size.z
		if ar > ref_area:
			ref_area = ar
			ref = ci
	if ref < 0:
		return
	var span0: Vector2 = cands[ref][3]
	var stone := mat_named("counter_stone", Color(0.92, 0.92, 0.94))
	stone.uv1_scale = Vector3(clampf(3.2 / span0.x, 1.5, 6.0), clampf(3.2 / span0.y, 1.5, 6.0), 1)
	for cd in cands:
		var cb3 := cd[2] as AABB
		if int(round(cb3.end.y * 50.0)) == best_key and cb3.size.x * cb3.size.z >= ref_area * 0.35:
			(cd[0] as MeshInstance3D).set_surface_override_material(int(cd[1]), stone)


static var _mean_cache := {}


## Round 15: a texture's TRUE average brightness, sampled once and cached.
## The old table guessed 0.75 for fabric while the painted fabric averages
## 0.40 and the downloaded sheet nearer 0.85 — so the same sofa landed
## pale on one machine and dark on another. Measuring the sheet itself
## ends that: authored colour in, authored colour out, on every machine.
static func _tex_mean(tex: Texture2D, tex_name: String) -> float:
	if _mean_cache.has(tex_name):
		return float(_mean_cache[tex_name])
	var fallback: float = float({"wood": 0.50, "wood_dark": 0.45, "fabric": 0.75, "leather": 0.55, "metal_matte": 0.60, "cardboard": 0.65, "plastic": 0.65}.get(tex_name, 0.45))
	var mean := fallback
	var img := tex.get_image() if tex != null else null
	if img != null and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.resize(16, 16)
		var sum := 0.0
		for yy in 16:
			for xx in 16:
				var px := img.get_pixel(xx, yy)
				sum += (px.r + px.g + px.b) / 3.0
		mean = clampf(sum / 256.0, 0.15, 0.95)
	_mean_cache[tex_name] = mean
	return mean


func apply_texture(n: Node3D, tex_name: String, tint := Color.WHITE) -> void:
	var tex := TextureLib.get_texture(tex_name) if n != null else null
	if tex == null:
		return
	# round 14: with no explicit tint, the SURFACE's own colour is the tint
	# (divided by the texture's mean brightness) — a purple sofa stays purple
	# WITH its weave, instead of every piece washing out to the raw texture.
	var mean := _tex_mean(tex, tex_name)
	var deepen := 0.85 if tex_name == "fabric" else 1.0  # round 15 (playtest): the sofa and armchair still read pale — fabric lands a touch deeper than authored
	var c := Color(clampf(tint.r / mean, 0.0, 1.0), clampf(tint.g / mean, 0.0, 1.0), clampf(tint.b / mean, 0.0, 1.0)) * deepen
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if "screen" in m.name.to_lower() or "tablecloth" in m.name.to_lower():
			continue  # round 12b/14: a screen is glass and a cloth is cloth — never texture either
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			if not _takes_texture(tex_name, src):
				continue  # round 12c: baked-in props keep their own materials
			var t := src.duplicate() as BaseMaterial3D
			t.albedo_texture = tex
			t.albedo_color = c if tint != Color.WHITE else Color(clampf(src.albedo_color.r / mean, 0.0, 1.0), clampf(src.albedo_color.g / mean, 0.0, 1.0), clampf(src.albedo_color.b / mean, 0.0, 1.0)) * deepen
			t.uv1_scale = Vector3(2.0, 2.0, 1.0)
			var p := surface_props(tex_name)
			t.roughness = float(p[0])
			t.metallic = float(p[1])
			_add_normal(t, tex_name)
			m.set_surface_override_material(i, t)


func mat(color: Color, texture := "", tiling := Vector2.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	_cel(m)
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
	if m is StandardMaterial3D and (m as StandardMaterial3D).has_meta("tile_m"):
		# a named material: keep the grain/weave scale constant whatever the box size (demo polish)
		var tile: float = (m as StandardMaterial3D).get_meta("tile_m")
		var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
		dup.uv1_scale = Vector3(maxf(size.x, size.z) / tile, maxf(size.y, size.z) / tile, 1.0)
		mi.material_override = dup
	else:
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
	if str(night.get("decor", "kitchen")) == "kitchen":
		_furniture()
	else:
		RoomFurniture.new(self).build(night.get("furn", []))


## The second half runs after the physics engine knows the furniture (things are placed on top of it).
func build_contents() -> void:
	RoomFurniture.new(self).decor(str(night.get("decor", "kitchen")))
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
	# round 8: per-room grading (the user asked for the whole game graded, not one
	# global curve) — each room kind gets its own ambient tint and adjustments:
	# kitchens crisp, living rooms warm and soft, the pantry cold and flat, kids'
	# rooms a touch sweeter. It Takes Two grades every room like a film set.
	var kind := str(night.get("decor", "kitchen"))
	var atint := Color(1, 1, 1)
	var ascale := 1.0  # round 10: the fill level per room (the lighting pass)
	match kind:
		"living", "dining":
			atint = Color(1.06, 0.97, 0.86)
			ascale = 0.78  # warm-keyed rooms: the fill drops so the fire/lamps own them
		"pantry":
			atint = Color(0.98, 0.98, 1.01)
		"kids":
			atint = Color(1.03, 0.98, 1.02)
	# soft and fairly bright, like the prototype (its hemisphere light 0x7d8fc4 × 0.75, no tone mapping)
	env.ambient_light_color = Color(0.60, 0.56, 0.50) * atint * 0.38  # round 14: the palette is set at 70/30 — warm sources carry the room, cool is moonlight and this fill only, warmed and lowered so rooms stop reading blue * ascale * float(pal.get("hemi", 0.8)) / 0.8  # round 4/10: the FILL of the cinematic scheme — low and cool against the keys; the motivated sources carry the room
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = hex(pal.get("fog", 0x0e1220))
	env.fog_density = 0.012
	# round 7: ACES filmic + a whisper of glow — highlights (candle cores, garland
	# bulbs, moonlight) roll off and bloom instead of clipping flat; the cheapest
	# real step toward a painted, graded look (It Takes Two is graded hard)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.85
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true  # bright and vivid, not realistic
	env.adjustment_brightness = 1.2  # a touch more than the linear era: ACES darkens the mids
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	match kind:  # round 8: the per-room grade (see the ambient tint above)
		"living", "dining":
			env.adjustment_brightness = 1.17
			env.adjustment_contrast = 1.08
			env.adjustment_saturation = 1.17
		"pantry":
			env.adjustment_brightness = 1.23
			env.adjustment_contrast = 1.04
			env.adjustment_saturation = 0.97
		"kids":
			env.adjustment_brightness = 1.21
			env.adjustment_saturation = 1.19
	var we := WorldEnvironment.new()
	we.environment = env
	g.env = env
	root.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.72, 0.8, 1.0)  # round 10: a deeper blue — the cool KEY of the night scheme
	moon.light_energy = 1.25 * float(pal.get("moon", 0.9)) / 0.9
	moon.shadow_enabled = true
	moon.shadow_opacity = 0.62  # round 10: deeper night shadows (ACES still rolls them off)
	moon.shadow_blur = 1.2  # fairly crisp, but no stair-steps on the small rat
	moon.shadow_bias = 0.08  # no striped shadow acne on flat tops
	moon.shadow_normal_bias = 2.5
	root.add_child(moon)
	g.moon = moon
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(165.0), 0)  # from the window in the north wall

	# Round 10, the cinematic scheme's shaped FILL: a faint cool directional from
	# over the camera's shoulder (south-east, high). Flat ambient alone modelled
	# nothing — this gives south faces a gentle blue modelling so the rat's
	# silhouette separates from dark furniture instead of melting into it. No
	# shadows, low energy: it is bounce, not a second moon.
	var fill := DirectionalLight3D.new()
	fill.name = "Moon fill"
	fill.light_color = Color(0.6, 0.7, 1.0)
	fill.light_energy = 0.15  # round 14: 70/30 — the fill is a whisper now
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-15.0), 0)

	for l in night.get("lights", []):
		var pl := OmniLight3D.new()
		pl.light_color = hex(l.get("c", 0xffa860))
		pl.light_energy = float(l.get("i", 1.0)) * 1.6
		pl.omni_range = float(l.get("r", 500)) / 100.0
		pl.omni_attenuation = 1.45  # round 10: a defined pool with real darkness past it, not an even wash
		pl.shadow_enabled = true
		pl.shadow_bias = 0.15
		pl.shadow_normal_bias = 2.0
		root.add_child(pl)
		pl.global_position = W(float(l.x), float(l.y), float(l.get("h", 60)))
		g.flickers.append([pl, pl.light_energy, "steady"])
		# round 4: every light gets a visible source — a little candle lantern at the light's own
		# spot (dark base, warm glowing core), so no light in the room comes from nowhere
		var lh := float(l.get("h", 60))
		if lh > 12.0:
			# round 15 (playtest: the fixture still looks bad — first a candle
			# on a stick, then a lantern on the same stick): a tall light
			# stands as a proper shaded lamp now.
			_lamp_stand(float(l.x), float(l.y), lh, hex(l.get("c", 0xffa860)))
		else:
			# a low light: a candle on its base at the light's own spot
			var base := MeshInstance3D.new()
			base.name = "Candle base"
			var bm := CylinderMesh.new()
			bm.top_radius = 0.035
			bm.bottom_radius = 0.05
			bm.height = 0.025
			base.mesh = bm
			base.material_override = mat(hex(0x2a2320))
			root.add_child(base)
			base.global_position = W(float(l.x), float(l.y), lh - 7.0)
			var flame := MeshInstance3D.new()
			flame.name = "Candle glow"
			var fm := SphereMesh.new()
			fm.radius = 0.028
			fm.height = 0.056
			flame.mesh = fm
			var fmat := StandardMaterial3D.new()
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.albedo_color = hex(l.get("c", 0xffa860))
			flame.material_override = fmat
			root.add_child(flame)
			flame.global_position = W(float(l.x), float(l.y), lh - 2.0)

	var room := OmniLight3D.new()  # the ceiling light: off at night, the owner switches it on
	room.name = "Ceiling light"
	room.light_color = Color(1.0, 0.93, 0.8)
	room.light_energy = 2.0
	room.omni_range = 9.0
	room.omni_attenuation = 1.3  # round 10: pooled under the ceiling — the room's edges fall dark when he flips it on
	room.shadow_enabled = true
	room.visible = false
	root.add_child(room)
	room.global_position = W(480, 300, 200)
	g.room_light = room
	# round 14 (asked: light with no lamp): the ceiling light hangs in a
	# chandelier, so its source is in the room even when it is off.
	var ch := spawn("rooms/chandelier", W(480, 300, 250), 0.0, root)
	if ch:
		var cbb := world_aabb(ch)
		ch.global_position.y -= cbb.end.y - 2.52


static func _section(p: float) -> int:
	return clampi(floori(p / 120.0), 0, 7)


## Round 5: the door leaf is a separate node in wall_door.glb, but its origin is the door's
## CENTRE — re-hang it on a pivot at its edge so the game can swing it when the owner comes
## and goes. (The rat can never slip out: the section's collision still walls the doorway,
## and the owner himself is the catch.)
func _make_door(section: Node3D) -> void:
	var door := section.find_child("door", true, false) as Node3D
	if door == null:
		return
	# round 7: round 5's math re-applied the leaf's own offset (its centre sits at
	# (0, 1.06, -0.02) in the model) INSIDE the pivot, lifting the leaf ~1 m — the
	# "drifted" door of night 1. The hinge goes at the leaf's edge in PARENT space
	# (through the leaf's own basis), and inside the pivot the leaf is exactly
	# (0.45, 0, 0) with no leftover offset.
	var edge := door.transform.basis * Vector3(-0.45, 0, 0)
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	door.get_parent().add_child(pivot)
	pivot.position = door.position + edge
	pivot.rotation = door.rotation
	door.reparent(pivot, false)
	door.position = Vector3(0.45, 0, 0)
	door.rotation = Vector3.ZERO
	pivot.set_meta("base_yaw", pivot.rotation.y)
	g.door_pivot = pivot


## Round 6: an irregular dark blob (a seeded fan of points) with a chipped-plaster
## rim behind it — the round flat discs read as pasted stickers; this reads as a hole.
func _blob(hole_name: String, r: float, seed: int) -> Node3D:
	var grp := Node3D.new()
	grp.name = hole_name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var radii: Array = []
	for i in 10:
		radii.append(r * rng.randf_range(0.7, 1.14))
	var rim := MeshInstance3D.new()
	rim.mesh = _blob_mesh(radii, 1.18)
	rim.material_override = mat(hex(0x2b2119))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.position.z = -0.004
	grp.add_child(rim)
	var dark := MeshInstance3D.new()
	dark.mesh = _blob_mesh(radii, 1.0)
	dark.material_override = mat(hex(0x050506))
	dark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grp.add_child(dark)
	return grp


func _blob_mesh(radii: Array, scl: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	norms.append(Vector3(0, 0, 1))
	var n := radii.size()
	for i in n:
		var a := TAU * float(i) / n
		verts.append(Vector3(cos(a), sin(a), 0) * float(radii[i]) * scl)
		norms.append(Vector3(0, 0, 1))
	for i in n:
		idx.append_array([0, 1 + i, 1 + (i + 1) % n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A hole in the floor (a gap she slips through).
func _hole_disc(at: Vector3, r: float) -> void:
	var grp := _blob("Hole", r, int(at.x * 131.0 + at.z * 57.0) + 7)
	grp.rotation.x = -PI / 2.0
	root.add_child(grp)
	grp.global_position = at + Vector3.UP * 0.006


## A hole ON a wall, at an elevated crack's height.
func _hole_on_wall(wall: String, at: Vector3) -> void:
	var grp := _blob("Hole (wall)", 0.1, int(at.x * 131.0 + at.y * 57.0) + 13)
	grp.scale = Vector3(1, 0.85, 1)
	root.add_child(grp)
	# pinned to the wall PLANE itself (the exit point sits d cm into the room, on the furniture)
	match wall:
		"n":
			grp.global_position = Vector3(at.x, at.y + 0.15, -2.955)
		"s":
			grp.rotation.y = PI
			grp.global_position = Vector3(at.x, at.y + 0.15, 2.955)
		"w":
			grp.rotation.y = PI / 2.0
			grp.global_position = Vector3(-4.755, at.y + 0.15, at.z)
		_:
			grp.rotation.y = -PI / 2.0
			grp.global_position = Vector3(4.755, at.y + 0.15, at.z)


## Round 5: a WORKING wall clock (the wall_clock model's hands are baked into one mesh).
## Built from primitives at the spot the static clock used; the game turns the hands —
## they show the night's own time (23:00 at the start, 06:00 at dawn, like the HUD clock).
func add_working_clock(at: Vector3, rot_deg: float) -> void:
	var grp := Node3D.new()
	grp.name = "Wall clock (working)"
	root.add_child(grp)
	grp.global_position = at
	grp.rotation.y = deg_to_rad(rot_deg)
	var rim := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.185; rc.bottom_radius = 0.185; rc.height = 0.035
	rim.mesh = rc
	rim.rotation_degrees.x = 90.0
	rim.material_override = mat_named("wood_dark", hex(0x4a3421))
	grp.add_child(rim)
	var face := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.168; fc.bottom_radius = 0.168; fc.height = 0.04
	face.mesh = fc
	face.rotation_degrees.x = 90.0
	face.material_override = mat(Color(0.92, 0.88, 0.76))
	grp.add_child(face)
	var dark := mat(Color(0.12, 0.1, 0.1))
	for k in 4:
		var tick := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.014, 0.032, 0.006)
		tick.mesh = tb
		tick.material_override = dark
		var ang := k * PI / 2.0
		tick.position = Vector3(sin(ang) * 0.138, cos(ang) * 0.138, 0.024)
		tick.rotation.z = -ang
		grp.add_child(tick)
	var hands := []
	for spec in [[0.02, 0.088, 0.034], [0.013, 0.128, 0.052]]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, 0.027)
		grp.add_child(pivot)
		var hand := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(spec[0], spec[1], 0.005)
		hand.mesh = hb
		hand.material_override = dark
		hand.position = Vector3(0, spec[2], 0)
		pivot.add_child(hand)
		hands.append(pivot)
	g.clock_hands = hands


## One sheet of the fake moon shaft (see _walls): a single quad, no shadow, additive.
func _add_shaft_quad(verts: Array, uvs: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	var mi := MeshInstance3D.new()
	mi.name = "Moon shaft"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _room() -> void:
	var pal: Dictionary = night.get("pal", {})
	var floor_tex := "floor_" + str(pal.get("floor", "tile"))
	var wall_tex := "wall_" + str(pal.get("wall", "stripes"))
	if not ResourceLoader.exists("res://assets/textures/" + floor_tex + ".png"): floor_tex = "floor_tile"
	if not ResourceLoader.exists("res://assets/textures/" + wall_tex + ".png"): wall_tex = "wall_stripes"
	var floor_mat := mat(Color.WHITE, floor_tex, Vector2(6, 3.75))
	if str(pal.get("floor", "")) == "tile":
		# round 12d: the real tile, asked from TextureLib (CDN pack → painted) —
		# the old code looked for res://assets/textures/ceramic_tile.png, a file
		# that never existed in the repo, so the check never fired and the
		# downloaded Tiles141 went unused. Tinted down to the old floor's tone
		# (its mean was ~(0.25, 0.27, 0.38)) so the night stays as dark as before.
		var ct := TextureLib.get_texture("ceramic_tile", false)
		if ct != null:
			floor_mat = mat(Color(0.46, 0.44, 0.41))  # round 14: warm-neutral — the old tint was blue, and it blued every tile floor
			floor_mat.albedo_texture = ct
			floor_mat.uv1_scale = Vector3(6, 3.75, 1)
			floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			floor_mat.roughness = 0.32  # glazed tile: smooth enough for the moon patch to read on it
			_add_normal(floor_mat, "ceramic_tile")
			_add_rough(floor_mat, "ceramic_tile")
	if str(pal.get("floor", "")) == "wood":
		# round 16: wood floors come from the pack too (floor_wood), like the tile
		var wt := TextureLib.get_texture("floor_wood", false)
		if wt != null:
			floor_mat = mat(Color(0.55, 0.52, 0.48))  # warm-neutral, keeps the nights as dark as the old PNG floor
			floor_mat.albedo_texture = wt
			floor_mat.uv1_scale = Vector3(6, 3.75, 1)
			floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			floor_mat.roughness = 0.62
			_add_normal(floor_mat, "floor_wood")
			_add_rough(floor_mat, "floor_wood")
	if str(pal.get("floor", "")) == "concrete":
		var ct2 := TextureLib.get_texture("floor_concrete", false)
		if ct2 != null:
			floor_mat = mat(Color(0.52, 0.50, 0.47))
			floor_mat.albedo_texture = ct2
			floor_mat.uv1_scale = Vector3(6, 3.75, 1)
			floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			floor_mat.roughness = 0.9
			_add_normal(floor_mat, "floor_concrete")
			_add_rough(floor_mat, "floor_concrete")
	var wall_mat := mat(Color.WHITE, wall_tex)
	# round 14 (asked: walls the same blue everywhere): a painted wallpaper
	# (TextureGen) tinted by THIS night's wallA replaces the bundled pattern,
	# so each room's walls carry its own colour. Falls back to the old pattern
	# until the painter has produced the wallpaper once.
	var wp_name := "wallpaper_" + str(pal.get("wall", "stripes"))
	if TextureLib.get_texture(wp_name, false) != null:
		wall_mat = mat_named(wp_name, Color.html(str(pal.get("wallA", "#8a8378"))))
	var trim := mat(hex(0x7a4a2a))

	# floor (a thin solid slab) and ceiling (no collision, casts no shadow)
	var fl := box("Floor", Vector3(0, -0.05, 0), Vector3(9.6, 0.1, 6.0), floor_mat, root)
	var fm := (fl as MeshInstance3D).mesh as BoxMesh
	fm.size = Vector3(9.6, 0.1, 6.0)
	var ceil := box("Ceiling", Vector3(0, 2.55, 0), Vector3(9.6, 0.1, 6.0), mat(hex(pal.get("ceil", 0x22263a))), root, false)
	# round 14 (asked: dust and air, everywhere): motes drift through the whole
	# room, catching the moon patch as they cross it — the air itself is alive.
	var motes := CPUParticles3D.new()
	motes.name = "Dust motes"
	motes.amount = 64
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(4.6, 1.1, 2.8)
	motes.direction = Vector3(0, -1, 0)
	motes.spread = 180.0
	motes.initial_velocity_min = 0.008
	motes.initial_velocity_max = 0.03
	motes.gravity = Vector3(0, -0.004, 0)
	var msm := SphereMesh.new()
	msm.radius = 0.006
	msm.height = 0.012
	msm.radial_segments = 6
	msm.rings = 3
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mmat.albedo_color = Color(1, 1, 1, 0.30)
	msm.material = mmat
	motes.mesh = msm
	root.add_child(motes)
	motes.global_position = W(480, 300, 120)
	var cb := StaticBody3D.new()  # the rat and the camera bump into the ceiling (up on the cabinets)
	cb.collision_layer = 1 | 4
	cb.collision_mask = 0
	var ccs := CollisionShape3D.new()
	var csh := BoxShape3D.new()
	csh.size = Vector3(9.6, 0.1, 6.0)
	ccs.shape = csh
	cb.add_child(ccs)
	ceil.add_child(cb)
	(ceil as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var north := []; var south := []; var west := []; var east := []
	north.resize(8); south.resize(8); west.resize(5); east.resize(5)
	var win: Dictionary = night.get("window", {})
	if float(win.get("w", 0)) > 0.0:
		north[_section(float(win.x) + float(win.w) / 2.0)] = "wall_window"
	south[1] = "wall_mousehole"
	var door_j := clampi(floori(float(night.get("door", 300)) / 120.0), 0, 4)
	east[door_j] = "wall_door"
	for c in night.get("cracks", []):
		if c.has("nest"):
			g.cracks.append(W(130, 690))  # the path can end in the nest itself
			continue
		if c.has("floor"):
			var fp := W(float(c.x), float(c.y))
			g.cracks.append(fp)
			_hole_disc(fp, 0.12)  # a dark gap in the floor (under the island's plinth, say)
			_hide("crack", float(c.x), float(c.y), 42, 42)
			continue
		var cx := float(c.get("x", 0)); var cy := float(c.get("y", 0))
		if float(c.get("h", 0)) > 0.0:
			# round 5: an elevated crack — the exit is a hole in the wall at height h (cm, the
			# height she STANDS at), pushed d cm into the room onto the surface below it (the
			# counter, the cabinet tops). The wall sections can't show it (furniture is in the
			# way), so it gets a dark disc on the wall instead of a wall_crack section.
			var hh := float(c.h); var dd := float(c.get("d", 40))
			var ep: Vector3
			match str(c.wall):
				"n": ep = W(cx, dd, hh)
				"s": ep = W(cx, 600.0 - dd, hh)
				"w": ep = W(dd, cy, hh)
				_: ep = W(960.0 - dd, cy, hh)
			g.cracks.append(ep)
			_hole_on_wall(str(c.wall), ep)
			var hz := add_zone(HideSpot, "Hide: crack", ep, Vector3(0.55, 0.6, 0.55)) as HideSpot
			hz.id = "crack"
			continue
		match str(c.wall):
			"s": g.cracks.append(W(cx, 588))
			"n": g.cracks.append(W(cx, 12))
			"w": g.cracks.append(W(12, cy))
			_: g.cracks.append(W(948, cy))
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
	for i in 8:
		var nsec := _wall(north[i] if north[i] else "wall_section", 60 + 120 * i, -5, 0.0, walls, wall_mat)
		if north[i] == "wall_window" and nsec:
			for cn in ["curtain_l", "curtain_r"]:
				var curt := nsec.find_child(cn, true, false) as Node3D
				if curt:
					g.curtains.append(curt)
	for i in 8: _wall(south[i] if south[i] else "wall_section", 60 + 120 * i, 605, 180.0, walls, wall_mat)
	_mouse_hole()  # round 15: a ragged plaster-rimmed entrance over the flat arch plate
	for j in 5: _wall(west[j] if west[j] else "wall_section", -5, 60 + 120 * j, 90.0, walls, wall_mat)
	for j in 5:
		var esec := _wall(east[j] if east[j] else "wall_section", 965, 60 + 120 * j, -90.0, walls, wall_mat)
		if j == door_j and esec:
			_make_door(esec)
	for p in [Vector2(-5, -5), Vector2(965, -5), Vector2(-5, 605), Vector2(965, 605)]:
		box("Corner", W(p.x, p.y, 125), Vector3(0.1, 2.5, 0.1), trim, walls)
	if float(win.get("w", 0)) > 0.0:
		# round 4: a fake light shaft — two translucent sheets from the window along the moon's
		# own direction, so the moonlight visibly COMES from the window instead of just being
		# there. The sky dims them together with the moonlight (it gets the materials below).
		var shaft_mats: Array = []
		var sdir := Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(165.0), 0.0)) * Vector3(0, 0, -1)
		var wcx := W(float(win.x) + float(win.w) / 2.0, 0).x
		var ww := float(win.w) / 100.0
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		smat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		smat.render_priority = 1
		# round 6: softer — a hint of a shaft, not a searchlight (asked for)
		var stex := TextureLib.get_texture("shaft")
		if stex != null:
			smat.albedo_texture = stex
			smat.albedo_color = Color(0.5, 0.62, 1.0, 0.26)
		else:
			smat.albedo_color = Color(0.5, 0.62, 1.0, 0.07)
		shaft_mats.append(smat)
		var top := 2.18
		var bot := 1.12
		var z0 := -2.98
		var a := Vector3(wcx - ww / 2.0, top, z0)
		var b := Vector3(wcx + ww / 2.0, top, z0)
		_add_shaft_quad([a, b, b + sdir * (top / -sdir.y), a + sdir * (top / -sdir.y)],
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], smat)
		var c := Vector3(wcx, top, z0)
		var d := Vector3(wcx, bot, z0)
		_add_shaft_quad([c, d, d + sdir * (bot / -sdir.y), c + sdir * (top / -sdir.y)],
			[Vector2(0.5, 0), Vector2(0.5, 0.3), Vector2(0.5, 1), Vector2(0.5, 0.7)], smat)
		# round 3: a living sky outside the window — the moon, clouds drifting past it, branches
		# swaying (window_sky.gd). The clouds also dim the moonlight itself, via Game.moon_cloud.
		var sky := WindowSky.new()
		sky.name = "Window sky"
		root.add_child(sky)
		sky.global_position = Vector3(W(float(win.x) + float(win.w) / 2.0, 0).x, 0.0, -3.02)
		sky.build_sky(g, hash(str(night.get("id", "night"))), shaft_mats)

	var lamp := str(night.get("lamp", ""))
	var shade := spawn("rooms/chandelier" if lamp == "chandelier" else ("rooms/lamp_bulb" if lamp == "bulb" else "rooms/lamp_shade"), W(480, 300), 0.0, decor)
	if shade:
		shade.global_position.y = 2.5 - world_aabb(shade).size.y


func _wall(model: String, x: float, y: float, rot: float, parent: Node3D, wall_mat: Material) -> Node3D:
	var n := spawn("rooms/" + model, W(x, y), rot, parent)
	if n == null:
		return null
	collide(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with(WALL_HEX):
				m.set_surface_override_material(i, wall_mat)
	return n


func _hide(kind: String, x: float, y: float, w: float, d: float, rot := 0.0) -> void:
	var z := add_zone(HideSpot, "Hide: " + kind, W(x, y), Vector3(w / 100.0, 0.2, d / 100.0), rot) as HideSpot
	z.id = kind


func _furniture() -> void:
	# levels.js kitchenFurniture: counters along the north and west walls, fridge, island, a box as a step,
	# the table with chairs, a low shelf and a stool. Fronts face into the room.
	furn_piece("furniture/counter_corner", 36, 36, 0.0, "counter", 72, 72)
	var n := 12
	var w := (800.0 - 72.0) / n  # round 14: the run ends at 800 — a slot is left by the fridge (below)
	for i in n:
		var piece := furn_piece("furniture/counter_sink" if i == 6 else "furniture/counter_section", 72 + w * (i + 0.5), 36, 0.0, "counter", w, 72)
		if i == 6 and piece:
			_sink_water(piece)
		if i == 3 and piece:
			_stove(piece)  # round 15 (asked): a gas hob for the kitchen — the kettle already steams over this segment
	for j in 4:
		furn_piece("furniture/counter_section", 36, 72 + 60 * (j + 0.5), 90.0, "counter", 60, 72)
	# round 15 (playtest: the fridge sat shoved against the wall, too
	# obvious): it stands CENTRED in its slot now — the counter run ends
	# at 800, the east wall is at 960 — with a rat-width slot on every
	# side: left, right and behind. Each slot is a hide of hers alone
	# (a HideSpot is a no-go on the hunters' grid).
	furn_piece("furniture/fridge", 880, 70, 0.0, "fridge", 124, 106)
	_hide("fridgeGap", 809, 61, 18, 122)
	_hide("fridgeGap", 951, 61, 18, 122)
	_hide("fridgeGap", 880, 8, 124, 17)
	add_zone(HumZone, "Fridge hum", W(880, 128), Vector3(1.8, 1.2, 1.2))
	furn_piece("furniture/kitchen_island", 480, 295, 180.0, "island", 200, 90)
	furn_piece("furniture/cardboard_box", 608, 284, 0.0, "box", 44, 44, 44)
	var table := furn_piece("furniture/table_kitchen", 720, 445, 0.0, "table", 200, 130)
	if table:
		apply_texture(table, "wood_dark")  # round 14 (asked): the kitchen table gets its wood too
	if table:
		var cloth := table.find_child("tablecloth*", true, false) as Node3D
		var spec := {}
		for f in night.get("furn", []):
			if str(f.t) == "table": spec = f
		var clothv := int(spec.get("cloth", 0))
		if cloth and clothv == 0:
			cloth.queue_free()
		elif cloth:
			# round 15 (asked: the cloth is one flat colour): the woven
			# check, in the night's own cloth colour
			dress_tablecloth(table, hex(clothv) if clothv > 1 else Color(0.85, 0.38, 0.30))
	_hide("table", 720, 445, 196, 126)
	# round 5: hiding under a bare table read as ridiculous — there are THINGS under it now:
	# a storage box and the kid's backpack, and she ducks in among them
	collide(spawn("props/small_box", W(655, 485), 18.0, decor))
	spawn("props/backpack", W(778, 402), -35.0, decor)
	for c in [[596, 420, 90], [596, 472, 90], [846, 446, -90]]:
		furn_piece("furniture/chair", c[0], c[1], c[2], "chair")
		_hide("chair", c[0], c[1], 42, 42)  # round 14: the whole chair is her cover — and a hunter no-go
	furn_piece("furniture/low_shelf", 231, 325, 0.0, "lowShelf", 62, 50)
	_hide("shelf", 231, 325, 54, 42)
	furn_piece("furniture/stool", 100, 252, 0.0, "stool")
	if bool(night.get("kitchenUpper", false)):
		_kitchen_upper()
	_kitchen_details()


func _kcyl(center: Vector3, r: float, h: float, m: Material, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Detail cyl"
	var cm := CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	decor.add_child(mi)
	mi.global_position = center
	return mi


## Round 17 (details pass, Muse's discretion): the fixed-layout kitchen gets
## its set dressing — hanging pans that sway with the plants, a dish rack by
## the sink, spice jars, a paper-towel roll, a bin, fruit on the table and a
## towel on the oven handle.
func _kitchen_details() -> void:
	var iron := mat(Color(0.16, 0.16, 0.17))
	iron.metallic = 0.7
	iron.roughness = 0.42
	for px in [150.0, 205.0, 560.0, 620.0]:
		var grp := Node3D.new()
		grp.name = "Hanging pan"
		decor.add_child(grp)
		grp.global_position = W(px, 8, 134)
		var pan := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.095; pm.bottom_radius = 0.082; pm.height = 0.028
		pan.mesh = pm
		pan.material_override = iron
		pan.rotation.x = PI / 2.0
		pan.position = Vector3(0, -0.15, 0.03)
		grp.add_child(pan)
		var hd := _mesh_box(Vector3(0.03, 0.15, 0.012), iron)
		hd.position = Vector3(0, -0.03, 0.03)
		grp.add_child(hd)
		g.plants.append([grp, grp.rotation, randf() * TAU])
	var ceramic := mat(Color(0.92, 0.90, 0.85))
	ceramic.roughness = 0.25
	box("Dish rack", W(520, 40, 93), Vector3(0.36, 0.025, 0.26), mat(Color(0.88, 0.87, 0.84)), decor, false)
	for i in 3:
		var pl := _kcyl(W(505.0 + float(i) * 11.0, 40, 99), 0.085, 0.008, ceramic)
		pl.rotation.z = 1.35
	var spice_cols := [Color(0.62, 0.25, 0.12), Color(0.80, 0.58, 0.15), Color(0.35, 0.45, 0.20), Color(0.90, 0.88, 0.82)]
	for i in 4:
		var sx := 100.0 + float(i) * 16.0
		_kcyl(W(sx, 12, 96.5), 0.026, 0.085, mat(spice_cols[i]))
		_kcyl(W(sx, 12, 101.3), 0.028, 0.014, mat(Color(0.20, 0.18, 0.16)))
	_kcyl(W(700, 32, 92.6), 0.07, 0.012, iron)
	_kcyl(W(700, 32, 104), 0.052, 0.23, mat(Color(0.94, 0.93, 0.90)))
	_kcyl(W(565, 395, 18), 0.13, 0.36, iron)
	_kcyl(W(708, 438, 81.5), 0.07, 0.05, ceramic, 0.11)
	var fruit_cols := [Color(0.62, 0.16, 0.12), Color(0.85, 0.45, 0.12), Color(0.85, 0.70, 0.20)]
	var fruit_pos := [[700.0, 432.0, 85.0], [716.0, 440.0, 85.5], [708.0, 445.0, 86.5]]
	for i in 3:
		var fr := MeshInstance3D.new()
		fr.name = "Fruit"
		var sm := SphereMesh.new()
		sm.radius = 0.034; sm.height = 0.068
		fr.mesh = sm
		fr.material_override = mat(fruit_cols[i])
		decor.add_child(fr)
		fr.global_position = W(fruit_pos[i][0], fruit_pos[i][1], fruit_pos[i][2])
	box("Oven towel", W(285, 74, 66), Vector3(0.17, 0.24, 0.014), mat_named("tablecloth", Color(0.85, 0.50, 0.42)), decor, false)


## The kitchen's second level (night 1): wall cabinets over the counter left and right of the window, a shelf over
## the window joining them, two open shelves on the west wall to climb up by (counter 92 → 140 → 180 → cabinet tops
## 215 → fridge top 185), a kettle and a toaster on the counter, a clock and pictures on the free walls.
func _kitchen_upper() -> void:
	var white := Color8(0xee, 0xe2, 0xc8)
	for blk in [[0.0, 400.0], [640.0, 830.0]]:
		var n := int(round((blk[1] - blk[0]) / 64.0))
		var cw: float = (blk[1] - blk[0]) / n
		for i in n:
			var c := spawn("furniture/upper_cabinet", W(0, 0), 0.0, furn)
			if c:
				fit(c, cw, 35, 70)
				_recolor(c, white)
				var bb := world_aabb(c)
				c.global_position += W(blk[0] + cw * (i + 0.5), 17.5, 145) - Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
				collide_box(c, "cabinet")
	# round 3: under-cabinet strip lights — a warm source you can see, washing the worktop, so the
	# kitchen's light reads: cold moon from the window, warm strips over the counter
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(1.0, 0.8, 0.52)
	for blk2 in [[0.0, 400.0], [640.0, 830.0]]:
		var bcx: float = (float(blk2[0]) + float(blk2[1])) / 2.0
		var strip := MeshInstance3D.new()
		strip.name = "Cabinet light strip"
		var sm := BoxMesh.new()
		sm.size = Vector3((float(blk2[1]) - float(blk2[0])) / 100.0 * 0.92, 0.015, 0.05)
		strip.mesh = sm
		strip.material_override = strip_mat
		furn.add_child(strip)
		strip.global_position = W(bcx, 30, 143)
		var spot := SpotLight3D.new()
		spot.name = "Cabinet spot"
		spot.light_color = Color(1.0, 0.72, 0.42)  # round 10: warmer, and a tighter cone — a defined pool on the counter, not a wash
		spot.light_energy = 1.35
		spot.spot_range = 1.7
		spot.spot_angle = 46.0
		spot.spot_attenuation = 1.15
		spot.rotation_degrees = Vector3(-90, 0, 0)
		furn.add_child(spot)
		spot.global_position = W(bcx, 30, 141)
	var wood := mat_named("wood", hex(0x8a5a34))
	box("Shelf over the window", W(520, 13, 213.5), Vector3(2.4, 0.03, 0.26), wood, furn).get_child(0).set_meta("surface", "shelf")
	for sh in [[195.0, 138.5], [100.0, 178.5]]:  # [y centre, top − 1.5]
		var b := box("Wall shelf", W(14, sh[0], sh[1]), Vector3(0.28, 0.03, 1.0), wood, furn)
		b.get_child(0).set_meta("surface", "shelf")
		for j in 3:  # jars and cups standing at the back
			var jar := spawn("props/jar" if j % 2 == 0 else "props/mug", W(6, sh[0] - 35 + j * 35, sh[1] + 1.5), 90.0, decor)
			if jar:
				jar.scale *= 0.8
				collide(jar)
	var ket := spawn("rooms/kettle", on_top(260, 30), 180.0, decor)
	collide(ket)
	if ket:
		g.kettle_pos = ket.global_position + Vector3.UP * 0.17  # world_fx steams here
	var toast := spawn("furniture/toaster", on_top(340, 28), 180.0, decor)
	if toast:
		var tb := world_aabb(toast)
		toast.global_position -= Vector3(tb.get_center().x - W(340, 28).x, 0, tb.get_center().z - W(340, 28).z)
		collide(toast)
	add_working_clock(W(958, 200, 195), -90.0)  # round 5: working hands, the night's real time
	_wall_art("rooms/wall_art_landscape", 2, 430, 160, 90.0)
	_wall_art("rooms/wall_art_flowers", 2, 540, 160, 90.0)
	_wall_art("rooms/wall_art_portrait", 720, 598, 165, 180.0)


## Round 15 (playtest: the bowl still reads as "something unclear"): a
## heaped mound wearing the kibble texture — pieces you can pick out,
## lit piece by piece — a few loose bits on the heap and a spill beside
## the bowl. No more uniform brown beads in a disc.
func _bowl_leftovers(bowl: Node3D) -> void:
	var bb := world_aabb(bowl)
	var c := bb.get_center()
	var r := minf(bb.size.x, bb.size.z) * 0.30
	var top := bb.position.y + bb.size.y * 0.55
	var dome := MeshInstance3D.new()
	dome.name = "Kibble mound"
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	dome.mesh = sm
	dome.scale = Vector3(r, r * 0.42, r)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.02, 0.98, 0.92)
	var ktex := TextureLib.get_texture("kibble")
	if ktex != null:
		dm.albedo_texture = ktex
		dm.uv1_scale = Vector3(2.0, 2.0, 1.0)
		_add_normal(dm, "kibble")
	dm.roughness = 0.85
	dome.material_override = dm
	decor.add_child(dome)
	dome.global_position = Vector3(c.x, top - r * 0.10, c.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 12:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.8
		var k := MeshInstance3D.new()
		var km2 := SphereMesh.new()
		km2.radius = rng.randf_range(0.007, 0.011)
		km2.height = km2.radius * 1.5
		k.mesh = km2
		var mat2 := mat(Color(0.50, 0.32, 0.15).lerp(Color(0.28, 0.16, 0.07), rng.randf()))
		mat2.roughness = 0.8
		k.material_override = mat2
		decor.add_child(k)
		var lift := r * 0.42 * sqrt(maxf(0.0, 1.0 - (d / r) * (d / r)))
		k.global_position = Vector3(c.x + cos(a) * d, top - r * 0.10 + lift + 0.004, c.z + sin(a) * d)
	for i2 in 4:  # the spill beside the bowl
		var a2 := rng.randf() * TAU
		var k2 := MeshInstance3D.new()
		var km3 := SphereMesh.new()
		km3.radius = rng.randf_range(0.007, 0.010)
		km3.height = km3.radius * 1.5
		k2.mesh = km3
		var mat3 := mat(Color(0.45, 0.28, 0.13).lerp(Color(0.30, 0.18, 0.08), rng.randf()))
		mat3.roughness = 0.8
		k2.material_override = mat3
		decor.add_child(k2)
		k2.global_position = Vector3(c.x + cos(a2) * (r + 0.06 + rng.randf() * 0.05), km3.radius * 0.7, c.z + sin(a2) * (r + 0.06 + rng.randf() * 0.05))


## A picture or clock on a wall, centred at (x, y) and h cm up, facing into the room.
func _wall_art(model: String, x: float, y: float, h: float, rot: float) -> void:
	var n := spawn(model, W(x, y, h), rot, decor)
	if n:
		n.global_position.y = h / 100.0 - world_aabb(n).size.y / 2.0


func _recolor(n: Node3D, col: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as BaseMaterial3D
			if src and src.albedo_color.r > 0.6 and src.albedo_color.b < 0.45:  # Kenney's wood → our cabinet white
				var c := src.duplicate() as BaseMaterial3D
				c.albedo_color = col
				m.set_surface_override_material(i, c)


func _decor() -> void:
	# round 12 (asked): the kitchen gets a houseplant too — the dressed rooms have
	# theirs from RoomFurniture.dress(). SW floor corner, clear of the west counter
	# leg and the mouse hole; it sways like the rest (Game.plants).
	var kp := spawn("furniture/plant", W(52, 548), randf() * 360.0, decor)
	collide(kp)
	if kp:
		g.plants.append([kp, kp.rotation, randf() * TAU])
	for p in night.get("props", []):
		match str(p.t):
			"foil":
				var c := W(float(p.x) + float(p.w) / 2.0, float(p.y) + float(p.h) / 2.0)
				var fn := spawn("props/foil", c, 0.0, decor)
				fit(fn, float(p.w), float(p.h))
				dress_foil(fn)
				(add_zone(NoisyZone, "Foil", c, Vector3(float(p.w) / 100.0, 0.2, float(p.h) / 100.0)) as NoisyZone).configure("foil")
			"breadbox":
				collide(spawn("props/bread_box", on_top(float(p.x) + float(p.w) / 2.0, float(p.y) + float(p.h) / 2.0), 0.0, decor))
			"noisy":
				_noisy(p)
			"hum":
				var hz := add_zone(HumZone, "Hum", on_top(float(p.x), float(p.y)), Vector3(float(p.get("r", 120)) / 50.0, 1.2, float(p.get("r", 120)) / 50.0))
				hz.size.y = 1.2
			"gnaw", "backpack":
				_gnaw(p, str(p.t) == "backpack")
			"sticky", "cage", "spray":
				_sticky(p, str(p.t))
	for f in night.get("furn", []):
		if bool(f.get("plate", false)):
			var pl1 := spawn("food/plate", on_top(680, 432), 0.0, decor)
			collide(pl1)
			dress_plate(pl1)
	var ex: Array = night.get("exit", [])
	if ex.size() >= 2:
		_exit(Nights.pos(ex))
	var cat_bed := spawn("props/cat_bed", Nights.pos(night.get("catBed")), 0.0, decor)  # the cat lies in it…
	if cat_bed:
		# round 14 (asked: she walks through the cat's bed): a rat-only collider
		# (layer 4 is in HER mask, not the hunters') — the bed is solid to her,
		# the cat still settles in as before.
		var bb := StaticBody3D.new()
		bb.collision_layer = 4
		bb.collision_mask = 0
		var bcs := CollisionShape3D.new()
		var bbs := BoxShape3D.new()
		bbs.size = Vector3(0.58, 0.13, 0.58)
		bcs.shape = bbs
		bcs.position.y = 0.065
		bb.add_child(bcs)
		cat_bed.add_child(bb)
	if (night.get("bowl", []) as Array).size() >= 2:
		var bowl := spawn("props/cat_bowl", Nights.pos(night.bowl), 0.0, decor)
		collide(bowl)
		if bowl and bool(night.get("kitchenUpper", false)):
			_bowl_leftovers(bowl)
	if (night.get("dock", []) as Array).size() >= 2 and (bool(night.get("vacuumStart", false)) or (night.get("threats", []) as Array).has("vacuum")):
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
	g.noisy.append(z)


## A bag (or the kid's backpack) the rat gnaws open by holding F: spills food.
func _gnaw(p: Dictionary, cookies: bool) -> void:
	var at := W(float(p.x), float(p.y)) if bool(p.get("floor", false)) else on_top(float(p.x), float(p.y))
	var gs := GnawSpot.new()
	gs.name = "Backpack" if cookies else "Bag"
	decor.add_child(gs)
	gs.global_position = at
	gs.cookies = cookies
	gs.spawn_n = int(p.get("spawn", 4))
	gs.tag = str(p.get("tag", ""))
	gs.model = spawn("props/backpack" if cookies else "props/grain_sack", at, randf_range(-30, 30), gs)
	collide(gs.model)
	g.gnaws.append(gs)


## Sticky tape, a cage trap or a cloud of poison spray: the rat is stuck for a while.
func _sticky(p: Dictionary, kind: String) -> void:
	var w := float(p.get("w", 40 if kind == "cage" else 70))
	var h := float(p.get("h", 40 if kind == "cage" else 70))
	var c := Vector2(float(p.x) + w / 2.0, float(p.y) + h / 2.0)
	var at := W(c.x, c.y) if (kind != "sticky" or bool(p.get("floor", false))) else on_top(c.x, c.y)
	var z := add_zone(StickyZone, "Sticky: " + kind, at, Vector3(w / 100.0, 0.25, h / 100.0)) as StickyZone
	z.kind = kind
	match kind:
		"sticky":
			fit(spawn("props/sticky_tape", at + Vector3.UP * 0.002, 0.0, decor), w, h)
		"cage":
			z.time = 4.0
			z.label = "A cage trap! Gnaw your way out!"
			fit(spawn("props/cage_trap", at + Vector3.UP * 0.13, 0.0, decor), w, h)
		"spray":
			z.time = 1.4
			z.label = "Cough! Cough! Poison spray!"
			spawn("props/spray_can", at + Vector3(w / 250.0, 0, h / 250.0), 0.0, decor)
			var cloud := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			cloud.mesh = sm
			var cm := StandardMaterial3D.new()
			cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.albedo_color = Color(0.6, 0.91, 0.42, 0.22)
			cm.cull_mode = BaseMaterial3D.CULL_DISABLED
			cloud.material_override = cm
			cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			decor.add_child(cloud)
			cloud.global_position = at + Vector3.UP * 0.08
			cloud.scale = Vector3(w / 100.0, 0.36, h / 100.0)


## The finale: a glowing ring by the front door where the family slips out.
func _exit(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.32
	tm.rings = 32
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.91, 0.48, 0.75)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.05, 1)
	decor.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.01
	var l := OmniLight3D.new()
	l.light_color = Color(0.72, 1.0, 0.6)
	l.light_energy = 1.2
	l.omni_range = 2.0
	decor.add_child(l)
	l.global_position = at + Vector3.UP * 0.3
	g.exit_point = at


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
		body.group = str(k.get("group", ""))
		body.push_dir = (W(float(k.toX), float(k.toY)) - W(float(k.x), float(k.y))).normalized()
		body.mass = 0.25
		body.collision_layer = 1
		body.collision_mask = 1
		decor.add_child(body)
		body.global_position = on_top(float(k.x), float(k.y))
		var model := spawn(path, body.global_position, 0.0, body)
		var b := aabb_of(model)
		var cs := CollisionShape3D.new()
		if body.is_round():  # a sphere, so it rolls
			var sp := SphereShape3D.new()
			sp.radius = maxf(b.size.x, b.size.z) * 0.5
			cs.shape = sp
		else:
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
		if bool(s.get("plate", false)):
			# round 12 (asked): some food is SERVED — a plate under it, and the food
			# sits in the plate rather than on the bare surface beneath
			dress_plate(spawn("food/plate", at, randf() * 360.0, decor))
			at += Vector3.UP * 0.02
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
	# round 5: the nest's light had no source (a bare omni mid-air) and the burrow read flat.
	# Now the light SPILLS THROUGH THE MOUSE HOLE from the kitchen: the lamp sits just inside
	# the hole, a warm glow disc marks the hole itself, and bedding mounds + a cloth give the
	# burrow some shape.
	var glow := MeshInstance3D.new()
	glow.name = "Hole glow"
	var gm := SphereMesh.new()
	gm.radius = 0.13
	gm.height = 0.26
	glow.mesh = gm
	glow.scale = Vector3(1.15, 0.85, 0.25)
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1.0, 0.8, 0.55)
	glow.material_override = gmat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nest.add_child(glow)
	glow.global_position = W(180, 604, 40)
	var light := OmniLight3D.new()
	light.light_color = Color8(0xff, 0xd0, 0xa0)
	light.light_energy = 0.95
	light.omni_range = 2.2
	light.omni_attenuation = 1.2  # round 10: the nest stays a pocket of warm dark
	light.shadow_enabled = true  # round 14: the wall must OCCLUDE it — the room's corner glowed with no source
	nest.add_child(light)
	light.global_position = W(180, 622, 42)
	for mnd in [[95, 705, 0.55, 0.42], [168, 712, 0.48, 0.38], [128, 660, 0.42, 0.34], [205, 668, 0.36, 0.3]]:
		var mound := MeshInstance3D.new()
		mound.name = "Bedding"
		var mm := SphereMesh.new()
		mm.radius = 0.3
		mm.height = 0.6
		mound.mesh = mm
		mound.scale = Vector3(mnd[2], 0.16, mnd[3])
		mound.material_override = earth
		nest.add_child(mound)
		mound.global_position = W(mnd[0], mnd[1], 2)
	var cloth := box("Old cloth", W(140, 700, 1), Vector3(0.8, 0.025, 0.55), mat(Color(0.42, 0.2, 0.18)), nest)
	cloth.rotation.y = 0.4
	for p in [[70, 715, 20, "sleep"], [105, 735, -60, "sleep"], [80, 745, 150, "idle"], [125, 705, 200, "sniff"]]:
		var o := W(p[0], p[1], 60)
		var hit := g.ray(o, o + Vector3.DOWN * 1.0)  # on top of the nest bedding, not inside it
		var pup := spawn("characters/rat_pup", (hit.position if not hit.is_empty() else W(p[0], p[1], 2)) + Vector3.UP * 0.006, p[2], nest)
		if pup:
			var cp := ClipPlayer.new(pup)
			cp.play(p[3], 0.0)
			g.nest_pups.append(pup)
	add_zone(NestZone, "Nest", W(130, 692), Vector3(2.4, 0.9, 1.75))
	g.hole = W(180, 585)
