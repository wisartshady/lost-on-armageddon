shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
#include "res://shaders/common.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float intensity = 1.7;
varying vec3 v_wpos;
void vertex() { v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = texture(atlas, UV).rgb;
	float seed = COLOR.a;
	float f = 1.0;
	if (seed > 0.82) {
		float n = noise2(vec2(TIME * 7.0, seed * 91.0));
		f = n > 0.3 ? 1.0 : 0.15;
	}
	float e = emp_factor(v_wpos);
	// small fog attenuation so distant neon still reads through the mist
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float fogk = exp(-dist * 0.006);
	ALBEDO = c * intensity * f * e * fogk;
}
