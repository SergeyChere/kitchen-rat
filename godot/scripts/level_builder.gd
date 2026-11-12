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
## Characters come out of Blender flat-shaded: every face has its own normals, so a rounded back was shaded in
## squares and the outline (pushed out along the normals) tore apart at every edge. This gives a character mesh
## smooth normals: all vertices at one point share the average normal, across materials too. Real creases
## (a vertex whose face looks more than ~80° away from the average) keep their own. Skin and materials are
## kept; done once per mesh.
static var _smoothed := {}


static func smooth_mesh(mesh: Mesh) -> Mesh:
	if mesh == null or OS.has_environment("FLAT"):  # dev: FLAT=1 shows the models as authored
		return mesh
	var id := mesh.get_instance_id()
	if _smoothed.has(id):
		return _smoothed[id]
	var surfaces := []
	var sum := {}
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		surfaces.append(arr)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns = arr[Mesh.ARRAY_NORMAL]
		if ns == null:
			continue
		for i in vs.size():
			var k := Vector3i(roundi(vs[i].x * 20000.0), roundi(vs[i].y * 20000.0), roundi(vs[i].z * 20000.0))
			sum[k] = sum.get(k, Vector3.ZERO) + (ns as PackedVector3Array)[i]
	var out := ArrayMesh.new()
	for si in surfaces.size():
		var arr: Array = surfaces[si]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if arr[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in vs.size():
				var k := Vector3i(roundi(vs[i].x * 20000.0), roundi(vs[i].y * 20000.0), roundi(vs[i].z * 20000.0))
				var avg: Vector3 = (sum[k] as Vector3).normalized()
				if avg.length() > 0.5 and avg.dot(ns[i]) > 0.17:
					ns[i] = avg
			arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_TANGENT] = null  # stale now, and nothing on a character uses a normal map
		var rest := PackedFloat32Array()  # where each vertex is in the rest pose: the fur's strands are placed by it
		rest.resize(vs.size() * 3)
		for i in vs.size():
			rest[i * 3] = vs[i].x
			rest[i * 3 + 1] = vs[i].y
			rest[i * 3 + 2] = vs[i].z
		arr[Mesh.ARRAY_CUSTOM0] = rest
		var flags: int = int(mesh.surface_get_format(si)) & int(Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		flags |= int(Mesh.ARRAY_CUSTOM_RGB_FLOAT) << int(Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		out.surface_set_material(si, mesh.surface_get_material(si))
		if mesh is ArrayMesh:
			out.surface_set_name(si, (mesh as ArrayMesh).surface_get_name(si))
	_smoothed[id] = out
	return out


static func _has_material(mesh: Mesh, mat_name: String) -> bool:
	for i in mesh.get_surface_count():
		var mm := mesh.surface_get_material(i)
		if mm and mm.resource_name == mat_name:
			return true
	return false


## Fur in shells: the coat is drawn again in thin layers pushed out along the (smooth) normals, each layer keeping
## only the dots where a strand is still that long. Strands sit in little cells of the rest pose (CUSTOM0, set by
## smooth_mesh), so they stay put while she moves. Dark at the roots, the coat's colour at the tips.
const FUR_LAYERS := 7
const FUR := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_back;
uniform vec3 coat : source_color;
uniform float h = 0.5;        // this layer: 0 at the skin … 1 at the tips
uniform float len = 0.004;    // fur length (mesh units)
uniform float density = 800.0; // strands per mesh unit
varying vec3 rp;
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void vertex() {
	rp = CUSTOM0.xyz;
	VERTEX += NORMAL * len * h;
}
void fragment() {
	vec3 p = rp * density;
	vec3 c = floor(p);
	float r = hash3(c);                      // how long this strand is
	float d = length(fract(p) - 0.5) * 2.0;  // distance from the strand's axis
	if (r * 0.75 + 0.25 < h || d > mix(1.05, 0.35, h)) {
		discard;
	}
	ALBEDO = coat * mix(0.84, 1.05, h) * (0.96 + 0.08 * hash3(c + 7.0));
	ROUGHNESS = 0.6;
}
"""
static var _fur_shader: Shader


## Returns the first pass of the chain: `after` (the outline) → shell 1 → … → shell N.
static func _fur(after: Material, coat: Color, length: float, scale: float) -> Material:
	if _fur_shader == null:
		_fur_shader = Shader.new()
		_fur_shader.code = FUR
	var first: Material = after.duplicate() if after else null  # the outline is shared: this chain needs its own
	var prev: Material = first
	for i in FUR_LAYERS:
		var sm := ShaderMaterial.new()
		sm.shader = _fur_shader
		sm.set_shader_parameter("coat", coat)
		sm.set_shader_parameter("h", float(i + 1) / FUR_LAYERS)
		sm.set_shader_parameter("len", length)
		sm.set_shader_parameter("density", scale / 0.0011)  # a strand every ~1.1 mm of the world
		if prev:
			prev.next_pass = sm
		else:
			first = sm
		prev = sm
	return first


func toonify(n: Node) -> void:
	if _outline == null:
		_outline = _outline_mat(OUTLINE)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var ref: Node3D = m
		var sk := m.get_node_or_null(m.skeleton) as Skeleton3D if m.skin else null
		if sk:
			ref = sk
			m.mesh = smooth_mesh(m.mesh)
		var sc := ref.global_transform.basis.get_scale().x
		var line := OUTLINE * (0.62 if sk else 1.0)  # characters: a finer line (it is unbroken now that they are smooth)
		var grow := snappedf(line / maxf(sc, 0.0001), 0.0001) if absf(sc - 1.0) > 0.01 else line
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if not (mat is BaseMaterial3D):
				continue
			var key := str(mat.get_instance_id()) + ":" + str(grow)
			if not _toon.has(key):
				var t := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				_cel(t)
				if m.skin:
					t.roughness = 0.5  # characters: a soft step from light to shadow over their rounded bodies
				var fine := mat.resource_name.begins_with("Whisker") or mat.resource_name.begins_with("Eye")  # too thin for an outline
				if t.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not fine:
					t.next_pass = _outline if grow == OUTLINE else _outline_mat(grow)
					var furry := 0.0  # fur length in metres: the rat's and the cat's coats
					if sk and mat.resource_name in ["Grey", "White"] and Settings.quality != "low" and not OS.has_environment("NOFUR"):
						if sk.find_bone("Tail1") >= 0:
							furry = 0.0045
						elif _has_material(m.mesh, "CatIris"):
							furry = 0.009
					if furry > 0.0:
						t.next_pass = _fur(t.next_pass as Material, t.albedo_color, furry / maxf(sc, 0.0001), sc)
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
	var det := TextureLib.get_detail(tex_name)  # the grain only: the colour is the one asked for
	if not det.is_empty():
		var m := mat(color)
		m.albedo_texture = det[0]
		m.albedo_color = TextureLib.detail_colour(m.albedo_color, float(det[1]))
		m.uv1_scale = Vector3(tiling.x, tiling.y, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.set_meta("tile_m", 0.5)  # one texture tile ~ 0.5 m: box() scales the UV by the box size
		var p := surface_props(tex_name)
		m.roughness = float(p[0])
		m.metallic = float(p[1])
		_add_normal(m, tex_name)
		return m
	return mat(color)


## A <name>_normal.png (e.g. the normal map from a CC0 PBR set) is picked up
## automatically wherever TextureLib finds the colour map — CDN pack or repo file.
static func _add_normal(m: StandardMaterial3D, tex_name: String) -> void:
	var n := TextureLib.get_texture(tex_name + "_normal", false)
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n


## Give a placed model a real surface: the texture's grain / weave / scratches laid over the materials it
## belongs on, each keeping its OWN designed colour (the purple sofa stays purple with gold cushions, the
## books in the bookcase stay books). `tint` (a colour for the piece from the night data) replaces the
## colour of those materials when given. Mapped in world space, so the grain is the same size on a big
## panel and on a thin leg. No texture -> no change at all.
## `shade` darkens (< 1) the designed colour of the parts that take the surface: a pale top under the moon
## came out pure white.
func apply_texture(n: Node3D, tex_name: String, tint := Color.WHITE, shade := 1.0) -> void:
	var det := TextureLib.get_detail(tex_name) if n != null else []
	if det.is_empty():
		return
	var cache := {}
	var meshes := n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as BaseMaterial3D
			if src == null or not _takes(tex_name, src):
				continue
			var key := src.get_instance_id()
			if not cache.has(key):
				var t := src.duplicate() as BaseMaterial3D
				t.albedo_texture = det[0]
				var base := src.albedo_color if tint == Color.WHITE else tint
				t.albedo_color = TextureLib.detail_colour(Color(base.r * shade, base.g * shade, base.b * shade, base.a), float(det[1]))
				t.uv1_triplanar = true
				t.uv1_world_triplanar = true
				t.uv1_triplanar_sharpness = 4.0
				t.uv1_scale = Vector3.ONE * (1.0 / TILE_M.get(tex_name, 0.5))
				t.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				var p := surface_props(tex_name)
				t.roughness = float(p[0])
				t.metallic = float(p[1])
				_add_normal(t, tex_name)
				cache[key] = t
			m.set_surface_override_material(i, cache[key])


## How big one tile of each texture is in the world (m).
const TILE_M := {"wood": 0.6, "wood_dark": 0.6, "fabric": 0.3, "leather": 0.4, "metal_matte": 0.5, "cardboard": 0.4, "plastic": 0.4}


## Does this material of a model take the surface `tex_name`? Wood grain goes on the wooden parts (warm browns),
## not on the books or the TV; brushed metal and plastic on the pale body, not on the door glass or the magnets;
## fabric and cardboard on everything but the near-black bits (legs, gaps). Glowing and see-through parts never.
static func _takes(tex_name: String, src: BaseMaterial3D) -> bool:
	if src.emission_enabled or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or src.albedo_texture != null:
		return false
	var c := src.albedo_color
	if c.v < 0.16:
		return false
	match tex_name:
		"wood", "wood_dark":
			return c.h > 0.015 and c.h < 0.14 and c.s > 0.3 and c.v < 0.9
		"metal_matte", "plastic":
			return c.s < 0.3 and c.v > 0.35
	return true


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
			atint = Color(0.9, 0.99, 1.07)
		"kids":
			atint = Color(1.03, 0.98, 1.02)
	# soft and fairly bright, like the prototype (its hemisphere light 0x7d8fc4 × 0.75, no tone mapping)
	env.ambient_light_color = Color(0.5, 0.56, 0.8) * atint * 0.38 * ascale * float(pal.get("hemi", 0.8)) / 0.8  # round 4/10: the FILL of the cinematic scheme — low and cool against the keys; the motivated sources carry the room
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
	# The grade keeps each room's character (round 8) but stays inside the range: at 1.2 / 1.17 a tenth of the
	# frame clipped to pure white or neon (measured on screenshots: lit floors, rugs, sofas, the cat). Vivid,
	# not burnt.
	env.adjustment_brightness = 1.05
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.02
	match kind:  # round 8: the per-room grade (see the ambient tint above)
		"living", "dining":
			env.adjustment_brightness = 1.02
			env.adjustment_contrast = 1.05
			env.adjustment_saturation = 1.03
		"pantry":
			env.adjustment_brightness = 1.08
			env.adjustment_contrast = 1.03
			env.adjustment_saturation = 0.95
		"kids":
			env.adjustment_brightness = 1.06
			env.adjustment_saturation = 1.06
	if OS.has_environment("GRADE"):  # dev: GRADE=brightness,contrast,saturation[,linear|filmic|aces|agx] to compare grades
		var gv := OS.get_environment("GRADE").split(",")
		env.adjustment_brightness = float(gv[0])
		env.adjustment_contrast = float(gv[1])
		env.adjustment_saturation = float(gv[2])
		if gv.size() > 3:
			env.tonemap_mode = {"linear": Environment.TONE_MAPPER_LINEAR, "filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES, "agx": Environment.TONE_MAPPER_AGX}.get(gv[3], Environment.TONE_MAPPER_ACES)
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
	# the shadow map only has to cover the room and the nest (≈ 12 m), not the default 100 m: at 100 m a texel
	# was 2.5 cm and the shadow crossing a 20 cm rat came out in blocks
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 11.5  # the room's diagonal: every metre less is a finer shadow on her
	moon.directional_shadow_fade_start = 0.95
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
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-15.0), 0)

	for l in night.get("lights", []):
		var pl := OmniLight3D.new()
		pl.light_color = hex(l.get("c", 0xffa860))
		pl.light_energy = float(l.get("i", 1.0)) * 1.3  # 1.6 burnt the floor under it to white
		pl.omni_range = float(l.get("r", 500)) / 100.0
		pl.omni_attenuation = 1.45  # round 10: a defined pool with real darkness past it, not an even wash
		pl.shadow_enabled = true
		pl.shadow_bias = 0.15
		pl.shadow_normal_bias = 4.0  # her own shadow from a candle crossed her round back in centimetre steps
		root.add_child(pl)
		pl.global_position = W(float(l.x), float(l.y), float(l.get("h", 60)))
		g.flickers.append([pl, pl.light_energy, "steady"])
		# round 4: every light gets a visible source — a little candle lantern at the light's own
		# spot (dark base, warm glowing core), so no light in the room comes from nowhere
		var base := MeshInstance3D.new()
		base.name = "Candle base"
		var bm := CylinderMesh.new()
		bm.top_radius = 0.035
		bm.bottom_radius = 0.05
		bm.height = 0.025
		base.mesh = bm
		base.material_override = mat(hex(0x2a2320))
		root.add_child(base)
		base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no black disc under its own lamp
		base.global_position = W(float(l.x), float(l.y), float(l.get("h", 60)) - 7.0)
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
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no black disc under its own lamp
		flame.global_position = W(float(l.x), float(l.y), float(l.get("h", 60)) - 2.0)
		# round 6: the candle stood on AIR (a light at h=60 in an empty corner) — now a
		# slim stand carries it down to the floor, so the light visibly stands on something
		var lh := float(l.get("h", 60))
		if lh > 12.0:
			var pole := MeshInstance3D.new()
			pole.name = "Candle stand"
			var pm := CylinderMesh.new()
			pm.top_radius = 0.013
			pm.bottom_radius = 0.013
			pm.height = (lh - 8.0) / 100.0
			pole.mesh = pm
			pole.material_override = mat(hex(0x2a2320))
			root.add_child(pole)
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no black disc under its own lamp
			pole.global_position = W(float(l.x), float(l.y), (lh - 8.0) / 2.0)
			var foot := MeshInstance3D.new()
			foot.name = "Candle stand foot"
			var dm := CylinderMesh.new()
			dm.top_radius = 0.075
			dm.bottom_radius = 0.085
			dm.height = 0.012
			foot.mesh = dm
			foot.material_override = mat(hex(0x2a2320))
			root.add_child(foot)
			foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no black disc under its own lamp
			foot.global_position = W(float(l.x), float(l.y), 0.6)

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
	var tile := TextureLib.get_detail("ceramic_tile", 0.5) if str(pal.get("floor", "")) == "tile" else []
	if not tile.is_empty():
		# real tile instead of the placeholder pattern (the texture pack's, or the painted one): its joints and
		# glaze as detail over the old floor's own tone, so the night stays as dark and as blue as before.
		# (This looked for res://assets/textures/ceramic_tile.png, which is never in the repo — it never ran.)
		floor_mat = mat(Color.WHITE)
		floor_mat.albedo_texture = tile[0]
		# a cool grey-blue: the moon and its fill are blue already, and a blue floor under blue light came out
		# electric ultramarine (measured: saturation 0.74). The stains of the scan are flattened (contrast 0.5).
		floor_mat.albedo_color = TextureLib.detail_colour(Color(0.31, 0.32, 0.385), float(tile[1]))
		floor_mat.uv1_scale = Vector3(6, 3.75, 1)
		floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_add_normal(floor_mat, "ceramic_tile")
	var wall_mat := mat(Color.WHITE, wall_tex)
	if str(pal.get("floor", "")) == "tile":
		wall_mat.albedo_color = Color(1.0, 0.95, 0.84)  # kitchens: the blue wall under blue moonlight, same story
	var trim := mat(hex(0x7a4a2a))
	# The room itself (floor, walls) is shaded softly: lamps and candles lay POOLS of light on it that fade out.
	# With the toon step every pool was a hard-edged disc (a white plate on the floor under the candle). Things
	# in the room keep their toon shading.
	for sm in [floor_mat, wall_mat]:
		(sm as StandardMaterial3D).diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		(sm as StandardMaterial3D).rim_enabled = false

	# floor (a thin solid slab) and ceiling (no collision, casts no shadow)
	var fl := box("Floor", Vector3(0, -0.05, 0), Vector3(9.6, 0.1, 6.0), floor_mat, root)
	var fm := (fl as MeshInstance3D).mesh as BoxMesh
	fm.size = Vector3(9.6, 0.1, 6.0)
	# the ceiling faces away from every light, so it was a pure black void over the room: it glows a little in
	# its own colour instead (the night's bounce light), enough to close the room at the top
	var ceil_mat := mat(hex(pal.get("ceil", 0x22263a)))
	ceil_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	ceil_mat.rim_enabled = false
	ceil_mat.emission_enabled = true
	ceil_mat.emission = hex(pal.get("ceil", 0x22263a))
	ceil_mat.emission_energy_multiplier = 0.55
	var ceil := box("Ceiling", Vector3(0, 2.55, 0), Vector3(9.6, 0.1, 6.0), ceil_mat, root, false)
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
		# seen from across the room it is a shaft of moonlight; with the camera inside it (up on the counter,
		# by the window) the sheet was a hard white wedge over half the screen — it fades out near the camera
		smat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		smat.distance_fade_min_distance = 2.5
		smat.distance_fade_max_distance = 7.5
		# round 6: softer — a hint of a shaft, not a searchlight (asked for)
		var stex := TextureLib.get_texture("shaft_soft")
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
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], smat)
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
	# Surfaces (look pass 2): wood grain on the worktops, the island's butcher block and the table (only their
	# wooden parts take it: the cream fronts and the blue body stay painted), cardboard on the box, a woven red
	# cloth. The island's pale top is shaded down: under the moon it was pure white and the white rat vanished
	# on it.
	apply_texture(furn_piece("furniture/counter_corner", 36, 36, 0.0, "counter", 72, 72), "wood")
	var n := 12
	var w := (830.0 - 72.0) / n
	for i in n:
		var piece := furn_piece("furniture/counter_sink" if i == 6 else "furniture/counter_section", 72 + w * (i + 0.5), 36, 0.0, "counter", w, 72)
		apply_texture(piece, "wood")
		if i == 6 and piece:
			_sink_water(piece)
	for j in 4:
		apply_texture(furn_piece("furniture/counter_section", 36, 72 + 60 * (j + 0.5), 90.0, "counter", 60, 72), "wood")
	furn_piece("furniture/fridge", 895, 56, 0.0, "fridge", 130, 110)
	add_zone(HumZone, "Fridge hum", W(895, 140), Vector3(1.8, 1.2, 1.2))
	apply_texture(furn_piece("furniture/kitchen_island", 480, 295, 180.0, "island", 200, 90), "wood", Color.WHITE, 0.72)
	apply_texture(furn_piece("furniture/cardboard_box", 608, 284, 0.0, "box", 44, 44, 44), "cardboard")
	var table := furn_piece("furniture/table_kitchen", 720, 445, 0.0, "table", 200, 130)
	if table:
		var cloth := table.find_child("tablecloth*", true, false) as Node3D
		if cloth:
			apply_texture(cloth, "fabric", Color(0.62, 0.13, 0.1))  # a deep red: the pale one washed out to pink
		apply_texture(table, "wood")
		var spec := {}
		for f in night.get("furn", []):
			if str(f.t) == "table": spec = f
		if cloth and int(spec.get("cloth", 0)) == 0:
			cloth.queue_free()
	_hide("table", 720, 445, 184, 114)
	# round 5: hiding under a bare table read as ridiculous — there are THINGS under it now:
	# a storage box and the kid's backpack, and she ducks in among them
	collide(spawn("props/small_box", W(655, 485), 18.0, decor))
	spawn("props/backpack", W(778, 402), -35.0, decor)
	for c in [[596, 420, 90], [596, 472, 90], [846, 446, -90]]:
		furn_piece("furniture/chair", c[0], c[1], c[2], "chair")
		_hide("chair", c[0], c[1], 28, 28)
	furn_piece("furniture/low_shelf", 231, 325, 0.0, "lowShelf", 62, 50)
	_hide("shelf", 231, 325, 54, 42)
	furn_piece("furniture/stool", 100, 252, 0.0, "stool")
	if bool(night.get("kitchenUpper", false)):
		_kitchen_upper()


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


## A few kibbles left in the cat's bowl.
func _bowl_leftovers(bowl: Node3D) -> void:
	var bb := world_aabb(bowl)
	var c := bb.get_center()
	var r := minf(bb.size.x, bb.size.z) * 0.28
	var kib := mat(hex(0x8a5a2e))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 22:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var k := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.009
		sm.height = 0.012
		k.mesh = sm
		k.material_override = kib
		decor.add_child(k)
		k.global_position = Vector3(c.x + cos(a) * d, bb.position.y + bb.size.y * 0.6 + rng.randf() * 0.008, c.z + sin(a) * d)


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
				fit(spawn("props/foil", c, 0.0, decor), float(p.w), float(p.h))
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
			collide(spawn("food/plate", on_top(680, 432), 0.0, decor))
	var ex: Array = night.get("exit", [])
	if ex.size() >= 2:
		_exit(Nights.pos(ex))
	spawn("props/cat_bed", Nights.pos(night.get("catBed")), 0.0, decor)  # no collision: the cat lies in it
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
			spawn("food/plate", at, randf() * 360.0, decor)
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
	# The burrow's front wall: earth around the mouse hole, so from inside she doesn't look at the back of the
	# kitchen's wallpaper (the wall section's rear face).
	box("Front", W(89, 608, 50), Vector3(1.58, 1.0, 0.04), earth, nest, false)
	box("Front", W(221, 608, 50), Vector3(0.58, 1.0, 0.04), earth, nest, false)
	box("Front", W(180, 608, 60), Vector3(0.24, 0.8, 0.04), earth, nest, false)
	# The light SPILLS IN THROUGH THE MOUSE HOLE (round 5): a soft warm cone from the hole across the burrow's
	# floor and bedding. It used to be an omni 20 cm from the wall, which burnt a white patch around the hole.
	var light := SpotLight3D.new()
	light.name = "Hole light"
	light.light_color = Color8(0xff, 0xd0, 0xa0)
	light.light_energy = 1.5
	light.spot_range = 3.2
	light.spot_angle = 62.0
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 0.9
	nest.add_child(light)
	light.global_position = W(180, 613, 20)  # just inside the front wall, in the mouth of the hole
	light.look_at(W(140, 730, 0), Vector3.UP)
	var fillc := OmniLight3D.new()  # the bounce of that light off the floor: keeps the corners readable
	fillc.name = "Burrow fill"
	fillc.light_color = Color8(0xe8, 0xa8, 0x78)
	fillc.light_energy = 0.7
	fillc.omni_range = 2.6
	fillc.omni_attenuation = 0.8
	nest.add_child(fillc)
	fillc.global_position = W(130, 690, 60)
	# bedding: flat heaps of straw and wood shavings, softly shaded (a toon-shaded dark dome read as a pit)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = hex(0xa88a52)
	straw.roughness = 1.0
	straw.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var straw2 := straw.duplicate() as StandardMaterial3D
	straw2.albedo_color = hex(0x8f7445)
	# Each heap is a low mound with loose straws lying over and around it (thin sticks at every angle): seen from
	# rat height one smooth mound read as a giant bread roll.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var straw_mats := [straw, straw2, straw.duplicate()]
	(straw_mats[2] as StandardMaterial3D).albedo_color = hex(0xc4a868)
	var stick := BoxMesh.new()
	stick.size = Vector3(1, 1, 1)
	for mnd in [[95, 705, 0.55, 0.42], [168, 712, 0.48, 0.38], [128, 660, 0.42, 0.34], [205, 668, 0.36, 0.3]]:
		var mound := MeshInstance3D.new()
		mound.name = "Bedding"
		var mm := SphereMesh.new()
		mm.radius = 0.3
		mm.height = 0.6
		mm.radial_segments = 14
		mm.rings = 6
		mound.mesh = mm
		mound.scale = Vector3(mnd[2], 0.07, mnd[3])
		mound.material_override = straw2
		mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nest.add_child(mound)
		mound.global_position = W(mnd[0], mnd[1], 0.5)
		for i in 46:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 1.25  # some straws spill out past the heap
			var off := Vector3(cos(a) * r * 0.3 * float(mnd[2]), 0.0, sin(a) * r * 0.3 * float(mnd[3]))
			var hgt := 0.021 * maxf(1.0 - r * r, 0.0) + 0.004 + rng.randf() * 0.006
			var st := MeshInstance3D.new()
			st.name = "Straw"
			st.mesh = stick
			st.material_override = straw_mats[rng.randi() % 3]
			st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nest.add_child(st)
			st.global_position = W(mnd[0], mnd[1], 0.0) + off + Vector3.UP * hgt
			st.rotation = Vector3(rng.randf_range(-0.22, 0.22), rng.randf() * PI, rng.randf_range(-0.08, 0.08))
			st.scale = Vector3(rng.randf_range(0.07, 0.15), 0.005, rng.randf_range(0.005, 0.008))
	# the old cloth: a rag in three overlapping pieces lying a little askew, with a patch sewn on
	var rag := mat(Color(0.5, 0.22, 0.2))
	var rag2 := mat(Color(0.42, 0.18, 0.17))
	for cl in [[140, 700, 0.62, 0.44, 0.4, rag, 1.0], [118, 712, 0.38, 0.3, 0.75, rag2, 1.6], [160, 690, 0.3, 0.34, 0.1, rag2, 1.4]]:
		var piece := box("Old cloth", W(cl[0], cl[1], cl[6]), Vector3(cl[2], 0.012, cl[3]), cl[5], nest, false)
		piece.rotation.y = cl[4]
		(piece as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var patch := box("Cloth patch", W(150, 706, 2.3), Vector3(0.13, 0.006, 0.11), mat(Color(0.25, 0.38, 0.5)), nest, false)
	patch.rotation.y = 0.9
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
