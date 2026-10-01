# Implements §8.3 loading overlay: full-screen ui_bg, a 600 x 10 cyan progress bar and a
# rotating gameplay tip; fades out over 0.25 s once the world is built.
class_name LoadingOverlay
extends Control

const TIPS: Array[String] = [
	"Hold S to dive down wind shafts",
	"Buzzsaw blades hit harder after a bounce",
	"Bots can't see you for 2 s after you respawn",
	"Wind shafts refuel your jetpack - ride them up",
	"Press E near a weapon to take it - you can carry two",
	"Rocket Boost: infinite jetpack for 10 s",
	"Black Arrow headshots are one-shot kills",
	"Hold right mouse to aim a grenade, release to throw",
]

var _t: float = 0.0
var _fading: bool = false
var _tip: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(Palette.UI_BG, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := UiKit.label("LOADING OUTPOST SKYRA", 44, Palette.UI_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.place_center_x(title, 420, Vector2(1000, 60))
	add_child(title)
	_tip = UiKit.label(TIPS[randi() % TIPS.size()], 26, Palette.UI_SUBTEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.place_center_x(_tip, 560, Vector2(1200, 40))
	add_child(_tip)

func fade_out() -> void:
	_fading = true

func _process(delta: float) -> void:
	_t += delta
	if _fading:
		modulate.a = maxf(0.0, modulate.a - delta / 0.25)
		if modulate.a <= 0.0:
			queue_free()
	queue_redraw()

func _draw() -> void:
	var w := 600.0
	var x := (size.x - w) * 0.5
	var y := 500.0
	draw_rect(Rect2(x, y, w, 10.0), Color("#1E2744"))
	var k := clampf(_t / 0.4, 0.0, 1.0) if not _fading else 1.0
	draw_rect(Rect2(x, y, w * k, 10.0), Palette.UI_ACCENT)
