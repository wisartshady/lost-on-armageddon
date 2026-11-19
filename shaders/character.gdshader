shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Characters: albedo texture or flat colour + fabric detail, lit by the street light field and a cold rim.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_albedo = true;
uniform bool use_normal = true;
uniform bool use_rough = false;
uniform bool use_detail = false;
uniform vec4 color : source_color = vec4(1.0);
uniform float detail_scale = 18.0;
uniform float roughness_v = 0.75;
uniform float specular_v = 0.4;
uniform float wet_response = 0.5;
uniform float rim = 0.35;
uniform float lf_mult = 0.9;
uniform float emission_v = 0.0;
uniform bool cloth_mode = false;          // garment atlas: alpha selects the tint (1 top, .66 bottom, .33 shoes, 0 none)
uniform vec4 top_col : source_color = vec4(0.3);
uniform vec4 bottom_col : source_color = vec4(0.2);
uniform vec4 shoes_col : source_color = vec4(0.1);
uniform float fill = 1.0;
uniform float view_fill = 0.0; // soft light from the camera so the player reads from behind
varying vec3 v_wpos;
varying vec3 v_wnrm;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 alb = color.rgb;
	if (cloth_mode) {
		vec4 t = texture(albedo_tex, UV);
		vec3 tint = t.a > 0.83 ? top_col.rgb : (t.a > 0.5 ? bottom_col.rgb : (t.a > 0.16 ? shoes_col.rgb : vec3(1.0)));
		alb = t.rgb * tint;
	} else if (use_albedo) alb *= texture(albedo_tex, UV).rgb;
	if (use_detail) alb *= 0.75 + 0.5 * texture(detail_tex, UV * detail_scale).r;
	float w = wetness * wet_response * clamp(v_wnrm.y * 0.5 + 0.6, 0.0, 1.0);
	alb *= 1.0 - 0.3 * w;
	ALBEDO = alb;
	float r = use_rough ? texture(rough_tex, UV).r : roughness_v;
	ROUGHNESS = mix(r, r * 0.45, w);
	SPECULAR = specular_v;
	if (use_normal) NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 lf = lf_raw(v_wpos.xz + v_wnrm.xz * 0.6) * emp_factor(v_wpos) * lf_mult;
	float up = clamp(v_wnrm.y * 0.5 + 0.6, 0.15, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// small fill so characters never disappear into the dark, plus a cold rim for the stylised look
	EMISSION = alb * (lf * up + vec3(0.035, 0.04, 0.055) * fill + sky_fill(v_wpos, v_wnrm) * 1.3) + (lf * 0.6 + vec3(0.1, 0.13, 0.19)) * fres * rim + alb * emission_v;
	EMISSION += alb * clamp(dot(NORMAL, VIEW), 0.0, 1.0) * view_fill * vec3(0.55, 0.6, 0.72);
	EMISSION += alb * lightning * vec3(0.5, 0.55, 0.7) * up;
}
