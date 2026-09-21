// Port of Unity Ice Shader to Godot 4 (Overlay Version)
// by NekotoArts / Adapted with aesthetic default parameters

shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

uniform float FresnelPower = 3.0;
uniform vec4 FresnelColor : source_color = vec4(0.7, 0.85, 1.0, 1.0);
uniform vec4 Color : source_color = vec4(0.8, 0.9, 1.0, 0.85);
uniform vec3 Tiling = vec3(2.0, 2.0, 0.0);
uniform vec3 Offset = vec3(0.0, 0.0, 0.0);
uniform sampler2D Ice_Texture : source_color;
uniform float RefractionAmount = 0.5;
uniform float Metallic = 0.1;
uniform float Smoothness = 0.9;
uniform float Normals = 0.6;

// TilingAndOffsetUV
vec2 ti1ingN0ffsetFunc(vec2 _uv_tN0, vec2 _offset_tN0){
	return vec2(mod(_uv_tN0.x + _offset_tN0.x, 1.0), mod(_uv_tN0.y + _offset_tN0.y, 1.0));
}

// ReadNormalMap
vec3 read_normalmap(in vec3 normalmap, in vec3 normal, in vec3 tangent, in vec3 binormal, in float normaldepth) {
	normalmap.xy = normalmap.xy * 2.0 - 1.0;
	normalmap.z = sqrt(max(0.0, 1.0 - dot(normalmap.xy, normalmap.xy)));
	return normalize(mix(normal, tangent * normalmap.x + binormal * normalmap.y + normal * normalmap.z, normaldepth));
}

void vertex() {
}

void fragment() {
	// Fresnel calculation for rim ice glow
	float n_out23p0 = FresnelPower;
	float n_out22p0 = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), n_out23p0);

	vec3 n_out24p0 = FresnelColor.rgb;
	vec3 n_out25p0 = vec3(n_out22p0) * vec3(n_out24p0);

	vec3 n_out5p0 = Color.rgb;
	float n_out5p1 = Color.a;

	// UV Tiling and Offset for Ice Texture
	vec3 n_out29p0 = vec3(UV, 0.0);
	vec3 n_out31p0 = Tiling;
	vec3 n_out30p0 = n_out29p0 * n_out31p0;
	vec3 n_out28p0 = Offset;

	vec3 n_out27p0;
	{
		n_out27p0 = vec3(ti1ingN0ffsetFunc(n_out30p0.xy, n_out28p0.xy), 0);
	}

	// Sample Ice Texture
	vec4 ice_tex_read = texture(Ice_Texture, n_out27p0.xy);
	vec3 n_out11p0 = ice_tex_read.rgb;

	// Combine ice texture details with tint color and fresnel rim
	vec3 n_out20p0 = n_out11p0 + vec3(0.2);
	vec3 n_out21p0 = n_out5p0 * n_out20p0;
	vec3 n_out26p0 = n_out25p0 + n_out21p0;

	// OVERLAY ALPHA: Driven by ice texture brightness + Fresnel rim for patch frost look
	float ice_luminance = dot(n_out11p0, vec3(0.333, 0.333, 0.333));
	float overlay_alpha = clamp((ice_luminance * 0.7 + n_out22p0 * 0.5) * n_out5p1, 0.0, 1.0);

	float n_out2p0 = Metallic;
	float n_out3p0 = Smoothness;
	float n_out4p0 = Normals;

	vec3 n_out18p0;
	{
		n_out18p0 = read_normalmap(n_out11p0, vec3(n_out4p0), TANGENT, BINORMAL, n_out4p0);
	}

	// Output assignments for overlay blending
	ALBEDO = n_out26p0;
	ALPHA = overlay_alpha;
	METALLIC = n_out2p0;
	SPECULAR = n_out3p0;
	NORMAL = n_out18p0;
}