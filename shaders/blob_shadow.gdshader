shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Soft contact shadow under vehicles and props (rounded-rectangle falloff on a ground quad).
uniform float strength = 0.62;
uniform float softness = 0.35;
void fragment() {
	vec2 q = abs(UV * 2.0 - 1.0);
	vec2 d = max(q - vec2(1.0 - softness), vec2(0.0)) / softness;
	float a = 1.0 - clamp(length(d), 0.0, 1.0);
	a = a * a * (3.0 - 2.0 * a);
	ALBEDO = vec3(0.0);
	ALPHA = a * strength;
}
