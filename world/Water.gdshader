shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
// world/Water.gdshader — agua animada procedural, sin assets.
// Solo TIME + math: no toca sim. Compatible GL Compatibility.

uniform vec4 shallow_color : source_color = vec4(0.16, 0.44, 0.56, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.24, 0.40, 1.0);
uniform float wave_height = 0.12;
uniform float wave_speed = 1.2;
uniform float band_scale = 34.0;

void vertex() {
	float w = sin(VERTEX.x * 0.35 + TIME * wave_speed)
		+ 0.6 * sin(VERTEX.z * 0.5 - TIME * wave_speed * 0.8)
		+ 0.4 * sin((VERTEX.x + VERTEX.z) * 0.22 + TIME * wave_speed * 0.6);
	VERTEX.y += w * wave_height * 0.33;
}

void fragment() {
	float w1 = sin(UV.x * band_scale + TIME * 1.4);
	float w2 = sin((UV.x + UV.y) * (band_scale * 0.7) - TIME * 1.0);
	float m = (w1 + w2) * 0.25 + 0.5; // 0..1 aprox
	m = smoothstep(0.15, 0.95, m);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.30 + 0.45 * m);
	ROUGHNESS = 0.4;
}
