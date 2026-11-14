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
const OUTLINE := 0.0034  # outline width (m): a pen line over the paint (round 14; it was 0.0055, bold cartoon)


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
## only the spots where a lock is still that long (round 14: locks and flat painted tones, see fragment()). Strands sit in little cells of the rest pose (CUSTOM0, set by
## smooth_mesh), so they stay put while she moves. Dark at the roots, the coat's colour at the tips.
static func fur_layers() -> int:  # round 16: 14 shells on every furry animal cost more than the rest of the frame
	return 12 if Settings.quality == "high" else 7
const FUR := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_back;
uniform vec3 coat : source_color;
uniform float h = 0.5;          // this layer: 0 at the skin … 1 at the tips
uniform float len = 0.004;      // fur length (mesh units)
uniform float density = 1600.0; // strands per mesh unit
uniform vec3 comb = vec3(0.0, -0.35, -1.0); // which way the coat lies (mesh space): back toward the tail, a little down
uniform float z_front = 1.0;    // rest-pose z of the nose and of the tail root: the fur is shorter on the face
uniform float z_back = 0.0;
uniform float grey = 0.0;       // 0 = the coat's own colour … 1 = its grey (the rats: a grey coat, not a brown one)
uniform float shade = 1.0;      // darkens the whole coat
varying vec3 rp;
varying float tone;
varying float up;
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void vertex() {
	rp = CUSTOM0.xyz;
	float along = clamp((rp.z - z_back) / max(z_front - z_back, 0.0001), 0.0, 1.0); // 0 rump … 1 nose
	float l = len * mix(1.0, 0.4, smoothstep(0.62, 0.9, along));
	vec3 n = normalize(NORMAL);
	vec3 lay = comb - n * dot(comb, n);          // the combing direction, along the skin
	// each layer goes out a little and back a lot more the higher it is: the strands curve over and lie down
	VERTEX += (n * (h * 0.55) + lay * (h * h * 0.9)) * l;
	tone = h;
	up = n.y;
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void fragment() {
	// Round 14, painted fur: not a pelt of dots but LOCKS — cells three times longer along the body than
	// across it, so each one is a short stroke of the brush lying back toward the tail, and the outline of
	// the coat breaks into tufts.
	vec3 p = rp * density * vec3(1.0, 1.0, 0.33);
	vec3 c = floor(p);
	float r = hash3(c);                               // how long this lock is
	vec3 jit = vec3(hash3(c + 3.1), hash3(c + 5.7), hash3(c + 9.3)) - 0.5;
	float d = length(fract(p) - 0.5 - jit * 0.5) * 2.0; // distance from the lock's (jittered) axis
	// thick and overlapping at the root (no bare skin between locks), a fine point at the tip
	// (the lowest layer is a solid undercoat in the coat's own colour: the model's skin under it is another
	// colour, and every gap between locks showed it as a dark dash)
	if (h > 0.16 && (r * 0.6 + 0.4 < tone || d > mix(1.5, 0.25, tone))) {
		discard;
	}
	// the colour is laid in two or three flat tones with brush-shaped borders, as a painter blocks in fur:
	// broad darker strokes, a few lighter warm ones on top
	vec3 sp = rp * density * vec3(0.07, 0.07, 0.03);
	float s1 = vnoise(sp);
	float s2 = vnoise(sp * 1.7 + 7.3);
	vec3 base = mix(coat, vec3(dot(coat, vec3(0.3, 0.59, 0.11))) * vec3(1.1, 1.0, 0.88), grey) * shade;
	// round 17 (the painted key art the player sent): cool grey strokes, warm tan ones catching the light along
	// the back, the flanks a shade darker toward the belly — brushwork you can see, but in two or three tones
	vec3 col = base * mix(0.95, 1.0, smoothstep(0.3, 0.56, s1));
	float top = smoothstep(-0.1, 0.7, up);
	col = mix(col, base * vec3(1.3, 1.14, 0.9), smoothstep(0.5, 0.72, s2 * 0.7 + s1 * 0.3) * (0.2 + 0.6 * top));
	col *= mix(0.86, 1.0, smoothstep(-0.7, 0.1, up));
	ALBEDO = col;  // one flat tone through the whole depth of the coat: the gaps between locks must not read as dots
	ROUGHNESS = 0.6;
}
// The lamps and the moon are tuned for a dark floor; a pale animal standing in the moon patch next to the
// night-light burnt out to a white blob. So the coat takes direct light at six tenths, and the glow along
// its edge now needs the light to actually reach it (the built-in rim ignores shadow and distance: every
// lamp in range added to it). In shade — most of the game — nothing changes.
void light() {
	float lit = smoothstep(-0.6, 0.6, dot(NORMAL, LIGHT));
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	DIFFUSE_LIGHT += (lit * 0.6 + edge * 0.38 * (0.35 + 0.65 * lit)) * ATTENUATION * LIGHT_COLOR / PI;
}
"""
static var _fur_shader: Shader


## Returns the first pass of the chain: `after` (the outline) → shell 1 → … → shell N.
## `z_front` / `z_back`: the mesh's rest-pose extent along its length (the face gets shorter fur).
static func _fur(after: Material, coat: Color, length: float, scale: float, z_front := 1.0, z_back := 0.0, grey := 0.0, shade := 1.0) -> Material:
	if _fur_shader == null:
		_fur_shader = Shader.new()
		_fur_shader.code = FUR
	var first: Material = after.duplicate() if after else null  # the outline is shared: this chain needs its own
	var prev: Material = first
	var layers := fur_layers()
	for i in layers:
		var sm := ShaderMaterial.new()
		sm.shader = _fur_shader
		sm.set_shader_parameter("coat", coat)
		sm.set_shader_parameter("h", float(i + 1) / layers)
		sm.set_shader_parameter("len", length)
		sm.set_shader_parameter("density", scale / 0.0022)  # a lock every ~2 mm of the world (and ~7 mm long)
		sm.set_shader_parameter("grey", grey)
		sm.set_shader_parameter("shade", shade)
		sm.set_shader_parameter("z_front", z_front)
		sm.set_shader_parameter("z_back", z_back)
		if prev:
			prev.next_pass = sm
		else:
			first = sm
		prev = sm
	return first


## A white glint in each eye (the rat and her pups: two black beads without one look blind). The eyes are the
## mesh's "Eye" surface; each glint is a tiny unshaded sphere riding the Head bone, set on the eye's upper outer
## side, where a lamp above would reflect.
func _catchlights(m: MeshInstance3D, sk: Skeleton3D) -> void:
	var hb := sk.find_bone("Head")
	if hb < 0 or sk.has_node("Catchlights"):
		return
	var si := -1
	for i in m.mesh.get_surface_count():
		var mm := m.mesh.surface_get_material(i)
		if mm and mm.resource_name in ["Eye", "Eyes", "Eyes_White"]:  # rat and pups · people · the dog
			si = i
	if si < 0:
		return
	var arr := m.mesh.surface_get_arrays(si)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var att := BoneAttachment3D.new()
	att.name = "Catchlights"
	sk.add_child(att)
	att.bone_name = "Head"
	# a skinned vertex ends up at  bone pose × bind pose × vertex : so in the Head bone's own space (where the
	# attachment's children live) a point of the mesh is  bind pose × point
	var to_head := Transform3D.IDENTITY
	var found := false
	for bi in m.skin.get_bind_count():
		if m.skin.get_bind_name(bi) == &"Head" or m.skin.get_bind_bone(bi) == hb:
			to_head = m.skin.get_bind_pose(bi)
			found = true
			break
	if not found:
		att.queue_free()
		return
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1, 1, 1)
	# eyelids in the colour of the coat around the eyes (see Blink)
	var coat := Color(0.6, 0.56, 0.54)
	for want in ["White", "Grey", "Skin", "Main"]:
		for i in m.mesh.get_surface_count():
			var cm := m.mesh.surface_get_material(i) as BaseMaterial3D
			if cm and cm.resource_name == want:
				coat = cm.albedo_color
	var lid_mat := mat(coat * 0.8)  # (the fur around it takes less direct light than a bare ball)
	var blink := Blink.new()
	blink.name = "Blink"
	# the people's "Eyes" surface also has a pile of degenerate faces down at their feet (in the stock models):
	# counted in, every eyelid came out the size of the whole body — the sleeping kid lay under a dark dome
	# and a blink flashed a huge ball. Only the vertices up at the top of the surface are the eyes.
	var ytop := -INF
	for v in vs:
		ytop = maxf(ytop, v.y)
	var reach := m.mesh.get_aabb().get_longest_axis_size() * 0.1
	var eye := func(v: Vector3) -> bool: return v.y > ytop - reach
	for side in [-1.0, 1.0]:
		var c := Vector3.ZERO
		var nrm := Vector3.ZERO
		var cnt := 0
		for i in vs.size():
			if vs[i].x * side > 0.0 and eye.call(vs[i]):
				c += vs[i]
				nrm += ns[i]
				cnt += 1
		if cnt < 3:
			continue
		c /= cnt
		nrm = Vector3(side, 0.0, 0.45).normalized()  # outward and a little forward (the eye is a whole ball: its normals average to nothing)
		var r := 0.0
		for i in vs.size():
			if vs[i].x * side > 0.0 and eye.call(vs[i]):
				r = maxf(r, vs[i].distance_to(c))
		var dot := MeshInstance3D.new()
		dot.name = "Glint"
		var sm := SphereMesh.new()
		sm.radius = r * 0.3
		sm.height = r * 0.6
		sm.radial_segments = 8
		sm.rings = 4
		dot.mesh = sm
		dot.material_override = white
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(dot)
		dot.position = to_head * (c + nrm * r * 0.8 + Vector3.UP * r * 0.45)
		dot.scale = Vector3.ONE * to_head.basis.get_scale().x
		blink.glints.append(dot)
		var lid := MeshInstance3D.new()
		lid.name = "Eyelid"
		var lm := SphereMesh.new()
		lm.radius = r * 1.1
		lm.height = r * 2.2
		lm.radial_segments = 10
		lm.rings = 5
		lid.mesh = lm
		lid.material_override = lid_mat
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(lid)
		lid.position = to_head * c
		lid.scale = Vector3.ONE * to_head.basis.get_scale().x
		blink.lids.append(lid)
	att.add_child(blink)


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
		if sk:
			_catchlights(m, sk)
		var sc := ref.global_transform.basis.get_scale().x
		var line := OUTLINE * (0.8 if sk else 1.0)  # characters: a finer line (it is unbroken now that they are smooth)
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
					# The built-in rim is added once per lamp in range, shadowed or not, whatever the distance:
					# with the moon, its fill and a lamp or two her tail and paws came out as pure white. Bodies
					# keep a hint of it, and pale skin gives the moon patch a little headroom.
					t.rim = 0.12
					if t.albedo_texture == null and t.albedo_color.v > 0.7 and not mat.resource_name.begins_with("Whisker"):
						t.albedo_color = t.albedo_color.darkened(0.1)
					elif t.albedo_texture != null:
						# a painted (Meshy) skin: its light greys and creams bleached to paper white under the lamps and
						# the watercolour filter — painted a shade darker, as the old rats' coats were
						t.albedo_color = Color(0.72, 0.7, 0.7)
						if sk.find_bone("Tail1") >= 0:
							t.albedo_color = Color(0.55, 0.53, 0.54)  # the rats: pale fur, and the camera is always close
					# round 14: tail, ears and paws are a clear painted pink, not a near-white that the lamps bleach
					if mat.resource_name == "Pink" and sk.find_bone("Tail1") >= 0:
						t.albedo_color = Color(0.83, 0.56, 0.55)
				# Round 14, watercolour: every plain painted thing (not the characters — their skin moves) gets the
				# wash laid over its own colour: patches of brushwork and drying lines instead of a flat fill.
				# Mapped in the model's own space, so the pattern travels with a thing that is pushed or carried.
				if not m.skin and t is StandardMaterial3D and t.albedo_texture == null and not t.emission_enabled \
						and t.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and t.albedo_color.v > 0.1 \
						and not OS.get_environment("HIDE").contains("wash"):
					var w := TextureLib.get_detail("wash", 1.9)
					if not w.is_empty():
						t.albedo_texture = w[0]
						t.albedo_color = TextureLib.detail_colour(t.albedo_color, float(w[1]))
						t.uv1_triplanar = true
						t.uv1_scale = Vector3.ONE * (sc / 0.9)
						t.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				var fine := mat.resource_name.begins_with("Whisker") or mat.resource_name.begins_with("Eye")  # too thin for an outline
				if t.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not fine:
					t.next_pass = _outline if grow == OUTLINE else _outline_mat(grow)
					var furry := 0.0  # fur length in metres: the rat's and the cat's coats
					if sk and mat.resource_name in ["Grey", "White"] and Settings.quality != "low" and not OS.has_environment("NOFUR"):
						if sk.find_bone("Tail1") >= 0:
							furry = 0.008
						elif _has_material(m.mesh, "CatIris"):
							furry = 0.011
					elif sk and mat.resource_name in ["Main", "Main_Light"] and _has_material(m.mesh, "Eyes_Pupil") \
							and Settings.quality != "low" and not OS.has_environment("NOFUR"):
						furry = 0.012  # round 15: the dog has a coat too
					# (not over a painted texture — a Meshy model is painted already, and the veil bleached it white)
					if sk and furry == 0.0 and Settings.quality != "low" and t.albedo_color.v > 0.12 and t.albedo_texture == null:
						t.next_pass = _wash_pass(t.next_pass as Material, sc)
					if furry > 0.0:
						var box := m.mesh.get_aabb()
						var rat_coat := furry < 0.01  # the rats: a grey coat a shade darker than the model's brown
						t.next_pass = _fur(t.next_pass as Material, t.albedo_color, furry / maxf(sc, 0.0001), sc, box.end.z, box.position.z,
								0.75 if rat_coat else 0.0, 0.7 if rat_coat else 0.9)
				_toon[key] = t
			m.set_surface_override_material(i, _toon[key])


## Round 15: brushwork on the characters. Their bodies move, so a pattern laid in world or model space would swim
## over them; this pass reads the REST position smooth_mesh() stored in CUSTOM0 and multiplies the wash over the
## lit surface — a shirt or a trouser leg is a painted patch that bends with the body.
const SKIN_WASH := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_back;
uniform sampler2D wash : source_color, filter_linear_mipmap, repeat_enable;
uniform float density = 2.0;   // tiles per unit of the model's own space
uniform float mean = 0.48;     // the picture's average value (linear)
uniform float strength = 1.0;
uniform float lift = 0.0004;
varying vec3 rp;
varying vec3 rn;
void vertex() {
	rp = CUSTOM0.xyz * density;
	rn = abs(NORMAL);
	VERTEX += NORMAL * lift;
}
void fragment() {
	vec3 w = rn / max(rn.x + rn.y + rn.z, 0.001);
	float v = texture(wash, rp.zy).r * w.x + texture(wash, rp.xz).r * w.y + texture(wash, rp.xy).r * w.z;
	// (not blend_mul: on this renderer a multiply pass came out black. A veil instead: thin dark paint where the
	// wash is heavy, a breath of paper where it is thin.)
	float d = v / mean - 1.0;
	ALBEDO = d < 0.0 ? vec3(0.05, 0.04, 0.09) : vec3(1.0, 0.96, 0.88);
	ALPHA = clamp(d < 0.0 ? -d * 1.5 : d * 0.3, 0.0, 0.5) * strength;
}
"""
static var _skin_wash: Shader


## The wash pass for one character material; `after` (the outline) is drawn after it.
static func _wash_pass(after: Material, sc: float) -> Material:
	var w := TextureLib.get_detail("wash", 1.9)
	if w.is_empty() or OS.get_environment("HIDE").contains("wash"):
		return after
	if _skin_wash == null:
		_skin_wash = Shader.new()
		_skin_wash.code = SKIN_WASH
	var sm := ShaderMaterial.new()
	sm.shader = _skin_wash
	sm.set_shader_parameter("wash", w[0])
	sm.set_shader_parameter("mean", 1.0 / float(w[1]))  # get_detail returns the gain: 1 / the linear mean
	if OS.has_environment("WASHK"):
		sm.set_shader_parameter("strength", float(OS.get_environment("WASHK")))
	sm.set_shader_parameter("density", sc / 0.45)
	sm.set_shader_parameter("lift", 0.0005 / maxf(sc, 0.0001))
	sm.next_pass = after
	return sm


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
	o.albedo_color = Color(0.2, 0.115, 0.075)  # sepia ink, not black
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
	if TextureLib.painted(tex_name):
		return  # a painted surface is flat paper: no relief under the brushwork
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
		m.albedo_texture = TextureLib.get_texture(texture, false) if TextureLib.painted(texture) else load("res://assets/textures/" + texture + ".png")
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
	RoomFurniture.new(self).life(str(night.get("decor", "kitchen")))
	_ground_shadows()
	_practicals()


## Soft dark patches on the floor under every piece of furniture and along the foot of the walls (what a
## renderer with ambient occlusion would give): without them the furniture floats on the floor and the room has
## no corners. One flat quad per piece, the piece's footprint with a feathered edge; lighter and wider under
## things on legs.
const GROUND_SHADOW := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
uniform vec2 inner = vec2(0.5, 0.5);  // half footprint (m)
uniform vec2 quad = vec2(1.0, 1.0);   // the quad's full size (m)
uniform float feather = 0.16;
uniform float strength = 0.4;
void fragment() {
	vec2 p = (UV - 0.5) * quad;
	vec2 q = abs(p) - inner;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);  // distance outside the footprint
	float a = 1.0 - smoothstep(-feather * 0.35, feather, d);
	ALBEDO = vec3(0.015, 0.02, 0.06);
	ALPHA = a * a * strength;
}
"""
var _gs_shader: Shader


func _ground_shadow(at: Vector3, half: Vector2, yaw: float, feather: float, strength: float, parent: Node) -> void:
	if _gs_shader == null:
		_gs_shader = Shader.new()
		_gs_shader.code = GROUND_SHADOW
	var mi := MeshInstance3D.new()
	mi.name = "Ground shadow"
	var pm := PlaneMesh.new()
	var full := (half + Vector2(feather, feather)) * 2.0
	pm.size = full
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = _gs_shader
	sm.set_shader_parameter("inner", half)
	sm.set_shader_parameter("quad", full)
	sm.set_shader_parameter("feather", feather)
	sm.set_shader_parameter("strength", strength)
	sm.render_priority = -1
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at
	mi.rotation.y = yaw


func _ground_shadows() -> void:
	if OS.get_environment("HIDE").contains("ao"):  # dev: compare
		return
	var grp := group("Ground shadows")
	for c in furn.get_children():
		var n := c as Node3D
		if n == null or not n.visible:
			continue
		var nm := str(n.name).to_lower()
		var skip := false
		for k in ["rug", "carpet", "door", "window", "curtain", "mat_", "garland", "wall", "picture", "shadow"]:
			if nm.contains(k):
				skip = true
		if skip:
			continue
		var box := aabb_of(n)
		var wb := n.global_transform * box
		if wb.position.y > 0.06 or wb.size.y < 0.04 or box.size.x <= 0.0:
			continue  # hangs on a wall, or lies flat
		var sc := n.global_transform.basis.get_scale()
		var half := Vector2(box.size.x * sc.x, box.size.z * sc.z) * 0.5
		if half.x > 2.6 or half.y > 2.6:
			continue
		var legs := false
		for k in ["table", "chair", "stool", "desk", "bench", "crib", "cart", "ladder", "horse", "easel", "floor_lamp", "plant"]:
			if nm.contains(k):
				legs = true
		var centre := n.global_transform * (box.position + box.size * 0.5)
		_ground_shadow(Vector3(centre.x, 0.004, centre.z), half * (0.82 if legs else 1.0), n.global_rotation.y, 0.24 if legs else 0.15, 0.3 if legs else 0.5, grp)
	# the foot of the four walls
	var w := Nights.ROOM_W / 100.0
	var d := Nights.ROOM_D / 100.0
	var o := Nights.world(0, 0)
	for wall in [[Vector3(o.x + w * 0.5, 0.003, o.z), Vector2(w * 0.5, 0.02)], [Vector3(o.x + w * 0.5, 0.003, o.z + d), Vector2(w * 0.5, 0.02)],
			[Vector3(o.x, 0.003, o.z + d * 0.5), Vector2(0.02, d * 0.5)], [Vector3(o.x + w, 0.003, o.z + d * 0.5), Vector2(0.02, d * 0.5)]]:
		_ground_shadow(wall[0], wall[1], 0.0, 0.38, 0.34, grp)


## Warm lights against the cold moon (the It Takes Two scheme: every room has both).
##  · every room: the hall light is on behind the door — a glowing gap under it and a warm streak across the floor
##  · kitchens (the bluest rooms): a plug-in night-light on the wall by the mouse hole, a pool of amber at home's door
func _practicals() -> void:
	if OS.get_environment("HIDE").contains("warm"):  # dev: compare
		return
	var grp := group("Practicals")
	var warm := Color(1.0, 0.7, 0.4)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.82, 0.55)
	# the door (east wall): section j is 120 cm wide, the leaf sits in its middle
	var door_j := clampi(floori(float(night.get("door", 300)) / 120.0), 0, 4)
	var dy := door_j * 120.0 + 60.0
	var gap := box("Door gap glow", W(957.5, dy, 0.6), Vector3(0.02, 0.012, 0.8), glow, grp, false)
	(gap as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the streak itself is painted on the floor (a light skimming the floor at that angle lights nothing in a
	# toon-shaded scene): an additive wedge that starts as wide as the door and fades out 1.7 m into the room
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.62, 0.3);
void fragment() {
	float along = 1.0 - UV.x;              // 0 at the door … 1 at the far end
	float across = abs(UV.y - 0.5) * 2.0;  // 0 on the axis … 1 at the edge
	float w = mix(0.62, 1.0, along);       // the wedge opens as it goes
	float a = pow(1.0 - along, 2.2) * (1.0 - smoothstep(w * 0.55, w, across));
	ALBEDO = tint * a * 0.8;
}
"""
	var sm0 := ShaderMaterial.new()
	sm0.shader = sh
	var streak := MeshInstance3D.new()
	streak.name = "Hall light on the floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.7, 1.25)
	streak.mesh = pm
	streak.material_override = sm0
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grp.add_child(streak)
	streak.global_position = W(960 - 85, dy, 0.5)
	var spill := OmniLight3D.new()  # and it warms whatever stands by the door
	spill.name = "Hall light spill"
	spill.light_color = warm
	spill.light_energy = 0.32      # (0.9 with a falloff of 1.6, this close to the floor, was ten times that under it)
	spill.omni_range = 1.6
	spill.omni_attenuation = 0.6
	grp.add_child(spill)
	spill.global_position = W(925, dy, 30)
	if str(night.get("decor", "kitchen")) != "kitchen":
		return
	# the night-light: a little plug with a glowing amber dome, right of the hole
	var plug := box("Night-light", W(262, 597, 15), Vector3(0.045, 0.06, 0.03), mat(hex(0xe8e2d4)), grp, false)
	(plug as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dome := MeshInstance3D.new()
	dome.name = "Night-light dome"
	var sm := SphereMesh.new()
	sm.radius = 0.026
	sm.height = 0.052
	dome.mesh = sm
	var amber := StandardMaterial3D.new()
	amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amber.albedo_color = Color(1.0, 0.74, 0.36)
	dome.material_override = amber
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grp.add_child(dome)
	dome.global_position = W(262, 594, 15)
	var nl := OmniLight3D.new()
	nl.name = "Night-light"
	nl.light_color = Color(1.0, 0.64, 0.3)
	# A small pool of amber, no more. Godot's lamps follow an inverse-power law: with the lamp 10 cm off the
	# wall and a falloff of 1.5 the wall next to it got forty times the lamp's energy — the wall, the floor and
	# she were burnt to white right at her own door. So: a little out from the wall, a nearly flat falloff
	# (the range window shapes the pool instead), and a third of the energy.
	nl.light_energy = 0.24
	nl.omni_range = 1.5
	nl.omni_attenuation = 0.6
	nl.shadow_enabled = true
	nl.shadow_bias = 0.15
	nl.shadow_normal_bias = 4.0
	grp.add_child(nl)
	nl.global_position = W(262, 576, 20)


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
			if kind == "dining":
				ascale = 1.2  # round 15: near-black purple walls — it was the darkest room in the house
		"pantry":
			atint = Color(0.9, 0.99, 1.07)
			ascale = 1.6  # round 14 (1.3), round 15 (1.6): dark wood walls and a dark floor need far more fill than the pale kitchen
		"kids":
			atint = Color(1.03, 0.98, 1.02)
	# soft and fairly bright, like the prototype (its hemisphere light 0x7d8fc4 × 0.75, no tone mapping)
	env.ambient_light_color = Color(0.5, 0.56, 0.8) * atint * 0.78 * ascale * float(pal.get("hemi", 0.8)) / 0.8  # round 14: 0.78 (it was 0.38 — "the locations look dark"): a painted night is blue, not black. Before: round 4/10: the FILL of the cinematic scheme — low and cool against the keys; the motivated sources carry the room
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
	fill.light_energy = 0.34  # round 14 (0.22): the user found the painted rooms too dark
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
		if float(l.get("h", 60)) > 40.0:
			# round 16 (asked: "the floor lamp in the kitchen corner looks silly"): a light standing in the room
			# was a candle on a bare stick; now it is a real floor lamp, the light inside its shade
			floor_lamp(W(float(l.x), float(l.y)), true)
			pl.global_position = W(float(l.x), float(l.y), 140)
			pl.light_energy *= 0.8
			continue
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


## Dust hanging in the moonlight: a few dozen specks drifting inside the shaft from the window down to its
## patch on the floor. They only exist where the light is, so the beam reads as a volume of air.
func _dust_motes(from: Vector3, dir: Vector3, width: float, height: float) -> void:
	var length := from.y / -dir.y  # down to the floor
	var p := CPUParticles3D.new()
	p.name = "Dust motes"
	p.amount = 120
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.randomness = 1.0
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.42, height * 0.36, length * 0.46)
	p.direction = Vector3(0.3, -1.0, 0.2)
	p.spread = 180.0
	p.gravity = Vector3(0, -0.003, 0)
	p.initial_velocity_min = 0.004
	p.initial_velocity_max = 0.022
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()  # each speck swims into the light and out of it again
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 1))
	ramp.add_point(0.7, Color(1, 1, 1, 0.8))
	p.color_ramp = ramp
	var dot := GradientTexture2D.new()
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = dot
	m.albedo_color = Color(0.72, 0.82, 1.0, 0.7)
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA  # none of them in her face
	m.distance_fade_min_distance = 0.9   # (up close they were snowflakes; they are specks in a beam seen from a way off)
	m.distance_fade_max_distance = 2.4
	var q := QuadMesh.new()
	q.size = Vector2(0.015, 0.015)
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	# the box lies along the beam: its long axis (z) is the moon's direction
	var mid := from + dir * (length * 0.5)
	p.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), mid)


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
	var tile := TextureLib.get_detail("ceramic_tile", 1.0 if TextureLib.painted("ceramic_tile") else 0.5) if str(pal.get("floor", "")) == "tile" else []
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
	ceil_mat.emission_energy_multiplier = 1.0  # round 14 (0.55): the ceiling is part of the picture, not a black lid
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
		# the light the window throws into the room, with the tree's leaves swaying through it (asked for: "a
		# tree outside, swaying, and its shadows moving in the room"). The real moon shadow is too faint against
		# the room's fill to show leaves, so the patch is painted by a box round the beam (moon_patch.gdshader).
		var pm := ShaderMaterial.new()
		pm.shader = preload("res://shaders/moon_patch.gdshader")
		pm.render_priority = 2
		pm.set_shader_parameter("sdir", sdir)
		pm.set_shader_parameter("wall_z", z0)
		pm.set_shader_parameter("win_min", Vector2(wcx - ww / 2.0, bot))
		pm.set_shader_parameter("win_size", Vector2(ww, top - bot))
		var lo := Vector3(INF, 0.0, z0)
		var hi := Vector3(-INF, top + 0.1, z0)
		for q in [a, b, Vector3(wcx - ww / 2.0, bot, z0), Vector3(wcx + ww / 2.0, bot, z0)]:
			var f: Vector3 = q + sdir * (q.y / -sdir.y)
			lo.x = minf(lo.x, minf(q.x, f.x))
			hi.x = maxf(hi.x, maxf(q.x, f.x))
			hi.z = maxf(hi.z, f.z)
		var beam := MeshInstance3D.new()
		beam.name = "Moon patch"
		var bm := BoxMesh.new()
		bm.size = hi - lo + Vector3(0.3, 0.1, 0.3)
		beam.mesh = bm
		beam.material_override = pm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
		beam.global_position = (lo + hi) / 2.0
		shaft_mats.append(pm)
		if Settings.quality != "low" and not OS.get_environment("HIDE").contains("motes"):
			_dust_motes(Vector3(wcx, (top + bot) / 2.0, z0), sdir, ww, top - bot)
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
			elif src and model == "wall_mousehole" and src.resource_name == "c7a4a2a.001":
				# round 16 (asked: "the entrance looks strange"): the model's splintered plank trim round the
				# hole is hidden; _mouse_hole() builds an arch instead
				var clear := StandardMaterial3D.new()
				clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				clear.albedo_color = Color(0, 0, 0, 0)
				m.set_surface_override_material(i, clear)
			elif src and model == "wall_window" and src.resource_name == "c9ac4e8":
				# the panes were opaque blue: now clear glass with a faint cool sheen, so the tree and the sky
				# outside (window_sky.gd) show through
				var glass := StandardMaterial3D.new()
				glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glass.albedo_color = Color(0.6, 0.72, 0.95, 0.12)
				glass.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.set_surface_override_material(i, glass)
	if model == "wall_mousehole":
		_mouse_hole(n)
	return n


