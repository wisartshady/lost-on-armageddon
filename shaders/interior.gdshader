shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/interior_types.gdshaderinc"
// Real 3D shop interiors (tools/shop_interiors.py) seen through the shop windows. Light is baked in the shader:
// the room's ceiling lamps (colour per trade, knocked out by the symbiote pulse), daylight falling in through the
// window and fading towards the back, vertex occlusion in COLOR.a, fake reflections of the ceiling panels on
// glossy, metal and mirror parts. UV = surface metres (0..1 on labels), UV2.x = part, UV2.y = floor pattern.
uniform vec4 room_front = vec4(0.0);    // xyz: window plane point at floor level, w: room type index
uniform vec4 room_in = vec4(0.0, 0.0, 1.0, 1.0);  // xyz: direction into the room, w: lights on (0/1)
uniform vec4 room_size = vec4(5.0, 3.375, 6.0, 0.0);  // width, height, depth
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_part;
varying float v_pat;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_part = UV2.x;
	v_pat = UV2.y;
}

// 1 where a pattern of this cell size is resolved on screen, 0 where it would only alias (far / grazing)
float aa_k(vec2 p, float cell) {
	vec2 w = fwidth(p) / cell;
	return 1.0 - smoothstep(0.12, 0.45, max(w.x, w.y));
}

float floor_pattern(vec2 p, float pat, out float gloss) {
	gloss = 0.0;
	if (pat < 0.5) {            // checker tiles
		vec2 c = floor(p / 0.3);
		float k = mod(c.x + c.y, 2.0);
		vec2 g = abs(fract(p / 0.3) - 0.5);
		float grout = step(0.47, max(g.x, g.y)) * aa_k(p, 0.3);
		gloss = 0.7;
		return mix(mix(mix(0.22, 1.25, k), 0.73, 1.0 - aa_k(p, 0.6)), 0.5, grout);
	} else if (pat < 1.5) {     // wood planks
		float row = floor(p.y / 0.14);
		float x = p.x + hash11(row * 3.7) * 2.0;
		float plank = floor(x / 1.2);
		float tone = 0.8 + 0.35 * hash12(vec2(row, plank));
		float grain = 0.92 + 0.08 * sin(x * 38.0 + noise2(vec2(x * 2.0, row)) * 6.0);
		float seam = (step(0.94, fract(p.y / 0.14)) + step(0.995, fract(x / 1.2))) * aa_k(p, 0.14);
		gloss = 0.35;
		return tone * grain * (1.0 - 0.45 * clamp(seam, 0.0, 1.0));
	} else if (pat < 2.5) {     // terrazzo
		float chips = step(0.72, noise2(p * 22.0)) * 0.35 + step(0.8, noise2(p * 41.0 + 7.0)) * 0.25;
		gloss = 0.8;
		return 0.9 + chips - 0.12 * noise2(p * 1.5);
	} else if (pat < 3.5) {     // carpet
		gloss = 0.0;
		return 0.85 + 0.15 * noise2(p * 60.0) - 0.1 * noise2(p * 2.0);
	}
	vec2 g = abs(fract(p / 0.2) - 0.5);   // small square tiles
	gloss = 0.6;
	return mix(1.0, 0.7, step(0.46, max(g.x, g.y)) * aa_k(p, 0.2));
}

