shader_type spatial;
render_mode unshaded, cull_back;
// Distant towers beyond the streets. Lit like the rest of the far city (sky light by day, lit windows at night)
// and left to the scene fog, so with distance they fade into the haze instead of standing out as black blocks.
global uniform float lightning;
global uniform float daylight;
global uniform float lamp_power;
global uniform vec4 day_sky;
uniform sampler2D windows_tex : source_color, filter_linear_mipmap;
uniform vec2 scale = vec2(80.0, 224.0);
uniform vec3 base_col : source_color = vec3(0.02, 0.022, 0.028);
uniform float glass = 0.0;
varying vec3 v_wnrm;
float hash12_2(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
void vertex() { v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	vec2 uv = UV / scale + vec2(COLOR.a * 7.31, COLOR.a * 3.17);
	vec4 w = texture(windows_tex, uv);
	float night = 1.0 - daylight;
	// facade by day: concrete / brick lit by the overcast sky, a touch brighter on the sides facing up and the sun
	float facing = 0.82 + 0.18 * clamp(v_wnrm.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 wall_day = day_sky.rgb * (0.46 + 0.16 * COLOR.r) * facing;
	vec3 win_day = day_sky.rgb * 0.32 + vec3(0.02, 0.025, 0.035);
	vec3 col_day = mix(wall_day, win_day, w.a * 0.65);
	vec3 col_night = base_col * COLOR.rgb + w.rgb * w.a * 1.4 * lamp_power;
	if (glass > 0.5) {
		vec2 g = fract(UV / vec2(3.0, 3.6));
		float line = step(0.94, g.x) + step(0.92, g.y);
		col_night = vec3(0.02, 0.035, 0.06) + vec3(0.1, 0.35, 0.6) * line * 0.25;
		float lit = step(0.6, hash12_2(floor(UV / vec2(3.0, 3.6))));
		col_night += vec3(0.75, 0.88, 1.0) * lit * 0.5 * (1.0 - line) * lamp_power;
		col_day = day_sky.rgb * mix(0.38, 0.55, line) + vec3(0.03, 0.05, 0.08);
	}
	vec3 col = mix(col_night, col_day, daylight);
	ALBEDO = col + lightning * vec3(0.15, 0.17, 0.22) * night;
}
