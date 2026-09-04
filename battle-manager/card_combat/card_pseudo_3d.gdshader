shader_type canvas_item;

// Pseudo-3D Card + Shadow Shader adapted for Godot 4 Control elements
// Based on GodotShaders (Card Shadow + Pseudo 3D Shader)

uniform bool debug = false;
uniform float border_scale : hint_range(1.0, 3.0) = 1.0;
uniform vec2 shadow_offset = vec2(0.0, 20.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform float blur_amount : hint_range(0.0, 5.0) = 1.5;
uniform float shadow_scale : hint_range(1.0, 2.0) = 1.05;
uniform bool disable_rotating = false;

// 3D Perspective controls
uniform float fov : hint_range(1, 179) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-180, 180) = 0.0;
uniform float x_rot : hint_range(-180, 180) = 0.0;
uniform float inset : hint_range(0, 1) = 0.0;

// Interactive dynamics
uniform float hovering : hint_range(0.0, 1.0) = 0.0;
uniform vec2 mouse_screen_pos = vec2(0.0, 0.0);
uniform float rand_trans_power : hint_range(0.0, 2.0) = 0.0;
uniform float rand_seed = 0.0;
uniform float rotation : hint_range(-10.0, 10.0) = 0.0;

varying flat vec4 modulate;
varying flat float sprite_rotation;
varying flat vec2 o;
varying vec3 p;
varying vec2 transformed_world_to_canvas_coordinates;
varying flat vec2 pivot;
varying flat vec2 region_rate;
varying flat mat3 inv_rot_mat;

vec2 rotate(vec2 uv, vec2 pivot_r, float angle) {
	mat2 rotation_mat = mat2(
		vec2(cos(angle), -sin(angle)),
		vec2(sin(angle), cos(angle))
	);
	uv -= pivot_r;
	uv = uv * rotation_mat;
	uv += pivot_r;
	return uv;
}

void vertex() {
	vec2 my_region_rate = abs(VERTEX) * 2.0;
	region_rate = TEXTURE_PIXEL_SIZE * my_region_rate;

	if (VERTEX_ID == 0) {
		pivot = UV;
	} else if (VERTEX_ID == 1) {
		pivot = UV - vec2(0.0, region_rate.y);
	} else if (VERTEX_ID == 2) {
		pivot = UV - vec2(region_rate.x, region_rate.y);
	} else if (VERTEX_ID == 3) {
		pivot = UV - vec2(region_rate.x, 0.0);
	}

	float rand_angle = rand_trans_power * mod(TIME * (0.9 + mod(rand_seed, 0.5)), 2.0 * PI);
	vec2 rand_vec = vec2(cos(rand_angle), sin(rand_angle));

	transformed_world_to_canvas_coordinates = (inverse(MODEL_MATRIX) * vec4(mouse_screen_pos, 0.0, 1.0)).xy;
	
	float region_len = length(region_rate / max(TEXTURE_PIXEL_SIZE, vec2(0.0001)));
	if (region_len < 0.001) region_len = 1.0;

	vec2 mouse_force = hovering * 0.5 * (transformed_world_to_canvas_coordinates) / region_len + rand_vec * 0.05 * rand_trans_power;

	float sin_b = sin(y_rot / 180.0 * PI + mouse_force.x);
	float cos_b = cos(y_rot / 180.0 * PI + mouse_force.x);
	float sin_c = sin(x_rot / 180.0 * PI + -mouse_force.y);
	float cos_c = cos(x_rot / 180.0 * PI + -mouse_force.y);

	inv_rot_mat[0][0] = cos_b;
	inv_rot_mat[0][1] = 0.0;
	inv_rot_mat[0][2] = -sin_b;

	inv_rot_mat[1][0] = sin_b * sin_c;
	inv_rot_mat[1][1] = cos_c;
	inv_rot_mat[1][2] = cos_b * sin_c;

	inv_rot_mat[2][0] = sin_b * cos_c;
	inv_rot_mat[2][1] = -sin_c;
	inv_rot_mat[2][2] = cos_b * cos_c;

	vec2 uv = (UV - pivot) / max(region_rate, vec2(0.0001));
	float t = tan(fov / 360.0 * PI);

	VERTEX += (uv - 0.5) * 1.0 * my_region_rate * t * (1.0 - inset);

	float final_scale = max(border_scale, border_scale * shadow_scale);
	VERTEX.xy *= vec2(final_scale);
	modulate = COLOR;
	sprite_rotation = atan(MODEL_MATRIX[0][1], MODEL_MATRIX[0][0]);
}