// wall finishes (UV = metres along the wall, height): 0 paint, 1 wainscot, 2 tiles, 3 brick, 4 boards
vec3 wall_finish(vec3 alb, vec2 p, float pat) {
	if (pat < 0.5) {
		return alb * (0.93 + 0.07 * noise2(p * 3.0) + 0.04 * noise2(p * 19.0));
	} else if (pat < 1.5) {
		if (p.y < 1.0) {
			float groove = step(0.96, fract(p.x / 0.6)) * aa_k(p, 0.6);
			return alb * 0.62 * (1.0 - 0.35 * groove) * (0.95 + 0.05 * noise2(p * 8.0));
		}
		float rail = step(p.y, 1.06);
		return alb * mix(0.93 + 0.07 * noise2(p * 3.0), 1.1, rail);
	} else if (pat < 2.5) {
		if (p.y < 1.8) {
			vec2 g = abs(fract(p / vec2(0.15, 0.075)) - 0.5);
			float grout = (step(0.465, g.x) + step(0.44, g.y)) * aa_k(p, 0.075);
			vec3 tile = mix(vec3(0.9, 0.9, 0.87), alb, 0.25) * (0.97 + 0.06 * hash12(floor(p / vec2(0.15, 0.075))));
			return mix(tile, tile * 0.78, clamp(grout, 0.0, 1.0));
		}
		float trim = step(p.y, 1.86);
		return mix(alb * (0.95 + 0.05 * noise2(p * 3.0)), alb * 0.45, trim);
	} else if (pat < 3.5) {
		float row = floor(p.y / 0.075);
		float x = p.x / 0.215 + mod(row, 2.0) * 0.5;
		vec2 f = vec2(fract(x), fract(p.y / 0.075));
		float k = aa_k(p, 0.075);
		float mortar = (step(0.94, f.x) + step(0.86, f.y)) * k;
		vec3 brick = mix(vec3(0.42, 0.2, 0.13), alb, 0.35) * mix(0.97, 0.8 + 0.35 * hash12(vec2(floor(x), row)), k);
		return mix(brick, vec3(0.5, 0.47, 0.42) * 0.7, clamp(mortar, 0.0, 1.0));
	}
	float board = floor(p.x / 0.12);
	float seam = step(0.95, fract(p.x / 0.12)) * aa_k(p, 0.12);
	return alb * (0.8 + 0.3 * hash11(board * 3.3)) * (0.9 + 0.1 * sin(p.y * 30.0 + noise2(vec2(board, p.y * 2.0)) * 6.0)) * (1.0 - 0.5 * seam);
}

