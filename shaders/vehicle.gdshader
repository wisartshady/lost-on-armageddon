shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// One-draw vehicles. UV2.x = part id (see tools/vehicles.py MAT), COLOR.rgb = part albedo, COLOR.a = baked AO.
instance uniform vec4 paint : source_color = vec4(0.32, 0.05, 0.06, 0.4);   // rgb + metallic flake amount
instance uniform float lights_on = 0.0;     // head/tail lights
instance uniform float braking = 0.0;
instance uniform float siren = 0.0;         // police / ambulance light bar
instance uniform float dirt = 0.25;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;

varying flat int v_part;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec3 v_lpos;

void vertex() {
	v_part = int(UV2.x + 0.5);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_lpos = VERTEX;
}

float fresnel(float f0, float ndv) {
	return f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0);
}

void fragment() {
	int part = v_part;
	vec3 N = normalize(v_wnrm);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	vec3 R = reflect(-V, N);
	float ao = COLOR.a;
	float w = clamp(wetness, 0.0, 1.0);
	vec3 alb = COLOR.rgb;
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	float refl = 0.0;          // strength of the fake environment reflection
	vec3 emis = vec3(0.0);
	float grime = dirt * smoothstep(0.75, 0.2, v_lpos.y) * (0.6 + 0.4 * noise2(v_lpos.xz * 9.0 + v_lpos.y * 4.0));

	if (part == 0 || part == 17) {                 // body paint (17: secondary paint from vertex colour)
		alb = part == 0 ? paint.rgb : COLOR.rgb;
		alb = mix(alb, vec3(0.16, 0.14, 0.12), grime * 0.7);
		rough = mix(0.28, 0.12, w) + grime * 0.4;
		metal = paint.a * 0.55;
		spec = 0.6;
		refl = fresnel(0.05, ndv) * (1.0 - grime * 0.7) * 1.4 + metal * 0.25;
	} else if (part == 1 || part == 16) {          // glass / mirror
		alb = part == 1 ? vec3(0.012, 0.014, 0.016) : vec3(0.15);
		rough = 0.05;
		spec = 0.9;
		refl = fresnel(part == 1 ? 0.06 : 0.6, ndv) * 1.8;
		// faint cabin silhouette: lower part of the window catches a little interior light
		float inner = smoothstep(1.25, 0.95, v_lpos.y) * 0.025;
		alb += vec3(inner);
	} else if (part == 2) {                        // chrome
		alb = vec3(0.55, 0.56, 0.58);
		metal = 1.0;
		rough = 0.12;
		refl = 1.1;
	} else if (part == 3 || part == 9 || part == 11) {   // black trim / grille / underbody
		rough = 0.55;
		spec = 0.3;
		refl = fresnel(0.03, ndv) * 0.4;
	} else if (part == 4) {                        // tyre
		alb = vec3(0.028, 0.028, 0.03);
		rough = mix(0.88, 0.5, w);
		spec = 0.3;
	} else if (part == 5) {                        // rim
		alb = vec3(0.42, 0.43, 0.45);
		metal = 0.7;
		rough = 0.3;
		refl = 0.5;
	} else if (part == 6) {                        // headlight
		alb = vec3(0.7, 0.72, 0.75);
		rough = 0.08;
		refl = 0.6;
		float reflector = 0.6 + 0.4 * sin(v_lpos.x * 140.0) * sin(v_lpos.y * 140.0);
		emis = vec3(1.0, 0.94, 0.82) * lights_on * (3.5 + reflector);
	} else if (part == 7) {                        // tail light lens
		alb = vec3(0.45, 0.02, 0.02);
		rough = 0.1;
		refl = 0.3;
		float ribs = 0.75 + 0.25 * step(0.5, fract(v_lpos.y * 60.0));
		emis = vec3(1.0, 0.04, 0.02) * ribs * (lights_on * 1.4 + braking * 3.0) + vec3(0.08, 0.0, 0.0);
	} else if (part == 8) {                        // amber indicator
		alb = vec3(0.6, 0.3, 0.03);
		rough = 0.1;
		refl = 0.3;
		emis = vec3(1.0, 0.45, 0.05) * 0.06;
	} else if (part == 15) {                       // reversing lamp
		alb = vec3(0.6);
		rough = 0.1;
		refl = 0.3;
	} else if (part == 10 || part == 14) {         // textured decals (plates, lettering, taxi sign)
		alb = texture(atlas, UV).rgb;
		rough = 0.45;
		refl = fresnel(0.04, ndv) * 0.6;
		if (part == 14) {
			emis = alb * (0.4 + lights_on * 1.6);
		}
	} else if (part == 12 || part == 13) {         // light bar
		vec3 c = part == 12 ? vec3(1.0, 0.05, 0.04) : vec3(0.08, 0.2, 1.0);
		alb = c * 0.35;
		rough = 0.1;
		refl = 0.4;
		float ph = part == 12 ? 0.0 : 0.5;
		float flash = step(0.5, fract(TIME * 2.2 + ph)) * step(0.3, fract(TIME * 8.8));
		emis = c * (0.05 + siren * flash * 6.0);
	}
	ALBEDO = alb * ao;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	vec3 lf = light_field_at(v_wpos, N);
	vec3 diffuse_amb = alb * (lf + vec3(0.012, 0.014, 0.02)) * ao * (1.0 - metal * 0.9);
	vec3 env = env_reflect(R, v_wpos, rough) * refl * mix(vec3(1.0), alb * 1.6, metal) * mix(0.5, 1.0, ao);
	EMISSION = diffuse_amb + env + emis * emp_factor(v_wpos) + alb * lightning * vec3(0.5, 0.55, 0.7) * 0.6;
}
