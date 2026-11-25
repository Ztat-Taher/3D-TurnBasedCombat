shader_type spatial;
// Pillar of light for chest openings, PS2-style: a flat column (QuadMesh) that
// turns around its Y axis to face the camera, with hard posterized bands across
// its width, a white-hot core, stepped stripes marching up and choppy timing.
// The column is pushed `push_back` units away from the camera (horizontally),
// so whatever floats on its axis (the item) is always drawn in front of it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform vec4 beam_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float intensity = 1.0;
// Mesh height in local units, used to normalize the vertical fade
uniform float beam_height = 2.0;
// 0..1: how much of the beam is "grown" from the bottom (animate for the shoot-up)
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float band_speed = 1.2;
uniform float band_count = 6.0;
// Brightness levels across the width (fewer = chunkier bands)
uniform float posterize_steps = 3.0;
// Animation frame rate (lower = choppier)
uniform float anim_fps = 12.0;
// Bottom width relative to the top
uniform float taper = 0.75;
// How far behind its axis (away from the camera) the column is drawn
uniform float push_back = 0.15;

varying float height01;
varying float across;

void vertex() {
	height01 = VERTEX.y / beam_height + 0.5;
	across = UV.x * 2.0 - 1.0;

	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	float width_scale = length(MODEL_MATRIX[0].xyz);
	float height_scale = length(MODEL_MATRIX[1].xyz);

	// Face the camera around the beam's own up axis
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	to_cam -= up * dot(to_cam, up);
	vec3 toward = normalize(to_cam);
	vec3 right = normalize(cross(up, toward));

	float half_w = VERTEX.x * width_scale * mix(taper, 1.0, clamp(height01, 0.0, 1.0));
	vec3 world = origin + right * half_w + up * VERTEX.y * height_scale - toward * push_back;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(toward, 0.0)).xyz;
}

void fragment() {
	float t = floor(TIME * anim_fps) / anim_fps;

	// Hard bands from the edges (dim) to the core (bright)
	float level = 1.0 - abs(across);
	level = ceil(level * posterize_steps) / posterize_steps;
	float core = step(0.8, 1.0 - abs(across));

	// Stepped fade toward the top, hard cut at the bottom
	float top_fade = ceil((1.0 - smoothstep(0.25, 1.0, height01)) * 4.0) / 4.0;
	float base_cut = step(0.0, height01);

	// Hard stripes of light marching up the beam
	float stripe = step(0.5, fract(height01 * band_count - t * band_speed));
	float bands = 0.7 + 0.3 * stripe;

	// Grow from the bottom while revealing (hard edge)
	float grown = step(height01, reveal);

	float a = level * top_fade * base_cut * bands * grown * intensity;
	ALBEDO = mix(beam_color.rgb, vec3(1.0), core * 0.55) * a;
}
