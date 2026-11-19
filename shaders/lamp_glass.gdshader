shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
// Lamp bulbs / emissive glass. COLOR.a: 1 = on, 0.5 = flickering, 0 = broken/off. UV.x = per-lamp seed.
uniform float intensity = 3.0;
varying vec3 v_wpos;
void vertex() { v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float on = lamp_on(COLOR.a, UV.x) * emp_factor(v_wpos);
	vec3 base = COLOR.rgb;
	ALBEDO = mix(base * 0.08, base * intensity, on);
}
