shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
void fragment() {
	float on = step(fract(TIME * 0.45 + COLOR.a), 0.12);
	ALBEDO = vec3(1.0, 0.08, 0.04) * (0.08 + on * 5.0);
}
