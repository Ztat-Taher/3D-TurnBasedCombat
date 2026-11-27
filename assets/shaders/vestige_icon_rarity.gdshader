// Rarity glow for vestige icons. One shader for every rarity: [effect] picks
// the look, [glow_color] the tint (Vestige.RARITY_COLORS).
// 0 pulse (common), 1 edge energy (uncommon), 2 ring shimmer (rare),
// 3 distorted pulse (boss), 4 orbiting motes (event), 5 soft shine (shop).
shader_type canvas_item;

uniform int effect = 0;
uniform vec4 glow_color : source_color = vec4(1.0);

float edge_mask(vec2 uv, float width) {
	return step(1.0 - width, uv.x) + step(1.0 - width, uv.y) + step(uv.x, width) + step(uv.y, width);
}

void fragment() {
	vec2 uv = UV;
	if (effect == 3) {
		uv.x += sin(TIME * 5.0 + UV.y * 10.0) * 0.02;
		uv.y += cos(TIME * 5.0 + UV.x * 10.0) * 0.02;
	}
	vec4 tex = texture(TEXTURE, uv);
	vec3 glow = vec3(0.0);
	if (effect == 0) {
		glow = glow_color.rgb * (0.5 + 0.5 * sin(TIME * 2.0)) * 0.3;
	} else if (effect == 1) {
		glow = glow_color.rgb * (0.5 + 0.5 * sin(TIME * 3.0 + UV.x * 5.0)) * 0.5 * edge_mask(UV, 0.1);
	} else if (effect == 2) {
		float d = distance(UV, vec2(0.5));
		float ring = smoothstep(0.4, 0.5, d) * smoothstep(0.5, 0.4, d);
		glow = glow_color.rgb * (0.5 + 0.5 * sin(TIME * 4.0 + (UV.x + UV.y) * 10.0)) * 0.6 * ring;
	} else if (effect == 3) {
		glow = glow_color.rgb * (0.5 + 0.5 * sin(TIME * 3.0)) * 0.7 * edge_mask(UV, 0.15);
	} else if (effect == 4) {
		float motes = 0.0;
		for (float i = 0.0; i < 4.0; i++) {
			vec2 p = vec2(0.5 + 0.4 * sin(TIME * 2.0 + i * 1.57), 0.5 + 0.4 * cos(TIME * 2.0 + i * 1.57));
			motes += smoothstep(0.1, 0.0, distance(UV, p));
		}
		glow = glow_color.rgb * motes * 0.8;
	} else {
		float shine = 0.5 + 0.5 * sin(TIME * 2.5 + UV.x * 8.0);
		glow = glow_color.rgb * (shine * 0.4 + smoothstep(0.5, 0.0, distance(UV, vec2(0.5))) * 0.3);
	}
	COLOR = vec4(tex.rgb + glow, tex.a);
}
