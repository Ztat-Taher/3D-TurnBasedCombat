shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 2.0;

uniform sampler2D noise_texture;
uniform vec2 pan_speed = vec2(-2.0, 0.0);
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.2;

uniform float trail_length_fade_power : hint_range(0.1, 5.0) = 2.0;
uniform float edge_fade_power : hint_range(0.1, 10.0) = 3.0;

void fragment() {
	// UV.x maps from 0.0 (tail end of the trail) to 1.0 (sword blade head)
	// UV.y maps from 0.0 (bottom of the blade) to 1.0 (top of the blade)
	
	// Create a panning UV for the noise, based on TIME
	vec2 noise_uv = UV + (TIME * pan_speed);
	
	// Sample the noise
	float noise_val = texture(noise_texture, noise_uv).r;
	
	// Distortion effect along the Y (edges) based on noise
	float distorted_y = clamp(UV.y + (noise_val - 0.5) * distortion_strength, 0.0, 1.0);
	
	// Calculate masks
	// 1. Length Fade: More opaque at the head of the swing (UV.x -> 1)
	float length_mask = pow(UV.x, trail_length_fade_power);
	
	// 2. Edge Fade: Fades out at the top (y=1) and bottom (y=0) of the blade.
	// We want it brightest in the middle (y=0.5)
	float edge_dist = abs(distorted_y - 0.5) * 2.0; // 0 at center, 1 at edges
	float edge_mask = 1.0 - pow(edge_dist, edge_fade_power);
	
	// Combine masks
	float alpha_mask = length_mask * edge_mask * noise_val;
	
	// Calculate color glowing on the edge vs base
	vec4 final_color = mix(base_color, edge_color, edge_dist);
	
	ALBEDO = final_color.rgb * emission_energy;
	ALPHA = final_color.a * alpha_mask;
}
