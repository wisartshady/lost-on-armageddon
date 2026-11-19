shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
global uniform vec4 fog_far_color;
global uniform float lightning;
global uniform float daylight;
global uniform vec4 day_sky;
uniform sampler2D windows_tex : source_color, filter_linear_mipmap;
uniform vec2 scale = vec2(80.0, 224.0);
uniform vec3 base_col : source_color = vec3(0.02, 0.022, 0.028);
uniform float fog_density = 0.0016;
uniform float glass = 0.0;
varying vec3 v_wpos;
float hash12_2(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
void vertex() { v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = UV / scale + vec2(COLOR.a * 7.31, COLOR.a * 3.17);
	vec4 w = texture(windows_tex, uv);
	vec3 col = base_col * COLOR.rgb + w.rgb * w.a * 1.4 * (1.0 - 0.8 * daylight);
	col += day_sky.rgb * daylight * (0.32 + 0.12 * COLOR.r) * (0.8 + 0.2 * w.a);
	if (glass > 0.5) {
		vec2 g = fract(UV / vec2(3.0, 3.6));
		float line = step(0.94, g.x) + step(0.92, g.y);
		col = vec3(0.02, 0.035, 0.06) + vec3(0.1, 0.35, 0.6) * line * 0.25;
		float lit = step(0.6, hash12_2(floor(UV / vec2(3.0, 3.6))));
		col += vec3(0.75, 0.88, 1.0) * lit * 0.5 * (1.0 - line);
	}
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float f = 1.0 - exp(-dist * fog_density);
	col = mix(col, fog_far_color.rgb, f * 0.85) + lightning * vec3(0.15, 0.17, 0.22) * f;
	ALBEDO = col;
}
