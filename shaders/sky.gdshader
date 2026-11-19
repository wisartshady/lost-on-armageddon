shader_type sky;
// Photographic skies (Poly Haven "pure sky" HDRIs, CC0, tonemapped by tools/make_skies.py), blended by weather and
// time of day: clear / cloudy / overcast by `cover`, a sunset sky when the sun is low, a cloudy night sky lit by
// the city. Each panorama is turned so the sun in the photo sits where the game's sun is, and its height is warped
// so the photo's sun also rises and sets with it. Set from scripts/world/world.gd; no TIME (the sky is cached).
uniform sampler2D sky_clear : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_cloudy : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_overcast : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_dusk : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_night : source_color, filter_linear_mipmap, repeat_enable;
// x clear, y cloudy, z overcast, w dusk: horizontal turn (fraction of a full turn)
uniform vec4 turn = vec4(0.0);
// x clear, y cloudy, z overcast, w dusk: elevation of the sun in the photo (radians)
uniform vec4 photo_sun_el = vec4(0.836, 1.024, 0.396, 0.049);
uniform float night_turn = 0.0;
uniform float daylight = 0.0;
uniform float cover = 1.0;
uniform float dusk = 0.0;
uniform float lightning_v = 0.0;
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.2);
uniform vec3 sun_col = vec3(1.0, 0.95, 0.88);
uniform vec3 city_glow : source_color = vec3(0.30, 0.19, 0.11);

// game elevation -> photo elevation, so the photo's sun follows the game sun
float warp(float e, float es, float ep) {
	es = max(es, 0.14);
	if (e < es) return e * (ep / es);
	return ep + (e - es) * (1.5708 - ep) / max(1.5708 - es, 0.01);
}

vec3 pano(sampler2D t, vec3 d, float tu, float es, float ep) {
	float az = atan(d.x, -d.z) * 0.15915494 + 0.5;
	float e = asin(clamp(d.y, 0.0, 1.0));
	float v = 1.0 - warp(e, es, ep) / 1.5708;
	return texture(t, vec2(az + tu, clamp(v, 0.002, 0.998))).rgb;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sd = normalize(sun_dir);
	float es = asin(clamp(sd.y, 0.0, 1.0));
	vec3 dd = vec3(d.x, max(h, 0.0), d.z);
	// --- day: three cloud states
	float w_clear = 1.0 - smoothstep(0.2, 0.62, cover);
	float w_over = smoothstep(0.72, 0.96, cover);
	float w_cloudy = max(1.0 - w_clear - w_over, 0.0);
	vec3 day = vec3(0.0);
	if (w_clear > 0.001) day += pano(sky_clear, dd, turn.x, es, photo_sun_el.x) * w_clear;
	if (w_cloudy > 0.001) day += pano(sky_cloudy, dd, turn.y, es, photo_sun_el.y) * w_cloudy;
	if (w_over > 0.001) day += pano(sky_overcast, dd, turn.z, es, photo_sun_el.z) * w_over;
	// low sun: the sunset photo, greyer and darker under heavy cloud
	if (dusk > 0.001) {
		vec3 ds = pano(sky_dusk, dd, turn.w, es, photo_sun_el.w);
		float lum = dot(ds, vec3(0.3, 0.55, 0.15));
		ds = mix(ds, vec3(lum) * vec3(1.04, 0.98, 0.94), cover * 0.7) * mix(1.0, 0.7, cover);
		day = mix(day, ds, dusk);
	}
	// --- night: cloudy sky lit from below by the city, warmer and brighter towards the horizon
	vec3 night = pano(sky_night, dd, night_turn, 0.6, 0.6) * 0.8;
	night += city_glow * pow(1.0 - clamp(h, 0.0, 1.0), 4.0) * 0.55;
	vec3 col = mix(night, day, daylight);
	// below the horizon (only seen through gaps): continue the horizon colour, a little darker
	if (h < 0.0) col *= mix(1.0, 0.82, smoothstep(0.0, -0.25, h));
	// the sun itself when it is not hidden by cloud
	float s = max(dot(d, sd), 0.0);
	float open = (1.0 - cover * 0.95) * daylight;
	col += sun_col * (smoothstep(0.99962, 0.99982, s) * 6.0 + pow(s, 900.0) * 0.5) * open;
	col += lightning_v * vec3(0.5, 0.55, 0.7) * (0.35 + 0.65 * smoothstep(0.0, 0.4, h));
	COLOR = col;
}
