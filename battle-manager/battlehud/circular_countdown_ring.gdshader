shader_type canvas_item;

uniform float ring_radius : hint_range(0.0, 1.0) = 0.3;           // Base radius of the circular ring
uniform float ring_width : hint_range(0.01, 0.2) = 0.05;          // Thickness of the ring border
uniform vec3 ring_color : source_color = vec3(0.6, 0.8, 0.9);     // Tint color applied to the ring
uniform float ring_fade : hint_range(0.0, 1.0) = 1.0;             // Global visibility of the ring (0.0 = hidden, 1.0 = full)
uniform float ring_countdown : hint_range(0.0, 1.0) = 1.0;        // Countdown progress from 1.0 (complete) to 0.0 (fully depleted clockwise)

void fragment() {
	// Map UV to [-1,1]
	vec2 uv = UV * 2.0 - 1.0;
	float dis = length(uv);

	// Basic ring shape
	float ring_shape = smoothstep(ring_radius - ring_width, ring_radius, dis)
	                 - smoothstep(ring_radius, ring_radius + ring_width, dis);
	ring_shape *= ring_fade;

	// Clockwise countdown starting from 12 o'clock
	float angle = atan(-uv.x, -uv.y);     // 12 o'clock is 0, increases clockwise
	angle = mod(angle, 6.2831853);        // [0, 2π]
	angle /= 6.2831853;                   // Map to [0,1]
	float countdown_mask = step(angle, ring_countdown);

	// Final ring
	float ring_value = ring_shape * countdown_mask;
	vec3 color = ring_color * ring_value;
	float alpha = max(max(color.r, color.g), color.b);

	COLOR = vec4(color, alpha);
}