## The mouse hole as a little front door: a round-topped arch of wooden blocks with a keystone, a scrap of
## carpet for a doormat, and a picture hung on the wall above it, at the people's height.
func _mouse_hole(wall: Node3D) -> void:
	var grp := group("Mouse hole")
	var face := wall.global_transform.basis.z.normalized()  # out of the wall into the room
	var along := wall.global_transform.basis.x.normalized()
	var base := wall.global_position + face * 0.045
	var wood := _paint(Color(0.55, 0.36, 0.2))
	var dark := _paint(Color(0.36, 0.22, 0.12))
	var r := 0.135
	var cy := 0.13
	var n := 9
	for k in n:
		var a := PI * (float(k) + 0.5) / n
		var p := base + along * cos(a) * r + Vector3.UP * (cy + sin(a) * r)
		var b := _bit(grp, p, Vector3(0.05, 0.034 if k != n / 2 else 0.05, 0.03), dark if k == n / 2 else wood)
		b.global_basis = Basis(face, a - PI / 2.0) * Basis.looking_at(-face, Vector3.UP)
	for sd in [-1.0, 1.0]:
		for j in 2:
			var p: Vector3 = base + along * sd * r + Vector3.UP * (0.025 + j * 0.06)
			var b := _bit(grp, p, Vector3(0.05, 0.05, 0.03), wood)
			b.global_basis = Basis.looking_at(-face, Vector3.UP)
	var mat_p := base + face * 0.12 + Vector3.UP * 0.004
	var mat := _bit(grp, mat_p, Vector3(0.3, 0.006, 0.17), _paint(Color(0.72, 0.28, 0.24)))
	mat.global_basis = Basis.looking_at(-face, Vector3.UP)
	for k in 3:
		var st := _bit(grp, mat_p + Vector3.UP * 0.002 + face * (-0.05 + k * 0.05), Vector3(0.3, 0.006, 0.018), _paint(Color(0.94, 0.86, 0.66)))
		st.global_basis = Basis.looking_at(-face, Vector3.UP)
	# the picture above it: a framed meadow with a sun
	var pic := base + Vector3.UP * 1.35 - face * 0.02
	var fr := _bit(grp, pic, Vector3(0.5, 0.38, 0.03), _paint(Color(0.5, 0.32, 0.17)))
	fr.global_basis = Basis.looking_at(-face, Vector3.UP)
	var layers := [[Vector3(0, 0, 0.016), Vector3(0.42, 0.3, 0.004), Color(0.74, 0.86, 0.95)],
			[Vector3(0, -0.08, 0.019), Vector3(0.42, 0.14, 0.004), Color(0.5, 0.7, 0.4)],
			[Vector3(0.1, -0.04, 0.021), Vector3(0.16, 0.1, 0.004), Color(0.4, 0.6, 0.36)],
			[Vector3(-0.12, 0.07, 0.022), Vector3(0.06, 0.06, 0.004), Color(0.97, 0.8, 0.3)],
			[Vector3(-0.05, -0.05, 0.023), Vector3(0.07, 0.06, 0.004), Color(0.86, 0.36, 0.28)]]
	for ly in layers:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = ly[1]
		mi.mesh = bm
		mi.material_override = _paint(ly[2])
		fr.add_child(mi)
		mi.position = ly[0]
	for mi in grp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _hide(kind: String, x: float, y: float, w: float, d: float, rot := 0.0) -> void:
	var z := add_zone(HideSpot, "Hide: " + kind, W(x, y), Vector3(w / 100.0, 0.2, d / 100.0), rot) as HideSpot
	z.id = kind


