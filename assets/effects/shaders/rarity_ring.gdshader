shader_type spatial;
// Low-poly shockwave on the ground (put on a flat PlaneMesh).
// A hard-edged polygon (default 12 sides) that grows outward in choppy steps.
// Animate `progress` 0 -> 1.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float sides = 12.0;
// Growth steps across the whole expansion (lower = choppier)
uniform float progress_steps = 10.0;
// Ring thickness at the start and end (in UV radius units)
uniform float start_width = 0.16;
uniform float end_width = 0.03;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	// Distance to the center measured as a regular polygon instead of a circle
	float seg = 6.2831853 / sides;
	float ang = atan(p.y, p.x);
	float poly_dist = length(p) * cos(seg * 0.5) / cos(mod(ang, seg) - seg * 0.5);

	float prog = floor(progress * progress_steps + 0.5) / progress_steps;
	float width = mix(start_width, end_width, prog);
	float ring = step(abs(poly_dist - prog), width * 0.5);
	// Flat inner flash that only lasts for the first steps
	float fill = step(poly_dist, prog) * step(prog, 0.35) * 0.4;
	float fade = floor((1.0 - prog) * 3.0 + 0.999) / 3.0;
	ALBEDO = ring_color.rgb * (ring + fill) * fade * intensity;
}
