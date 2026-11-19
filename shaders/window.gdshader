shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/interior_types.gdshaderinc"
// Fake interiors ("interior mapping") behind every window – no extra geometry.
// Flats:  COLOR r = seed, g = lit, b = kind (0 flat, 1 office), a = curtains.
// Shops:  COLOR r = interior type (x/32), g = lit, b = kind (.5 window, .6/.62 chinese, .75 door, .85 tea, .9 lobby),
//         a = variant; UV = position in the room in metres (x along the wall, y above the floor),
//         UV2 = (room width, room depth). The room is rendered from Blender layers (tools/interiors_blender.py):
//         back wall, side walls, floor/ceiling, a midground card (counters, racks) and the window display.
global uniform float window_detail;
uniform bool shop = false;
uniform float room_depth = 1.1;
uniform sampler2DArray int_back : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray int_side : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray int_mid : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray int_front : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray int_fc : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec2 v_room;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_room = UV2;
}

vec3 lamp_colour(float seed, float kind) {
	float s = fract(seed * 7.13);
	if (s < 0.5) return vec3(1.0, 0.72, 0.42);
	if (s < 0.75) return vec3(1.0, 0.85, 0.65);
	if (s < 0.9) return vec3(0.75, 0.85, 1.0);
	return vec3(0.35, 0.5, 1.0); // TV glow
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
	float curtain = COLOR.a;
	vec2 uv = UV;
	vec3 n = normalize(v_wnrm);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	vec3 vd = normalize(v_wpos - CAMERA_POSITION_WORLD);
	vec3 rd = vec3(dot(vd, right), vd.y, dot(vd, n));
	vec3 col;
	float frame = 0.0;
	if (shop) {
		int ti = clamp(int(seed * 32.0), 0, INT_TYPES - 1);
		float lodk = smoothstep(55.0, 70.0, distance(CAMERA_POSITION_WORLD, v_wpos));
		vec3 flat_c = INT_LAMP[ti] * 0.34 * lit + room_amb() * 0.4;
		if (window_detail < 0.5 || lodk > 0.999) {
			col = flat_c;
		} else {
			float dh;
			col = mix(shop_room(uv, rd, seed, kind, lit, curtain, dh), flat_c, lodk);
		}
		// glass, frames and door hardware in room metres
		float W = max(v_room.x, 0.6);
		// grime: low-frequency smudges, dirtier towards the bottom of the pane
		float g = noise2(v_wpos.xz * 2.3 + v_wpos.y * 1.7) * 0.6 + noise2(v_wpos.xz * 9.0 + v_wpos.y * 7.0) * 0.4;
		float dirt = (0.05 + 0.12 * g) * (1.0 - smoothstep(0.3, 1.6, uv.y));
		col = mix(col, vec3(0.05, 0.05, 0.045), dirt);
		// rain on the glass
		if (wetness > 0.05) {
			float colm = floor(v_wpos.x * 31.0 + v_wpos.z * 31.0);
			float sp = 0.6 + hash11(colm) * 1.4;
			float drip = fract(v_wpos.y * 1.3 + TIME * sp * 0.25 + hash11(colm * 3.1));
			float streak = smoothstep(0.92, 1.0, drip) * step(0.55, hash11(colm * 7.7));
			float beads = smoothstep(0.82, 1.0, noise2(vec2(v_wpos.x + v_wpos.z, v_wpos.y) * 38.0));
			col += (streak * 0.35 + beads * 0.12) * wetness * (light_field_at(v_wpos, n) * 0.6 + 0.04);
		}
	} else {
		vec3 lamp = lamp_colour(seed, kind);
		lit *= step(fract(seed * 5.31), mix(1.0, 0.3, daylight));   // fewer lamps on by day
		bool tv = fract(seed * 7.13) > 0.9;
		float tvflick = tv ? 0.6 + 0.4 * noise2(vec2(TIME * 4.0, seed * 30.0)) : 1.0;
		float flod = smoothstep(60.0, 76.0, distance(CAMERA_POSITION_WORLD, v_wpos));
		vec3 fflat = lamp * 0.3 * lit * tvflick + room_amb() * 0.38;
		if (window_detail < 0.5 || flod > 0.999) {
			col = fflat;
		} else {
			float D = room_depth * (0.8 + 0.4 * fract(seed * 3.7));
			vec3 ro = vec3(uv.x, uv.y, 0.0);
			vec3 inv = 1.0 / (rd + vec3(1e-5));
			float tx = (rd.x > 0.0 ? (1.0 - ro.x) : (-ro.x)) * inv.x;
			float ty = (rd.y > 0.0 ? (1.0 - ro.y) : (-ro.y)) * inv.y;
			float tz = (-D - ro.z) * inv.z;
			float t = min(min(tx, ty), tz);
			vec3 h = ro + rd * t;
			vec3 hc = hash31(seed * 113.0);
			vec3 wall = mix(vec3(0.42, 0.36, 0.3), vec3(0.55, 0.52, 0.45), hc.x);
			if (hc.y > 0.7) wall = vec3(0.32, 0.38, 0.36);
			vec3 c;
			float depthk = clamp(-h.z / D, 0.0, 1.0);
			if (t == tz) {
				c = wall;
				float fr = step(abs(h.x - 0.3 - hc.z * 0.4), 0.12) * step(abs(h.y - 0.62), 0.1);
				c = mix(c, vec3(0.15, 0.1, 0.08), fr);
				float sofa = step(h.y, 0.25) * step(0.2, h.x) * step(h.x, 0.8);
				c = mix(c, vec3(0.2, 0.12, 0.1), sofa * step(0.4, hc.x));
			} else if (t == ty) {
				c = rd.y < 0.0 ? mix(vec3(0.22, 0.15, 0.1), vec3(0.26, 0.26, 0.28), hc.z) : vec3(0.42, 0.41, 0.4);
			} else {
				c = wall * 0.85;
			}
			float ceiling_light = rd.y > 0.0 && t == ty ? 1.25 : 1.0;
			float fall = mix(1.0, 0.55, depthk) * (0.6 + 0.4 * h.y) * ceiling_light;
			col = c * (lamp * fall * lit * tvflick + room_amb());
			if (curtain > 0.62) {
				float cw = 0.18 + 0.2 * fract(curtain * 13.0);
				float m = step(uv.x, cw) + step(1.0 - cw, uv.x);
				float folds = 0.75 + 0.25 * sin(uv.x * 60.0);
				vec3 cc = hash31(curtain * 77.0) * 0.5 + 0.2;
				col = mix(col, cc * folds * (lit > 0.5 ? lamp * 0.9 : vec3(0.03)), clamp(m, 0.0, 1.0));
			} else if (curtain > 0.4) {
				float bl = step(0.45, fract(uv.y * 14.0)) * step(0.35 + fract(curtain * 9.0) * 0.5, uv.y);
				col = mix(col, (lit > 0.5 ? lamp * 0.55 : vec3(0.03)), bl);
			}
			col = mix(col, fflat, flod);
		}
		float fw = 0.06;
		frame = step(uv.x, fw) + step(1.0 - fw, uv.x) + step(uv.y, fw) + step(1.0 - fw, uv.y);
		frame += step(abs(uv.y - 0.52), 0.025);
		if (kind < 0.5) frame += step(abs(uv.x - 0.5), 0.018);
	}
	vec3 frame_base = vec3(0.12, 0.11, 0.1) + vec3(0.5) * hash31(seed * 5.0).x * (shop ? 0.15 : 1.0);
	vec3 frame_col = frame_base * (vec3(0.05, 0.055, 0.075) + light_field_at(v_wpos, n) * 0.8 + lightning * vec3(0.4) + day_light(n) * 0.9);
	// glass reflection of the street lights
	float fres = pow(1.0 - clamp(abs(dot(vd, n)), 0.0, 1.0), 3.0);
	vec3 refl = light_field_at(v_wpos, n) * 0.25 + vec3(0.02, 0.025, 0.035) + env_reflect(reflect(vd, n), v_wpos, 0.06) * daylight * 0.5;
	col = col + refl * (0.3 + 1.2 * fres);
	ALBEDO = mix(col, frame_col, clamp(frame, 0.0, 1.0));
}
