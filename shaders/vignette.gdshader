shader_type canvas_item;
// Cheap always-on vignette + film grain (no screen read).
uniform float strength = 0.45;
uniform float grain = 0.04;
void fragment() {
	vec2 c = UV - 0.5;
	float v = smoothstep(0.35, 0.85, length(c * vec2(1.3, 1.0)));
	float n = fract(sin(dot(UV * 1000.0 + TIME * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(vec3(n * grain * 0.5), v * strength + (n - 0.5) * grain * 0.0);
}
