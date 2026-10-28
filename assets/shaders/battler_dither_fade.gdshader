shader_type spatial;
render_mode unshaded, ensure_correct_normals;

uniform float alpha : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Dither pattern (4x4 Bayer matrix)
float dither_pattern(ivec2 fragcoord) {
	const float pattern[] = {
		0.00, 0.50, 0.10, 0.65,
		0.75, 0.25, 0.90, 0.35,
		0.20, 0.70, 0.05, 0.50,
		0.95, 0.40, 0.80, 0.30
	};

	int x = fragcoord.x % 4;
	int y = fragcoord.y % 4;

	return pattern[y * 4 + x];
}

void vertex() {
	VERTEX = VERTEX;
}

void fragment() {
	vec4 tex_color = color;

	// Apply dither-based transparency
	ivec2 uv = ivec2(FRAGCOORD.xy);
	float dither_value = dither_pattern(uv);

	// Adjust alpha based on dither pattern
	// If dither_value is below threshold, pixel is transparent
	float threshold = alpha * dither_strength;
	float final_alpha = (dither_value < threshold) ? 0.0 : alpha;

	ALBEDO = tex_color.rgb;
	ALPHA = final_alpha;
}
