// The moonlight the window throws into the room, with the shadows of the tree's leaves outside (window_sky.gd)
// drifting through it in the wind; the clouds dim it all. A box round the beam draws it: for every pixel the
// box covers it finds the point of the room behind (from the depth buffer), follows the moon's ray back to the
// window wall and, if that ray came in through the glass, adds light — so the patch falls on whatever is
// there: the floor, the island's top, a chair, the rat herself.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float strength = 0.22;  // how much the panes brighten what they fall on
uniform vec4 shade : source_color = vec4(0.04, 0.06, 0.15, 1.0);
uniform float shade_strength = 0.5;  // how dark the leaves and the frame are
uniform float cloud = 1.0;
uniform float wind = 1.0;
uniform vec3 sdir = vec3(-0.204, -0.616, 0.761);  // where the moonlight goes
uniform float wall_z = -2.98;                       // the window's plane
uniform vec2 win_min = vec2(0.0, 1.12);             // the glass: left edge (x) and sill (y)…
uniform vec2 win_size = vec2(1.0, 1.06);            // …and its width and height

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 wp = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	// back along the ray to the window wall
	float back = (wp.z - wall_z) / sdir.z;
	vec3 q = wp - sdir * back;
	vec2 uv = (q.xy - win_min) / win_size;  // x across the glass, y from the sill up
	float inside = step(0.0, back) * step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float edge = smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x) * smoothstep(0.0, 0.05, uv.y) * smoothstep(1.0, 0.95, uv.y);
	float bars = max(1.0 - smoothstep(0.012, 0.03, abs(uv.x - 0.5)), 1.0 - smoothstep(0.012, 0.03, abs(uv.y - 0.5)));
	// the leaves: blobs of noise, swaying together (the boughs) and fluttering a little (the leaves)
	float t = TIME;
	vec2 sway = vec2(sin(t * 0.7) * 0.07 + sin(t * 1.9) * 0.025, sin(t * 0.55 + 1.3) * 0.035) * wind * 2.2;
	vec2 p = uv * vec2(3.2, 3.0) + sway + vec2(sin(t * 4.7 + uv.y * 9.0), cos(t * 5.1 + uv.x * 7.0)) * 0.012 * wind;
	float n = noise(p * 1.7) * 0.6 + noise(p * 4.3 + 3.1) * 0.4;
	// the crown fills the top of the window, more on one side
	float crown = smoothstep(0.2, 0.8, uv.y) * (0.55 + 0.45 * smoothstep(0.1, 0.9, uv.x));
	float leaves = smoothstep(0.42, 0.62, n) * crown;
	// surfaces turned away from the moon get none (the sides of things)
	vec3 nrm = normalize(cross(dFdx(wp), dFdy(wp)));
	float lambert = clamp(abs(dot(nrm, -sdir)) * 1.3, 0.0, 1.0);
	// drawn over the room (not added: on a white worktop added light would not show): the panes a cool wash,
	// the leaves and the frame's cross darker patches in it
	float dark = max(leaves * 0.9, bars * 0.75);
	float k = smoothstep(0.05, 0.6, dark);
	ALBEDO = mix(tint.rgb, shade.rgb, k);
	ALPHA = inside * edge * lambert * cloud * mix(strength, shade_strength, k);
}
