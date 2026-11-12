class_name Food
extends Node3D
## Food the rat picks up by walking over it, or a find (secret) that sets a flag. Like the prototype: a crumb weighs 1
## and is worth 1, a cheese weighs 2 and is worth 5, big food (sausage, chicken…) weighs 3, is worth 6 and is dragged.

const BIG := ["sausage", "chicken", "pizza", "cake", "potato", "fat", "biscuit", "salami"]
## Round 5: no crumbs — she collects PIECES of real food. "crumb" in night data is remapped to
## one of these at spawn (see game.spawn_food): a cheese wedge, a pizza slice, a rusk chunk.
const LIGHT := ["crumb", "wedge", "slice", "chunk"]
const PIECES := ["wedge", "slice", "chunk"]

var type := "crumb"
var wscale := 1.0  # world scale for this type (set at spawn; small food used to be unreadable)
var id := ""
var hidden := false
var poison := false
var is_find := false
var label := ""
var carried := false
var reveal_t := 0.0


func big() -> bool: return BIG.has(type)
func is_cheese() -> bool: return not is_find and type != "crumb"
func weight() -> int: return 0 if is_find else (3 if big() else (1 if LIGHT.has(type) else 2))
func value() -> int: return 0 if (is_find or poison) else (6 if big() else (1 if type == "crumb" else (2 if LIGHT.has(type) else 5)))


## Floor presence per type: pieces and small foods sit bigger than life so they READ as food.
static func world_scale(t: String) -> float:
	match t:
		"wedge": return 0.62
		"slice": return 0.55
		"chunk": return 0.85
		"crumb": return 0.9
	if BIG.has(t):
		return 1.12
	return 1.22


func make_poison() -> void:
	poison = true
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D:
				var c := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				c.albedo_color = c.albedo_color.lerp(Settings.poison_color(), 0.65)
				m.set_surface_override_material(i, c)


## Fling this food sideways off whatever it was on: an arc to a floor point 0.35–0.55 m to the
## side, so a dropped sausage never wedges at a table's base (round 5, playtest: it stuck there).
func toss_scatter() -> void:
	var from := global_position
	var side := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var at := from + side * randf_range(0.35, 0.55)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 3.0)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	set_meta("dropped_at", at)
	var tw := create_tween()
	tw.tween_method(func(t: float): global_position = from.lerp(at, t) + Vector3.UP * sin(t * PI) * 0.16, 0.0, 1.0, 0.38)
	tw.tween_callback(func(): rotation = Vector3(0, randf() * TAU, 0))


## Every few seconds a small four-pointed glint pops on a piece of food that lies waiting: it catches the
## eye from across the room the way a collectible should, without an arrow or an icon over it.
const GLINT := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform float a = 0.0;
void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = abs(UV - 0.5) * 2.0;
	float star = max(0.0, 1.0 - (sqrt(p.x) + sqrt(p.y)));
	float core = max(0.0, 1.0 - length(p) * 3.0);
	ALBEDO = vec3(1.0, 0.94, 0.72) * (star * 2.2 + core) * a;
}
"""
static var _glint_shader: Shader
var _glint: MeshInstance3D
var _glint_mat: ShaderMaterial
var _glint_wait := 0.0
var _glint_t := -1.0
static var _glint_hold := OS.get_environment("GLINT") == "hold"


func _tick_glint(dt: float) -> void:
	var on := visible and not carried and not hidden and not poison
	if not on:
		if _glint:
			_glint.visible = false
		_glint_t = -1.0
		return
	if _glint_t < 0.0:
		if _glint_wait <= 0.0:
			_glint_wait = randf_range(1.5, 5.0)
		_glint_wait -= dt
		if _glint_wait > 0.0 and not _glint_hold:
			return
		if _glint == null:
			if _glint_shader == null:
				_glint_shader = Shader.new()
				_glint_shader.code = GLINT
			_glint_mat = ShaderMaterial.new()
			_glint_mat.shader = _glint_shader
			_glint = MeshInstance3D.new()
			_glint.name = "Glint"
			var q := QuadMesh.new()
			q.size = Vector2(0.075, 0.075)
			_glint.mesh = q
			_glint.material_override = _glint_mat
			_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_glint.top_level = true
			add_child(_glint)
		_glint_t = 0.0
		_glint.global_position = global_position + Vector3(randf_range(-0.012, 0.012), randf_range(0.03, 0.05), randf_range(-0.012, 0.012))
		_glint.visible = true
	_glint_t += dt
	var k := _glint_t / 0.6
	if _glint_hold:  # dev: GLINT=hold keeps every glint lit, for a screenshot
		k = 0.5
	if k >= 1.0:
		_glint_t = -1.0
		_glint.visible = false
		return
	_glint_mat.set_shader_parameter("a", sin(k * PI))
	_glint.scale = Vector3.ONE * (0.55 + 0.45 * sin(k * PI))


func _process(dt: float) -> void:
	if reveal_t > 0.0:
		reveal_t -= dt
	if not carried and visible:
		rotate_y(0.5 * dt)
	_tick_glint(dt)


static func model_for(t: String) -> String:
	match t:
		"wedge": return "food/cheese"
		"slice": return "food/pizza_slice"
		"chunk": return "food/rusk"
		"crumb": return "food/rusk"
		"sausage", "salami": return "food/sausage"
		"chicken": return "food/chicken_leg"
		"pizza": return "food/pizza_slice"
		"cake": return "food/cake_slice"
		"potato": return "food/potato"
		"fat": return "food/lard"
		"biscuit", "treat": return "food/dog_biscuit"
		"cookie": return "food/cookie"
		"kibble": return "food/kibble"
		"rusk": return "food/rusk"
	return "food/cheese"
