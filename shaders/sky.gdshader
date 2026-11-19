shader_type sky;
// Night: dark city sky with a sodium glow on the horizon, clouds lit from below, the moon.
// Day: blue sky with the sun, or a grey overcast / misty sky; clouds drift with the wind. `daylight` and `cover`
// come from the weather (scripts/world/weather.gd).
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith : source_color = vec3(0.018, 0.02, 0.032);
uniform vec3 horizon : source_color = vec3(0.12, 0.09, 0.08);
uniform vec3 cloud_lit : source_color = vec3(0.2, 0.15, 0.13);
uniform vec3 moon_dir = vec3(-0.3, 0.55, -0.78);
uniform float lightning_v = 0.0;
uniform float daylight = 0.0;
uniform float cover = 1.0;
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.2);
uniform vec3 sun_col = vec3(1.0, 0.95, 0.88);
uniform vec2 cloud_offset = vec2(0.0);   // drifts slowly; set by the script (no TIME here: the sky is cached)

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	// --- night
	vec3 night = mix(horizon, zenith, smoothstep(-0.02, 0.5, h));
	if (h < 0.0) night = horizon * 0.6;
	float cov = 0.0;
	vec2 cuv = d.xz / (max(h, 0.0) + 0.12) * 0.35;
	if (h > 0.0) {
		float c1 = texture(clouds, cuv + cloud_offset).r;
		float c2 = texture(clouds, cuv * 2.3 - vec2(cloud_offset.x * 1.5, 0.0)).r;
		cov = smoothstep(0.15, 0.85, c1 * 0.75 + c2 * 0.25);
		vec3 cc = mix(cloud_lit, zenith * 1.5, smoothstep(0.0, 0.6, h));
		night = mix(night, cc, cov * 0.85);
	}
	vec3 md = normalize(moon_dir);
	float m = dot(d, md);
	float disc = smoothstep(0.9993, 0.9996, m);
	float halo = pow(max(m, 0.0), 180.0) * 0.25 + pow(max(m, 0.0), 12.0) * 0.03;
	night += (vec3(0.75, 0.78, 0.85) * disc + vec3(0.4, 0.45, 0.55) * halo) * (1.0 - cov * 0.85);
	// --- day
	vec3 sd = normalize(sun_dir);
	float sh = clamp(sd.y, 0.0, 1.0);
	vec3 blue_z = vec3(0.16, 0.32, 0.62);
	vec3 blue_h = vec3(0.62, 0.72, 0.84);
	vec3 clear = mix(blue_h, blue_z, pow(smoothstep(-0.05, 0.75, h), 0.7));
	// warm horizon near a low sun
	float toward = pow(max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-4), normalize(vec3(sd.x, 0.0, sd.z) + 1e-4)), 0.0), 3.0);
	clear += vec3(0.45, 0.25, 0.08) * toward * (1.0 - smoothstep(0.0, 0.35, sh)) * (1.0 - smoothstep(0.0, 0.3, h));
	vec3 grey = mix(vec3(0.64, 0.66, 0.69), vec3(0.5, 0.53, 0.57), smoothstep(0.0, 0.7, h));
	vec3 dayc = mix(clear, grey, cover);
	if (h > 0.0) {
		// clouds: bright tops facing the sun, grey bellies; overcast skies are a soft blanket
		float dens = clamp(cov * (0.55 + 0.6 * cover) + cover * 0.25, 0.0, 1.0);
		vec3 cl = mix(vec3(0.6, 0.62, 0.66), vec3(0.97, 0.97, 0.96), 0.35 + 0.65 * (1.0 - cover));
		dayc = mix(dayc, cl * mix(0.85, 1.0, sh), dens * mix(0.7, 0.35, cover));
	} else {
		dayc = mix(dayc, vec3(0.42, 0.44, 0.47), smoothstep(0.0, -0.2, h));
	}
	float s = max(dot(d, sd), 0.0);
	float sun_disc = smoothstep(0.99955, 0.9998, s) * (1.0 - cover * 0.92) * (1.0 - cov * 0.7);
	float sun_glow = (pow(s, 600.0) * 0.6 + pow(s, 24.0) * 0.18) * (1.0 - cover * 0.6);
	dayc += sun_col * (sun_disc * 9.0 + sun_glow);
	vec3 col = mix(night, dayc, daylight);
	col += lightning_v * vec3(0.5, 0.55, 0.7) * (0.3 + cov);
	COLOR = col;
}
