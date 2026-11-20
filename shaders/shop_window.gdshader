shader_type spatial;
render_mode unshaded, cull_back, blend_premul_alpha, depth_draw_never;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/interior_types.gdshaderinc"
// Shop windows and doors: real glass. Near the camera the pane is transparent (grime, rain, reflections of the
// street) and the furnished 3D room behind it shows through (tools/shop_interiors.py, shaders/interior.gdshader).
// Further away, where the rooms are no longer drawn, it fades to the old interior mapping (opaque), then to a flat
// lit colour. Transoms above building doors (kind .9) have no room behind them: frosted, dimly lit from inside.
// COLOR r = interior type (x/32), g = lit, b = kind (.5 window, .6/.62 chinese, .75 door, .85 tea, .9 transom),
// a = variant; UV = position in the room in metres; UV2 = (room width, room depth).
global uniform float window_detail;
uniform sampler2DArray int_back : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray int_side : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray int_mid : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray int_front : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray int_fc : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float near_end = 36.0;     // the 3D rooms are drawn up to here (city.gd: ROOM_RANGE)
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec2 v_room;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_room = UV2;
}

// ------------------------------------------------------------------------------------------- shop rooms
vec3 shop_room(vec2 uv, vec3 rd, float tsel, float kind, float lit, float var, out float depth_hit) {
	float W = max(v_room.x, 0.6);
	float D = max(v_room.y, 1.5);
	int ti = clamp(int(tsel * 32.0), 0, INT_TYPES - 1);
	float layer = float(ti);
	vec3 ro = vec3(clamp(uv.x, 0.0, W), clamp(uv.y, 0.0, INT_H), 0.0);
	vec3 inv = 1.0 / (rd + sign(rd) * 1e-5 + vec3(rd.x == 0.0 ? 1e-5 : 0.0, rd.y == 0.0 ? 1e-5 : 0.0, 0.0));
	float tx = rd.x > 0.0 ? (W - ro.x) * inv.x : -ro.x * inv.x;
	float ty = rd.y > 0.0 ? (INT_H - ro.y) * inv.y : -ro.y * inv.y;
	float tz = -D * inv.z;
	float t = min(min(tx, ty), tz);
	vec3 h = ro + rd * t;
	// per-shop offsets so neighbours of the same kind show different parts of the strips
	float ob = var * 41.0;
	vec3 c;
	float shade = 1.0;
	if (t == tz) {
		c = texture(int_back, vec3((h.x + ob) / INT_TILE, 1.0 - h.y / INT_H, layer)).rgb;
	} else if (t == tx) {
		float dep = -h.z;
		float u = (rd.x < 0.0 ? dep : -dep) + var * 17.0 + (rd.x < 0.0 ? 0.0 : 2.7);
		c = texture(int_side, vec3(u / INT_TILE, 1.0 - h.y / INT_H, layer)).rgb;
		shade = 0.9;
	} else {
		bool up = rd.y > 0.0;
		float fl = up ? INT_FLOORS + INT_CEIL[ti] : INT_FLOOR[ti];
		c = texture(int_fc, vec3(vec2(h.x + ob, -h.z) / 3.0, fl)).rgb;
		if (!up) {
			// floor: darker towards the walls, a soft sheen of the ceiling lights
			float edge = min(min(h.x, W - h.x), D + h.z);
			shade = mix(0.62, 0.95, smoothstep(0.0, 1.2, edge));
			shade += 0.18 * smoothstep(0.6, 1.0, sin(-h.z * 1.05 + 0.4) * 0.5 + 0.5) * smoothstep(0.2, 2.0, edge);
		} else {
			shade = 1.05;
		}
	}
	c *= shade;
	// midground card (counters, racks, tables)
	float Dm = clamp(D * INT_MID[ti], 1.2, max(D - 0.8, 1.25));
	float tm = -Dm * inv.z;
	if (tm < t) {
		vec3 pm = ro + rd * tm;
		if (pm.y >= 0.0 && pm.y <= INT_MID_H && pm.x >= 0.05 && pm.x <= W - 0.05) {
			vec4 m = texture(int_mid, vec3((pm.x + var * 23.0) / INT_TILE, 1.0 - pm.y / INT_MID_H, layer));
			c = mix(c, m.rgb, m.a);
			t = mix(t, tm, step(0.5, m.a));
		}
	}
	// window display right behind the glass (not through the door)
	if (kind < 0.7 && INT_FRONT[ti] > 0.5) {
		float tf = -INT_FRONT_Z * inv.z;
		vec3 pf = ro + rd * tf;
		if (pf.y >= 0.0 && pf.y <= INT_FRONT_H && pf.x >= 0.0 && pf.x <= W) {
			vec4 f = texture(int_front, vec3((pf.x + var * 13.0) / INT_TILE, 1.0 - pf.y / INT_FRONT_H, layer));
			c = mix(c, f.rgb, f.a);
			t = mix(t, tf, step(0.5, f.a));
		}
	}
	depth_hit = t;
	// the renders already carry the shop's light; tint it by the lamp colour and fade a little with depth
	vec3 lamp = INT_LAMP[ti];
	float fall = mix(1.0, 0.82, clamp(-h.z / 9.0, 0.0, 1.0));
	return c * lamp * fall * lit * 1.08 + c * room_amb();
}

