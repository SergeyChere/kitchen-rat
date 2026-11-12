class_name ContactShadow
extends MeshInstance3D
## A soft dark patch on the ground right under a character. Away from the moon patch nothing in the room casts
## a real shadow, and a character without one floats over the floor instead of standing on it. The patch finds
## the surface below (floor, rug, table top), fades and spreads as she leaves the ground, and is gone when she
## is hidden or away.

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
uniform vec2 inner = vec2(0.03, 0.06);
uniform vec2 quad = vec2(0.2, 0.26);
uniform float feather = 0.07;
uniform float strength = 0.5;
void fragment() {
	vec2 p = (UV - 0.5) * quad;
	float d = length(p / (inner + vec2(feather))) ;   // 0 at the centre … 1 at the rim of the patch
	float a = 1.0 - smoothstep(0.3, 1.0, d);
	ALBEDO = vec3(0.012, 0.016, 0.05);
	ALPHA = a * strength;
}
"""
static var _shader: Shader

var target: Node3D
var base := 0.5
var _mat: ShaderMaterial


static func attach(t: Node3D, half: Vector2, feather: float, strength: float) -> ContactShadow:
	if t == null or OS.get_environment("HIDE").contains("blob"):
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var s := ContactShadow.new()
	s.name = "Contact shadow"
	s.target = t
	s.base = strength
	var full := (half + Vector2(feather, feather)) * 2.0
	var pm := PlaneMesh.new()
	pm.size = full
	s.mesh = pm
	s._mat = ShaderMaterial.new()
	s._mat.shader = _shader
	s._mat.set_shader_parameter("inner", half)
	s._mat.set_shader_parameter("quad", full)
	s._mat.set_shader_parameter("feather", feather)
	s._mat.render_priority = -1
	s.material_override = s._mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.top_level = true
	t.add_child(s)
	return s


func _process(_dt: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	var on := target.is_visible_in_tree()
	if on and target.has_method("in_room"):
		on = target.call("in_room")
	if not on:
		visible = false
		return
	var from := target.global_position + Vector3.UP * 0.06
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.1, 1)
	if target is CollisionObject3D:
		q.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
		visible = false
		return
	visible = true
	var h := maxf(target.global_position.y - (hit.position as Vector3).y, 0.0)
	var k := clampf(1.0 - h / 0.45, 0.0, 1.0)
	global_position = (hit.position as Vector3) + Vector3.UP * 0.006
	global_rotation = Vector3(0, target.global_rotation.y, 0)
	scale = Vector3.ONE * lerpf(1.3, 1.0, k)
	_mat.set_shader_parameter("strength", base * k * k)
