shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, ensure_correct_normals;

uniform vec4 indicator_color : source_color = vec4(1.0, 0.8, 0.0, 1.0);
uniform int indicator_type : hint_range(0, 2) = 0; // 0=circle, 1=X, 2=caret
uniform float pulse_speed : hint_range(0.0, 20.0) = 5.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float line_thickness : hint_range(0.01, 0.5) = 0.15;
uniform float progress : hint_range(0.0, 1.0) = 1.0; // For charge-up animations

void fragment() {
	vec2 uv = UV;
	// Center UVs for radial effects
	vec2 centered_uv = uv * 2.0 - 1.0;
	float dist = length(centered_uv);
	
	// Pulsing glow effect
	float pulse = sin(TIME * pulse_speed) * pulse_intensity + (1.0 - pulse_intensity);
	
	// Base shape based on type
	float shape = 0.0;
	
	if (indicator_type == 0) {
		// Circle
		float outer_edge = smoothstep(0.4 - line_thickness, 0.4, dist);
		float inner_edge = smoothstep(0.4 + line_thickness, 0.4 + line_thickness * 2.0, dist);
		shape = outer_edge - inner_edge;
		
		// Add a glow ring
		float glow = smoothstep(0.6, 0.0, dist) * 0.3;
		shape += glow;
	}
	else if (indicator_type == 1) {
		// X shape (cross)
		float line1 = smoothstep(line_thickness, 0.0, abs(centered_uv.x + centered_uv.y));
		float line2 = smoothstep(line_thickness, 0.0, abs(centered_uv.x - centered_uv.y));
		shape = max(line1, line2);
		
		// Add glow
		float glow1 = smoothstep(line_thickness * 3.0, 0.0, abs(centered_uv.x + centered_uv.y)) * 0.3;
		float glow2 = smoothstep(line_thickness * 3.0, 0.0, abs(centered_uv.x - centered_uv.y)) * 0.3;
		shape += max(glow1, glow2);
	}
	else if (indicator_type == 2) {
		// Smooth Upward Caret shape (^) using line segments
		vec2 cuv = centered_uv;
		cuv.y -= 0.05; // Slight vertical centering adjustment
		
		// Define exact coordinates for the caret vertices (Peak at the bottom, legs pointing UP)
		vec2 peak = vec2(0.0, -0.25);
		vec2 left_top = vec2(-0.35, 0.25);
		vec2 right_top = vec2(0.35, 0.25);
		
		// Distance to left leg segment
		vec2 pa_l = cuv - peak;
		vec2 ba_l = left_top - peak;
		float h_l = clamp(dot(pa_l, ba_l) / dot(ba_l, ba_l), 0.0, 1.0);
		float d_left = length(pa_l - ba_l * h_l);
		
		// Distance to right leg segment
		vec2 pa_r = cuv - peak;
		vec2 ba_r = right_top - peak;
		float h_r = clamp(dot(pa_r, ba_r) / dot(ba_r, ba_r), 0.0, 1.0);
		float d_right = length(pa_r - ba_r * h_r);
		
		// Combine segments for the base caret
		float d_caret = min(d_left, d_right);
		shape = smoothstep(line_thickness, 0.0, d_caret);
		
		// Add matching smooth glow
		float glow = smoothstep(line_thickness * 3.0, 0.0, d_caret) * 0.3;
		shape += glow;
	}
	
	// Apply pulse
	shape *= pulse;
	
	// Fade out based on progress (for charge-up animations)
	if (dist > progress * 1.5) {
		shape = 0.0;
	}
	
	// Apply alpha fade at edges
	float alpha_fade = smoothstep(1.0, 0.7, dist);
	shape *= alpha_fade;
	
	// Final color
	vec3 final_color = indicator_color.rgb * shape;
	float alpha = shape * indicator_color.a;
	
	ALBEDO = final_color;
	ALPHA = alpha;
}