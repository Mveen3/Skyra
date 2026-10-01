// Implements §7.3.2 sky.gdshader: 4-stop vertical gradient, sun disc with a soft
// exp(-d/60) glow and hash-based twinkling stars in the upper sky.
shader_type canvas_item;

uniform vec4 sky_top : source_color = vec4(0.055, 0.106, 0.302, 1.0);
uniform vec4 sky_mid : source_color = vec4(0.227, 0.310, 0.639, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.949, 0.620, 0.427, 1.0);
uniform vec4 sky_bottom : source_color = vec4(1.0, 0.820, 0.631, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.890, 0.639, 1.0);
uniform vec2 sun_pos = vec2(0.78, 0.62);
uniform float sun_radius = 90.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 col;
	if (uv.y < 0.45) {
		col = mix(sky_top.rgb, sky_mid.rgb, uv.y / 0.45);
	} else if (uv.y < 0.78) {
		col = mix(sky_mid.rgb, sky_horizon.rgb, (uv.y - 0.45) / 0.33);
	} else {
		col = mix(sky_horizon.rgb, sky_bottom.rgb, (uv.y - 0.78) / 0.22);
	}
	vec2 px = uv / SCREEN_PIXEL_SIZE;
	vec2 sun_px = sun_pos / SCREEN_PIXEL_SIZE;
	float d = distance(px, sun_px);
	col += sun_color.rgb * exp(-max(d - sun_radius, 0.0) / 60.0) * 0.55;
	col = mix(col, sun_color.rgb, smoothstep(sun_radius + 1.5, sun_radius - 1.5, d) * 0.95);
	// Stars fade in toward the top of the sky
	float star_zone = 1.0 - smoothstep(0.05, 0.45, uv.y);
	if (star_zone > 0.0) {
		vec2 cell = floor(px / 3.0);
		float h = hash(cell);
		if (h > 0.9965) {
			float tw = 0.55 + 0.45 * sin(TIME * (1.5 + h * 3.0) + h * 91.0);
			col += vec3(0.95, 0.97, 1.0) * tw * star_zone;
		}
	}
	COLOR = vec4(col, 1.0);
}
