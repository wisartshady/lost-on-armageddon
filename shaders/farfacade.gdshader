shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
// Low-cost facades for the streets beyond the barricades: procedural windows.
varying vec3 v_wpos;
varying vec3 v_wnrm;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 tint = COLOR.rgb;
	vec3 wall = vec3(0.05, 0.035, 0.03) * tint + tint * 0.42 * day_light(v_wnrm);
	if (v_wnrm.y > 0.5) { ALBEDO = vec3(0.015) + day_light(v_wnrm) * 0.3; }
	else {
		vec2 cell = vec2(UV.x / 3.0, -UV.y / 3.3);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.25, f.y) * step(f.y, 0.85) * step(1.0, id.y);
		float r = hash12(id + COLOR.a * 100.0);
		vec3 lit = (r < 0.22 * mix(1.0, 0.25, daylight) ? vec3(1.0, 0.72, 0.42) : (r < 0.27 ? vec3(0.7, 0.8, 1.0) : vec3(0.0))) * 0.9 * lamp_power
			+ day_light(v_wnrm) * 0.22;
		vec3 c = mix(wall, vec3(0.015, 0.018, 0.025) + lit, win);
		float shop = step(id.y, 0.5) * step(0.85, hash12(vec2(id.x, COLOR.a * 50.0)));
		c += shop * vec3(1.0, 0.8, 0.5) * 0.4 * step(0.1, f.y) * step(f.y, 0.75);
		ALBEDO = c + wall * light_field_at(v_wpos, v_wnrm);
	}
}
