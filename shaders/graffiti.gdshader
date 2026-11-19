shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap;
varying vec3 v_wpos;
varying vec3 v_wnrm;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec4 t = texture(atlas, UV);
	// paint sits in the wall: worn thinner in patches (world-space, so no two walls wear the same) and soaked
	// darker when wet; spray paint is a little glossier than the brick around it
	vec2 wp = v_wpos.xz + v_wpos.yy * vec2(0.7, -0.5);
	float wear = tnoise(wp * 0.9) * 0.6 + tnoise(wp * 4.3) * 0.4;
	ALBEDO = t.rgb * 0.8 * (1.0 - 0.25 * wetness);
	ROUGHNESS = mix(0.5, 0.25, wetness);
	SPECULAR = 0.4;
	EMISSION = ALBEDO * light_field_at(v_wpos, v_wnrm);
	ALPHA = t.a * COLOR.a * clamp(0.72 + wear * 0.45, 0.0, 1.0);
}
