# Implements §8.2 Bots count segmented toggle (default 5, options 3 / 5 / 7): three
# 120 x 72 buttons (selected = cyan with glow), ←/→ when focused, keys 3/5/7, and a
# preview row of the selected bots' helmet heads in their colours (pop-in animation).
class_name BotsToggle
extends Control

signal bot_count_changed(new_count: int)

const VALID_COUNTS: Array[int] = [3, 5, 7]
const DEFAULT_COUNT: int = 5
const BTN := Vector2(120.0, 72.0)
const GAP: float = 12.0

var bot_count: int = DEFAULT_COUNT
var _pop: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
var _hover: int = -1

func _init(initial_count: int = DEFAULT_COUNT) -> void:
	set_bot_count(initial_count)
	custom_minimum_size = Vector2(3.0 * BTN.x + 2.0 * GAP + 24.0 + 7.0 * 44.0, BTN.y)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_bot_count(count: int) -> void:
	if count in VALID_COUNTS and count != bot_count:
		var prev := bot_count
		bot_count = count
		for i in range(prev, count):
			_pop[i] = 0.0
		bot_count_changed.emit(bot_count)
		if is_inside_tree():
			Audio.play(&"ui.toggle")
			queue_redraw()

func on_key_input(keycode: Key) -> void:
	match keycode:
		KEY_3, KEY_KP_3:
			set_bot_count(3)
		KEY_5, KEY_KP_5:
			set_bot_count(5)
		KEY_7, KEY_KP_7:
			set_bot_count(7)

func _btn_rect(i: int) -> Rect2:
	return Rect2(Vector2(float(i) * (BTN.x + GAP), 0.0), BTN)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		for i in range(3):
			if _btn_rect(i).has_point(event.position):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(3):
			if _btn_rect(i).has_point(event.position):
				grab_focus()
				set_bot_count(VALID_COUNTS[i])
				accept_event()
	elif event is InputEventKey and event.pressed and has_focus():
		var idx := VALID_COUNTS.find(bot_count)
		if event.keycode == KEY_LEFT:
			set_bot_count(VALID_COUNTS[maxi(0, idx - 1)])
			accept_event()
		elif event.keycode == KEY_RIGHT:
			set_bot_count(VALID_COUNTS[mini(2, idx + 1)])
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()

func _process(delta: float) -> void:
	var dirty := false
	for i in range(7):
		if _pop[i] < 1.0:
			_pop[i] = minf(1.0, _pop[i] + delta / 0.25)
			dirty = true
	if dirty:
		queue_redraw()

func _draw() -> void:
	var font := ThemeFactory.heading_font()
	for i in range(3):
		var r := _btn_rect(i)
		var sel := VALID_COUNTS[i] == bot_count
		if sel:
			draw_style_box(ThemeFactory.stylebox(Color(Palette.UI_ACCENT, 0.25), 16), r.grow(6.0))
		var bg := Palette.UI_ACCENT if sel else (Color("#26325A") if _hover == i else Color("#1E2744"))
		var border := Color.WHITE if (sel and has_focus()) else (Palette.UI_ACCENT if _hover == i else Palette.UI_STROKE)
		draw_style_box(ThemeFactory.stylebox(bg, 14, border, 2), r)
		var txt := str(VALID_COUNTS[i])
		var fs := 40
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, r.position + Vector2((r.size.x - tw) * 0.5, r.size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#0B1020") if sel else Palette.UI_TEXT)
	# Bot preview: helmet heads in bot colours
	var x0 := 3.0 * BTN.x + 2.0 * GAP + 36.0
	for i in range(bot_count):
		if i >= Data.bots.size():
			break
		var prof: BotProfile = Data.bots[i]
		var k := _pop[i]
		var s := 0.6 + 0.4 * k + 0.15 * sin(k * PI)
		var c := Vector2(x0 + float(i) * 44.0, BTN.y * 0.5)
		draw_circle(c, 18.0 * s + 2.5, Palette.OUTLINE)
		draw_circle(c, 18.0 * s, prof.primary)
		draw_rect(Rect2(c + Vector2(-3.0, -5.0) * s, Vector2(16.0, 10.0) * s), prof.visor)
