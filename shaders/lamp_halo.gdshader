shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
#include "res://shaders/common.gdshaderinc"
// Soft glow sprite around a light source (MultiMesh: COLOR.rgb = light colour, COLOR.a = state / 2, custom.r = seed).
// Bigger and stronger in rain (light scattered by the wet air).
uniform float strength = 0.55;
varying vec3 v_center;
varying vec3 v_col;
varying float v_on;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - c;
	float d = length(to_cam);
	vec3 cc = c + to_cam / max(d, 0.001) * min(0.35, d * 0.3);    // pull in front of the lamp housing
	float s = length(MODEL_MATRIX[0].xyz) * (1.0 + wetness * 0.35);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(cc, 1.0));
	v_center = c;
	v_col = COLOR.rgb;
	v_on = lamp_on(COLOR.a * 2.0, INSTANCE_CUSTOM.r) * emp_factor(c);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	float core = exp(-r2 * 16.0);
	float glow = exp(-r2 * 4.0);
	float a = (core * 0.9 + glow * 0.45) * (1.0 - smoothstep(0.7, 1.0, r2));
	float d = distance(CAMERA_POSITION_WORLD, v_center);
	float fade = smoothstep(0.8, 3.0, d) * (1.0 - smoothstep(110.0, 160.0, d));
	// distant halos grow a little relative to the lamp so the street reads as a string of lights
	float far = mix(1.0, 1.6, smoothstep(20.0, 90.0, d));
	ALBEDO = v_col * strength * (0.75 + 0.5 * wetness) * far;
	ALPHA = clamp(a * fade * v_on, 0.0, 1.0);
}
