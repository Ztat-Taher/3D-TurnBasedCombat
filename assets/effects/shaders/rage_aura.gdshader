// Rage Aura Shader
// Red smoky aura overlay with texture-driven 3D vertex animation

shader_type spatial;
render_mode blend_add, cull_back, unshaded;

group_uniforms Color;
uniform vec3 primary_color : source_color = vec3(1.0, 0.1, 0.1);
uniform vec3 secondary_color : source_color = vec3(0.8, 0.05, 0.05);
uniform vec3 tertiary_color : source_color = vec3(0.6, 0.0, 0.0);
uniform float emission = 2.0;
uniform float color_curve = 1.0;
uniform float hue_variation = 0.05;

group_uniforms VertexAnimation;
uniform float vertex_wave_speed : hint_range(0.0, 20.0) = 4.0;
uniform float vertex_wave_amplitude : hint_range(0.0, 2.0) = 0.15;
uniform float vertex_frequency : hint_range(0.1, 20.0) = 5.0;

group_uniforms Smoke;
uniform sampler2D smoke_texture : repeat_enable;
uniform vec2 smoke_scale = vec2(1.0, 1.0);
uniform vec2 smoke_scroll = vec2(0.0, -0.2);
uniform float smoke_sharpness = 0.869;
uniform float time_scale = 0.2;
uniform float height_fade = 3.4;
uniform float scissor = 0.457;

group_uniforms Fade;
uniform float fade_size = 0.016;
uniform float fade_blend = 0.364;
uniform float fresnel_power = 2.0;
uniform float intensity : hint_range(0.0, 10.0) = 1.5;

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

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void vertex() {
    // Sample the smoke texture directly in the vertex shader to drive true 3D displacement
    vec2 vert_smoke_uv = UV * smoke_scale * vertex_frequency - TIME * time_scale * smoke_scroll;
    vec4 vert_smoke = texture(smoke_texture, vert_smoke_uv);
    
    // Displace vertices along the normal using the texture pattern + a sine wave pulse
    float displacement = (vert_smoke.r - 0.5) * vertex_wave_amplitude + 
                         sin(TIME * vertex_wave_speed + UV.y * 10.0) * (vertex_wave_amplitude * 0.5);
                         
    VERTEX += NORMAL * displacement;
}

void fragment() {
    // Smoke Texture with scrolling
    vec2 smoke_uv = UV * smoke_scale - TIME * time_scale * smoke_scroll;
    vec4 smoke_color = texture(smoke_texture, smoke_uv);
    float smoke_buffer = smoothstep(0.0, smoke_sharpness, smoke_color.r);
    
    // Secondary smoke sample for variation
    vec2 smoke_uv2 = UV * smoke_scale * 1.5 - TIME * time_scale * smoke_scroll * 0.7 + vec2(0.5, 0.3);
    vec4 smoke_color2 = texture(smoke_texture, smoke_uv2);
    float smoke_buffer2 = smoothstep(0.0, smoke_sharpness, smoke_color2.r);
    
    // Blend smoke samples
    float combined_smoke = mix(smoke_buffer, smoke_buffer2, 0.5);
    
    // Fresnel Fade
    float fres = fresnel(fresnel_power, NORMAL, VIEW);
    fres = smoothstep(fade_size, fade_size + fade_blend, fres);
    
    // Height fade
    float height_mask = clamp(sin(UV.y * PI) * height_fade - (height_fade / 2.0), 0.0, 1.0);
    
    // Color blending based on smoke intensity
    float heat = pow(combined_smoke * intensity, max(color_curve, 0.01));
    vec3 color = mix(tertiary_color, primary_color, heat);
    color = mix(color, secondary_color, pow(heat, 2.0 / max(color_curve, 0.01)));
    
    // Add hue variation
    color = shift_hue(color, (smoke_buffer2 - 0.5) * hue_variation);
    
    // Final alpha calculation
    float alpha = combined_smoke * fres * height_mask;
    
    if (proximity_fade) {
        float proximity_depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
        vec4 ndc = OUTPUT_IS_SRGB ? vec4(vec3(SCREEN_UV, proximity_depth_tex) * 2.0 - 1.0, 1.0) : vec4(SCREEN_UV * 2.0 - 1.0, proximity_depth_tex, 1.0);
        vec4 proximity_view_pos = INV_PROJECTION_MATRIX * ndc;
        proximity_view_pos.xyz /= proximity_view_pos.w;
        alpha *= clamp(1.0 - smoothstep(proximity_view_pos.z + proximity_fade_distance, proximity_view_pos.z, VERTEX.z), 0.0, 1.0);
    }
    
    // Edge fade
    alpha = clamp((alpha - edge_position) / (1.0 - edge_hardness), 0.0, 1.0);
    
    // Manual scissor effect using alpha
    alpha *= smoothstep(scissor, scissor + 0.1, 1.0);
    
    ALPHA = clamp(alpha, 0.0, 1.0);
    ALBEDO = color * emission;
}