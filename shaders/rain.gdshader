shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://shaders/common.gdshaderinc"
uniform sampler2D rain_tex : filter_linear_mipmap, repeat_enable;
uniform float speed = 2.2;
uniform float tiling = 6.0;
uniform float brightness = 0.55;
uniform float density = 1.0;
varying vec3 v_wpos;
varying vec3 v_light;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 l = lf_raw(v_wpos.xz) * emp_factor(v_wpos);
	v_light = l / (1.0 + max(max(l.r, l.g), l.b));
}
void fragment() {
	vec2 uv = vec2(UV.x * tiling, UV.y * 2.0 + TIME * speed);
	float r = texture(rain_tex, uv).r;
	float r2 = texture(rain_tex, uv * vec2(1.7, 0.8) + vec2(0.37, TIME * speed * 0.6)).r;
	float a = max(r, r2 * 0.7) * density;
	float fade = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.7, UV.y);
	vec3 c = (vec3(0.08, 0.09, 0.11) + v_light * 0.55 + lightning * vec3(0.6)) * brightness;
	ALBEDO = c * a * fade;
}
