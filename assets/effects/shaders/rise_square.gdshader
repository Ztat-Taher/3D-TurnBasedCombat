shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

group_uniforms Color;
uniform vec3 primary_color : source_color = vec3(1.0, 0.9, 0.6);
uniform vec3 secondary_color : source_color = vec3(1.0, 0.62, 0.25);
uniform vec3 tertiary_color : source_color = vec3(0.9, 0.4, 0.15);
uniform float emission = 5.0;
uniform float color_curve = 1.0;
uniform float hue_variation = 0.1;

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool proximity_fade = false;
uniform float proximity_fade_distance : hint_range(0.0, 4096.0, 0.01);
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying float id;

void vertex() {
    id = float(INSTANCE_ID);
}

void fragment() {
    vec2 cuv = UV * 2.0 - 1.0;
    float dist = length(cuv);

    // Rim (edge) glow of the tile.
    float rim = smoothstep(1.0, 0.82, dist);

    // Per-face brightness from orientation: tiles tilted away from the camera are dimmer -> 3D read.
    float face = abs(NORMAL.z);
    float shade = 0.38 + 0.62 * face;

    vec3 color = mix(secondary_color, primary_color, shade);
    color = mix(tertiary_color, color, shade);
    color *= (0.5 + 0.5 * COLOR.r);

    // Subtle per-particle twinkle.
    float pulse = 0.85 + 0.15 * sin(TIME * 2.5 + id);

    ALBEDO = color * COLOR.rgb * emission * pulse;
    ALPHA = COLOR.a * mix(0.45, 1.0, rim);

    // Proximity Fade
    if(proximity_fade){
        float proximity_depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
        vec4 ndc = OUTPUT_IS_SRGB ? vec4(vec3(SCREEN_UV, proximity_depth_tex) * 2.0 - 1.0, 1.0) : vec4(SCREEN_UV * 2.0 - 1.0, proximity_depth_tex, 1.0);
        vec4 proximity_view_pos = INV_PROJECTION_MATRIX * ndc;
        proximity_view_pos.xyz /= proximity_view_pos.w;
        ALPHA *= clamp(1.0 - smoothstep(proximity_view_pos.z + proximity_fade_distance, proximity_view_pos.z, VERTEX.z), 0.0, 1.0);
    }

    ALPHA = clamp((ALPHA - edge_position) / (1.0 - edge_hardness), 0.0, 1.0);
}