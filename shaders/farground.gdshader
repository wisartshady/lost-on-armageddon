shader_type spatial;
render_mode unshaded, cull_back;
global uniform float daylight;
global uniform vec4 day_sky;
// ground of the far city: dark asphalt at night, sky-lit grey by day; the scene fog does the rest
void fragment() { ALBEDO = mix(vec3(0.012, 0.012, 0.014), day_sky.rgb * 0.26, daylight); }
