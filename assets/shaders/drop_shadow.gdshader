shader_type canvas_item;
// Drop Shadow Shader for 2D sprites & UI elements.
//
// Based on: https://godotshaders.com/shader/simple-shadow-shader-for-2d-sprites/
// (Simple Shadow Shader for 2D Sprites, MIT) by Joan Roig / Moai.
// Extended with:
//   - shadow_strength: animate this (0..1) to make the shadow appear/disappear.
//   - blur_amount: soft gaussian falloff on the shadow edge.
//   - disable_rotating: keep the shadow pointing straight down even when the
//     node itself is rotated (fan layouts, tilt animations, etc).
//
// Usage: place a node behind the element you want to shadow, sized/anchored to
// match it, assign this shader and tune shadow_offset / shadow_color. For a
// sprite or TextureRect the node should display the same texture. Animate
// shadow_strength to fade the shadow in and out. Pair with the DropShadow
// component (res://battle-manager/effects/drop_shadow.gd) for convenience.

// Offset of the shadow in screen pixels (positive Y = below the element).
uniform vec2 shadow_offset = vec2(0.0, 6.0);
// Shadow tint color; the alpha controls the shadow's opacity.
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.35);
// 0.0 hides the shadow, 1.0 shows it at full strength. Tween this to fade.
uniform float shadow_strength : hint_range(0.0, 1.0) = 1.0;
// Softness of the shadow edge in texels (0.0 = crisp, reference-style shadow).
uniform float blur_amount : hint_range(0.0, 6.0) = 1.5;
// When true the offset is not rotated back from the node's rotation, keeping
// the shadow nailed to screen space (standard for UI drop shadows).
uniform bool disable_rotating = false;

varying float sprite_rotation;

vec2 rotate_point(vec2 point, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec2(point.x * c - point.y * s, point.x * s + point.y * c);
}

void vertex() {
	sprite_rotation = atan(MODEL_MATRIX[0][1], MODEL_MATRIX[0][0]);
	vec2 offset = disable_rotating
		? shadow_offset
		: rotate_point(shadow_offset, -sprite_rotation);
	VERTEX.xy += offset;
}

void fragment() {
	float alpha = texture(TEXTURE, UV).a;

	if (blur_amount > 0.001) {
		float acc = 0.0;
		float weight_sum = 0.0;
		const int radius = 3;
		for (int x = -radius; x <= radius; x++) {
			for (int y = -radius; y <= radius; y++) {
				float weight = exp(-0.5 * float(x * x + y * y) / max(blur_amount * blur_amount, 0.01));
				acc += texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE).a * weight;
				weight_sum += weight;
			}
		}
		alpha = acc / max(weight_sum, 0.0001);
	}

	COLOR = vec4(shadow_color.rgb, alpha * shadow_color.a * shadow_strength);
}