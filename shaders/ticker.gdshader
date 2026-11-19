shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
// Scrolling LED news ticker. UV.x is laid out so 1.0 = one full strip length (tools/city.py).
uniform sampler2D strip : source_color, filter_linear_mipmap, repeat_enable;
uniform float speed = 0.014;
uniform float intensity = 2.4;
varying vec3 v_wpos;
void vertex() { v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = texture(strip, vec2(UV.x + TIME * speed, UV.y)).rgb;
	ALBEDO = (c * intensity + vec3(0.012, 0.008, 0.004)) * emp_factor(v_wpos);
}
