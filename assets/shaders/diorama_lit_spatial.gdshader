shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_map = true;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
uniform float light_influence : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform vec4 ambient_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool is_cutout = true;

void fragment() {
	vec4 albedo_sample = texture(albedo_texture, UV);

	if (is_cutout && albedo_sample.a < alpha_scissor_threshold) {
		discard;
	}

	ALBEDO = albedo_sample.rgb * ambient_tint.rgb;

	if (use_normal_map) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	ROUGHNESS = roughness_val;
	SPECULAR = 0.1;

	// Balance baked painted art with real-time scene lighting:
	// Unlit portion stays vivid via emission, lit portion catches directional light & spell flashes
	EMISSION = albedo_sample.rgb * ambient_tint.rgb * (1.0 - light_influence);
}