var _worktop := 0.92  # height of the kitchen worktop (m), measured from the first counter section
var _fridge: Node3D   # the kitchen fridge (the bread box lives on it)


## On top of the fridge (cm across its front-to-back depth from the wall), or null without a fridge.
func _on_fridge(x: float, y: float):
	if _fridge == null or not is_instance_valid(_fridge):
		return null
	var p := W(x, y)
	return Vector3(p.x, world_aabb(_fridge).end.y, p.z)


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
		if i == 0 and piece:
			_worktop = world_aabb(piece).end.y
		if i == 6 and piece:
			_sink_water(piece)
	for j in 4:
		apply_texture(furn_piece("furniture/counter_section", 36, 72 + 60 * (j + 0.5), 90.0, "counter", 60, 72), "wood")
	# round 16 (asked): 15 cm out from the wall — a gap behind it to hide in
	# (and 104 cm wide, off the east wall too: the way into the gap behind it is down the side by that wall —
	# the worktop closes the other side)
	var fridge := furn_piece("furniture/fridge", 884, 71, 0.0, "fridge", 104, 110)
	_hide("behind", 890, 15.5, 126, 15)
	_hide("behind", 944.5, 70, 15, 110)
	if fridge:  # the model's box can stick out past 110 cm (the handle): measure where its back really is
		var fb := world_aabb(fridge)
		var back_cm := (fb.position.z - W(0, 0).z) * 100.0
		if back_cm < 24.0:  # (the wall takes the first 7 cm: this leaves her ~17)
			fridge.global_position.z += (24.0 - back_cm) / 100.0
			var bb: Node3D = fridge.get_meta("box_body")
			bb.global_position.z += (24.0 - back_cm) / 100.0
		var fb2 := world_aabb(fridge)
		var east_cm := (W(960, 0).x - fb2.end.x) * 100.0
		if east_cm < 24.0:
			fridge.global_position.x -= (24.0 - east_cm) / 100.0
			var bb2: Node3D = fridge.get_meta("box_body")
			bb2.global_position.x -= (24.0 - east_cm) / 100.0
	_fridge = fridge
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
	_backsplash()
	_kitchen_life(fridge)
	_nest_corner()


