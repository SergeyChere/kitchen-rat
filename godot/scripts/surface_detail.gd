class_name SurfaceDetail
extends RefCounted
## Gives the flat-coloured furniture and props a surface: wood grain, painted fronts, stone, fabric, brushed metal,
## cardboard. The grayscale detail textures (tools/textures/make_detail.py) multiply the material's own colour and are
## mapped triplanar in world space, so the Blender models need no UVs and the colours stay as they were designed.
## Which surface a material gets is decided by the model's name and the material's colour.

const TEX := {
	"wood": ["res://assets/textures/detail_wood.png", 1.3, 0.885],
	"paint": ["res://assets/textures/detail_paint.png", 2.0, 0.961],
	"stone": ["res://assets/textures/detail_stone.png", 2.5, 0.926],
	"fabric": ["res://assets/textures/detail_fabric.png", 3.5, 0.901],
	"metal": ["res://assets/textures/detail_metal.png", 2.0, 0.93],
	"cardboard": ["res://assets/textures/detail_cardboard.png", 3.0, 0.91],
}
const FABRIC := ["curtain", "tablecloth", "cat_bed", "sofa", "armchair", "rug", "cushion", "pillow", "towel", "blanket", "bed", "laundry", "couch", "nest", "mattress"]
const METAL := ["fridge", "kettle", "toaster", "sink", "pot", "pan", "oven", "stove", "washer", "washing", "can", "radiator", "microwave", "trash"]
const CARDBOARD := ["cardboard", "box_", "crate_card"]
const SKIP := ["wall_art", "art_", "picture", "poster", "foil", "glass", "bulb", "lamp_shade", "chandelier", "clock", "window", "mirror", "tv", "screen", "plate", "mug", "jar", "bottle", "crumb", "cheese", "apple", "bread_", "sausage", "orange", "banana", "food", "trap", "crack", "mousehole", "hole"]

var _cache := {}
var _tex := {}


func apply(root: Node) -> int:
	var n := 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		n += _mesh(m as MeshInstance3D)
	return n


func _mesh(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	var names := ""
	var p: Node = mi
	for i in 6:
		if p == null:
			break
		if p is Skeleton3D or p is Food or p is Rat:
			return 0  # characters and food keep their look
		names += str(p.name).to_lower() + " "
		p = p.get_parent()
	for s in SKIP:
		if names.contains(s):
			return 0
	var done := 0
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i) as StandardMaterial3D
		if src == null or src.albedo_texture != null or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var kind := _kind(names, src.albedo_color)
		if kind == "":
			continue
		var key := str(src.get_instance_id()) + kind
		if not _cache.has(key):
			_cache[key] = _detailed(src, kind)
		mi.set_surface_override_material(i, _cache[key])
		done += 1
	return done


func _kind(names: String, c: Color) -> String:
	if c.v < 0.12:
		return ""  # handles, shadows, gaps
	for s in FABRIC:
		if names.contains(s):
			return "fabric"
	for s in CARDBOARD:
		if names.contains(s):
			return "cardboard"
	var warm_brown := c.h > 0.025 and c.h < 0.13 and c.s > 0.28 and c.v < 0.82
	if warm_brown:
		return "wood"
	for s in METAL:
		if names.contains(s):
			return "metal" if c.s < 0.25 else "paint"
	if names.contains("counter") and c.s < 0.3 and c.v > 0.6:
		return "paint"
	if c.s < 0.35 and c.v > 0.55:
		return "paint"
	if c.s >= 0.35:
		return "paint"  # coloured fronts and seats: painted
	return ""


func _detailed(src: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	var d: Array = TEX[kind]
	var m := src.duplicate() as StandardMaterial3D
	if not _tex.has(kind):
		_tex[kind] = load(d[0])
	m.albedo_texture = _tex[kind]
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * float(d[1])
	var k := 1.0 / float(d[2])  # keep the average colour as designed
	var c := src.albedo_color
	m.albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)
	if kind == "metal":
		m.metallic = maxf(src.metallic, 0.35)
		m.roughness = minf(src.roughness, 0.45)
	elif kind == "fabric":
		m.roughness = 1.0
	return m
