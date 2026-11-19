shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Upper-floor facades of the big city in ONE quad per wall: the wall texture comes from the surface arrays
// (world-space mapping), and the window grid, frames, sills, lintels and the rooms behind the glass are drawn here.
//   UV      = (bay coordinate, floor coordinate): integer part = bay / floor index, fraction = position in the cell
//   UV2     = (surface layer, window style)
//   COLOR   = rgb wall tint, a = building seed
// Window styles (rows of WS0/WS1/WS2): see tools/facades.py
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 p0[24]; // uv_scale, rough_dry, rough_wet, porosity
uniform vec4 p1[24]; // normal_depth, grime, specular, reflect
uniform bool use_normal = true;
uniform float brightness = 1.0;
global uniform float window_detail;
#include "res://shaders/facade_styles.gdshaderinc"

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying flat int v_layer;
varying flat int v_style;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_layer = int(UV2.x + 0.5);
	v_style = int(UV2.y + 0.5);
}

// room behind one window cell (flats / offices), cell-local uv 0..1
vec3 room(vec2 uv, vec3 rd, float seed, float office, float lit, out float depth) {
	float D = office > 0.5 ? 1.8 : 1.1 * (0.8 + 0.4 * fract(seed * 3.7));
	vec3 ro = vec3(uv, 0.0);
	vec3 inv = 1.0 / (rd + vec3(1e-5));
	float tx = (rd.x > 0.0 ? (1.0 - ro.x) : (-ro.x)) * inv.x;
	float ty = (rd.y > 0.0 ? (1.0 - ro.y) : (-ro.y)) * inv.y;
	float tz = -D * inv.z;
	float t = min(min(tx, ty), tz);
	vec3 h = ro + rd * t;
	depth = t;
	vec3 hc = hash31(seed * 113.0);
	vec3 wall = mix(vec3(0.42, 0.36, 0.3), vec3(0.55, 0.52, 0.45), hc.x);
	if (office > 0.5) wall = vec3(0.62, 0.62, 0.6);
	vec3 c;
	if (t == tz) {
		c = wall;
		if (office > 0.5) {
			// partitions, desks with monitors
			float desk = step(h.y, 0.38) * step(0.3, h.y);
			c = mix(c, vec3(0.25, 0.24, 0.22), desk);
			float mon = step(abs(fract(h.x * 2.0) - 0.5), 0.12) * step(0.38, h.y) * step(h.y, 0.5);
			c = mix(c, vec3(0.25, 0.45, 0.6) * 1.6, mon * step(0.4, hc.y));
		} else {
			float fr = step(abs(h.x - 0.3 - hc.z * 0.4), 0.12) * step(abs(h.y - 0.62), 0.1);
			c = mix(c, vec3(0.15, 0.1, 0.08), fr);
			float sofa = step(h.y, 0.25) * step(0.2, h.x) * step(h.x, 0.8);
			c = mix(c, vec3(0.2, 0.12, 0.1), sofa * step(0.4, hc.x));
		}
	} else if (t == ty) {
		if (rd.y > 0.0) {
			c = vec3(0.42, 0.41, 0.4);
			if (office > 0.5) c = mix(c, vec3(1.6), step(abs(fract(h.x * 1.5) - 0.5), 0.2) * step(abs(fract(-h.z * 0.8) - 0.5), 0.15));
		} else {
			c = office > 0.5 ? vec3(0.3, 0.31, 0.33) : mix(vec3(0.22, 0.15, 0.1), vec3(0.26, 0.26, 0.28), hc.z);
		}
	} else {
		c = wall * 0.85;
	}
	float s = fract(seed * 7.13);
	vec3 lamp = s < 0.5 ? vec3(1.0, 0.72, 0.42) : (s < 0.75 ? vec3(1.0, 0.85, 0.65) : (s < 0.9 ? vec3(0.75, 0.85, 1.0) : vec3(0.35, 0.5, 1.0)));
	if (office > 0.5) lamp = vec3(0.9, 0.95, 1.0);
	bool tv = office < 0.5 && s > 0.9;
	float tvf = tv ? 0.6 + 0.4 * noise2(vec2(TIME * 4.0, seed * 30.0)) : 1.0;
	float depthk = clamp(-h.z / D, 0.0, 1.0);
	float fall = mix(1.0, 0.55, depthk) * (0.6 + 0.4 * h.y);
	return c * (lamp * fall * lit * tvf + room_amb());
}

