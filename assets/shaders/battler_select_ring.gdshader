shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_opaque;

// Main color of the effect (e.g., blood red, necromantic purple, sickly green)
uniform vec4 color : source_color = vec4(0.8, 0.1, 0.1, 1.0);

// Scrolling direction and speed
uniform vec2 offset = vec2(1.0, 0.0);
uniform float speed : hint_range(0.0, 10.0) = 0.4;

// Mask Texture (Set texture filter to Nearest in Godot for best PS2 crunch)
uniform sampler2D mask_texture : source_color, filter_nearest;

// PS2 pixelation / low-res texel snap factor (0 to disable, higher = chunkier)
uniform float pixelation_amount : hint_range(0.0, 256.0) = 64.0;

// Dark fantasy ritual flicker / pulse
uniform float flicker_speed : hint_range(0.0, 20.0) = 6.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.35;

// Overall intensity of the effect
uniform float intensity : hint_range(0.0, 5.0) = 1.5;

void fragment() {
	vec2 uv = UV;
	
	// 1. PS2-style UV quantization (snaps texture coordinates to a low-res grid)
	if (pixelation_amount > 0.0) {
		uv = floor(uv * pixelation_amount) / pixelation_amount;
	}
	
	// 2. Scrolling calculation
	float scroll = TIME * speed;
	float scroll_amount = offset.x * scroll;
	vec2 scrolled = uv + vec2(scroll_amount);
	
	// 3. Sample mask texture
	vec4 mask_color = texture(mask_texture, scrolled);
	
	// 4. PS2-style hard binary cutoff (1-bit alpha occult look)
	float mask_binary = step(0.5, mask_color.r);
	
	// 5. Unstable dark-magic flicker (sine wave mixed with organic pulse)
	float flicker = 1.0 - (sin(TIME * flicker_speed) * 0.5 + 0.5) * flicker_intensity;
	
	// 6. Final color & alpha assembly
	vec3 final_color = color.rgb * mask_binary * flicker;
	
	float clamped_intensity = clamp(intensity, 0.0, 5.0);
	float final_alpha = color.a * mask_binary * clamped_intensity * flicker;
	
	ALBEDO = final_color;
	ALPHA = final_alpha;
}