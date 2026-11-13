// The tree outside the window (window_sky.gd): a dark moonlit silhouette that sways in the wind. COLOR.r is how
// far a vertex sways (none at the root), COLOR.g the phase of its leaf clump, COLOR.b marks leaves (they also
// flutter), COLOR.a a little per-vertex shade. The shadow pass runs vertex() too, so the shadow on the floor moves.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 bark : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform vec4 leaf : source_color = vec4(0.07, 0.11, 0.15, 1.0);
uniform vec4 rim : source_color = vec4(0.22, 0.3, 0.42, 1.0);
uniform float wind = 1.0;

void vertex() {
	float f = COLOR.r * COLOR.r;
	float ph = COLOR.g * 6.2832;
	float t = TIME;
	vec3 sway = vec3(sin(t * 0.7 + ph * 0.3) * 0.07 + sin(t * 1.9 + ph) * 0.025, 0.0,
		sin(t * 0.55 + 1.3 + ph * 0.2) * 0.035) * f;
	sway.y = -abs(sway.x) * 0.3;
	sway += vec3(sin(t * 5.1 + ph * 3.0), sin(t * 4.3 + ph * 5.0), cos(t * 4.7 + ph * 2.0)) * 0.014 * COLOR.b * COLOR.r;
	VERTEX += sway * wind;
}

void fragment() {
	vec3 c = mix(bark.rgb, leaf.rgb, COLOR.b) * (0.8 + 0.35 * COLOR.a);
	// the moon is behind and to the right of the tree: a cool rim on the leaves that face it
	float facing = clamp(dot(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), normalize(vec3(0.4, 0.5, -0.6))), 0.0, 1.0);
	ALBEDO = mix(c, rim.rgb, facing * facing * 0.5 * COLOR.b);
}
