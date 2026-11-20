shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Separate garments (tools/blender/vaynara_outfit.py): a tiling photographed fabric (Poly Haven, CC0) tinted to
// the garment colour, its normal map, ribbed knit on hems and cuffs (COLOR.a), vertex shading for seams and folds
// (COLOR.rgb). Double sided: the inside of an open hoodie, sleeve or boot shaft is the darker back of the cloth.
// UV is in metres. Lighting extras as shaders/character.gdshader (light field, rim, fill for the hero).
uniform sampler2D fabric_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_fabric = true;
uniform vec4 color : source_color = vec4(0.2);
uniform vec4 inner_color : source_color = vec4(0.12);
uniform float tile = 3.7;              // fabric repeats per metre (the photos are ~27 cm across)
uniform float normal_amount = 1.0;
uniform float roughness_v = 0.85;
uniform float specular_v = 0.3;
uniform float metallic_v = 0.0;
uniform int pattern = 0;               // 0 cloth, 1 zip teeth, 2 skin
uniform float wet_response = 0.8;
uniform float rim = 0.35;
uniform float fill = 1.0;
uniform float view_fill = 0.0;
varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * tile;
	vec3 alb = color.rgb;
	float rough = roughness_v;
	float spec = specular_v;
	float metal = metallic_v;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float rib = COLOR.a;
	if (pattern == 1) {
		// zip: a tape with interlocking metal teeth down its middle
		float along = UV.y / 0.0042;
		float side = UV.x;
		float teeth = step(0.3, side) * step(side, 0.95) * step(0.35, fract(along + (side > 0.62 ? 0.5 : 0.0)));
		alb = mix(color.rgb, vec3(0.32, 0.32, 0.34), teeth);
		metal = teeth * 0.9;
		rough = mix(0.8, 0.35, teeth);
		spec = mix(0.3, 0.6, teeth);
	} else if (pattern == 2) {
		alb *= 0.9 + 0.2 * texture(detail_tex, UV * 9.0).r;
		rough = 0.55;
		spec = 0.35;
	} else if (use_fabric) {
		vec3 f = texture(fabric_tex, uv).rgb * 2.0;
		if (rib > 0.5) {
			// rib knit: tight vertical ridges, a little darker in the furrows
			float r = sin(UV.x * 1150.0);
			f *= 0.88 + 0.12 * r;
			nm = vec3(0.5 + 0.35 * cos(UV.x * 1150.0), 0.5, 1.0);
		} else {
			nm = mix(vec3(0.5, 0.5, 1.0), texture(fabric_n, uv).rgb, normal_amount);
		}
		alb *= f;
	}
	alb *= COLOR.rgb;
	if (!FRONT_FACING) {
		alb = inner_color.rgb * COLOR.rgb;
		nm = vec3(0.5, 0.5, 1.0);
	}
	float w = wetness * wet_response * clamp(v_wnrm.y * 0.5 + 0.6, 0.0, 1.0);
	alb *= 1.0 - 0.3 * w;
	ALBEDO = alb;
	ROUGHNESS = mix(rough, rough * 0.5, w);
	SPECULAR = spec;
	METALLIC = metal;
	NORMAL_MAP = nm;
	vec3 lf = lf_raw(v_wpos.xz + v_wnrm.xz * 0.6) * emp_factor(v_wpos) * 0.9;
	float up = clamp(v_wnrm.y * 0.5 + 0.6, 0.15, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = alb * (lf * up + vec3(0.035, 0.04, 0.055) * fill + sky_fill(v_wpos, v_wnrm) * 1.3) + (lf * 0.6 + vec3(0.1, 0.13, 0.19)) * fres * rim;
	EMISSION += alb * clamp(dot(NORMAL, VIEW), 0.0, 1.0) * view_fill * vec3(0.55, 0.6, 0.72);
	EMISSION += alb * lightning * vec3(0.5, 0.55, 0.7) * up;
}