## Round 17 (asked: "the corner by the burrow is very empty"): the kitchen's south-west corner, round our hole,
## gets the clutter a real kitchen keeps there — a tall pantry cupboard on the west wall, a big potted plant in
## the corner, the mop and bucket, a crate of empty bottles. The hole itself (x 150…210) stays clear, and a
## piece is left out wherever the night puts food, a find or something to knock over.
func _nest_corner() -> void:
	if OS.get_environment("HIDE").contains("life"):
		return
	var taken: Array = []
	for s in night.get("food", {}).get("spots", []):
		taken.append(Vector2(float(s.x), float(s.y)))
	for key in ["knock", "knockables", "secrets", "props", "noisy"]:
		for k in night.get(key, []):
			if k is Dictionary and k.has("x"):
				taken.append(Vector2(float(k.x), float(k.y)))
	var free := func(x: float, y: float, r: float) -> bool:
		for t in taken:
			if (t as Vector2).distance_to(Vector2(x, y)) < r:
				return false
		return true
	if free.call(30, 455, 60):
		furn_piece("furniture/cabinet_tall", 30, 455, 90.0, "cabinet", 60, 45)
	if free.call(42, 562, 40):
		collide(spawn("furniture/plant", W(42, 562), 0.0, decor))
	if free.call(112, 566, 35):
		collide(spawn("props/bucket_mop", W(112, 566), 25.0, decor))
	if free.call(285, 560, 40):
		var crate := spawn("furniture/crate", W(285, 560), -8.0, decor)
		if crate:
			collide(crate)
			var top := world_aabb(crate).end.y
			for i in 4:
				var bt := spawn("props/bottle", W(272 + (i % 2) * 22, 548 + (i / 2) * 22, top * 100.0 - 18.0), 0.0, decor)
				if bt:
					bt.scale *= 0.8


