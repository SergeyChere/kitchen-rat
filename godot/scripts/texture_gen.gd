class_name TextureGen
extends RefCounted
## Round 6: the material textures, painted IN GDScript at runtime — the user has no
## Python on his machine and will not install it, so tools/make_textures.py can no
## longer be the way textures arrive. Same brief as the Python generator (round 4):
## the It Takes Two lesson — big readable painted shapes, a plank you can COUNT, a
## tile that swells, a weave you can see — not photographic noise. Textures are
## generated once and cached by TextureLib (user://gen_textures); real CDN textures
## (TextureLib) always win over these. Deterministic: same seeds, same pictures.

const S := 256

## All paintable material names (the shaft gradient is separate: make("shaft")).
const NAMES := ["wood", "wood_dark", "ceramic_tile", "fabric", "leather",
	"metal_matte", "cardboard", "plastic", "counter_stone", "cheese"]


static func make(tex_name: String) -> Texture2D:
	var img := make_image(tex_name)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## The painting itself, texture-free — safe to call from TextureLib's background
## thread (no RenderingServer work happens until a texture is created from it).
static func make_image(tex_name: String) -> Image:
	var img: Image
	match tex_name:
		"wood": img = _wood(11, Color(0.485, 0.345, 0.185), Color(0.36, 0.24, 0.12))
		"wood_dark": img = _wood(23, Color(0.30, 0.20, 0.115), Color(0.21, 0.135, 0.07))
		"ceramic_tile": img = _ceramic()
		"fabric": img = _fabric()
		"leather": img = _leather()
		"metal_matte": img = _metal()
		"cardboard": img = _cardboard()
		"plastic": img = _plastic()
		"counter_stone": img = _stone()
		"cheese": img = _cheese()
		"cheese_normal": img = _cheese_normal()
		"shaft": img = _shaft()
		_: return null
	if img == null:
		return null
	img.generate_mipmaps()
	return img


## Generate every material into files under `dir` (used by TextureLib's background
## thread, so the first night does not pay for painting). Skips files that exist.
static func make_all_files(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for n in NAMES + ["shaft"]:
		var p: String = dir + "/" + str(n) + ".png"
		if FileAccess.file_exists(p) or FileAccess.file_exists("user://textures/" + str(n) + ".png"):
			continue
		var img := make_image(str(n))
		if img != null:
			img.save_png(p + ".tmp")
			DirAccess.rename_absolute(p + ".tmp", p)


# ---------------------------------------------------------------- noise (tileable)

static func _h2(x: int, y: int, seed: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + seed * 974634239) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 1023) / 1023.0


static func _vn(u: float, v: float, per: int, seed: int) -> float:
	var x := u * per
	var y := v * per
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - xi
	var yf := y - yi
	var sx := xf * xf * (3.0 - 2.0 * xf)
	var sy := yf * yf * (3.0 - 2.0 * yf)
	var a := _h2(wrapi(xi, 0, per), wrapi(yi, 0, per), seed)
	var b := _h2(wrapi(xi + 1, 0, per), wrapi(yi, 0, per), seed)
	var c := _h2(wrapi(xi, 0, per), wrapi(yi + 1, 0, per), seed)
	var d := _h2(wrapi(xi + 1, 0, per), wrapi(yi + 1, 0, per), seed)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


## A tileable fbm field over the whole texture (precomputed once per material).
static func _field(per: int, seed: int, octaves := 3) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(S * S)
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			var s := 0.0
			var amp := 0.5
			var p := per
			for o in octaves:
				s += amp * _vn(u, v, p, seed + o * 131)
				amp *= 0.5
				p *= 2
			f[y * S + x] = s / 0.875
	return f


static func _img(data: PackedByteArray) -> Image:
	return Image.create_from_data(S, S, false, Image.FORMAT_RGBA8, data)


