// Implements §7.3.2 updraft.gdshader: scrolling vertical streak noise over the backdrop of
// the updraft shafts. Streaks live in world space (12-wu lanes), so neighbouring shaft
// rects tile seamlessly; they rise at `speed` × (1 + per-lane jitter).
shader_type canvas_item;

uniform float time = 0.0;
uniform float speed = 1.2;
uniform vec4 streak_color : source_color = vec4(0.62, 0.90, 1.0, 0.22);

varying vec2 world_pos;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float lane = floor(world_pos.x / 12.0);
	float h = hash(lane);
	float h2 = hash(lane + 71.0);
	// Thin soft line in the middle of the lane; only ~60 % of the lanes carry streaks
	float across = 1.0 - smoothstep(0.08, 0.32, abs(fract(world_pos.x / 12.0) - 0.5));
	float on = step(0.4, h);
	// Streak head at the top of each period with a tail fading downward (rising motion)
	float period = 140.0 + 120.0 * h2;
	float s = fract(world_pos.y / period + time * speed * (0.8 + 0.6 * h) + h2 * 5.0);
	float streak = smoothstep(0.0, 0.04, s) * (1.0 - smoothstep(0.04, 0.45, s));
	COLOR = vec4(streak_color.rgb, streak_color.a * streak * across * on);
}
