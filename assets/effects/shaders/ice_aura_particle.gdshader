// Ice Aura Particle Shader
// Atmospheric icy vapor effect with wispy smoke texture

shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

uniform vec4 Color : source_color = vec4(0.8, 0.9, 1.0, 0.85);
uniform sampler2D Ice_Texture : source_color;
uniform float Emission = 2.0;
uniform float Scale = 1.0;
uniform float ScrollSpeed = 0.2;
uniform float RotationSpeed = 0.1;
uniform float NoiseScale = 1.0;
uniform float Frostiness = 0.5;
uniform float Softness = 0.5;

varying float v_random;
varying float v_age;
varying vec2 v_uv;
varying float v_size_factor;

void vertex() {
	// Generate random value based on instance ID
	v_random = float(INSTANCE_ID % 1000) / 1000.0;
	
	// Get particle age if available
	v_age = INSTANCE_CUSTOM.y;
	
	// Calculate size factor - larger particles rotate slower
	// Using INSTANCE_CUSTOM.x which contains scale information
	float particle_scale = INSTANCE_CUSTOM.x;
	v_size_factor = 1.0 / (1.0 + particle_scale * 1.0);
	
	// Pass UV to fragment
	v_uv = UV;
}

void fragment() {
	// Centered UV coordinates (-1.0 to 1.0)
	vec2 centered_uv = UV * 2.0 - 1.0;
	
	// Calculate distance from center for circular particle boundary
	float dist = length(centered_uv);
	
	// Soft circular fade for wispy vapor edges with more gradual falloff
	float quad_fade = smoothstep(1.0, 0.2, dist);
	
	// Add noise distortion to edges to break up straight lines
	float edge_noise = sin(centered_uv.x * 15.0 + v_random * 6.28 + TIME * 0.5) * 
	                   sin(centered_uv.y * 15.0 + v_random * 6.28 + TIME * 0.3) * 0.15;
	quad_fade *= (1.0 + edge_noise);
	
	// Slower, more atmospheric scrolling
	vec2 scroll_offset = vec2(v_random * 5.0, v_random * 3.0) + (TIME * ScrollSpeed * 0.5);
	
	// Gentle rotation for vapor drift - scaled by particle size
	float rot = TIME * RotationSpeed * 0.5 * v_size_factor + v_random * 3.14;
	mat2 rot_mat = mat2(vec2(cos(rot), -sin(rot)), vec2(sin(rot), cos(rot)));
	vec2 rotated_uv = rot_mat * centered_uv;
	
	// Add more noise distortion to UVs to break up patterns
	vec2 uv_noise = vec2(
		sin(rotated_uv.y * 8.0 + v_random * 6.28) * 0.1,
		cos(rotated_uv.x * 8.0 + v_random * 6.28) * 0.1
	);
	rotated_uv += uv_noise * Softness;
	
	// Combine for wispy, layered vapor effect
	vec2 final_uv = (rotated_uv * 0.5 + 0.5) * NoiseScale + scroll_offset;
	
	// Sample smoke texture
	vec4 tex_sample = texture(Ice_Texture, final_uv);
	
	// Add secondary sample for depth and variation
	vec2 final_uv2 = (rotated_uv * 0.5 + 0.5) * NoiseScale * 1.5 - scroll_offset * 0.5;
	vec4 tex_sample2 = texture(Ice_Texture, final_uv2);
	
	// Blend samples for layered vapor effect
	vec4 combined_tex = mix(tex_sample, tex_sample2, 0.5);
	
	// Enhance icy feel with blue tint in shadows
	vec3 icy_tint = mix(vec3(0.6, 0.8, 1.0), vec3(0.8, 0.95, 1.0), combined_tex.r);
	
	// Apply frostiness for crystalline edge highlights
	float frost_edge = smoothstep(0.3, 0.7, combined_tex.a) * Frostiness;
	vec3 frost_color = vec3(0.9, 0.95, 1.0) * frost_edge;
	
	// Combine texture with color and emission
	vec3 final_color = (combined_tex.rgb * icy_tint * Color.rgb * Emission) + frost_color;
	
	// Enhanced alpha for wispy vapor with soft edges
	float final_alpha = combined_tex.a * Color.a * quad_fade * (1.0 + frost_edge * 0.3);
	
	ALBEDO = final_color;
	ALPHA = clamp(final_alpha, 0.0, 1.0);
}
