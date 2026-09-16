shader_type spatial;
render_mode unshaded;

group_uniforms Color;
uniform vec3 primary_color : source_color = vec3(1.0, 0.8, 0.2);
uniform vec3 secondary_color : source_color = vec3(1.0, 0.4, 0.1);
uniform vec3 tertiary_color : source_color = vec3(0.6, 0.1, 0.05);
uniform float emission = 2.0;
uniform float color_curve = 1.0;
uniform float hue_variation = 0.1;
uniform bool use_secondary = false;

group_uniforms Shape;
uniform sampler2D noise_texture;
uniform vec2 noise_scale = vec2(0.5);
uniform vec2 noise_scroll = vec2(0.0, 0.1);
uniform float shape_curve = 2.0;
uniform float noise_twist : hint_range(-1.0, 1.0, 0.05) = 0.0;
uniform float waviness : hint_range(0.0, 1.0, 0.01) = 0.2;

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool proximity_fade = false;
uniform float proximity_fade_distance : hint_range(0.0, 4096.0, 0.01);
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

vec3 shift_hue(vec3 color, float shift) {
	vec3 gray = vec3(0.57735);
	vec3 projection = gray * dot(gray, color.rgb);
	vec3 U = color.rgb - projection;
	vec3 V = cross(gray, U);
	vec3 shifted = U * cos(shift * 2.0 * PI) + V * sin(shift * 2.0 * PI) + projection;
	return shifted;
}

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Elliptical flame / aura shape from center
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	
	// Flame / column vertical tapering: wider at base, tapered at top
	float taper = mix(1.2, 0.7, clamp(UV.y, 0.0, 1.0));
	float dist_mask = clamp(1.0 - (r / taper), 0.0, 1.0);
	
	vec2 noise_uv = (vec2(UV.x + UV.y * noise_twist, UV.y) + COLOR.r) * noise_scale + (noise_scroll * TIME);
	
	float wave = sin(UV.y * 16.0 + TIME * 8.0);
	noise_uv.x += wave * 0.1 * waviness;
	
	float noise = texture(noise_texture, noise_uv).r;
	
	// Flame noise shaping: subtract distance from center smoothly rather than raw noise - r
	float value = pow(clamp((noise * 1.2 - 0.2) * dist_mask, 0.0, 1.0), shape_curve) * COLOR.a;
	
	float color_value = pow(value, color_curve);
	color_value = mix(color_value, floor(color_value * 6.0) / 5.0, edge_hardness);
	vec3 main_color = use_secondary ? secondary_color : primary_color;
	vec3 color = mix(tertiary_color, main_color, color_value);
	color = shift_hue(color, (COLOR.r - 0.5) * hue_variation) * (0.5 + COLOR.r * 0.5);
	
	ALBEDO = color * emission;
	ALPHA = value;
	
	if (proximity_fade) {
		float proximity_depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 ndc = OUTPUT_IS_SRGB ? vec4(vec3(SCREEN_UV, proximity_depth_tex) * 2.0 - 1.0, 1.0) : vec4(SCREEN_UV * 2.0 - 1.0, proximity_depth_tex, 1.0);
		vec4 proximity_view_pos = INV_PROJECTION_MATRIX * ndc;
		proximity_view_pos.xyz /= proximity_view_pos.w;
		ALPHA *= clamp(1.0 - smoothstep(proximity_view_pos.z + proximity_fade_distance, proximity_view_pos.z, VERTEX.z), 0.0, 1.0);
	}
	
	ALPHA = clamp((ALPHA - edge_position) / (1.0 - edge_hardness), 0.0, 1.0);
}