## A plain painted material for the small things below: the wash over its colour, the pen line round it.
func _paint(color: Color) -> StandardMaterial3D:
	var m := mat(color)
	var w := TextureLib.get_detail("wash", 1.9)
	if not w.is_empty():
		m.albedo_texture = w[0]
		m.albedo_color = TextureLib.detail_colour(color, float(w[1]))
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * (1.0 / 0.5)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _outline == null:
		_outline = _outline_mat(OUTLINE)
	m.next_pass = _outline_mat(OUTLINE * 0.6)
	return m


## A small decorative block: no collision, no shadow of its own to speak of. `tilt` turns it in its own plane
## (degrees, around the axis that points out of a north-facing wall).
func _bit(parent: Node3D, at: Vector3, size: Vector3, m: Material, tilt := 0.0, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = at
	mi.rotation_degrees = Vector3(0, yaw, tilt)
	return mi


func _round(parent: Node3D, at: Vector3, radius: float, height: float, m: Material, face_out := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = at
	if face_out:
		mi.rotation_degrees = Vector3(90, 0, 0)  # the flat side looks into the room from a north or south wall
	return mi


## The things a lived-in kitchen collects (the user: "throw some random things in, so the room comes alive"):
## magnets, notes and a child's drawing on the fridge; a rail of pans and utensils over the worktop; a pot, a
## knife block, a chopping board, a bread box and bottles on it; a runner by the sink, a mat at the door, a
## calendar on the wall. All of it is scenery: nothing here is a task, a noise or an obstacle on the floor.
func _kitchen_life(fridge: Node3D) -> void:
	if OS.get_environment("HIDE").contains("life"):
		return
	var grp := group("Kitchen life")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var steel := _paint(Color(0.62, 0.64, 0.68))
	var dark := _paint(Color(0.2, 0.19, 0.22))
	var wood := _paint(Color(0.62, 0.42, 0.24))
	var paper := _paint(Color(0.93, 0.91, 0.84))

	# --- the fridge door: magnets, two notes, a drawing
	if fridge:
		var fb := world_aabb(fridge)
		var z := fb.end.z + 0.003
		var cx := fb.get_center().x
		var bright := [Color(0.86, 0.22, 0.2), Color(0.96, 0.78, 0.2), Color(0.3, 0.62, 0.32), Color(0.24, 0.42, 0.8), Color(0.93, 0.5, 0.16), Color(0.82, 0.4, 0.62)]
		# the drawing: a sheet with a sun, a house and grass in crayon colours
		var sheet := Vector3(cx - 0.3, 1.5, z)
		_bit(grp, sheet, Vector3(0.21, 0.16, 0.002), paper, -4.0)
		_round(grp, sheet + Vector3(0.06, 0.04, 0.002), 0.022, 0.002, _paint(Color(0.97, 0.8, 0.2)), true)
		_bit(grp, sheet + Vector3(-0.03, -0.01, 0.002), Vector3(0.07, 0.06, 0.002), _paint(Color(0.85, 0.3, 0.25)), -4.0)
		_bit(grp, sheet + Vector3(-0.03, 0.035, 0.0025), Vector3(0.06, 0.06, 0.002), _paint(Color(0.45, 0.3, 0.6)), 41.0)
		_bit(grp, sheet + Vector3(0.0, -0.06, 0.002), Vector3(0.19, 0.025, 0.002), _paint(Color(0.36, 0.66, 0.34)), -4.0)
		_round(grp, sheet + Vector3(0.0, 0.07, 0.006), 0.014, 0.008, _paint(bright[0]), true)
		# a shopping list and a note
		_bit(grp, Vector3(cx + 0.02, 1.58, z), Vector3(0.075, 0.13, 0.002), _paint(Color(0.97, 0.93, 0.6)), 3.0)
		_bit(grp, Vector3(cx + 0.02, 1.635, z + 0.004), Vector3(0.028, 0.028, 0.008), _paint(bright[3]), 3.0)
		_bit(grp, Vector3(cx + 0.22, 1.42, z), Vector3(0.1, 0.1, 0.002), _paint(Color(0.99, 0.72, 0.78)), -7.0)
		_round(grp, Vector3(cx + 0.22, 1.46, z + 0.004), 0.013, 0.008, _paint(bright[2]), true)
		# and a scatter of loose magnets
		for i in 9:
			var at := Vector3(cx + rng.randf_range(-0.42, 0.42), rng.randf_range(1.08, 1.72), z + 0.004)
			var c: Color = bright[i % bright.size()]
			if i % 3 == 0:
				_round(grp, at, rng.randf_range(0.011, 0.017), 0.008, _paint(c), true)
			else:
				_bit(grp, at, Vector3(rng.randf_range(0.022, 0.04), rng.randf_range(0.022, 0.034), 0.008), _paint(c), rng.randf_range(-25.0, 25.0))

	# --- a rail over the worktop, left of the window: a frying pan, a saucepan, a ladle, a spatula, a whisk, a mitt
	var rail_h := 138.0
	_bit(grp, W(205, 3.2, rail_h), Vector3(2.2, 0.014, 0.014), steel)
	for bx in [98.0, 312.0]:
		_bit(grp, W(bx, 1.6, rail_h), Vector3(0.02, 0.03, 0.032), steel)
	var copper := _paint(Color(0.72, 0.4, 0.22))
	# frying pan (its bottom toward the room), hanging by the end of its handle
	_bit(grp, W(125, 3.4, rail_h - 6.5), Vector3(0.022, 0.13, 0.012), dark)
	_round(grp, W(125, 4.2, rail_h - 21.5), 0.09, 0.03, dark, true)
	_round(grp, W(125, 5.8, rail_h - 21.5), 0.074, 0.004, _paint(Color(0.3, 0.29, 0.32)), true)
	# copper saucepan
	_bit(grp, W(160, 3.4, rail_h - 6.0), Vector3(0.02, 0.12, 0.012), dark)
	_round(grp, W(160, 5.5, rail_h - 18.0), 0.062, 0.06, copper, true)
	# ladle
	_bit(grp, W(192, 3.4, rail_h - 10.5), Vector3(0.012, 0.21, 0.008), steel)
	_round(grp, W(192, 4.4, rail_h - 22.5), 0.03, 0.022, steel, true)
	# spatula
	_bit(grp, W(214, 3.4, rail_h - 9.0), Vector3(0.012, 0.18, 0.008), wood)
	_bit(grp, W(214, 3.4, rail_h - 21.5), Vector3(0.05, 0.075, 0.005), dark)
	# whisk
	_bit(grp, W(236, 3.4, rail_h - 6.5), Vector3(0.014, 0.13, 0.012), wood)
	var whisk := MeshInstance3D.new()
	var wm := SphereMesh.new()
	wm.radius = 0.026
	wm.height = 0.11
	wm.radial_segments = 10
	wm.rings = 6
	whisk.mesh = wm
	whisk.material_override = steel
	grp.add_child(whisk)
	whisk.global_position = W(236, 3.6, rail_h - 18.0)
	# an oven mitt and a checked towel
	_bit(grp, W(268, 3.6, rail_h - 9.5), Vector3(0.1, 0.17, 0.02), _paint(Color(0.8, 0.26, 0.22)), 4.0)
	_bit(grp, W(268, 4.7, rail_h - 14.5), Vector3(0.1, 0.03, 0.004), _paint(Color(0.95, 0.9, 0.8)), 4.0)
	_bit(grp, W(298, 3.4, rail_h - 12.0), Vector3(0.11, 0.24, 0.008), _paint(Color(0.93, 0.9, 0.82)))
	for k in 3:
		_bit(grp, W(298, 3.9, rail_h - 5.0 - k * 7.0), Vector3(0.11, 0.022, 0.004), _paint(Color(0.24, 0.42, 0.8)))

	# --- on the worktop, at the back by the tiles (the front two thirds stay clear for her)
	var top := _worktop
	if top > 0.5 and top < 1.2:
		# a chopping board leaning on the tiles
		var board := _bit(grp, Vector3(W(180, 7).x, top + 0.17, W(180, 7).z), Vector3(0.3, 0.36, 0.022), wood)
		board.rotation_degrees = Vector3(-13, 0, 0)
		_bit(grp, Vector3(W(214, 9.5).x, top + 0.13, W(214, 9.5).z), Vector3(0.2, 0.27, 0.016), _paint(Color(0.78, 0.6, 0.38))).rotation_degrees = Vector3(-16, 0, 6)
		# a pot with its lid
		var pot := Vector3(W(400, 16).x, top, W(400, 16).z)
		_round(grp, pot + Vector3(0, 0.06, 0), 0.1, 0.12, _paint(Color(0.82, 0.3, 0.2)))
		_round(grp, pot + Vector3(0, 0.127, 0), 0.105, 0.014, _paint(Color(0.74, 0.26, 0.18)))
		_round(grp, pot + Vector3(0, 0.146, 0), 0.02, 0.024, dark)
		for hx in [-0.115, 0.115]:
			_bit(grp, pot + Vector3(hx, 0.095, 0), Vector3(0.035, 0.014, 0.05), dark)
		var pb := StaticBody3D.new()
		var ps := CollisionShape3D.new()
		var pc := CylinderShape3D.new()
		pc.radius = 0.11
		pc.height = 0.15
		ps.shape = pc
		pb.add_child(ps)
		grp.add_child(pb)
		pb.global_position = pot + Vector3(0, 0.075, 0)
		# a knife block
		var kb := Vector3(W(690, 13).x, top, W(690, 13).z)
		var block := box("Knife block", kb + Vector3(0, 0.1, 0), Vector3(0.1, 0.2, 0.13), wood, grp)
		for k in 4:
			_bit(grp, kb + Vector3(-0.03 + (k % 2) * 0.06, 0.225, -0.03 + (k / 2) * 0.05), Vector3(0.02, 0.06, 0.03), dark)
		# three bottles (oil, vinegar, sauce)
		for k in 3:
			var bot := spawn("props/bottle", Vector3(W(600 + k * 11, 9 + (k % 2) * 3).x, top, W(600, 9 + (k % 2) * 3).z), rng.randf_range(0.0, 360.0), decor)
			collide(bot)

	# --- on the floor and the walls
	var runner := _paint(Color(0.7, 0.24, 0.2))
	_bit(grp, W(483, 110, 0.5), Vector3(1.3, 0.008, 0.55), runner)
	for k in 5:
		_bit(grp, W(483 - 52 + k * 26, 110, 0.75), Vector3(0.05, 0.008, 0.55), _paint(Color(0.93, 0.87, 0.72)))
	_bit(grp, W(905, 320, 0.5), Vector3(0.45, 0.008, 0.75), _paint(Color(0.52, 0.4, 0.28)))
	# a calendar on the east wall, between the fridge and the door
	var cal := W(958.6, 170, 150)
	_bit(grp, cal, Vector3(0.006, 0.42, 0.3), paper)
	_bit(grp, cal + Vector3(-0.002, 0.15, 0), Vector3(0.006, 0.11, 0.3), _paint(Color(0.8, 0.26, 0.22)))
	for r in 4:
		for c in 6:
			if (r * 6 + c) % 5 != 3:
				_bit(grp, cal + Vector3(-0.003, 0.05 - r * 0.055, -0.115 + c * 0.046), Vector3(0.004, 0.03, 0.03), _paint(Color(0.72, 0.74, 0.8)))
	for mi in grp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Tiles on the wall behind the worktops (a kitchen without a backsplash is a room with cupboards): small cream
## tiles from the worktop up to where the wall cabinets hang, stepping down under the window. They catch the
## moon and the light strip under the cabinets.
func _backsplash() -> void:
	var tile := TextureLib.get_detail("ceramic_tile", 0.8)
	if tile.is_empty() or OS.get_environment("HIDE").contains("splash"):
		return
	var m := mat(Color.WHITE)
	m.albedo_texture = tile[0]
	m.albedo_color = TextureLib.detail_colour(Color(0.8, 0.77, 0.68), float(tile[1]))
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * (1.0 / 0.24)  # the scan is 2 × 2 tiles: 12 cm tiles
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.3
	_add_normal(m, "ceramic_tile")
	var grp := group("Backsplash")
	var win: Dictionary = night.get("window", {})
	var wx := float(win.get("x", 0))
	var ww := float(win.get("w", 0))
	var lo := 92.0
	var hi := 142.0
	# north wall, x 0…830 (the fridge stands beyond): full height beside the window, a low strip under it
	var spans := [[0.0, 830.0, hi]]
	if ww > 0.0:
		spans = [[0.0, wx - 28.0, hi], [wx - 28.0, wx + ww + 28.0, 108.0], [wx + ww + 28.0, 830.0, hi]]
	for sp in spans:
		var a: float = sp[0]
		var b: float = sp[1]
		var top: float = sp[2]
		if b - a < 5.0:
			continue
		var t := box("Tiles", W((a + b) / 2.0, 0.7, (lo + top) / 2.0), Vector3((b - a) / 100.0, (top - lo) / 100.0, 0.014), m, grp, false)
		(t as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# west wall, y 0…312
	var wt := box("Tiles", W(0.7, 156, (lo + hi) / 2.0), Vector3(0.014, (hi - lo) / 100.0, 3.12), m, grp, false)
	(wt as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
	# (not on_top(): the colliders built this frame are not in the physics world yet, the ray found nothing, and
	# the kettle and the toaster have been standing on the FLOOR inside the counter, out of sight)
	var ket := spawn("rooms/kettle", Vector3(W(260, 30).x, _worktop, W(260, 30).z), 180.0, decor)
	collide(ket)
	if ket:
		g.kettle_pos = ket.global_position + Vector3.UP * 0.17  # world_fx steams here
	var toast := spawn("furniture/toaster", Vector3(W(340, 28).x, _worktop, W(340, 28).z), 180.0, decor)
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
				# round 16 (asked): on top of the fridge — it used to land on top of the wall cabinets
				var at = _on_fridge(872, 30)
				if at == null:
					at = on_top(float(p.x) + float(p.w) / 2.0, float(p.y) + float(p.h) / 2.0)
				collide(spawn("props/bread_box", at, 0.0, decor))
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
			plate(on_top(680, 432), true)
	var ex: Array = night.get("exit", [])
	if ex.size() >= 2:
		_exit(Nights.pos(ex))
	var cbed := spawn("props/cat_bed", Nights.pos(night.get("catBed")), 0.0, decor)
	# round 16 (asked: "the rat must not walk through the cat bed"): its real shape, rim and hollow, on a layer
	# only the rat collides with — the navigation mesh (layer 1) must keep the bed open, the cat walks into it
	if cbed:
		for mi in cbed.find_children("*", "MeshInstance3D", true, false):
			var mm := mi as MeshInstance3D
			if mm.mesh == null:
				continue
			var body := StaticBody3D.new()
			body.collision_layer = 8
			body.collision_mask = 0
			body.set_meta("surface", "cat_bed")
			var cs := CollisionShape3D.new()
			cs.shape = mm.mesh.create_trimesh_shape()
			body.add_child(cs)
			mm.add_child(body)
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


## A floor lamp (round 16, asked: "the floor lamp in the corner looks silly — make a normal one"): a weighted
## brass foot, a slim pole with a joint, a pleated drum shade of cream linen. `lit`: the shade glows from inside.
func floor_lamp(at: Vector3, lit := false) -> Node3D:
	var root_n := Node3D.new()
	root_n.name = "Floor lamp"
	(furn if furn else root).add_child(root_n)
	root_n.global_position = at
	var brass := _paint(Color(0.66, 0.5, 0.24))
	var dark := _paint(Color(0.24, 0.2, 0.17))
	var linen := _paint(Color(0.94, 0.86, 0.68))
	if lit:
		linen.emission_enabled = true
		linen.emission = Color(1.0, 0.78, 0.46)
		linen.emission_energy_multiplier = 0.9
	var parts := [  # radius top, radius bottom, height, y of centre, material
		[0.13, 0.15, 0.03, 0.015, dark],
		[0.05, 0.08, 0.025, 0.042, brass],
		[0.011, 0.011, 1.2, 0.65, brass],
		[0.02, 0.02, 0.04, 0.8, dark],
		[0.03, 0.012, 0.05, 1.27, brass],
		[0.15, 0.2, 0.27, 1.42, linen],
	]
	for pr in parts:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = pr[0]
		cm.bottom_radius = pr[1]
		cm.height = pr[2]
		cm.radial_segments = 20 if pr[0] > 0.05 else 10
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = pr[4]
		root_n.add_child(mi)
		mi.position = Vector3.UP * pr[3]
	# pleats: thin darker ribs down the shade, and a trim at its top and bottom
	var rib := _paint(Color(0.82, 0.72, 0.54))
	for k in 16:
		var a := k * TAU / 16.0
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.008, 0.27, 0.004)
		r.mesh = bm
		r.material_override = rib
		root_n.add_child(r)
		r.position = Vector3(sin(a) * 0.176, 1.42, cos(a) * 0.176)
		r.rotation = Vector3(0, a, 0)
		r.rotate_object_local(Vector3.RIGHT, -atan2(0.05, 0.27))
	for t in [[0.2, 1.285], [0.15, 1.555]]:
		var ti := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = t[0] - 0.006
		tm.outer_radius = t[0] + 0.006
		tm.rings = 24
		tm.ring_segments = 6
		ti.mesh = tm
		ti.material_override = brass
		root_n.add_child(ti)
		ti.position = Vector3.UP * t[1]
	for mi in root_n.get_children():
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.15
	cy.height = 0.05
	cs.shape = cy
	body.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cy2 := CylinderShape3D.new()
	cy2.radius = 0.02
	cy2.height = 1.3
	cs2.shape = cy2
	cs2.position = Vector3.UP * 0.65
	body.add_child(cs2)
	root_n.add_child(body)
	body.position = Vector3.UP * 0.025
	return root_n


## A plate (round 16, asked: "plates look silly, as if flush with the table"). The model was a flat disc 1 cm
## thick; this one has a foot, a well and a raised rim, so it stands on the table and holds what is on it.
func plate(at: Vector3, solid := false) -> Node3D:
	var root_n := Node3D.new()
	root_n.name = "Plate"
	decor.add_child(root_n)
	root_n.global_position = at
	var china := _paint(Color(0.95, 0.94, 0.9))
	var band := _paint(Color(0.36, 0.52, 0.76))
	var parts := [[0.06, 0.007, 0.0035, china], [0.1, 0.006, 0.009, china]]
	for pr in parts:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = pr[0]
		cm.bottom_radius = pr[0] * 0.92
		cm.height = pr[1]
		cm.radial_segments = 24
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = pr[3]
		root_n.add_child(mi)
		mi.position = Vector3.UP * pr[2]
	for r in [[0.104, 0.122, china, 0.016], [0.112, 0.119, band, 0.0215]]:
		var ti := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r[0]
		tm.outer_radius = r[1]
		tm.rings = 28
		tm.ring_segments = 8
		ti.mesh = tm
		ti.material_override = r[2]
		ti.scale = Vector3(1.0, 0.55, 1.0)
		root_n.add_child(ti)
		ti.position = Vector3.UP * r[3]
	for mi in root_n.get_children():
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.12
		cy.height = 0.024
		cs.shape = cy
		body.add_child(cs)
		root_n.add_child(body)
		body.position = Vector3.UP * 0.012
	return root_n


func _food() -> void:
	var fd: Dictionary = night.get("food", {})
	for s in fd.get("spots", []):
		var at := W(float(s.x), float(s.y)) if bool(s.get("floor", false)) else on_top(float(s.x), float(s.y))
		if str(s.get("tag", "")) == "bread" and _on_fridge(925, 34) != null:
			at = _on_fridge(925, 34)  # the cheese hidden by the bread box goes where the bread box is
		if bool(s.get("plate", false)):
			# round 12 (asked): some food is SERVED — a plate under it, and the food
			# sits in the plate rather than on the bare surface beneath
			plate(at)
			at += Vector3.UP * 0.014
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
	# (round 16: the sides and the roof start BEHIND the kitchen wall — they used to poke 5 cm through it, a dark
	# brown frame on the wallpaper round the mouse hole: the user's "strange stripes")
	box("Side", W(5, 697, 50), Vector3(0.1, 1.0, 1.76), earth, nest)
	box("Side", W(255, 697, 50), Vector3(0.1, 1.0, 1.76), earth, nest)
	var roof := box("Roof", W(130, 697, 95), Vector3(2.6, 0.1, 1.76), earth, nest)
	var heap := spawn("rooms/nest", W(90, 725), 0.0, nest)
	collide(heap)
	apply_texture(heap, "wood", Color.WHITE, 0.85)  # the twigs get a grain (the paper scraps stay plain)
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
	light.light_energy = 1.0   # (1.5 + the fill turned the brown twigs orange and her coat white: a burrow is dim)
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
	fillc.light_energy = 0.45
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
	NestDecor.build_all(self, nest)
	g.decor_parent = nest
