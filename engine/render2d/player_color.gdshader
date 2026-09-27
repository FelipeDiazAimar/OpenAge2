shader_type canvas_item;
// Tiñe con el color del jugador los píxeles marcados en la máscara del AoE2
// (m_*.png: alpha > 0 = zona teñible), conservando el sombreado del sprite.

uniform sampler2D mask_tex : filter_nearest;
uniform vec4 player_color : source_color = vec4(0.16, 0.29, 1.0, 1.0);
uniform bool has_mask = false;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (has_mask) {
		float m = texture(mask_tex, UV).a;
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec3 tinted = player_color.rgb * (lum * 1.5 + 0.2);
		c.rgb = mix(c.rgb, tinted, m);
	}
	COLOR = c;
}
