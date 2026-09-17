shader_type spatial;
render_mode blend_add, cull_back, unshaded;

// Fire rim aura, adapted from Fire and Electric Shader by flakmonkeydev
// (https://godotshaders.com/shader/fire-and-electric-shader/, CC0).
// Uniforms follow the StatusFX pack conventions so VFXStatusBB drives them.

group_uniforms Color;
uniform vec3 primary_color : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 secondary_color : source_color = vec3(1.0, 0.9, 0.4);
uniform vec3 tertiary_color : source_color = vec3(0.5, 0.05, 0.0);
uniform float emission = 3.0;
uniform float color_curve = 1.0;
uniform float hue_variation = 0.05;

group_uniforms Shape;
uniform sampler2D noise_texture : repeat_enable;
uniform vec2 noise_scale = vec2(1.0, 1.0);
uniform vec2 noise_scroll = vec2(0.0, -0.5);
uniform float shape_curve = 1.5;
uniform float intensity : hint_range(0.0, 10.0) = 2.2;
uniform float fresnel_power : hint_range(0.0, 5.0) = 3.0;
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.08;

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool proximity_fade = false;
uniform float proximity_fade_distance : hint_range(0.0, 4096.0, 0.01) = 1.0;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

vec3 shift_hue(vec3 color, float shift) {
    vec3 gray = vec3(0.57735);
    vec3 projection = gray * dot(gray, color.rgb);
    vec3 U = color.rgb - projection;
    vec3 V = cross(gray, U);
    vec3 shifted = U * cos(shift * 2.0 * PI) + V * sin(shift * 2.0 * PI) + projection;
    return shifted;
}

void vertex() {
    float n = texture(noise_texture, UV * noise_scale + noise_scroll * TIME * 0.5).r;
    VERTEX += NORMAL * n * distortion_strength;
}

void fragment() {
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
    vec2 uv = UV * noise_scale + noise_scroll * TIME;
    float noise = texture(noise_texture, uv).r;
    float noise2 = texture(noise_texture, uv * 1.7 + vec2(0.31, 0.67)).r;

    noise = pow(noise, max(shape_curve, 0.01));
    float mask = clamp(fresnel * noise * intensity, 0.0, 1.0);
    float heat = pow(mask, max(color_curve, 0.01));

    vec3 color = mix(tertiary_color, primary_color, heat);
    color = mix(color, secondary_color, pow(heat, 2.0 / max(color_curve, 0.01)));
    color = shift_hue(color, (noise2 - 0.5) * hue_variation);

    float flicker = sin(TIME * 10.0) * 0.1 + 0.9;

    ALPHA = clamp(mask * flicker, 0.0, 1.0);

    if (proximity_fade) {
        float proximity_depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
        vec4 ndc = OUTPUT_IS_SRGB ? vec4(vec3(SCREEN_UV, proximity_depth_tex) * 2.0 - 1.0, 1.0) : vec4(SCREEN_UV * 2.0 - 1.0, proximity_depth_tex, 1.0);
        vec4 proximity_view_pos = INV_PROJECTION_MATRIX * ndc;
        proximity_view_pos.xyz /= proximity_view_pos.w;
        ALPHA *= clamp(1.0 - smoothstep(proximity_view_pos.z + proximity_fade_distance, proximity_view_pos.z, VERTEX.z), 0.0, 1.0);
    }

    ALPHA = clamp((ALPHA - edge_position) / (1.0 - edge_hardness), 0.0, 1.0);
    ALBEDO = color * emission * flicker;
}
