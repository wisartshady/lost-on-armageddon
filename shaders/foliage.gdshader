shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Tree leaf cards (alpha tested, double sided). Normals are spherical around the crown (set by the generator) and are
// used for both faces so the crown shades as one soft volume; COLOR.a = how much the vertex sways in the wind.
uniform sampler2D leaves : source_color, filter_linear_mipmap, repeat_disable;
varying vec3 v_wpos;
varying vec3 v_wnrm;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = clamp(COLOR.a, 0.0, 1.0);
	float ph = dot(w.xz, vec2(0.11, 0.17)) + w.y * 0.05;
	float gust = 0.65 + 0.35 * sin(TIME * 0.37 + ph * 0.2);
	vec3 off = vec3(sin(TIME * 1.45 + ph), 0.35 * sin(TIME * 2.3 + ph * 1.7), cos(TIME * 1.15 + ph * 1.3)) * 0.07 * sway * gust;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	v_wpos = w + off;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec4 t = texture(leaves, UV);
	float w = clamp(wetness, 0.0, 1.0);
	vec3 alb = t.rgb * COLOR.rgb * (1.0 - 0.25 * w);
	ALBEDO = alb;
	ROUGHNESS = mix(0.75, 0.32, w);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_wnrm, 0.0)).xyz);
	BACKLIGHT = alb * 0.45;
	EMISSION = alb * light_field_at(v_wpos, v_wnrm) * 0.9 + alb * lightning * vec3(0.5, 0.55, 0.7) * 0.4;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
}
