shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Hair cards, eyebrows and eyelashes (MakeHuman CC0 textures): alpha tested strands, the grey photo tinted to the
// hair colour, COLOR.rgb darkens the roots, a shifted strand highlight (Kajiya-Kay style) along the hair.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 color : source_color = vec4(0.8, 0.62, 0.38, 1.0);
uniform float desaturate = 1.0;          // 1: use the texture as grey detail only
uniform float alpha_cut = 0.42;
uniform float highlight = 0.35;
uniform float wet_response = 0.9;
uniform float gloss = 0.0;             // eyes: wet glossy surface
uniform float flat_color = 0.0;        // brows, lashes: the colour itself, the texture gives only the shape
uniform float rim = 0.35;
uniform float fill = 1.0;
uniform float view_fill = 0.0;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec3 v_wtan;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wtan = normalize((MODEL_MATRIX * vec4(0.0, -1.0, 0.0, 0.0)).xyz);   // strands hang down
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < alpha_cut) discard;
	float lum = dot(t.rgb, vec3(0.3, 0.55, 0.15));
	vec3 grey = vec3(lum / 0.62);
	vec3 alb = mix(mix(t.rgb, grey, desaturate) * color.rgb, color.rgb, flat_color) * COLOR.rgb;
	float w = wetness * wet_response;
	alb *= 1.0 - 0.35 * w;
	ALBEDO = alb;
	ROUGHNESS = mix(mix(0.55, 0.06, gloss), 0.3, w);
	SPECULAR = mix(0.35, 0.8, gloss);
	// strand highlight: bright where the view-light half vector is perpendicular to the strand
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_wpos);
	vec3 H = normalize(V + vec3(0.3, 0.9, 0.2));
	float th = dot(normalize(v_wtan), H);
	float kk = pow(sqrt(max(1.0 - th * th, 0.0)), 60.0);
	vec3 lf = lf_raw(v_wpos.xz + v_wnrm.xz * 0.6) * emp_factor(v_wpos) * 0.9;
	vec3 amb = lf + vec3(0.035, 0.04, 0.055) * fill + sky_fill(v_wpos, v_wnrm) * 1.3 + day_light(vec3(0.0, 1.0, 0.0)) * 0.25;
	float up = clamp(v_wnrm.y * 0.5 + 0.6, 0.15, 1.0);
	float fres = pow(1.0 - clamp(abs(dot(normalize(v_wnrm), V)), 0.0, 1.0), 3.0);
	EMISSION = alb * amb * up + color.rgb * kk * highlight * (amb + daylight * 0.25) + (lf * 0.6 + vec3(0.1, 0.13, 0.19)) * fres * rim * 0.5;
	EMISSION += alb * view_fill * vec3(0.55, 0.6, 0.72) * 0.6;
	EMISSION += alb * lightning * vec3(0.5, 0.55, 0.7) * up;
}
