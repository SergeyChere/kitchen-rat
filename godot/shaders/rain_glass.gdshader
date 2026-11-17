// Rain on the window glass (storm nights only): the pane keeps its faint cool sheen, and
// streaks of drops run down it in three layers at different speeds, plus a few beads that
// sit and tremble. Applied to the wall_window model's own glass (level_builder.gd _wall),
// so it fits the panes exactly and the frame occludes it like real glass.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 sheen : source_color = vec4(0.6, 0.72, 0.95, 0.12);
uniform vec4 drop_tint : source_color = vec4(0.78, 0.86, 1.0, 1.0);
uniform float strength = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	// the glass's UVs are rotated (measured from wall_window.glb): U runs UP the pane and
	// V runs ACROSS it, and U spans only ~0.25 over the pane's full height — so the axes
	// are swapped here, and the vertical frequency is scaled up to match.
	vec2 uv = vec2(UV.y, UV.x);
	float streaks = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		// a column of drops, falling: the pattern scrolls toward DECREASING U (down the
		// pane), so time is ADDED — with a minus the rain ran up the glass
		vec2 g = vec2(uv.x * (52.0 + fi * 30.0), uv.y * (14.0 + fi * 8.0) + TIME * (2.0 + fi * 0.9));
		vec2 id = floor(g);
		float h = hash(id + fi * 17.0);
		vec2 f = fract(g);
		float drop = step(0.72, h);
		drop *= smoothstep(0.0, 0.1, f.y) * (1.0 - smoothstep(0.1, 0.5, f.y));  // bright head, fading tail
		drop *= 1.0 - smoothstep(0.06, 0.22, abs(f.x - 0.5));  // a thin column
		streaks += drop * (0.4 + 0.6 * h);
	}
	streaks = clamp(streaks, 0.0, 1.0) * strength;
	// beads: small bright dots that sit on the glass (roughly square cells on the pane)
	vec2 b = vec2(uv.x * 70.0, uv.y * 170.0);
	vec2 bid = floor(b);
	float bh = hash(bid + 3.1);
	vec2 bf = fract(b) - 0.5;
	float beads = step(0.94, bh) * smoothstep(0.3, 0.08, length(bf));
	float lit = clamp(streaks * 0.85 + beads * 0.7, 0.0, 1.0);
	ALBEDO = mix(sheen.rgb, drop_tint.rgb, lit);
	ALPHA = sheen.a + lit * 0.55;
}
