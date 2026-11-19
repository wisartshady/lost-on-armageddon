shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
varying vec3 v_wpos;
varying vec3 v_wnrm;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	ALBEDO = vec3(0.015, 0.018, 0.022) * COLOR.rgb;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = light_field_at(v_wpos, v_wnrm) * (0.3 + 0.9 * fres) * 0.6 + vec3(0.02, 0.025, 0.04) * fres
		+ env_reflect(reflect(normalize(v_wpos - CAMERA_POSITION_WORLD), v_wnrm), v_wpos, 0.08) * daylight * (0.25 + 0.7 * fres);
	ALPHA = mix(COLOR.a, 1.0, fres * 0.6);
}
