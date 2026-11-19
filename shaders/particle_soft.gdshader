shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/common.gdshaderinc"
// Billboarded steam / smoke lit by the street lights.
uniform sampler2D tex : filter_linear_mipmap;
uniform vec3 base_col : source_color = vec3(0.16, 0.17, 0.19);
uniform float opacity = 0.35;
uniform float lit_mult = 0.9;
varying vec3 v_light;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec3 wp = MODEL_MATRIX[3].xyz;
	v_light = lf_raw(wp.xz) * emp_factor(wp);
}
void fragment() {
	float a = texture(tex, UV).r;
	ALBEDO = base_col + v_light * lit_mult + lightning * vec3(0.3);
	ALPHA = a * opacity * COLOR.a;
}
