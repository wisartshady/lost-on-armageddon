shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
// Neon Square LED billboards: frames from a 4x8 atlas (tools/gen_bigtex.py).
// COLOR: r = first frame / 32, g = frame count / 32, b = phase seed, a = brightness.
uniform sampler2D frames : source_color, filter_linear_mipmap_anisotropic;
uniform float intensity = 2.1;
varying vec3 v_wpos;
varying vec4 v_col;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}
vec3 frame_col(float idx, vec2 uv) {
	float i = mod(idx, 32.0);
	vec2 cell = vec2(mod(i, 4.0), floor(i / 4.0));
	return texture(frames, (cell + clamp(uv, vec2(0.004), vec2(0.996))) / vec2(4.0, 8.0)).rgb;
}
void fragment() {
	float first = floor(v_col.r * 32.0 + 0.5);
	float cnt = max(1.0, floor(v_col.g * 32.0 + 0.5));
	float period = 6.0 + v_col.b * 4.0;
	float t = TIME / period + v_col.b * 11.0;
	float k = floor(t);
	float ph = fract(t);
	vec2 uv = UV;
	float a = first + mod(k, cnt);
	float b = first + mod(k + 1.0, cnt);
	// wipe + glitch transition at the end of each slot
	float w = smoothstep(0.9, 1.0, ph);
	float edge = w * 1.15 - 0.075 + 0.04 * sin(uv.y * 23.0 + TIME * 7.0);
	float glitch = step(0.9, ph) * (1.0 - step(0.999, ph));
	uv.x += glitch * (hash12(vec2(floor(uv.y * 30.0), floor(TIME * 24.0))) - 0.5) * 0.03;
	vec3 c = mix(frame_col(a, uv), frame_col(b, uv), step(uv.x, edge));
	// LED pixel grid, visible only up close
	vec2 px = fract(UV * vec2(192.0, 96.0));
	float led = smoothstep(0.0, 0.25, px.x) * smoothstep(1.0, 0.75, px.x) * smoothstep(0.0, 0.25, px.y) * smoothstep(1.0, 0.75, px.y);
	float dist = distance(CAMERA_POSITION_WORLD, v_wpos);
	float grid = mix(0.6 + 0.4 * led, 1.0, smoothstep(10.0, 35.0, dist));
	float e = emp_factor(v_wpos);
	vec3 col = c * intensity * v_col.a * grid;
	if (e < 0.99) {
		col *= e;
		col += vec3(0.4, 0.6, 1.0) * step(0.97, hash12(UV * 200.0 + TIME)) * (1.0 - e) * 0.6;
	}
	ALBEDO = col;
}