static func _put(data: PackedByteArray, x: int, y: int, c: Color) -> void:
	var i := (y * S + x) * 4
	data[i] = int(clampf(c.r, 0.0, 1.0) * 255.0)
	data[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
	data[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
	data[i + 3] = int(clampf(c.a, 0.0, 1.0) * 255.0)


static func _wdist(x: float, y: float, cx: float, cy: float) -> float:
	var dx := absf(x - cx)
	dx = minf(dx, 1.0 - dx)
	var dy := absf(y - cy)
	dy = minf(dy, 1.0 - dy)
	return sqrt(dx * dx + dy * dy)


# ---------------------------------------------------------------- the materials

static func _wood(seed: int, base: Color, dark: Color) -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(4, seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919
	var knots: Array = []
	for i in 3:
		knots.append(Vector2(rng.randf(), rng.randf()))
	var planks := 4
	var ph := S / planks
	for y in S:
		var v := float(y) / S
		var plank := mini(y / ph, planks - 1)
		var lv := float(y - plank * ph) / ph
		var tone := 0.9 + 0.22 * _h2(plank, 7, seed)
		var phase := _h2(plank, 13, seed) * 6.0
		for x in S:
			var u := float(x) / S
			var fv := f[y * S + x]
			# wavy growth rings inside the plank (7 per plank, warped by the field)
			var ring := 0.5 + 0.5 * sin((lv * 7.0 + fv * 1.6 + phase) * TAU)
			var c := base.lerp(dark, 0.25 + 0.5 * ring * ring) * (tone * (0.92 + 0.16 * fv))
			# knots: dark rings around a darker heart
			for k in knots:
				var d := _wdist(u, v, k.x, k.y)
				if d < 0.085:
					var kr := 0.5 + 0.5 * sin(d * 130.0 - fv * 5.0)
					c = c.lerp(dark * 0.55, (1.0 - d / 0.085) * (0.35 + 0.4 * kr))
			# the seam between planks: a dark line, a lit bevel under it, nails
			var edge := mini(y - plank * ph, (plank + 1) * ph - 1 - y)
			if edge == 0:
				c *= 0.45
			elif edge == 1:
				c *= 1.18
			if (y - plank * ph) == 6 and (absi(x - 12) <= 1 or absi(x - S + 13) <= 1):
				c = Color(0.16, 0.15, 0.16)
			_put(data, x, y, c)
	return _img(data)


static func _ceramic() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(6, 41)
	var base := Color(0.52, 0.60, 0.58)
	var half := S / 2
	for y in S:
		var ly := float(y % half) / half
		for x in S:
			var lx := float(x % half) / half
			var ex := minf(lx, 1.0 - lx)
			var ey := minf(ly, 1.0 - ly)
			var e := minf(ex, ey) * 2.0  # 0 at the grout line, 1 at the tile centre
			var fv := f[y * S + x]
			var c: Color
			if e < 0.055:
				c = Color(0.23, 0.22, 0.20)
			else:
				var bump := sin(PI * clampf(e * 1.15, 0.0, 1.0))
				c = base * (0.8 + 0.3 * bump) * (0.93 + 0.13 * fv)
			_put(data, x, y, c)
	return _img(data)


static func _fabric() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(5, 53)
	var base := Color(0.44, 0.40, 0.36)
	var threads := 20
	for y in S:
		var ty := y * threads / S
		var slub := 1.0 + (0.10 if _h2(ty, 3, 53) > 0.78 else 0.0)
		for x in S:
			var tx := x * threads / S
			var over := (tx + ty) % 2 == 0
			var c := base * ((1.05 if over else 0.95) * slub) * (0.94 + 0.11 * f[y * S + x])
			_put(data, x, y, c)
	return _img(data)


static func _leather() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(16, 67, 2)
	var base := Color(0.36, 0.22, 0.13)
	for y in S:
		for x in S:
			var fv := f[y * S + x]
			var crease := clampf(1.0 - absf(fv - 0.52) * 7.0, 0.0, 1.0)
			var c := base * (0.9 + 0.2 * fv) * (1.0 - 0.28 * crease)
			if _h2(x, y, 71) > 0.985:
				c *= 0.8
			_put(data, x, y, c)
	return _img(data)


static func _metal() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(6, 83)
	var base := Color(0.42, 0.44, 0.47)
	for y in S:
		for x in S:
			var brush := 0.94 + 0.10 * _h2(x >> 1, 5, 89)
			var c := base * brush * (0.94 + 0.11 * f[y * S + x])
			_put(data, x, y, c)
	return _img(data)


static func _cardboard() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(4, 97)
	var base := Color(0.62, 0.50, 0.34)
	var rng := RandomNumberGenerator.new()
	rng.seed = 97 * 31
	var stains: Array = []
	for i in 2:
		stains.append(Vector2(rng.randf(), rng.randf()))
	for y in S:
		var v := float(y) / S
		for x in S:
			var u := float(x) / S
			var c := base * (0.92 + 0.15 * f[y * S + x]) * (1.0 + 0.03 * sin(u * TAU * 32.0))
			for st in stains:
				var d := _wdist(u, v, st.x, st.y)
				if d < 0.16:
					c *= 1.0 - 0.16 * (1.0 - d / 0.16)
			_put(data, x, y, c)
	return _img(data)


static func _plastic() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(4, 103)
	var base := Color(0.55, 0.57, 0.60)
	for y in S:
		for x in S:
			var c := base * (0.96 + 0.07 * f[y * S + x])
			if _h2(x, y, 107) > 0.992:
				c *= 1.1
			_put(data, x, y, c)
	return _img(data)


static func _stone() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var f := _field(5, 113)
	var fleck := _field(48, 127, 1)
	var base := Color(0.40, 0.41, 0.44)
	for y in S:
		for x in S:
			var c := base * (0.93 + 0.13 * f[y * S + x])
			var fl := fleck[y * S + x]
			if fl > 0.86:
				c = c.lerp(Color(0.78, 0.74, 0.66), 0.7)
			elif fl < 0.14:
				c *= 0.72
			_put(data, x, y, c)
	return _img(data)


## The moon shaft's soft gradient: fades along its length and toward its side edges.
static func _shaft() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	for y in S:
		var v := float(y) / S
		var a := pow(1.0 - v, 1.6)
		for x in S:
			var u := float(x) / S
			var edge := 0.25 + 0.75 * pow(sin(PI * u), 1.2)
			_put(data, x, y, Color(0.78, 0.84, 1.0, a * edge))
	return _img(data)


## Round 12 (asked): the cheese. The GLB's flat yellow read as plastic; this is a
## painted cheese — a warm marbled rind and real HOLES, darker and shadowed at
## their hearts. The hole list is shared with the normal map, so the dips the
## light catches are the same holes the eye sees. Wrap-aware: it tiles.
static func _cheese_holes() -> Array:
	var holes: Array = []
	for i in 11:
		var r := 0.045 + 0.05 * _h2(i, 11, 139)
		holes.append([_h2(i, 3, 131), _h2(i, 7, 137), r, r * (0.68 + 0.3 * _h2(i, 13, 149))])
	return holes


## How deep the surface dips at (u, v): 0 on the rind, 1 at a hole's heart.
static func _cheese_dip(u: float, v: float, holes: Array) -> float:
	var dip := 0.0
	for h in holes:
		var dx := absf(u - float(h[0]))
		dx = minf(dx, 1.0 - dx)
		var dy := absf(v - float(h[1]))
		dy = minf(dy, 1.0 - dy)
		var rx := float(h[2])
		var ry := float(h[3])
		var d := sqrt(dx * dx / (rx * rx) + dy * dy / (ry * ry))
		if d < 1.0:
			var s := 1.0 - d
			dip = maxf(dip, s * s * (3.0 - 2.0 * s))
	return dip


static func _cheese() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var holes := _cheese_holes()
	var f := _field(6, 151)
	var base := Color(0.97, 0.74, 0.27)
	var deep := Color(0.70, 0.42, 0.09)
	for y in S:
		for x in S:
			var c := base * (0.93 + 0.13 * f[y * S + x])
			var dip := _cheese_dip(float(x) / S, float(y) / S, holes)
			if dip > 0.0:
				c = c.lerp(deep, dip * 0.85)
				c *= 1.0 - 0.25 * dip  # a hole's heart sits in its own shadow
			_put(data, x, y, c)
	return _img(data)


static func _cheese_normal() -> Image:
	var data := PackedByteArray()
	data.resize(S * S * 4)
	var holes := _cheese_holes()
	var e := 1.5 / S
	for y in S:
		for x in S:
			var u := float(x) / S
			var v := float(y) / S
			# the surface height is the NEGATIVE dip, so the normal tilts along
			# the dip's own gradient, into the hole
			var gx := _cheese_dip(u + e, v, holes) - _cheese_dip(u - e, v, holes)
			var gy := _cheese_dip(u, v + e, holes) - _cheese_dip(u, v - e, holes)
			var n := Vector3(gx * 1.6, gy * 1.6, 1.0).normalized()
			_put(data, x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return _img(data)
