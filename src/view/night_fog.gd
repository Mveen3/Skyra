# Sniper Post atmosphere: soft fog banks drifting across the lower half of Outpost
# Skyra. World-space, drawn behind the map tiles; view-only (no Sim effect).
class_name NightFog
extends Node2D

const BANKS := 9
var _t: float = 0.0
var _tex: Texture2D

func _ready() -> void:
	_tex = FxManager.soft_texture()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	for i in range(BANKS):
		var seed_f := float(i) * 1.618
		var y := 2000.0 + fmod(seed_f * 911.0, 1700.0)
		var speed := 18.0 + fmod(seed_f * 37.0, 22.0)
		var x := fmod(seed_f * 1733.0 + _t * speed, 9200.0) - 760.0
		var w := 1400.0 + fmod(seed_f * 517.0, 900.0)
		var h := 260.0 + fmod(seed_f * 211.0, 160.0)
		draw_texture_rect(_tex, Rect2(x - w * 0.5, y - h * 0.5, w, h), false, Color(0.62, 0.7, 0.95, 0.16))
