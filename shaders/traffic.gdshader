shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
// COLOR.a: 0 = red, 0.5 = amber, 1 = green, 0.25 = pedestrian
varying vec3 v_wpos;
varying float v_phase;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_phase = COLOR.b;
}
void fragment() {
	float t = fract(TIME / 24.0 + v_phase);
	float slot = COLOR.a;
	vec3 col = vec3(0.0);
	float on = 0.0;
	if (slot < 0.1) { col = vec3(1.0, 0.08, 0.04); on = step(0.5, t); }
	else if (slot < 0.35) { col = vec3(1.0, 0.95, 0.85); on = step(t, 0.4); }
	else if (slot < 0.75) { col = vec3(1.0, 0.55, 0.05); on = step(0.42, t) * step(t, 0.5); }
	else { col = vec3(0.1, 1.0, 0.55); on = step(t, 0.42); }
	on *= emp_factor(v_wpos);
	ALBEDO = mix(col * 0.06, col * 3.0, on);
}
