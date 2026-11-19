shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, world_vertex_coords;
#include "res://shaders/common.gdshaderinc"
// Rain as individual falling drops (MultiMesh of thin quads). Every drop has a fixed place in the world and falls
// through a box that wraps around the camera, so there is rain right next to the player and far away, with no ring
// or cylinder; drops fade out well before the box edge so they never pop. Seen from below a drop is a vertical
// sliver, so looking up shows rain coming at you instead of drops "hitting" an invisible ceiling.
// INSTANCE_CUSTOM: xyz = position seed (0..1), w = size / speed seed.
uniform vec3 box = vec3(30.0, 18.0, 30.0);
uniform float speed = 6.6;           // m/s
uniform vec2 wind = vec2(0.6, 0.25); // m/s sideways drift
uniform float streak = 0.34;         // m (motion blur length at full speed)
uniform float brightness = 0.5;
uniform float amount = 1.0;          // 0..1 fraction of drops shown
uniform vec3 fall_offset = vec3(0.0); // distance fallen so far, wrapped by the script (keeps float precision)
varying float v_alpha;
varying vec3 v_col;
varying float v_u;

void vertex() {
	vec4 s = INSTANCE_CUSTOM;
	vec3 vel = vec3(wind.x, -speed, wind.y);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 base = s.xyz * box + fall_offset;
	vec3 p = mod(base - cam + box * 0.5, box) - box * 0.5 + cam;
	vec3 to_cam = cam - p;
	float d = length(to_cam);
	vec3 dir = normalize(vel);
	vec3 side = cross(dir, to_cam / max(d, 1e-3));
	side = side / max(length(side), 1e-3);
	// at least ~1 pixel wide at any distance; the alpha is scaled down to keep the same total light
	float w0 = 0.0042 * (0.8 + 0.4 * s.w);
	float w = max(w0, d * 0.0011);
	float len = streak * (0.75 + 0.5 * s.w);
	p += side * (UV.x - 0.5) * w + dir * (UV.y - 0.5) * len;
	VERTEX = p;
	// fades: very close (no huge drops in the lens), the edges of the box, the shown fraction
	vec3 rel = abs(p - cam) / (box * 0.5);
	float edge = 1.0 - smoothstep(0.62, 0.9, max(rel.x, rel.z));
	edge *= 1.0 - smoothstep(0.7, 0.95, rel.y);
	float near = smoothstep(0.35, 1.3, d);
	float shown = step(fract(s.x * 13.7 + s.z * 7.1), amount);
	v_alpha = edge * near * shown * (w0 / w);
	// drops are lit by what is around them: street lamps and signs at night, the grey sky by day
	vec3 l = lf_raw(p.xz) * emp_factor(p);
	l = l / (1.0 + max(max(l.r, l.g), l.b));
	v_col = (vec3(0.06, 0.07, 0.09) + l * 0.6 + day_sky.rgb * daylight * 0.32 + lightning * vec3(0.6)) * brightness;
	v_u = UV.y;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.35, v_u) * smoothstep(1.0, 0.6, v_u);
	ALBEDO = v_col * across * across * along * v_alpha;
}
