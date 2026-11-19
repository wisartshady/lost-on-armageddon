shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Tinted car glass for near-range vehicles: dark film you can see the cabin through, more reflective at a glancing
// angle. The mirrors (part 16) live in the body surface. window_open > 0.5: the driver's window is wound down.
instance uniform vec4 paint : source_color = vec4(0.32, 0.05, 0.06, 0.4);
instance uniform float window_open = 0.0;
uniform float tint = 0.5;       // opacity of the film looking straight through
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec3 v_lpos;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_lpos = VERTEX;
}
void fragment() {
	if (window_open > 0.5 && v_lpos.x < -0.5 && v_lpos.z > -0.93 && v_lpos.z < 0.40 && v_lpos.y > 0.9) {
		discard;
	}
	vec3 N = normalize(v_wnrm);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = 0.06 + 0.94 * pow(1.0 - ndv, 5.0);
	vec3 R = reflect(-V, N);
	vec3 env = env_reflect(R, v_wpos, 0.05);
	vec3 lf = light_field_at(v_wpos, N);
	ALBEDO = vec3(0.01, 0.012, 0.014);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	EMISSION = env * (0.14 + 1.25 * fres) + lf * 0.03;
	ALPHA = clamp(tint + fres * (1.0 - tint), 0.0, 0.97);
}
