class_name Dof
extends MeshInstance3D
## Depth of field, the "macro lens" look: what is far behind the rat goes soft, so she reads as small and the
## house as huge (It Takes Two shoots its tiny heroes the same way). The Compatibility renderer has no built-in
## depth of field, so this is a full-screen quad in front of the camera that redraws the far part of the frame
## blurred. It is drawn before every other transparent thing (light shafts, water, ground shadows), which then
## draw over it as usual. Sharp pixels are not touched at all.
##
## Settings → "Depth of field"; off at Low quality and in the rat's-eye view.

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, blend_mix;
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float focus = 0.8;      // m from the lens to the rat
uniform float far_start = 1.1;  // m behind her where the blur begins
uniform float far_len = 3.6;    // m over which it grows to full
uniform float max_px = 5.5;     // blur radius at full strength, in pixels of a 1080p frame

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float dist_at(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

float blur_at(vec2 uv, mat4 inv_proj) {
	return smoothstep(far_start, far_start + far_len, dist_at(uv, inv_proj) - focus);
}

void fragment() {
	float c0 = blur_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	if (c0 < 0.02) {
		discard;
	}
	vec2 px = vec2(1.0) / VIEWPORT_SIZE;
	float rad = c0 * max_px * VIEWPORT_SIZE.y / 1080.0;
	vec3 acc = texture(screen, SCREEN_UV).rgb * (0.2 + c0);
	float wsum = 0.2 + c0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 2.39996;
		float r = sqrt((float(i) + 0.5) / 12.0);
		vec2 uv = SCREEN_UV + vec2(cos(a), sin(a)) * r * rad * px;
		// a tap that lands on something sharp (the rat, the near floor) counts for little: no halo of her
		// colours smeared into the soft background
		float w = 0.05 + blur_at(uv, INV_PROJECTION_MATRIX);
		acc += texture(screen, uv).rgb * w;
		wsum += w;
	}
	ALBEDO = acc / wsum;
	ALPHA = smoothstep(0.02, 0.3, c0);
}
"""

var mat: ShaderMaterial


func _init() -> void:
	name = "Depth of field"
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mesh = q
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = -100  # before every other transparent surface
	material_override = mat
	extra_cull_margin = 16000.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Called by the camera every frame: `focus` is the distance to the rat; `on` hides it (first person, Low…).
func tick(focus: float, on: bool) -> void:
	visible = on and Settings.dof and Settings.quality != "low" and not OS.get_environment("HIDE").contains("dof")
	if visible:
		mat.set_shader_parameter("focus", focus)
