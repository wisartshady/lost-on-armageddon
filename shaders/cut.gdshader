shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Alpha-tested / double-sided surfaces (railings, gratings, fences, road paint, awnings) from one texture array.
uniform sampler2DArray tex_arr : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 c0[8]; // uv_scale
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying flat int v_layer;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_layer = int(UV2.x + 0.5);
}
void fragment() {
	vec4 t = texture(tex_arr, vec3(UV * c0[v_layer].x, float(v_layer)));
	vec3 alb = t.rgb * COLOR.rgb;
	// awning layer (5, see CUT_LAYERS in tools/city_v02.py) with vertex alpha 0.5: two-tone stripes, the light
	// stripes stay cream and only the grey ones take the shop colour
	if (v_layer == 5 && COLOR.a < 0.75) {
		float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		// (linear values: grey stripes ~0.26, light ones ~0.69, both with weave noise and streaks)
		float dark = 1.0 - smoothstep(0.38, 0.5, lum);
		vec3 cream = vec3(0.72, 0.69, 0.6) * (lum / 0.69);
		vec3 tint = COLOR.rgb * 0.69 * (lum / 0.26);
		alb = mix(cream, tint, dark);
	}
	float w = clamp(wetness, 0.0, 1.0);
	ALBEDO = alb * (1.0 - 0.2 * w);
	ROUGHNESS = mix(0.7, 0.35, w);
	SPECULAR = 0.45;
	vec3 n = v_wnrm;
	if (!FRONT_FACING) n = -n;
	EMISSION = alb * light_field_at(v_wpos, n) + alb * lightning * vec3(0.5, 0.55, 0.7) * 0.5;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