void fragment() {
	vec3 N = normalize(v_wnrm);
	vec3 V = normalize(v_wpos - CAMERA_POSITION_WORLD);
	vec3 R = reflect(V, N);
	vec3 alb = COLOR.rgb;
	float ao = COLOR.a;
	int ti = clamp(int(room_front.w + 0.5), 0, INT_TYPES - 1);
	float on = room_in.w * emp_factor(v_wpos);
	vec3 lamp = INT_LAMP[ti] * on;
	vec3 rin = normalize(room_in.xyz);
	float depth = max(dot(v_wpos - room_front.xyz, rin), 0.0);
	float h = v_wpos.y - room_front.y;
	vec3 rright = normalize(cross(rin, vec3(0.0, 1.0, 0.0)));
	float rx = dot(v_wpos - room_front.xyz, rright);
	// soft darkening into the corners and along the walls (where the ceiling lights reach less)
	float edge = min(min(abs(rx), abs(room_size.x - rx)), abs(room_size.z - depth));
	float corner = mix(0.7, 1.0, smoothstep(0.0, 1.4, edge)) * mix(0.72, 1.0, smoothstep(0.0, 1.3, h)) * mix(1.0, 0.85, smoothstep(2.6, 3.3, h));
	// light pools under the ceiling panels (one every ~1.8 m)
	float pool = 0.88 + 0.12 * (0.5 + 0.5 * cos(rx * 3.49)) * (0.5 + 0.5 * cos(depth * 3.49));
	// ceiling lamps: strongest on what faces up, a soft bounce on walls and the ceiling, a little dimmer at the back
	float facing = mix(0.62, 1.0, clamp(N.y * 0.5 + 0.5, 0.0, 1.0));
	vec3 Lk = lamp * 0.98 * facing * corner * pool * mix(1.0, 0.82, clamp(depth / 7.0, 0.0, 1.0));
	// daylight through the window: falls off with depth, lights what faces the window
	float toward = clamp(dot(N, -rin) * 0.5 + 0.5, 0.0, 1.0);
	vec3 Ld = day_sky.rgb * daylight * (0.12 + 0.5 * exp(-depth * 0.45)) * mix(0.5, 1.0, toward);
	vec3 L = (Lk * 0.9 + Ld + vec3(0.01, 0.012, 0.018)) * ao;
	float gloss = 0.0;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float part = v_part;
	if (part < 0.5) {                       // matte paint, card, plastic
		gloss = 0.1;
	} else if (part < 1.5) {                // floor
		float g;
		alb *= floor_pattern(UV, v_pat, g);
		gloss = g;
	} else if (part < 2.5) {                // gloss: lacquer, vinyl, ceramics
		gloss = 0.75;
	} else if (part < 3.5) {                // light panel / bulb / lantern
		emit = alb * lamp * 1.7 + alb * 0.02;
		alb = vec3(0.0);
	} else if (part < 4.5) {                // screen
		vec2 cell = floor(UV * vec2(9.0, 6.0));
		float k = hash12(cell + floor(TIME * 0.4 + alb.r * 10.0));
		float scan = 0.85 + 0.15 * sin(UV.y * 300.0);
		emit = alb * (0.55 + 0.6 * k) * scan * on * 1.3;
		alb *= 0.05;
		gloss = 0.9;
	} else if (part < 5.5) {                // product label: a pale band with print on the coloured pack
		float band = step(0.38, UV.y) * step(UV.y, 0.72);
		float print = step(0.55, fract(UV.x * 7.0 + hash11(floor(UV.y * 9.0)) * 3.0)) * step(0.45, fract(UV.y * 9.0));
		vec3 pale = mix(vec3(0.92, 0.9, 0.85), alb * 0.3, print * 0.7);
		alb = mix(alb, pale, band * 0.85);
		gloss = 0.35;
	} else if (part < 6.5) {                // mirror: the room behind the viewer, mostly its lights
		emit = (lamp * (0.25 + 0.35 * clamp(R.y, 0.0, 1.0)) + Ld * 0.6) * vec3(0.9, 0.95, 1.0);
		alb *= 0.15;
		gloss = 1.0;
	} else if (part < 7.5) {                // walls
		alb = wall_finish(alb, UV, v_pat);
	} else if (part < 8.5) {                // glass (washing machine doors): dark, glossy
		alb *= 0.35;
		gloss = 1.0;
	} else if (part < 9.5) {                // metal
		metal = 1.0;
		gloss = 0.6;
	} else if (part < 10.5) {               // wood
		alb *= 0.86 + 0.14 * sin(UV.x * 45.0 + noise2(UV * vec2(3.0, 30.0)) * 5.0);
		gloss = 0.4;
	} else if (part < 11.5) {               // fabric
		alb *= 0.9 + 0.1 * noise2(UV * 90.0);
		gloss = 0.0;
	} else {                                // ceiling: drop-ceiling tiles, or plain dark paint
		if (v_pat < 0.5) {
			vec2 g = abs(fract(UV / 0.6) - 0.5);
			alb *= mix(1.0, 0.55, step(0.475, max(g.x, g.y))) * (0.96 + 0.04 * hash12(floor(UV / 0.6)));
		}
	}
	// fake reflection of the ceiling panels and window light (Fresnel), metals tint it with their colour
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(-dot(V, N), 0.0, 1.0), 5.0);
	float up = clamp(R.y, 0.0, 1.0);
	vec3 refl = lamp * (pow(up, 6.0) * 0.6 + 0.08) + Ld * 0.4 * clamp(dot(R, -rin), 0.0, 1.0);
	vec3 spec = refl * gloss * mix(fres, 1.0, metal) * mix(vec3(1.0), alb, metal);
	vec3 col = alb * L * mix(1.0, 0.35, metal) + spec * ao + emit;
	col += alb * lightning * vec3(0.3, 0.33, 0.4) * 0.15 * exp(-depth * 0.5);
	ALBEDO = col;
}