void fragment() {
	float seed = COLOR.r;
	float lit = COLOR.g * emp_factor(v_wpos);
	float kind = COLOR.b;
	float var = COLOR.a;
	vec2 uv = UV;
	vec3 n = normalize(v_wnrm);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	vec3 vd = normalize(v_wpos - CAMERA_POSITION_WORLD);
	vec3 rd = vec3(dot(vd, right), vd.y, dot(vd, n));
	int ti = clamp(int(seed * 32.0), 0, INT_TYPES - 1);
	float dist = distance(CAMERA_POSITION_WORLD, v_wpos);
	bool transom = kind > 0.87;
	// how much of the real room shows through (1 near .. 0 where the rooms stop being drawn)
	float see = transom || window_detail < 0.5 ? 0.0 : 1.0 - smoothstep(near_end - 10.0, near_end - 2.0, dist);
	vec3 body = vec3(0.0);
	if (see < 0.999) {
		if (transom) {
			// frosted glass with the hall light behind it
			float frost = 0.85 + 0.15 * noise2(uv * 23.0);
			float glow = 0.75 + 0.25 * noise2(uv * 1.7 + var * 9.0);
			body = (INT_LAMP[ti] * 0.16 * lit * glow + room_amb() * 0.55 + vec3(0.015, 0.014, 0.013)) * frost;
		} else {
			vec3 flat_c = INT_LAMP[ti] * 0.34 * lit + room_amb() * 0.4;
			float lodk = smoothstep(55.0, 70.0, dist);
			if (window_detail < 0.5 || lodk > 0.999) {
				body = flat_c;
			} else {
				float dh;
				body = mix(shop_room(uv, rd, seed, kind, lit, var, dh), flat_c, lodk);
			}
		}
	}
	// grime: low-frequency smudges, dirtier towards the bottom of the pane
	float g = noise2(v_wpos.xz * 2.3 + v_wpos.y * 1.7) * 0.6 + noise2(v_wpos.xz * 9.0 + v_wpos.y * 7.0) * 0.4;
	float dirt = (0.05 + 0.12 * g) * (1.0 - smoothstep(0.3, 1.6, uv.y));
	vec3 dirt_c = vec3(0.05, 0.05, 0.045) * (light_field_at(v_wpos, n) * 0.8 + day_light(n) * 0.6 + 0.2);
	// rain on the glass
	vec3 wet = vec3(0.0);
	float wet_a = 0.0;
	if (wetness > 0.05) {
		float colm = floor(v_wpos.x * 31.0 + v_wpos.z * 31.0);
		float sp = 0.6 + hash11(colm) * 1.4;
		float drip = fract(v_wpos.y * 1.3 + TIME * sp * 0.25 + hash11(colm * 3.1));
		float streak = smoothstep(0.92, 1.0, drip) * step(0.55, hash11(colm * 7.7));
		float beads = smoothstep(0.82, 1.0, noise2(vec2(v_wpos.x + v_wpos.z, v_wpos.y) * 38.0));
		wet_a = (streak * 0.35 + beads * 0.12) * wetness;
		wet = wet_a * (light_field_at(v_wpos, n) * 0.6 + day_light(n) * 0.4 + 0.04);
	}
	// reflection of the street (Fresnel): the transoms reflect less (frosted)
	float fres = pow(1.0 - clamp(abs(dot(vd, n)), 0.0, 1.0), 3.0);
	vec3 refl = light_field_at(v_wpos, n) * 0.25 + vec3(0.02, 0.025, 0.035) + env_reflect(reflect(vd, n), v_wpos, 0.06) * daylight * 0.5;
	float rk = (0.3 + 1.2 * fres) * (transom ? 0.35 : 1.0);
	// opaque version (far / transom): body + reflection, as the old windows
	vec3 opaque = mix(body, vec3(0.05, 0.05, 0.045), dirt) + wet + refl * rk;
	// glass version: what it adds on top of the room behind it, and how much of the room it hides
	float a_glass = clamp(0.06 + 0.55 * fres + dirt * 0.8 + wet_a * 0.5, 0.0, 0.92);
	vec3 add = refl * rk * 0.8 + dirt_c * dirt + wet;
	ALBEDO = mix(opaque, add, see);
	ALPHA = mix(1.0, a_glass, see);
}
