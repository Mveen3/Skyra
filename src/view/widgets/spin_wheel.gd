# Implements §8.2.1 Duration spin wheel widget (clamped 5..10, default 7): a vertical
# drum with three 56-px slots, centre highlight band, ▲/▼ chevrons, mouse wheel, drag,
# slot clicks and ↑/↓ keys; plays ui.spin.tick on every change.
class_name SpinWheel
extends Control

signal value_changed(new_value: int)

const MIN_VALUE: int = 5
const MAX_VALUE: int = 10
const DEFAULT_VALUE: int = 7
const SLOT_HEIGHT: float = 56.0
const WIDGET_SIZE := Vector2(220.0, 140.0)

var value: int = DEFAULT_VALUE
var drag_accum_y: float = 0.0
var _anim_offset: float = 0.0 # visual drum offset easing back to 0 after a change
var _dragging: bool = false
var _press_y: float = 0.0
var _moved: bool = false

func _init(initial_value: int = DEFAULT_VALUE) -> void:
	value = clampi(initial_value, MIN_VALUE, MAX_VALUE)
	custom_minimum_size = WIDGET_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Match length: %d minutes" % value

func set_value(v: int) -> void:
	var clamped := clampi(v, MIN_VALUE, MAX_VALUE)
	if clamped != value:
		_anim_offset += float(clamped - value) * SLOT_HEIGHT
		value = clamped
		tooltip_text = "Match length: %d minutes" % value
		value_changed.emit(value)
		if is_inside_tree():
			Audio.play(&"ui.spin.tick")
	elif is_inside_tree() and v != value:
		_anim_offset = signf(float(v - value)) * -12.0 # rubber-band nudge at the ends
		queue_redraw()

func adjust(delta: int) -> void:
	set_value(value + delta)

func on_mouse_wheel(wheel_down: bool) -> void:
	# §8.2.1: wheel down = +1, wheel up = -1
	adjust(1 if wheel_down else -1)

func on_drag(delta_y: float) -> void:
	# §8.2.1: vertical drag moves 1 value per 56 px
	drag_accum_y += delta_y
	while drag_accum_y >= SLOT_HEIGHT:
		drag_accum_y -= SLOT_HEIGHT
		adjust(-1) # dragging down scrolls up / decrements
	while drag_accum_y <= -SLOT_HEIGHT:
		drag_accum_y += SLOT_HEIGHT
		adjust(1) # dragging up scrolls down / increments

func on_key_input(keycode: Key) -> void:
	# §8.2.1: ↑/↓ and +/-
	match keycode:
		KEY_UP, KEY_EQUAL, KEY_KP_ADD:
			adjust(1)
		KEY_DOWN, KEY_MINUS, KEY_KP_SUBTRACT:
			adjust(-1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			on_mouse_wheel(true)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			on_mouse_wheel(false)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_dragging = true
				_moved = false
				_press_y = mb.position.y
				drag_accum_y = 0.0
			else:
				_dragging = false
				if not _moved:
					_click_at(mb.position.y)
				drag_accum_y = 0.0
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if absf(mm.position.y - _press_y) > 6.0:
			_moved = true
		if _moved:
			on_drag(-mm.relative.y)
		accept_event()
	elif event is InputEventKey and event.pressed and has_focus():
		var k := (event as InputEventKey).keycode
		if k == KEY_UP or k == KEY_DOWN:
			on_key_input(k)
			accept_event()

## Click: upper slot / ▲ = −1, lower slot / ▼ = +1 (§8.2.1).
func _click_at(y: float) -> void:
	var mid := size.y * 0.5
	if y < mid - SLOT_HEIGHT * 0.5:
		adjust(-1)
	elif y > mid + SLOT_HEIGHT * 0.5:
		adjust(1)

func _process(delta: float) -> void:
	if absf(_anim_offset) > 0.1:
		_anim_offset = lerpf(_anim_offset, 0.0, 1.0 - exp(-18.0 * delta))
		queue_redraw()
	elif _anim_offset != 0.0:
		_anim_offset = 0.0
		queue_redraw()

func _draw() -> void:
	var font := ThemeFactory.heading_font()
	var w := size.x
	var mid := size.y * 0.5
	draw_style_box(ThemeFactory.stylebox(Color("#10162C"), 14, Palette.UI_ACCENT if has_focus() else Palette.UI_STROKE, 2), Rect2(Vector2.ZERO, size))
	# Centre highlight band
	draw_rect(Rect2(6.0, mid - SLOT_HEIGHT * 0.5, w - 12.0, SLOT_HEIGHT), Color(Palette.UI_ACCENT, 0.15))
	draw_line(Vector2(6.0, mid - SLOT_HEIGHT * 0.5), Vector2(w - 6.0, mid - SLOT_HEIGHT * 0.5), Palette.UI_ACCENT, 2.0)
	draw_line(Vector2(6.0, mid + SLOT_HEIGHT * 0.5), Vector2(w - 6.0, mid + SLOT_HEIGHT * 0.5), Palette.UI_ACCENT, 2.0)
	# Values: neighbours scale 0.7, α 0.45, squashed
	for k in range(-2, 3):
		var v := value + k
		if v < MIN_VALUE or v > MAX_VALUE:
			continue
		var y := mid + float(k) * SLOT_HEIGHT + _anim_offset
		var dist := absf(y - mid) / SLOT_HEIGHT
		if dist > 1.6:
			continue
		var centre := dist < 0.5
		var fs := int(lerpf(56.0, 34.0, clampf(dist, 0.0, 1.0)))
		var alpha := lerpf(1.0, 0.45, clampf(dist, 0.0, 1.0)) * clampf(1.6 - dist, 0.0, 1.0)
		var txt := str(v)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := w * 0.42 - tw * 0.5
		draw_string(font, Vector2(x, y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.UI_TEXT, alpha))
		if centre:
			draw_string(ThemeFactory.body_font(), Vector2(w * 0.42 + tw * 0.5 + 8.0, y + 12.0), "MIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(Palette.UI_SUBTEXT, alpha))
	# Fade gradients at the top and bottom
	for i in range(10):
		var a := 0.08 * float(10 - i) / 10.0
		draw_rect(Rect2(2.0, 2.0 + i * 3.0, w - 4.0, 3.0), Color(0.06, 0.08, 0.17, a * 6.0))
		draw_rect(Rect2(2.0, size.y - 5.0 - i * 3.0, w - 4.0, 3.0), Color(0.06, 0.08, 0.17, a * 6.0))
	# Chevrons ▲ / ▼
	var cx := w - 30.0
	var up_col := Palette.UI_ACCENT if value > MIN_VALUE else Palette.UI_STROKE
	var dn_col := Palette.UI_ACCENT if value < MAX_VALUE else Palette.UI_STROKE
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 12, 30), Vector2(cx + 12, 30), Vector2(cx, 16)]), up_col)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 12, size.y - 30), Vector2(cx + 12, size.y - 30), Vector2(cx, size.y - 16)]), dn_col)
