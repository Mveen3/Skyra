# Implements §7.3 parallax: far floating islands (factor 0.12), far cloud banks (0.25,
# drifting +6 wu/s) and near wisps (0.45, α 0.35, +14 wu/s). Each layer is placed at
# camera_pos × (1 − factor) and its pattern repeats every 4096 wu.
class_name ParallaxLayers
extends Node2D

const REPEAT: float = 4096.0
const Y_FACTOR: float = 0.08 # weak vertical parallax keeps the horizon near mid-screen

class Layer extends Node2D:
	var factor: float = 0.0
	var drift: float = 0.0
	var kind: String = ""
	var _drift_x: float = 0.0

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(kind)
		for tile in range(-2, 4):
			var ox := tile * ParallaxLayers.REPEAT
			match kind:
				"islands": _draw_islands(ox, rng)
				"clouds_far": _draw_clouds(ox, rng, 6, 360.0, 180.0, Palette.CLOUD_SHADE, Palette.CLOUD_LIGHT, 0.9)
				"clouds_near": _draw_clouds(ox, rng, 5, 520.0, 150.0, Palette.CLOUD_LIGHT, Color.WHITE, 0.35)
			rng.seed = hash(kind) # same pattern in every repeat

	func _draw_islands(ox: float, rng: RandomNumberGenerator) -> void:
		for i in range(6):
			var cx := ox + 300.0 + i * 680.0 + rng.randf_range(-120.0, 120.0)
			var cy := -120.0 + rng.randf_range(-220.0, 160.0)
			var w := rng.randf_range(160.0, 320.0)
			var top := PackedVector2Array()
			top.append(Vector2(cx - w, cy))
			for k in range(7):
				top.append(Vector2(cx - w + (2.0 * w) * float(k) / 6.0, cy - rng.randf_range(10.0, 40.0)))
			top.append(Vector2(cx + w, cy))
			top.append(Vector2(cx + w * 0.4, cy + w * 0.9))
			top.append(Vector2(cx, cy + w * 1.25))
			top.append(Vector2(cx - w * 0.45, cy + w * 0.85))
			draw_colored_polygon(top, Palette.FAR_ISLAND)
			draw_line(Vector2(cx - w, cy - 6.0), Vector2(cx + w, cy - 6.0), Palette.FAR_ISLAND.lightened(0.15), 6.0)

	func _draw_clouds(ox: float, rng: RandomNumberGenerator, count: int, base_y: float, spread: float,
			shade: Color, light: Color, alpha: float) -> void:
		for i in range(count):
			var cx := ox + i * (ParallaxLayers.REPEAT / float(count)) + rng.randf_range(0.0, 300.0)
			var cy := base_y + rng.randf_range(-spread, spread)
			var size := rng.randf_range(160.0, 300.0)
			for k in range(7):
				var px := cx + rng.randf_range(-size * 1.6, size * 1.6)
				var py := cy + rng.randf_range(-size * 0.25, size * 0.35)
				var r := size * rng.randf_range(0.45, 0.85)
				draw_circle(Vector2(px, py + r * 0.18), r, Color(shade, alpha))
				draw_circle(Vector2(px - r * 0.15, py), r * 0.86, Color(light, alpha))

var layers: Array[Layer] = []

func _ready() -> void:
	_add_layer("islands", 0.12, 0.0, -90)
	_add_layer("clouds_far", 0.25, 6.0, -80)
	_add_layer("clouds_near", 0.45, 14.0, -70)

func _add_layer(kind: String, factor: float, drift: float, z: int) -> void:
	var l := Layer.new()
	l.kind = kind
	l.factor = factor
	l.drift = drift
	l.z_index = z
	l.z_as_relative = false
	add_child(l)
	l.queue_redraw()
	layers.append(l)

func update_from_camera(cam_pos: Vector2) -> void:
	var dt := get_process_delta_time()
	for l in layers:
		l._drift_x = fposmod(l._drift_x + l.drift * dt, REPEAT)
		l.position = Vector2(cam_pos.x * (1.0 - l.factor) + l._drift_x, cam_pos.y * (1.0 - Y_FACTOR))
