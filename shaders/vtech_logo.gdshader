shader_type spatial;
render_mode unshaded, blend_add, cull_back, fog_disabled, depth_draw_never;
uniform sampler2D logo : source_color, filter_linear_mipmap;
void fragment() {
	vec3 c = texture(logo, UV).rgb;
	ALBEDO = c * (1.6 + 0.2 * sin(TIME * 0.7));
}
