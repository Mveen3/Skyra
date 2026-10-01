// Implements §7.3.2 screen_fx.gdshader: low-health vignette (#FF2244, radial 0.55 -> 1.0
// of the screen radius), additive damage / white flashes and luminance desaturation.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.0;
uniform float damage_flash = 0.0;
uniform float desaturate = 0.0;
uniform float white_flash = 0.0;

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desaturate);
	float r = length((SCREEN_UV - 0.5) * 2.0) / 1.4142;
	float v = smoothstep(0.55, 1.0, r) * vignette;
	col = mix(col, vec3(1.0, 0.133, 0.267), v);
	col += vec3(1.0, 0.15, 0.2) * damage_flash * 0.35;
	col += vec3(white_flash);
	COLOR = vec4(col, 1.0);
}
