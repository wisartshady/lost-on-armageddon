shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float glow = 2.4;
varying vec3 v_wpos;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.7 + o.z * 0.3;
	float sway = sin(TIME * 1.4 + ph) * 0.06 + sin(TIME * 2.3 + ph * 2.0) * 0.03;
	float k = clamp(0.35 - VERTEX.y, 0.0, 1.2);
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.6 * k;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = texture(tex, UV).rgb * COLOR.rgb;
	ALBEDO = c * 0.6;
	ROUGHNESS = 0.7;
	float e = emp_factor(v_wpos);
	EMISSION = c * glow * e;
}
