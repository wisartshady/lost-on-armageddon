// Shared helpers for all Lost on Armageddon world shaders.
global uniform sampler2D light_field : filter_linear_mipmap, repeat_disable;
global uniform vec4 light_field_rect;
global uniform float light_field_strength;
global uniform float wetness;
global uniform sampler2D env_map : source_color, filter_linear_mipmap, repeat_enable;
global uniform float lightning;
global uniform vec4 emp_zone_0;
global uniform vec4 emp_zone_1;
global uniform vec4 emp_zone_2;
global uniform vec4 emp_zone_3;
// time of day / weather (scripts/world/weather.gd via world.gd)
global uniform float daylight;          // 0 night .. 1 full day
global uniform float lamp_power;        // street lamps and lit windows: 1 at night, 0 by day
global uniform float rain_amount;       // 0 dry .. 1 storm
global uniform vec4 day_sky;            // rgb: sky light colour for unshaded surfaces, a: cloud cover
global uniform sampler2D env_map_day : source_color, filter_linear_mipmap, repeat_enable;
global uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;   // value noise, 64 cells per tile

float emp_one(vec4 z, vec3 p) {
	if (z.w <= 0.0) return 1.0;
	float d = distance(p.xz, z.xz);
	return smoothstep(z.w - 2.0, z.w + 0.5, d);
}

// 1 = powered, 0 = knocked out by the symbiote pulse
float emp_factor(vec3 p) {
	return min(min(emp_one(emp_zone_0, p), emp_one(emp_zone_1, p)), min(emp_one(emp_zone_2, p), emp_one(emp_zone_3, p)));
}

vec3 lf_raw(vec2 xz) {
	vec2 uv = (xz - light_field_rect.xy) / light_field_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec3(0.0);
	vec3 c = texture(light_field, uv).rgb;
	return c * c * light_field_strength * lamp_power;
}

// Night sky + city glow fill: cold from above, stronger high up (less occluded), so
// silhouettes and upper facades read instead of sinking into pure black.
vec3 sky_fill(vec3 p, vec3 n) {
	float up = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	float h = smoothstep(1.0, 28.0, p.y);
	// by day the real sun and sky ambient light the city; this night fill fades out
	return vec3(0.095, 0.11, 0.155) * mix(0.55, 1.0, up) * mix(0.8, 1.5, h) * (1.0 - daylight);
}

// Baked street lighting for a surface point with world normal n.
vec3 light_field_at(vec3 p, vec3 n) {
	vec3 c = lf_raw(p.xz + n.xz * 1.1);
	float hf = 1.0 - smoothstep(3.5, 13.0, p.y);
	if (n.y < -0.5) hf *= 0.45;
	float face = n.y > 0.5 ? 1.0 : 0.8;
	// lamps also wash the lower floors a little above their pool (soft bounce up the facade)
	float hf2 = (1.0 - smoothstep(6.0, 22.0, p.y)) * 0.18;
	return c * max(hf, hf2) * face * emp_factor(p) + sky_fill(p, n);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash31(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

// Lamp state: st 1 = on, 0.5 = flickering, 2 = blinking LED, 0 = off. seed = per-lamp random.
float lamp_on(float st, float seed) {
	if (st > 1.5) return step(0.82, fract(TIME * 0.7 + seed));
	// street lamps switch on one by one at dusk and off at dawn (photocells with different thresholds)
	float sw = step(0.08 + fract(seed * 7.13) * 0.5, lamp_power);
	if (st > 0.75) return sw;
	if (st > 0.25) {
		float n = noise2(vec2(TIME * 6.0, seed * 40.0));
		return (n > 0.45 ? 1.0 : (n > 0.3 ? 0.35 : 0.05)) * sw;
	}
	return 0.0;
}

// Night-city environment reflection (equirect), tinted by how lit the spot is so dark alleys stay dark.
vec3 env_reflect(vec3 R, vec3 wpos, float rough) {
	vec2 uv = vec2(atan(R.z, R.x) * 0.15915 + 0.5, acos(clamp(R.y, -1.0, 1.0)) * 0.31831);
	vec3 e = textureLod(env_map, uv, rough * 6.0).rgb;
	e = mix(vec3(dot(e, vec3(0.3, 0.55, 0.15))), e, 0.55) * vec3(0.92, 0.97, 1.08);
	vec3 lf = lf_raw(wpos.xz + R.xz * 3.0);
	float lit = clamp(dot(lf, vec3(0.3, 0.5, 0.2)) * 1.6 + 0.12, 0.0, 1.3);
	vec3 night = e * e * lit * emp_factor(wpos);
	if (daylight < 0.01) return night;
	// day: a real city sky (Poly Haven, CC0), greyed and dimmed under cloud
	vec3 d = textureLod(env_map_day, uv, rough * 6.0).rgb;
	d *= d;
	float lum = dot(d, vec3(0.3, 0.55, 0.15));
	d = mix(d, vec3(lum) * vec3(0.95, 0.98, 1.03), day_sky.a * 0.75) * mix(1.0, 0.62, day_sky.a);
	return mix(night, d * 0.85, daylight);
}

// Light inside rooms that is not from their own lamps: a faint glow at night, daylight through the window by day.
vec3 room_amb() {
	return vec3(0.012, 0.014, 0.02) + day_sky.rgb * daylight * 0.3;
}

// Day light for unshaded surfaces (distant facades, skyline): sky colour with a little sun.
vec3 day_light(vec3 n) {
	return day_sky.rgb * (0.65 + 0.35 * clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) * daylight;
}

// noise2() from a texture: same look, one texture read instead of four hashes
float tnoise(vec2 p) {
	return texture(macro_noise, p * (1.0 / 64.0)).r;
}
