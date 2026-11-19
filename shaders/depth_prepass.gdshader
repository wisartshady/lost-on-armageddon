shader_type spatial;
// Depth-only pre-pass for the big city meshes: drawn first (higher render priority), so the expensive lit city
// shader afterwards only runs on the pixels that end up visible (early depth test) instead of shading every wall
// behind the nearest one. The colour written here is always overwritten by the real pass at the same depth.
render_mode unshaded, cull_back, depth_draw_always, shadows_disabled, fog_disabled, ambient_light_disabled;
uniform float push = 0.00002;
void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// a hair further away than the real pass, so the real pass always wins the depth test even without
	// bit-identical positions (reverse-Z in Godot 4.3+: smaller z is further)
	POSITION.z -= push * POSITION.w;
}
void fragment() {
	ALBEDO = vec3(0.0);
}
