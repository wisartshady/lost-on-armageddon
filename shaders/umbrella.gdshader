shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Pedestrians' umbrellas (model: tools/blender/umbrella.py). The canopy fabric ripples in the wind between the
// ribs (strongest mid-panel at the rim), folds down along the shaft when the umbrella closes, beads with rain.
// COLOR.r = fabric, COLOR.g = flutter weight, COLOR.b = distance from the shaft; UV2.x = part.
instance uniform vec4 canopy : source_color = vec4(0.08, 0.08, 0.09, 1.0);
instance uniform float open = 1.0;        // 0 closed and furled .. 1 open
instance uniform float wind = 0.5;
instance uniform float phase = 0.0;
varying float v_part;
varying float v_fab;
varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_part = UV2.x;
	v_fab = COLOR.r;
	float w = COLOR.g;
	float r = COLOR.b;
	bool folds = UV2.x < 0.5 || (((UV2.x > 0.5 && UV2.x < 1.5) || UV2.x > 2.5) && r > 0.02);
	if (folds) {
		// close: everything on the canopy swings down towards the shaft about the apex
		float o = clamp(open, 0.0, 1.0);
		vec2 dir = r > 1e-4 ? VERTEX.xz / r : vec2(0.0);
		float apex = 0.99;
		float dy = apex - VERTEX.y;
		float ang = atan(r, max(dy, 0.001));          // angle of the point from the downward shaft
		float closed_ang = 0.07 + 0.05 * w;           // furled: lying along the shaft, fabric bunching out a little
		float na = mix(closed_ang, ang, o);
		float len = length(vec2(r, dy));
		VERTEX.xz = dir * sin(na) * len;
		VERTEX.y = apex - cos(na) * len;
		// wind ripple of the fabric between the ribs, more when open
		float t = TIME * (5.0 + 3.0 * wind) + phase;
		float a = atan(VERTEX.z, VERTEX.x);
		float rip = sin(t + a * 8.0 + r * 9.0) * 0.6 + sin(t * 1.7 - a * 5.0) * 0.4;
		float amt = (0.006 + 0.018 * wind) * w * o * COLOR.r;
		VERTEX.y += rip * amt;
		VERTEX.xz += dir * rip * amt * 0.4;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 N = normalize(v_wnrm);
	bool under = !FRONT_FACING;
	if (under) N = -N;
	vec3 alb;
	float rough;
	float spec;
	float metal = 0.0;
	if (v_part < 0.5) {
		// nylon: tight weave, a little sheen; wet it darkens and beads
		float weave = 0.94 + 0.06 * sin(UV.y * 260.0) * sin(UV.x * 300.0);
		alb = canopy.rgb * weave;
		float wet = clamp(wetness, 0.0, 1.0) * (under ? 0.2 : 1.0);
		alb *= 1.0 - 0.25 * wet;
		rough = mix(0.5, 0.18, wet);
		spec = 0.45;
		if (under) {
			alb *= 0.55;   // light through the fabric is dim on the inside
			rough = 0.8;
		}
	} else if (v_part < 1.5) {
		alb = vec3(0.32, 0.33, 0.35);
		metal = 0.9;
		rough = 0.35;
		spec = 0.5;
	} else if (v_part < 2.5) {
		alb = vec3(0.22, 0.12, 0.06);
		rough = 0.4;
		spec = 0.4;
	} else {
		alb = vec3(0.05);
		rough = 0.4;
		spec = 0.4;
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	vec3 lf = light_field_at(v_wpos, N);
	EMISSION = alb * (lf + vec3(0.012, 0.014, 0.02)) + alb * lightning * vec3(0.5, 0.55, 0.7) * 0.5;
}
