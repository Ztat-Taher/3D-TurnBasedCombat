shader_type spatial;
// Low-poly god-rays: meant for a mesh of flat triangle spikes in the XY plane
// (built by ChestRarityVFX). Vertex color .r marks the hot center (1) vs the
// spike tips (0).
// - Billboards toward the camera and keeps the node's scale, so it can be
//   parented to the item and grow with it.
// - Pushed slightly away from the camera so it always sits BEHIND the item.
// - Spins in choppy steps and is posterized for a PS2 feel.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec4 ray_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float spin_speed = 0.6;
uniform float anim_fps = 12.0;
uniform float posterize_steps = 3.0;
// How far behind the item (in view-space units) the rays are drawn
uniform float push_back = 0.05;

varying float heat;

void vertex() {
	float t = floor(TIME * anim_fps) / anim_fps;
	float a = t * spin_speed;
	vec2 v = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;

	vec2 node_scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 center_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	// Push back along the camera ray through the item (not straight down the view
	// axis), so the rays stay centered on it on screen; grow by the same factor so
	// their on-screen size doesn't shrink
	float dist = max(length(center_view), 0.001);
	float grow = (dist + push_back) / dist;
	VERTEX = center_view * grow + vec3(v * node_scale * grow, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	heat = COLOR.r;
}

void fragment() {
	float level = floor(heat * posterize_steps + 0.5) / posterize_steps;
	float a = (0.35 + 0.65 * level) * intensity;
	ALBEDO = mix(ray_color.rgb, vec3(1.0), step(0.99, level) * 0.5) * a;
}
