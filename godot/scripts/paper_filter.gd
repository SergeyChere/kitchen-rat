class_name PaperFilter
extends CanvasLayer
## The whole picture as a painting on paper (round 14, the watercolour look). One pass over the finished 3D
## frame, under the HUD and the menus:
##  · flat areas melt into an even wash (the specks of the fur, the banding of a gradient), edges stay crisp
##  · pigment pools along every edge — a darker line where two colours meet
##  · the tooth of the paper shows through, more in the dark colours (granulation)
##  · the hand wobbles: straight edges are not quite straight
##  · paper white warms the lights; the corners fall off a little (the old film vignette lives here now)
## Off on quality low; HIDE=paper to compare.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D paper : filter_linear, repeat_enable;
uniform float strength = 1.0;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 puv = SCREEN_UV / px / 512.0;   // the sheet: one texel per pixel
	float grain = texture(paper, puv).r;
	vec2 w = vec2(texture(paper, puv * 0.09 + vec2(0.37, 0.11)).r, texture(paper, puv * 0.09 + vec2(0.71, 0.53)).r) - 0.5;
	vec2 uv = SCREEN_UV + w * px * 7.0 * strength;
	float r = 1.4;
	vec3 c00 = texture(screen_tex, uv + vec2(-r, -r) * px).rgb;
	vec3 c10 = texture(screen_tex, uv + vec2(0.0, -r) * px).rgb;
	vec3 c20 = texture(screen_tex, uv + vec2(r, -r) * px).rgb;
	vec3 c01 = texture(screen_tex, uv + vec2(-r, 0.0) * px).rgb;
	vec3 c11 = texture(screen_tex, uv).rgb;
	vec3 c21 = texture(screen_tex, uv + vec2(r, 0.0) * px).rgb;
	vec3 c02 = texture(screen_tex, uv + vec2(-r, r) * px).rgb;
	vec3 c12 = texture(screen_tex, uv + vec2(0.0, r) * px).rgb;
	vec3 c22 = texture(screen_tex, uv + vec2(r, r) * px).rgb;
	vec3 mean = (c00 + c10 + c20 + c01 + c11 + c21 + c02 + c12 + c22) / 9.0;
	float gx = (lum(c20) + 2.0 * lum(c21) + lum(c22)) - (lum(c00) + 2.0 * lum(c01) + lum(c02));
	float gy = (lum(c02) + 2.0 * lum(c12) + lum(c22)) - (lum(c00) + 2.0 * lum(c10) + lum(c20));
	float edge = clamp(length(vec2(gx, gy)) * 1.6, 0.0, 1.0);
	vec3 col = mix(mean, c11, smoothstep(0.1, 0.4, edge));
	col *= 1.0 - 0.3 * edge * strength;
	float l = lum(col);
	col *= 1.0 + (grain - 0.5) * 2.0 * mix(0.24, 0.1, clamp(l * 1.4, 0.0, 1.0)) * strength;
	col = mix(vec3(lum(col)), col, 0.93);
	col *= mix(vec3(1.0), vec3(1.035, 1.0, 0.93), clamp(l * 1.3, 0.0, 1.0) * strength);
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - 0.16 * smoothstep(0.5, 1.05, length(v * vec2(1.4, 1.0)));
	COLOR = vec4(col, 1.0);
}
"""


static func wanted() -> bool:
	return Settings.quality != "low" and not OS.get_environment("HIDE").contains("paper")


func _ready() -> void:
	name = "Paper"
	layer = -1  # over the 3D picture, under the menu (0) and the HUD (10)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("paper", TextureLib.get_texture("paper", false))
	rect.material = m
	add_child(rect)