void fragment() {
	int L = v_layer;
	vec4 a = p0[L];
	vec4 b = p1[L];
	vec3 n = normalize(v_wnrm);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), n));
	// wall texture: metres along the wall / up
	vec2 wuv = vec2(dot(v_wpos, right), -v_wpos.y) * a.x;
	vec4 texa = texture(albedo_arr, vec3(wuv, float(L)));
	float macro = tnoise(v_wpos.xz * 0.11 + v_wpos.y * 0.07) * 0.6 + tnoise(v_wpos.xz * 0.37 + v_wpos.yy * 0.2) * 0.4;
	vec3 alb = texa.rgb * COLOR.rgb * brightness * (0.82 + 0.36 * macro);
	float rough = mix(a.y, texa.a, 0.6);
	float spec = b.z;
	// window cell
	vec4 S0 = WS0[v_style];   // x: window width frac, y: window height frac, z: sill (bottom) frac, w: kind (0 punched, 1 ribbon, 2 curtain glass, 3 arched)
	vec4 S1 = WS1[v_style];   // x: frame width, y: frame tint, z: lit fraction, w: office
	vec4 S2 = WS2[v_style];   // x: sill depth look, y: lintel, z: band every n floors, w: mullions per window
	vec2 cell = floor(UV);
	vec2 f = fract(UV);
	float seed = fract(sin(dot(cell + COLOR.a * 97.0, vec2(12.9898, 78.233))) * 43758.5453);
	float kind = S0.w;
	float hw = S0.x * 0.5;
	vec2 wmin = vec2(0.5 - hw, S0.z);
	vec2 wmax = vec2(0.5 + hw, S0.z + S0.y);
	if (kind > 0.5 && kind < 1.5) { wmin.x = 0.0; wmax.x = 1.0; }      // ribbon windows run through the bays
	if (kind > 1.5 && kind < 2.5) { wmin = vec2(0.0, 0.0); wmax = vec2(1.0); }  // glass curtain wall
	float inside = step(wmin.x, f.x) * step(f.x, wmax.x) * step(wmin.y, f.y) * step(f.y, wmax.y);
	if (kind > 2.5) {
		// arched top
		vec2 c2 = vec2(0.5, wmax.y - hw * 0.9);
		if (f.y > c2.y && length((f - c2) * vec2(1.0, 0.9)) > hw) inside = 0.0;
	}
	vec3 col;
	float emi = 0.0;
	if (inside > 0.5) {
		vec2 wf = (f - wmin) / max(wmax - wmin, vec2(1e-3));
		vec3 V = normalize(v_wpos - CAMERA_POSITION_WORLD);
		vec3 rd = vec3(dot(V, right), V.y, dot(V, n));
		float lit = step(seed, S1.z * mix(1.0, 0.3, daylight)) * emp_factor(v_wpos);
		float d;
		vec3 rc;
		// far windows (a few pixels each, behind fog): the room's average colour instead of tracing the room
		float sl = fract(seed * 7.13);
		vec3 flamp = sl < 0.5 ? vec3(1.0, 0.72, 0.42) : (sl < 0.75 ? vec3(1.0, 0.85, 0.65) : (sl < 0.9 ? vec3(0.75, 0.85, 1.0) : vec3(0.35, 0.5, 1.0)));
		if (S1.w > 0.5) flamp = vec3(0.9, 0.95, 1.0);
		vec3 flat_c = flamp * 0.3 * lit + room_amb() * 0.38;
		float lodk = smoothstep(60.0, 76.0, distance(CAMERA_POSITION_WORLD, v_wpos));
		if (window_detail < 0.5 || lodk > 0.999) {
			rc = flat_c;
		} else {
			rc = mix(room(wf, rd, seed, S1.w, lit, d), flat_c, lodk);
			// curtains / blinds on flats
			float cur = fract(seed * 13.37);
			if (S1.w < 0.5 && cur > 0.62) {
				float cw = 0.16 + 0.2 * fract(cur * 13.0);
				float m = step(wf.x, cw) + step(1.0 - cw, wf.x);
				vec3 cc = hash31(cur * 77.0) * 0.5 + 0.2;
				rc = mix(rc, cc * (0.75 + 0.25 * sin(wf.x * 60.0)) * (lit > 0.5 ? vec3(0.9, 0.7, 0.45) : vec3(0.03)), clamp(m, 0.0, 1.0));
			} else if (cur > 0.42) {
				float bl = step(0.45, fract(wf.y * 14.0)) * step(0.35 + fract(cur * 9.0) * 0.5, wf.y);
				rc = mix(rc, (lit > 0.5 ? vec3(0.55, 0.45, 0.32) : vec3(0.03)), bl);
			}
		}
		// mullions and transoms
		float mn = S2.w;
		float fw = S1.x;
		float mull = 0.0;
		if (mn > 0.5) mull = step(abs(fract(wf.x * mn) - 0.5) * 2.0, fw * 4.0 * mn);
		if (kind < 1.5) mull += step(abs(wf.y - 0.62), fw * 1.2);
		float edge = step(wf.x, fw) + step(1.0 - fw, wf.x) + step(wf.y, fw) + step(1.0 - fw, wf.y);
		if (kind > 1.5 && kind < 2.5) {
			// curtain wall: spandrel band at slab level hides the floor edge
			float spand = step(wf.y, 0.16);
			rc = mix(rc, vec3(0.05, 0.06, 0.07), spand);
			edge = step(wf.x, 0.012) + step(0.988, wf.x) + step(abs(wf.y - 0.16), 0.008);
		}
		vec3 frame_c = mix(vec3(0.85, 0.83, 0.78), vec3(0.08, 0.08, 0.09), S1.y);
		float fr = clamp(edge + mull, 0.0, 1.0);
		// glass reflection of the street lights and the sky
		float fres = pow(1.0 - clamp(abs(dot(V, n)), 0.0, 1.0), 3.0);
		vec3 refl = light_field_at(v_wpos, n) * 0.22 + vec3(0.02, 0.025, 0.035) + sky_fill(v_wpos, n) * 0.4
			+ env_reflect(reflect(V, n), v_wpos, 0.06) * daylight * 0.55;
		if (kind > 1.5 && kind < 2.5) {
			vec3 gt = GLASS_TINT[clamp(int(S2.x + 0.5), 0, 3)];
			refl *= 1.8 * gt;
			rc *= mix(vec3(1.0), gt, 0.6);
		}
		col = rc + refl * (0.3 + 1.3 * fres);
		col = mix(col, frame_c * (light_field_at(v_wpos, n) * 0.8 + vec3(0.06, 0.065, 0.08) + day_light(n) * 0.9), fr);
		emi = 1.0 - fr;
		rough = 0.08;
		spec = 0.6;
	} else {
		// sill under the window and a lintel above it (punched / arched)
		float sill = step(abs(f.x - 0.5), hw + 0.04) * step(wmin.y - 0.035, f.y) * step(f.y, wmin.y);
		float lint = step(abs(f.x - 0.5), hw + 0.02) * step(wmax.y, f.y) * step(f.y, wmax.y + 0.03) * S2.y;
		float band = 0.0;
		if (S2.z > 0.5) band = step(mod(cell.y, S2.z), 0.5) * step(f.y, 0.05);
		float shadow = step(abs(f.x - 0.5), hw) * step(wmin.y - 0.08, f.y) * step(f.y, wmin.y - 0.035);
		alb = mix(alb, alb * 0.55, shadow * (kind < 1.5 ? 1.0 : 0.0));
		alb = mix(alb, vec3(0.62, 0.6, 0.56) * COLOR.rgb * 0.9, clamp(sill + lint + band, 0.0, 1.0));
		col = vec3(0.0);
	}
	if (inside > 0.5) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = rough;
		SPECULAR = spec;
		EMISSION = col;
	} else {
		float vertical = step(abs(v_wnrm.y), 0.5);
		alb *= 1.0 - b.y * (1.0 - smoothstep(0.0, 1.8, v_wpos.y)) * vertical;
		float w = clamp(wetness, 0.0, 1.0) * 0.55;
		alb *= 1.0 - a.w * 0.45 * w;
		ALBEDO = alb;
		ROUGHNESS = mix(rough, a.z, w);
		SPECULAR = spec;
		if (use_normal && b.x > 0.01) {
			NORMAL_MAP = texture(normal_arr, vec3(wuv, float(L))).rgb;
			NORMAL_MAP_DEPTH = b.x;
		}
		vec3 lf = light_field_at(v_wpos, v_wnrm);
		EMISSION = alb * lf + alb * lightning * vec3(0.55, 0.6, 0.75) * 0.35;
	}
}
