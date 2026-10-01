// Implements §7.3.2 character.gdshader with the §3.13 formulas: stealth tint, scanlines
// and shimmer, the last-0.5-s blink, the materialize reveal with its scan edge, hit flash
// and burn. The rig is drawn with CanvasItem calls instead of per-part sprites, so the
// spec's UV.y is measured across the whole character: v = 0 at RIG_HEIGHT above the feet
// and 1 at the feet (the same for body, head and weapon).
shader_type canvas_item;

uniform float stealth : hint_range(0.0, 1.0) = 0.0;
uniform float stealth_time_left = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
// World-space y of the feet anchor, updated every frame.
uniform float feet_y = 0.0;

const float RIG_HEIGHT = 100.0;
const vec3 STEALTH_TINT = vec3(0.2235, 0.9020, 1.0); // #39E6FF
const vec3 SCAN_EDGE = vec3(0.9020, 1.0, 1.0); // #E6FFFF
const vec3 BURN_GLOW = vec3(1.0, 0.4784, 0.1020); // #FF7A1A

varying float v_rig;

void vertex() {
	float world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
	v_rig = 1.0 + (world_y - feet_y) / RIG_HEIGHT;
	// Horizontal shimmer, 0.004 of the rig size
	VERTEX.x += 0.004 * RIG_HEIGHT * stealth * sin(v_rig * 40.0 + TIME * 12.0);
}

void fragment() {
	float v = clamp(v_rig, 0.0, 1.0);
	if (v < 1.0 - reveal) {
		discard;
	}
	vec4 col = COLOR;
	col.rgb = mix(col.rgb, STEALTH_TINT, 0.55 * stealth);
	col.rgb += 0.15 * stealth * (0.5 + 0.5 * sin(v * 120.0 - TIME * 20.0));
	col.rgb = mix(col.rgb, vec3(1.0), hit_flash);
	col.rgb += BURN_GLOW * 0.35 * burn * (0.5 + 0.5 * sin(TIME * 18.0));
	if (reveal < 1.0 && v < 1.0 - reveal + 0.05) {
		col.rgb = SCAN_EDGE;
	}
	float a = mix(1.0, 0.45, stealth);
	if (stealth_time_left > 0.0 && stealth_time_left < 0.5) {
		a *= fract(TIME * 8.0) < 0.5 ? 1.0 : 0.6;
	}
	col.a *= a;
	COLOR = col;
}
