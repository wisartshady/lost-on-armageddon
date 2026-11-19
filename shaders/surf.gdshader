shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// All tiling city surfaces in one material: texture arrays, layer index in UV2.x, shading class in UV2.y.
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 p0[24]; // uv_scale, rough_dry, rough_wet, porosity
uniform vec4 p1[24]; // normal_depth, grime, specular, reflect
uniform bool use_normal = true;
uniform float brightness = 1.0;

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying flat int v_layer;
varying flat int v_class;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_layer = int(UV2.x + 0.5);
	v_class = int(UV2.y + 0.5);
}

void fragment() {
	vec4 a = p0[v_layer];
	vec4 b = p1[v_layer];
	vec2 uv = UV * a.x;
	vec4 texa = texture(albedo_arr, vec3(uv, float(v_layer)));
	vec3 tex = texa.rgb;
	// break up tiling with large-scale tone variation
	float macro = tnoise(v_wpos.xz * 0.11 + v_wpos.y * 0.07) * 0.6 + tnoise(v_wpos.xz * 0.37 + v_wpos.yy * 0.2) * 0.4;
	vec3 alb = tex * COLOR.rgb * brightness * (0.82 + 0.36 * macro);
	float vertical = step(abs(v_wnrm.y), 0.5);
	alb *= 1.0 - b.y * (1.0 - smoothstep(0.0, 1.8, v_wpos.y)) * vertical;
	float ground = step(0.5, v_wnrm.y);
	float w = clamp(wetness, 0.0, 1.0) * mix(0.55, 1.0, ground);
	float rdry = mix(a.y, texa.a, 0.6);
	float rwet = a.z;
	float spec = b.z;
	float por = a.w;
	if (v_class == 1) { rdry = 0.22; rwet = 0.08; spec = 0.75; por = 0.0; alb = COLOR.rgb * (0.85 + 0.15 * tex.r); }
	else if (v_class == 2) { rdry = 0.3; rwet = 0.15; spec = 0.6; por = 0.0; alb = COLOR.rgb * (0.8 + 0.2 * tex.r); }
	else if (v_class == 3) { rdry = 0.9; rwet = 0.6; spec = 0.3; por = 0.2; alb = COLOR.rgb * (0.8 + 0.2 * tex.r); }
	// water collects in the dark (low) parts of the texture: mortar joints, cracks, between setts
	float low = 1.0 - smoothstep(0.08, 0.35, dot(tex, vec3(0.33)));
	float wet_here = w * mix(0.75, 1.0, low * ground);
	alb *= 1.0 - por * 0.45 * wet_here;
	float rough = mix(rdry, rwet, wet_here);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = spec;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float nmd = 0.0;
	if (use_normal && b.x > 0.01) {
		nm = texture(normal_arr, vec3(uv, float(v_layer))).rgb;
		nmd = b.x * (1.0 - 0.5 * wet_here * ground);
	}
	// raindrop impacts on the ground: small rings that spread and fade (near the camera, only while it rains)
	float camd = distance(CAMERA_POSITION_WORLD, v_wpos);
	if (ground > 0.5 && rain_amount > 0.03 && camd < 22.0) {
		vec2 rg = vec2(0.0);
		for (int k = 0; k < 2; k++) {
			vec2 q = v_wpos.xz * 2.6 + float(k) * vec2(0.37, 0.71);
			vec2 cell = floor(q);
			vec2 f = fract(q) - 0.5;
			float h = hash12(cell + float(k) * 17.0);
			float ph = fract(TIME * (1.1 + 0.5 * h) + h * 7.0);
			vec2 c = (vec2(hash12(cell + 3.1), hash12(cell + 9.7)) - 0.5) * 0.5;
			vec2 dd = f - c;
			float r = length(dd);
			float ring = sin((r - ph * 0.45) * 55.0) * smoothstep(0.08, 0.0, abs(r - ph * 0.45)) * (1.0 - ph);
			rg += dd / max(r, 1e-3) * ring * step(h, rain_amount * 0.9);
		}
		rg *= (1.0 - smoothstep(12.0, 22.0, camd)) * wet_here;
		nm.xy += rg * 0.22;
		nmd = max(nmd, 0.6);
	}
	if (nmd > 0.0) {
		NORMAL_MAP = nm;
		NORMAL_MAP_DEPTH = nmd;
	}
	vec3 lf = light_field_at(v_wpos, v_wnrm);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float ndv = clamp(dot(v_wnrm, V), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	vec3 refl = vec3(0.0);
	if (ground > 0.5 && b.w > 0.0) {
		// wet-street reflections: lamps and neon stretched towards the viewer
		vec3 R = reflect(-V, vec3(0.0, 1.0, 0.0));
		vec2 dir = normalize(R.xz + vec2(1e-4));
		float k = length(R.xz) / max(R.y, 0.05);
		vec3 s1 = lf_raw(v_wpos.xz + dir * min(3.0 * k, 22.0));
		vec3 s2 = lf_raw(v_wpos.xz + dir * min(5.5 * k, 30.0));
		vec3 s3 = lf_raw(v_wpos.xz + dir * min(8.0 * k, 40.0));
		vec3 streak = (s1 * 0.45 + s2 * 0.35 + s3 * 0.2) * emp_factor(v_wpos);
		refl = streak * fres * 2.2 * wet_here * b.w * (1.0 - rough * 0.6);
		refl += env_reflect(R, v_wpos, rough) * fres * 0.5 * wet_here * b.w;
	}
	EMISSION = alb * lf + refl + lf * (w * b.w) * 0.05 * ground;
	EMISSION += alb * lightning * vec3(0.55, 0.6, 0.75) * max(v_wnrm.y, 0.35);
}
