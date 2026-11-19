shader_type canvas_item;
// Always-on final pass: sharpening (for upscaled 3D), cinematic grade, vignette, grain
// + the symbiote strain effect (blur, chromatic aberration, electric veins, tunnel vision).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;   // no mipmaps: they would be rebuilt every frame
uniform sampler2D veins : filter_linear_mipmap;
uniform float strain = 0.0;
uniform float pulse = 0.0;
uniform float collapse = 0.0;
uniform float sharpen = 0.35;
uniform float grade = 1.0;
uniform float brightness = 1.0;
uniform float vignette = 0.38;
uniform float grain = 0.025;

vec3 grade_col(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// lift the deepest blacks a touch with a cold tint (keeps silhouettes readable), warm the highlights
	vec3 lifted = c + vec3(0.012, 0.018, 0.026) * (1.0 - smoothstep(0.0, 0.25, l));
	vec3 split = mix(vec3(0.94, 1.0, 1.08), vec3(1.06, 1.0, 0.92), smoothstep(0.2, 0.8, l));
	vec3 g = lifted * split;
	// gentle filmic S-curve in the mid tones
	g = mix(g, g * g * (3.0 - 2.0 * g), 0.22);
	return mix(c, g, grade);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float s = clamp(strain, 0.0, 1.0);
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	float ca = (0.0025 * s * s + pulse * 0.005) * smoothstep(0.05, 0.35, r2);   // only towards the edges
	vec3 col = texture(screen_tex, uv).rgb;
	if (ca > 0.00001) {
		// chromatic fringe only while the symbiote strains (two extra reads, skipped the rest of the time)
		col.r = texture(screen_tex, uv + c * ca).r;
		col.b = texture(screen_tex, uv - c * ca).b;
	}
	// contrast-adaptive style sharpening
	vec3 n = texture(screen_tex, uv + vec2(0.0, -px.y)).rgb;
	vec3 so = texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb;
	vec3 avg = (n + so + e + w) * 0.25;
	vec3 mn = min(min(min(n, so), min(e, w)), col);
	vec3 mx = max(max(max(n, so), max(e, w)), col);
	vec3 amt = clamp(min(mn, 1.0 - mx) / max(mx, vec3(0.001)), 0.0, 1.0);
	col = col + (col - avg) * sqrt(amt) * sharpen * 1.6;
	float blur = smoothstep(0.6, 1.0, s) * smoothstep(0.08, 0.4, r2);
	col = mix(col, avg, blur * 0.35);
	col = grade_col(max(col, vec3(0.0))) * brightness;
	// vignette + grain
	float vg = smoothstep(0.35, 0.95, length(c * vec2(1.25, 1.0)));
	col *= 1.0 - vg * vignette;
	float nz = fract(sin(dot(uv * 1000.0 + fract(TIME) * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (nz - 0.5) * grain;
	// symbiote strain, kept subtle: a soft tunnel, a cold desaturated grade, faint veins only at the rim
	float rim = smoothstep(0.32, 0.62, length(c * vec2(1.15, 1.0)));
	float tunnel = smoothstep(0.35, 1.0, s);
	if (s + pulse + collapse < 0.001) {
		COLOR = vec4(col, 1.0);
	} else {
	vec4 v = texture(veins, UV);
	col *= 1.0 - rim * 0.38 * tunnel;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, mix(vec3(lum), col * vec3(0.9, 1.0, 1.1), 0.65), tunnel * 0.45);
	vec3 vcol = vec3(0.35, 0.8, 1.0);
	float vein = v.r * rim * rim * smoothstep(0.55, 1.0, s) * (0.55 + 0.45 * sin(TIME * 2.4 + v.b * 8.0));
	col += vcol * vein * 0.16;
	col += vcol * pulse * 0.1 * rim;
	col = mix(col, vec3(0.0), collapse);
	COLOR = vec4(col, 1.0);
	}
}