vec4 sample_texture_safe(sampler2D tex, vec2 uv) {
	return (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) 
		? vec4(0.0) 
		: texture(tex, uv);
}

vec4 apply_gaussian_blur(sampler2D tex, vec2 uv, vec2 pixel_size) {
	if (blur_amount <= 0.0) return sample_texture_safe(tex, uv);
	
	vec4 color_blur = vec4(0.0);
	float total_weight = 0.0;
	int kernel_size = int(clamp(blur_amount * 3.0, 1.0, 6.0));
	
	for (int x = -kernel_size; x <= kernel_size; x++) {
		for (int y = -kernel_size; y <= kernel_size; y++) {
			vec2 blur_offset = vec2(float(x), float(y)) * pixel_size;
			float weight = exp(-0.5 * (float(x * x + y * y)) / max(blur_amount * blur_amount, 0.01));
			color_blur += sample_texture_safe(tex, uv + blur_offset) * weight;
			total_weight += weight;
		}
	}
	
	return total_weight > 0.0 ? color_blur / total_weight : vec4(0.0);
}

vec2 rotate_point(vec2 pt, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec2(
		pt.x * c - pt.y * s,
		pt.x * s + pt.y * c
	);
}

float calculate_fade(float coord, float scale) {
	if (coord < 0.0) {
		return 1.0 + (coord / max(scale - 1.0, 0.001));
	} else if (coord > 1.0) {
		return 1.0 - ((coord - 1.0) / max(scale - 1.0, 0.001));
	}
	return 1.0;
}

vec4 process_texture(vec2 uv, sampler2D tex, bool is_main, vec2 pixel_size) {
	if (is_main) {
		return sample_texture_safe(tex, uv) * modulate;
	}
	
	vec4 blurred = apply_gaussian_blur(tex, uv, pixel_size);
	float fade_x = calculate_fade(uv.x, shadow_scale);
	float fade_y = calculate_fade(uv.y, shadow_scale);
	float fade = smoothstep(0.0, 1.0, min(fade_x, fade_y));
	
	return vec4(shadow_color.rgb, (blurred.a - (1.0 - shadow_color.a)) * modulate.a * fade);
}

void fragment() {
	vec2 uv = (UV - pivot) / max(region_rate, vec2(0.0001));

	float t = tan(fov / 360.0 * PI);
	p = inv_rot_mat * vec3((uv - 0.5), 0.5 / t);
	float v = (0.5 / t) + 0.5;
	p.xy *= v * inv_rot_mat[2].z;
	o = v * inv_rot_mat[2].xy;

	if (cull_back && p.z <= 0.0) discard;
	uv = (p.xy / max(p.z, 0.0001)).xy - o;
	uv += 0.5;
	
	vec2 reg_size = region_rate / max(TEXTURE_PIXEL_SIZE, vec2(0.0001));
	float asp = reg_size.x > 0.001 ? reg_size.y / reg_size.x : 1.0;
	uv.y *= asp;
	uv = rotate(uv, vec2(0.5, 0.5), rotation + rand_trans_power * 0.05 * sin(TIME * (0.9 + mod(rand_seed, 0.5)) + rand_seed * 123.8985));
	uv.y /= max(asp, 0.0001);

	if (uv.x > 1.0 || uv.x < 0.0 || uv.y > 1.0 || uv.y < 0.0) {
		discard;
	}
	
	vec2 perspective_uv = pivot + uv * region_rate;
	float final_scale = max(border_scale, border_scale * shadow_scale);
	vec2 scaled_uv = perspective_uv * final_scale - (0.5 * (final_scale - 1.0));

	vec4 main_texture = process_texture(scaled_uv, TEXTURE, true, TEXTURE_PIXEL_SIZE);

	vec2 adjusted_offset = disable_rotating ? shadow_offset : rotate_point(shadow_offset, -sprite_rotation);
	vec2 shadow_uv = scaled_uv + adjusted_offset * TEXTURE_PIXEL_SIZE;

	vec4 shadow = process_texture(shadow_uv, TEXTURE, false, TEXTURE_PIXEL_SIZE);

	vec4 res = mix(shadow, main_texture, main_texture.a);
	vec4 debug_layer = vec4(1.0, 0.0, 0.0, 0.3);
	COLOR = mix(debug ? debug_layer : res, res, res.a);
}
