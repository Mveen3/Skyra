# Implements §8.3 countdown (huge 3 · 2 · 1 then FIGHT!, scale 1.4 -> 1.0 with a fade per
# second; ui.countdown.beep / ui.countdown.go) and the §1.3 T13 "TIME!" end banner.
class_name CountdownOverlay
extends Control

var _text: String = ""
var _color: Color = Palette.UI_TEXT
var _age: float = 0.0
var _life: float = 1.0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	EventBus.countdown_tick.connect(_on_tick)

func _on_tick(seconds_left: int) -> void:
	if seconds_left > 0:
		show_text(str(seconds_left), Palette.UI_TEXT, 1.0)
		Audio.play(&"ui.countdown.beep")
	else:
		show_text("FIGHT!", Palette.UI_ACCENT2, 0.6)
		Audio.play(&"ui.countdown.go")

func show_text(t: String, col: Color, life: float) -> void:
	_text = t
	_color = col
	_age = 0.0
	_life = life
	queue_redraw()

func _process(delta: float) -> void:
	if _text.is_empty():
		return
	# Real time: the end banner shows while Engine.time_scale is reduced
	_age += delta / maxf(Engine.time_scale, 0.01)
	if _age >= _life:
		_text = ""
	queue_redraw()

func _draw() -> void:
	if _text.is_empty():
		return
	var k := clampf(_age / _life, 0.0, 1.0)
	var sc := lerpf(1.4, 1.0, minf(1.0, k * 2.5))
	var alpha := 1.0 - maxf(0.0, (k - 0.6) / 0.4)
	var font := ThemeFactory.heading_font()
	var fs := 200
	var tw := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := size * 0.5
	draw_set_transform(c, 0.0, Vector2(sc, sc))
	var pos := Vector2(-tw * 0.5, fs * 0.35)
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 22, Color(0.04, 0.06, 0.13, 0.85 * alpha))
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(_color, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)
