shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Photo-scanned props (Poly Haven, CC0): PBR textures + the city's baked street lighting + wet look.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;   // r = AO, g = roughness, b = metallic
uniform bool has_normal = true;
uniform bool has_orm = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float rough_mul = 1.0;
uniform float wet_response = 0.7;
uniform float emissive = 0.0;     // bulbs / glass
uniform bool use_custom = false;  // MultiMesh custom data r = bulb on/off
varying vec3 v_wpos;
varying float v_on;
varying vec3 v_wnrm;
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_on = use_custom ? lamp_on(INSTANCE_CUSTOM.r, INSTANCE_CUSTOM.g) : 1.0;
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	vec3 orm = has_orm ? texture(orm_tex, UV).rgb : vec3(1.0, 0.7, 0.0);
	vec3 alb = a.rgb * tint.rgb;
	float w = clamp(wetness, 0.0, 1.0) * wet_response * clamp(v_wnrm.y * 0.5 + 0.6, 0.0, 1.0);
	alb *= mix(1.0, 0.72, w * (1.0 - orm.b));
	ALBEDO = alb * orm.r;
	float rough = clamp(orm.g * rough_mul, 0.04, 1.0);
	ROUGHNESS = mix(rough, rough * 0.4, w);
	METALLIC = orm.b;
	SPECULAR = 0.5;
	if (has_normal) NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 lf = light_field_at(v_wpos, v_wnrm);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_wpos);
	vec3 R = reflect(-V, normalize(v_wnrm));
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(normalize(v_wnrm), V), 0.0, 1.0), 5.0);
	vec3 env = env_reflect(R, v_wpos, ROUGHNESS) * mix(fres, 1.0, orm.b) * mix(vec3(1.0), alb, orm.b) * (1.0 - ROUGHNESS * 0.7);
	EMISSION = alb * orm.r * (lf + vec3(0.012, 0.014, 0.02)) * (1.0 - orm.b * 0.8) + env * (0.4 + w)
		+ alb * emissive * v_on * 3.0 * emp_factor(v_wpos) + alb * lightning * vec3(0.5, 0.55, 0.7) * 0.6;
}
