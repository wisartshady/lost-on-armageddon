shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Sign atlas: rgb = artwork, alpha = backlit mask. Vertex colour alpha = sign is switched on.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float glow = 2.2;
uniform bool two_sided_offset = false;
varying vec3 v_wpos;
varying vec3 v_wnrm;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec4 a = texture(atlas, UV);
	ALBEDO = a.rgb * 0.85;
	ROUGHNESS = 0.55;
	float e = emp_factor(v_wpos);
	float seed = fract(v_wpos.x * 0.37 + v_wpos.z * 0.73);
	float flick = seed > 0.93 ? step(0.25, noise2(vec2(TIME * 9.0, seed * 50.0))) : 1.0;
	EMISSION = a.rgb * a.a * COLOR.a * glow * e * flick + ALBEDO * light_field_at(v_wpos, v_wnrm);
}
