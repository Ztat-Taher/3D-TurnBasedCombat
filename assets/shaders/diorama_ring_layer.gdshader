shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;

// Surface Detail Maps
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(0.0, 3.0) = 1.0;
uniform bool use_normal_map = false;

uniform sampler2D specular_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float specular_strength : hint_range(0.0, 2.0) = 0.5;
uniform bool use_specular_map = false;

uniform sampler2D ambient_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float ambient_strength : hint_range(0.0, 2.0) = 1.0;
uniform bool use_ambient_map = false;

uniform sampler2D displacement_texture : hint_default_black, filter_linear_mipmap_anisotropic;
uniform float displacement_scale : hint_range(0.0, 0.1) = 0.025;
uniform float displacement_min_layers : hint_range(4.0, 32.0) = 8.0;
uniform float displacement_max_layers : hint_range(8.0, 64.0) = 24.0;
uniform bool use_displacement_map = false;

// Tiling and alignment
uniform float horizontal_repeats : hint_range(0.5, 8.0) = 1.0;
uniform float rotation_offset_uv : hint_range(0.0, 1.0) = 0.0;
// uv_top / uv_bottom are baked into mesh UV.y — no shader offset needed

// Camera-reactive panoramic parallax (seam-safe: operates in angular space)
// Controls how much horizontal parallax shift occurs as camera yaws
uniform float camera_yaw_parallax : hint_range(0.0, 0.5) = 0.04;
// Controls vertical parallax/tilt as camera pitches
uniform float camera_pitch_parallax : hint_range(0.0, 0.3) = 0.02;
// Overall zoom: scale the texture inward/outward uniformly
uniform float camera_zoom_scale : hint_range(0.5, 2.0) = 1.0;
// FOV-reactive barrel/pincushion correction (subtle)
uniform float fov_warp : hint_range(0.0, 0.5) = 0.05;

// Vibrance & lighting
uniform float emission_energy : hint_range(0.0, 4.0) = 1.5;
uniform float color_saturation : hint_range(0.0, 2.5) = 1.25;
uniform vec4 modulate_color : source_color = vec4(1.0);

// Edge fading
// UV.y = 0.0 is the top pole/rim, UV.y = 1.0 is the bottom pole/rim
uniform float top_fade_margin : hint_range(0.0, 0.5) = 0.08;
uniform float bottom_fade_margin : hint_range(0.0, 0.5) = 0.0;

// Chromatic aberration
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_vertex_dir;
varying float v_equator_prox;  // 1.0 at equator, 0.0 at top/bottom poles (from UV2.y)

vec3 adjust_saturation(vec3 rgb, float sat) {
	float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(luma), rgb, sat);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vertex_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);
	// UV2.y holds equator proximity baked by DioramaRingMesh (1=equator, 0=pole)
	v_equator_prox = UV2.y;
}

