shader_type canvas_item;

uniform vec4 line_color : source_color = vec4(0.55, 0.55, 0.6, 0.5);
uniform vec4 traveled_color : source_color = vec4(0.95, 0.8, 0.35, 0.9);
uniform float line_width : float = 4.0;
uniform float dash_length : float = 10.0;
uniform float gap_length : float = 5.0;
uniform float animation_speed : float = 2.0;
uniform bool is_traveled : bool = false;
uniform bool animated : bool = true;

void fragment() {
	// Calculate distance along the line
	float distance = length(UV - vec2(0.5));
	
	// Create dashed pattern
	float total_dash = dash_length + gap_length;
	float pattern = mod(distance + (TIME * animation_speed if animated else 0.0), total_dash);
	
	// Determine if we're in a dash or gap
	float dash_value = step(pattern, dash_length);
	
	// Mix colors based on traveled state
	vec4 final_color = mix(line_color, traveled_color, float(is_traveled));
	
	// Apply dashed pattern
	float alpha = dash_value * final_color.a;
	
	COLOR = vec4(final_color.rgb, alpha);
}