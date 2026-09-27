shader_type canvas_item;
// Terreno estilo AoE2 DE. UV = coordenadas de casilla (el polígono es el rombo
// del mapa con UV (0,0)..(W,H), y la proyección iso es afín). Cuatro capas de
// texturas top-down que se repiten cada tiles_per_tex casillas, mezcladas por
// un mapa de control (1 texel por casilla, filtrado lineal) y un ruido de
// borde para transiciones orgánicas.

uniform sampler2D tex_0 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_1 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_2 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D tex_3 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D control_tex : filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 map_size = vec2(144.0, 144.0);
uniform float tiles_per_tex = 12.0;
uniform float softness = 0.16;

float weight(float w, float n) {
	return smoothstep(0.5 - softness, 0.5 + softness, w + (n - 0.5) * 0.7);
}

void fragment() {
	vec2 tile = UV;
	vec2 tuv = tile / tiles_per_tex;
	vec4 ctl = texture(control_tex, tile / map_size);
	float n1 = texture(noise_tex, tile / 7.0).r;
	float n2 = texture(noise_tex, tile / 5.0 + vec2(0.31, 0.77)).r;
	vec3 col = texture(tex_0, tuv).rgb;
	col = mix(col, texture(tex_1, tuv + vec2(0.37, 0.11)).rgb, weight(ctl.r, n1));
	col = mix(col, texture(tex_2, tuv + vec2(0.13, 0.71)).rgb, weight(ctl.g, n2));
	col = mix(col, texture(tex_3, tuv * 1.3).rgb, weight(ctl.b, n1));
	vec2 e = min(tile, map_size - tile);
	float edge = clamp(min(e.x, e.y) / 1.5, 0.0, 1.0);
	COLOR = vec4(col * mix(0.5, 1.0, edge), 1.0);
}
