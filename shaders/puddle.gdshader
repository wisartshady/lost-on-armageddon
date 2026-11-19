shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
varying vec3 v_wpos;
void vertex() { v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

vec2 ripple(vec2 p, float t, float seed) {
	vec2 g = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float cyc = t * (0.9 + fi * 0.27) + seed * 13.0 + fi * 0.37;
		float k = floor(cyc);
		float f = fract(cyc);
		vec2 c = vec2(hash12(vec2(k, seed * 31.0 + fi)), hash12(vec2(k + 11.0, seed * 17.0 + fi))) * 2.0 - 1.0;
		vec2 d = p - c * 0.8;
		float r = length(d);
		float wave = sin((r - f * 0.9) * 40.0) * smoothstep(0.15, 0.0, abs(r - f * 0.9)) * (1.0 - f);
		g += normalize(d + 1e-4) * wave;
	}
	return g;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float seed = COLOR.r;
	float n = noise2(UV * 3.0 + seed * 20.0) * 0.55 + noise2(UV * 7.0 - seed * 9.0) * 0.25;
	float d = length(p) + (n - 0.4) * 0.8;
	float a = smoothstep(1.0, 0.75, d);
	if (a < 0.01) discard;
	vec2 g = ripple(p * 1.5, TIME, seed) * wetness;
	NORMAL_MAP = normalize(vec3(g * 0.25, 1.0)) * 0.5 + 0.5;
	ALBEDO = vec3(0.012, 0.013, 0.016);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 lf = lf_raw(v_wpos.xz + g * 0.6) * emp_factor(v_wpos);
	EMISSION = lf * (0.25 + 0.9 * fres) + vec3(0.025, 0.03, 0.045) * fres + lightning * vec3(0.4, 0.45, 0.6) * fres
		+ env_reflect(reflect(normalize(v_wpos - CAMERA_POSITION_WORLD), vec3(0.0, 1.0, 0.0)), v_wpos, 0.05) * daylight * (0.35 + 0.6 * fres);
	ALPHA = a * 0.94 * clamp(wetness * 1.2, 0.0, 1.0);
}
