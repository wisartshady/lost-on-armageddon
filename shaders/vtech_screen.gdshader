shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
uniform sampler2D frames : source_color, filter_linear_mipmap;
uniform float intensity = 1.8;
varying vec3 v_wpos;
void vertex() { v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float period = 7.0;
	float t = TIME / period;
	float idx = mod(floor(t), 4.0);
	float ph = fract(t);
	vec2 uv = UV;
	float glitch = smoothstep(0.96, 1.0, ph);
	uv.x += glitch * (hash12(vec2(floor(uv.y * 40.0), floor(TIME * 30.0))) - 0.5) * 0.08;
	vec3 c = texture(frames, vec2(uv.x, (uv.y + idx) / 4.0)).rgb;
	float scan = 0.9 + 0.1 * sin(uv.y * 900.0);
	float e = emp_factor(v_wpos);
	vec3 col = c * intensity * scan * (1.0 - glitch * 0.5);
	if (e < 0.99) {
		col *= e;
		col += vec3(0.4, 0.6, 1.0) * step(0.97, hash12(uv * 200.0 + TIME)) * (1.0 - e) * 0.6;
	}
	ALBEDO = col;
}