void fragment() {
	// ---------------------------------------------------------------
	// CONTINUOUS SPHERICAL / ANGULAR MAPPING
	// UV.x from the mesh is u_ratio (0.0 to 1.0 around the circle).
	// But in fragment shaders, performing fract() or non-linear warps
	// per-pixel across the boundary between u=1.0 and u=0.0 splits the quad
	// and creates seam tearing / ghost copies.
	// We calculate the vertex horizontal angle around the dome center directly,
	// keeping it continuous across the seam using fwidth / gradient compensation.
	// ---------------------------------------------------------------

	// Sphere azimuth of the vertex in world space:
	// In diorama_ring_mesh: x = sin(lon) * r, z = cos(lon) * r
	// So atan(x, z) gives exactly the azimuth angle [ -PI .. +PI ]
	float vert_azimuth = atan(v_world_pos.x, v_world_pos.z); // -PI .. PI
	float u_angle = (vert_azimuth / TAU) + 0.5; // continuous 0.0 .. 1.0 around dome

	// Camera look direction in world space
	vec3 cam_fwd = -VIEW_MATRIX[2].xyz;
	float cam_yaw = atan(cam_fwd.x, cam_fwd.z); // -PI .. PI
	float cam_pitch = asin(clamp(cam_fwd.y, -1.0, 1.0));

	// Angular delta between vertex direction from camera and camera look direction
	float delta_yaw = atan(v_vertex_dir.x, v_vertex_dir.z) - cam_yaw;
	delta_yaw = mod(delta_yaw + PI, TAU) - PI; // wrap to [-PI, PI]

	float vert_pitch = asin(clamp(v_vertex_dir.y, -1.0, 1.0));
	float delta_pitch = vert_pitch - cam_pitch;

	// Base continuous U before wrap
	float base_u = u_angle * horizontal_repeats + rotation_offset_uv;
	float base_v = UV.y;

	// Center-relative coordinates for perspective/parallax/zoom warp
	// We shift relative to the camera's current viewing azimuth to avoid placing the
	// non-linear warp boundary directly inside the camera's viewport
	float parallax_u = (delta_yaw / PI) * camera_yaw_parallax;
	float parallax_v = (delta_pitch / (PI * 0.5)) * camera_pitch_parallax;

	// Compute sample coordinates
	float u = base_u - parallax_u;
	float v = base_v - parallax_v;

	// Optional zoom from equator center
	float zoom_inv = 1.0 / max(camera_zoom_scale, 0.01);
	v = mix(0.5, v, zoom_inv);

	// Compute screen-space derivatives of raw unwrapped UV to avoid mipmap & filtering explosion at wrap
	vec2 uv_raw = vec2(u, v);
	vec2 dx = dFdx(uv_raw);
	vec2 dy = dFdy(uv_raw);

	// Filter out the wrap-around derivative spike across the 0/1 boundary
	dx.x = dx.x - round(dx.x);
	dy.x = dy.x - round(dy.x);

	vec2 final_uv = vec2(fract(u), clamp(v, 0.0, 1.0));

	// Parallax Occlusion Mapping (POM)
	// Traces a view ray through the height field to find true surface self-occlusion
	// instead of simple 1-sample offsetting (which creates ghost double edges).
	if (use_displacement_map && displacement_scale > 0.0001) {
		// Tangent space view direction:
		// T is horizontal around dome (+U), B is vertical (+V), N is surface normal inward
		vec3 N = normalize(NORMAL);
		vec3 T = normalize(TANGENT);
		vec3 B = normalize(BINORMAL);
		mat3 tbn = mat3(T, B, N);

		// Transform world-space view direction (-v_vertex_dir) into tangent space
		vec3 view_dir_world = normalize(-v_vertex_dir);
		vec3 view_dir_tan = vec3(
			dot(view_dir_world, T),
			dot(view_dir_world, B),
			dot(view_dir_world, N)
		);
		// Force view ray to look toward the surface interior (+Z into height layers)
		if (view_dir_tan.z < 0.0) {
			view_dir_tan.z = -view_dir_tan.z;
		}
		view_dir_tan = normalize(view_dir_tan);

		// Grazing angle step adaptation: more steps at steep viewing angles
		float cos_theta = clamp(abs(view_dir_tan.z), 0.05, 1.0);
		float num_layers = mix(displacement_max_layers, displacement_min_layers, cos_theta);
		float layer_depth = 1.0 / num_layers;
		float current_layer_depth = 0.0;

		// At extreme grazing angles, tan.xy / tan.z approaches infinity, causing texture stretching/mush.
		// We clamp the maximum step offset and gracefully dampen the displacement at steep grazing angles
		// to maintain sharp silhouettes and prevent extreme edge bleeding.
		float grazing_dampen = smoothstep(0.0, 0.35, cos_theta);
		vec2 p_delta = (view_dir_tan.xy / max(cos_theta, 0.35)) * displacement_scale * grazing_dampen;
		// Clamp maximum parallax vector so rays cannot shoot across the screen
		float max_p = displacement_scale * 1.5;
		if (length(p_delta) > max_p) {
			p_delta = normalize(p_delta) * max_p;
		}
		vec2 delta_uv = p_delta / num_layers;

		vec2 current_uv = final_uv;
		float current_depth_map_value = 1.0 - textureGrad(displacement_texture, current_uv, dx, dy).r;

		vec2 prev_uv = current_uv;
		float prev_depth_map_value = current_depth_map_value;
		float prev_layer_depth = 0.0;

		// Raymarch through displacement slices
		int max_iter = int(displacement_max_layers);
		for (int i = 0; i < max_iter; i++) {
			if (float(i) >= num_layers) break;
			if (current_layer_depth >= current_depth_map_value) break;

			prev_uv = current_uv;
			prev_layer_depth = current_layer_depth;
			prev_depth_map_value = current_depth_map_value;

			current_uv.x = fract(current_uv.x + delta_uv.x);
			current_uv.y = clamp(current_uv.y - delta_uv.y, 0.0, 1.0);
			current_layer_depth += layer_depth;
			current_depth_map_value = 1.0 - textureGrad(displacement_texture, current_uv, dx, dy).r;
		}

		// Linear interpolation between the two slices before and after collision
		float after_depth  = current_depth_map_value - current_layer_depth;
		float before_depth = prev_depth_map_value - prev_layer_depth;
		float denom = after_depth - before_depth;
		float weight = 0.0;
		if (abs(denom) > 0.0001) {
			weight = clamp(after_depth / denom, 0.0, 1.0);
		}
		final_uv = mix(current_uv, prev_uv, weight);
		final_uv.x = fract(final_uv.x);
		final_uv.y = clamp(final_uv.y, 0.0, 1.0);
	}

	// Sample with optional chromatic aberration
	vec4 tex_color;
	if (chromatic_aberration > 0.0001) {
		float ca = (delta_yaw / PI) * chromatic_aberration;
		float r = textureGrad(albedo_texture, vec2(fract(final_uv.x + ca), final_uv.y), dx, dy).r;
		float g = textureGrad(albedo_texture, final_uv, dx, dy).g;
		float b = textureGrad(albedo_texture, vec2(fract(final_uv.x - ca), final_uv.y), dx, dy).b;
		tex_color = vec4(r, g, b, textureGrad(albedo_texture, final_uv, dx, dy).a);
	} else {
		tex_color = textureGrad(albedo_texture, final_uv, dx, dy);
	}

	// Color grading & base emission
	vec3 vivid = adjust_saturation(tex_color.rgb, color_saturation) * modulate_color.rgb * emission_energy;

	// Ambient occlusion map
	if (use_ambient_map) {
		float ao = textureGrad(ambient_texture, final_uv, dx, dy).r;
		// Blend AO into diffuse color based on ambient_strength
		vivid *= mix(1.0, ao, ambient_strength);
	}

	// Surface normal & specular response
	// Calculate pseudo-light / camera specular highlight based on normal perturbation
	vec3 surface_normal = NORMAL;
	if (use_normal_map) {
		vec3 n_tex = textureGrad(normal_texture, final_uv, dx, dy).rgb * 2.0 - 1.0;
		n_tex.xy *= normal_scale;
		// Construct TBN in fragment
		vec3 N = normalize(NORMAL);
		vec3 T = normalize(TANGENT);
		vec3 B = normalize(BINORMAL);
		mat3 tbn = mat3(T, B, N);
		surface_normal = normalize(tbn * n_tex);

		// Diffuse light enhancement from camera direction
		vec3 view_dir = normalize(-v_vertex_dir);
		float n_dot_v = max(dot(surface_normal, view_dir), 0.0);
		// Subtle 3D relief shading modulation
		vivid *= mix(0.7, 1.15, n_dot_v);
	}

	// Specular highlight / gloss
	if (use_specular_map) {
		vec3 spec_sample = textureGrad(specular_texture, final_uv, dx, dy).rgb;
		float spec_val = dot(spec_sample, vec3(0.299, 0.587, 0.114));

		vec3 view_dir = normalize(-v_vertex_dir);
		// Directional highlight simulating light source
		vec3 light_dir = normalize(cam_fwd + vec3(0.0, 0.4, 0.0));
		vec3 half_vector = normalize(light_dir + view_dir);
		float n_dot_h = max(dot(surface_normal, half_vector), 0.0);
		float specular_highlight = pow(n_dot_h, 16.0) * spec_val * specular_strength;

		vivid += vec3(specular_highlight) * modulate_color.rgb;
	}

	// Edge fading using baked equator proximity (UV2.y):
	//   v_equator_prox = 1.0 at equator, 0.0 at top AND bottom poles.
	//   top_fade_margin fades inward from the top pole (equator_prox → 0 going up).
	//   bottom_fade_margin fades inward from the bottom pole (equator_prox → 0 going down).
	//   UV.y < 0.5 = top hemisphere, UV.y > 0.5 = bottom hemisphere.
	float fade = 1.0;
	if (top_fade_margin > 0.001) {
		// Only apply to top hemisphere (UV.y <= 0.5)
		float top_mask = 1.0 - clamp((UV.y - 0.0) * 2.0, 0.0, 1.0);
		// equator_prox near 0 = at the top pole, near 1 = equator
		float top_fade = smoothstep(0.0, top_fade_margin, v_equator_prox);
		fade *= mix(1.0, top_fade, top_mask);
	}
	if (bottom_fade_margin > 0.001) {
		// Only apply to bottom hemisphere (UV.y >= 0.5)
		float bot_mask = clamp((UV.y - 0.5) * 2.0, 0.0, 1.0);
		float bot_fade = smoothstep(0.0, bottom_fade_margin, v_equator_prox);
		fade *= mix(1.0, bot_fade, bot_mask);
	}

	ALBEDO = vivid;
	ALPHA = tex_color.a * modulate_color.a * fade;
}
