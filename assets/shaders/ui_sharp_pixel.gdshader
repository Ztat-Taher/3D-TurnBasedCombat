shader_type canvas_item;
// "Sharp bilinear" sampling for pixel-art UI that gets rotated or scaled.
//
// Nearest filtering on a rotated sprite gives jagged stair-step edges and uneven
// pixel sizes; plain linear filtering makes it blurry. This keeps every texel a
// crisp, solid square and only antialiases the one-screen-pixel seam between
// texels, so tilted buttons and text stay sharp and clean at any angle.
//
// Requirements: the CanvasItem using this must have texture_filter = LINEAR
// (the AA comes from the hardware bilinear sample right on the seams).
// Works on TextureRect/TextureButton art and on regular (non-MSDF) fonts.

// 1.0 = one screen pixel of AA on texel seams. Higher = softer, lower = harsher.
uniform float seam_softness : hint_range(0.25, 3.0) = 1.0;

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = UV * tex_size;
	vec2 seam = floor(texel + 0.5);
	vec2 seam_width = max(fwidth(texel) * seam_softness, vec2(1e-4));
	texel = seam + clamp((texel - seam) / seam_width, -0.5, 0.5);
	COLOR = texture(TEXTURE, texel / tex_size) * vertex_color;
}
