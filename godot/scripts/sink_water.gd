class_name SinkWater
extends Zone
## Water in the kitchen sink. A rat that falls or jumps in swims (slowly) and must climb out over the edge
## (Space facing the side) before she runs out of breath; if she doesn't, it counts as being caught.

var level := 0.0   # world height of the water surface
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0
var _swimmer: Rat
var _stir := 0.0  # 0…1: rings spreading from her while she swims

## Dark water that moves: slow crossing swells, thin bright crests where they meet (the window is right above
## the sink, so it is the moon they catch), a pale line along the basin's walls, and rings around a swimmer.
const WATER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
uniform vec2 swimmer = vec2(0.0);
uniform float stir = 0.0;
varying vec2 at;
void vertex() { at = VERTEX.xz; }
void fragment() {
	vec2 p = at * 100.0;  // cm
	float w = sin(p.x * 0.42 + TIME * 1.3) + sin(p.y * 0.5 - TIME * 1.05) + sin((p.x + p.y) * 0.3 + TIME * 0.8);
	float d = length(at - swimmer);
	float rings = sin(d * 150.0 - TIME * 9.0) * exp(-d * 9.0) * stir;
	w += rings * 2.5;
	float crest = smoothstep(1.7, 2.7, w);
	vec2 e = min(UV, 1.0 - UV);
	float edge = 1.0 - smoothstep(0.0, 0.07, min(e.x, e.y));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(vec3(0.04, 0.12, 0.24), vec3(0.14, 0.34, 0.52), clamp(0.3 + w * 0.09 + fres * 0.5, 0.0, 1.0));
	col += vec3(0.7, 0.82, 1.0) * (crest * 0.5 + edge * 0.22 + max(rings, 0.0) * 0.5);
	ALBEDO = col;
	ALPHA = clamp(0.74 + edge * 0.2 + crest * 0.2, 0.0, 1.0);
}
"""


func setup(surface_y: float) -> void:
	level = surface_y
	_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	_mesh.mesh = pm
	var sh := Shader.new()
	sh.code = WATER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_mesh.global_position = Vector3(global_position.x, level, global_position.z)


func _process(dt: float) -> void:
	_t += dt
	if _mesh:
		_mesh.global_position.y = level + sin(_t * 2.0) * 0.0015  # a gentle lap
		var swimming := _swimmer != null and is_instance_valid(_swimmer) and _swimmer.water == self
		_stir = move_toward(_stir, 1.0 if swimming else 0.0, dt * (3.0 if swimming else 0.6))
		if swimming:
			var l := _mesh.to_local(_swimmer.global_position)
			_mat.set_shader_parameter("swimmer", Vector2(l.x, l.z))
		_mat.set_shader_parameter("stir", _stir)


func stay(rat: Rat, _dt: float) -> void:
	_swimmer = rat
	if rat.water == null and not rat.jumping and rat.global_position.y < level + 0.02:
		rat.start_swim(self)
