shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
#include "res://shaders/common.gdshaderinc"
// Fake light shaft under a street lamp: an open cone, bright at the bulb, soft at the silhouette, with falling rain in it.
// MultiMesh: COLOR.rgb = lamp colour, COLOR.a = state / 2, custom.r = seed. UV.y: 0 at the bulb, 1 on the ground.
uniform float strength = 0.2;
varying vec3 v_wpos;
varying vec3 v_wn;
varying vec3 v_col;
varying float v_on;
varying vec3 v_top;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_top = MODEL_MATRIX[3].xyz;
	v_col = COLOR.rgb;
	v_on = lamp_on(COLOR.a * 2.0, INSTANCE_CUSTOM.r) * emp_factor(v_top);
}
void fragment() {
	// soft silhouette from the horizontal view angle (the cone is round around a vertical axis)
	vec2 nh = normalize(v_wpos.xz - v_top.xz + vec2(1e-4));
	vec2 vh = normalize(CAMERA_POSITION_WORLD.xz - v_wpos.xz + vec2(1e-4));
	float edge = abs(dot(nh, vh));
	edge = pow(edge, 1.5);
	float down = UV.y;
	float vert = pow(1.0 - down, 1.6) * smoothstep(0.0, 0.06, down);
	float rain = 0.75 + 0.5 * noise2(vec2(UV.x * 48.0, down * 6.0 - TIME * 9.0)) * wetness;
	float near = smoothstep(0.6, 2.5, distance(CAMERA_POSITION_WORLD, v_wpos));
	float far = 1.0 - smoothstep(70.0, 110.0, distance(CAMERA_POSITION_WORLD, v_top));
	ALBEDO = v_col * strength * (0.45 + 0.75 * wetness);
	ALPHA = clamp(edge * vert * rain * near * far * v_on * 1.2, 0.0, 1.0);
}
