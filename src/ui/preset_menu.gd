# Implements §8.2 Preset menu: one screen with three choices (bots 3/5/7, mode cards,
# duration spin wheel), every choice pre-selected (Mini Post · 5 bots · 7 min), ENTER
# BATTLE focused on open, gear -> settings, Quit -> confirm. Keyboard: Enter starts from
# anywhere, Esc quits (confirm), 3/5/7 bots, M mode, +/- duration, Tab cycles focus.
class_name PresetMenu
extends Control

signal start_requested(config: MatchConfig)
signal settings_requested()
signal quit_requested()

const PANEL_SIZE := Vector2(880, 560)

var bots_toggle: BotsToggle
var mini_card: ModeCard
var sniper_card: ModeCard
var spin: SpinWheel
var enter_btn: Button
var summary_label: Label
var mode: StringName = &"mini_post"
var _t: float = 0.0
var _logo: Control

func _init(preset: MatchConfig = null) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	if preset:
		bots_toggle.bot_count = preset.bot_count
		spin.value = clampi(preset.duration_s / 60, SpinWheel.MIN_VALUE, SpinWheel.MAX_VALUE)
		_set_mode(preset.mode, false)
	_update_summary()

func _build() -> void:
	# Logo + subtitle
	_logo = Control.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place_center_x(_logo, 40, Vector2(900, 220))
	_logo.draw.connect(_draw_logo.bind(_logo))
	add_child(_logo)
	var sub := UiKit.label("Outpost Deathmatch", 24, Palette.UI_SUBTEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.place_center_x(sub, 236, Vector2(600, 36))
	add_child(sub)

	# Settings panel
	var panel := UiKit.panel(PANEL_SIZE)
	UiKit.place_center_x(panel, 290, PANEL_SIZE)
	add_child(panel)

	panel.add_child(_row_label("BOTS", Vector2(40, 40)))
	bots_toggle = BotsToggle.new()
	bots_toggle.position = Vector2(40, 76)
	bots_toggle.size = bots_toggle.custom_minimum_size
	bots_toggle.bot_count_changed.connect(func(_n: int) -> void: _update_summary())
	panel.add_child(bots_toggle)

	panel.add_child(_row_label("MODE", Vector2(40, 180)))
	mini_card = ModeCard.new(&"mini_post", "MINI POST", "All weapons · Magnum start", [&"ak47", &"magnum"])
	mini_card.position = Vector2(40, 216)
	mini_card.size = mini_card.custom_minimum_size
	mini_card.chosen.connect(func(m: StringName) -> void: _set_mode(m, true))
	panel.add_child(mini_card)
	sniper_card = ModeCard.new(&"sniper_post", "SNIPER POST", "Black Arrow + Frags only", [&"m93ba"])
	sniper_card.position = Vector2(460, 216)
	sniper_card.size = sniper_card.custom_minimum_size
	sniper_card.chosen.connect(func(m: StringName) -> void: _set_mode(m, true))
	panel.add_child(sniper_card)

	panel.add_child(_row_label("DURATION", Vector2(40, 370)))
	spin = SpinWheel.new()
	spin.position = Vector2(40, 400)
	spin.size = SpinWheel.WIDGET_SIZE
	spin.value_changed.connect(func(_v: int) -> void: _update_summary())
	panel.add_child(spin)

	summary_label = UiKit.label("", 30, Palette.UI_TEXT, true)
	summary_label.position = Vector2(300, 440)
	summary_label.size = Vector2(540, 44)
	panel.add_child(summary_label)
	var keys := UiKit.label("3 / 5 / 7  bots    M  mode    + / −  minutes", 18, Palette.UI_SUBTEXT)
	keys.position = Vector2(300, 492)
	keys.size = Vector2(540, 28)
	panel.add_child(keys)

	# ENTER BATTLE
	enter_btn = UiKit.gold_button("ENTER BATTLE", Vector2(520, 96))
	UiKit.place_center_x(enter_btn, 870, Vector2(520, 96))
	enter_btn.pressed.connect(_on_enter)
	add_child(enter_btn)
	var hint := UiKit.label("Press Enter", 18, Palette.UI_SUBTEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.place_center_x(hint, 976, Vector2(300, 28))
	add_child(hint)

	# Gear (top-right) and Quit (bottom-left)
	var gear := Button.new()
	gear.text = "⚙"
	gear.tooltip_text = "Settings — controls, audio, display"
	gear.add_theme_font_size_override("font_size", 40)
	gear.anchor_left = 1.0
	gear.anchor_right = 1.0
	gear.offset_left = -104
	gear.offset_right = -40
	gear.offset_top = 40
	gear.offset_bottom = 104
	gear.pressed.connect(func() -> void: Audio.play(&"ui.click"); settings_requested.emit())
	add_child(gear)
	var quit := UiKit.button("Quit (Esc)", Vector2(220, 56), 24)
	quit.anchor_top = 1.0
	quit.anchor_bottom = 1.0
	quit.offset_left = 40
	quit.offset_right = 260
	quit.offset_top = -96
	quit.offset_bottom = -40
	quit.pressed.connect(func() -> void: quit_requested.emit())
	add_child(quit)

	# Focus chain: bots -> mode cards -> spin -> ENTER -> gear -> quit
	bots_toggle.focus_next = bots_toggle.get_path_to(mini_card)
	mini_card.focus_next = mini_card.get_path_to(sniper_card)
	sniper_card.focus_next = sniper_card.get_path_to(spin)
	spin.focus_next = spin.get_path_to(enter_btn)

func _row_label(text: String, pos: Vector2) -> Label:
	var l := UiKit.label(text, 22, Palette.UI_SUBTEXT, true)
	l.position = pos
	l.size = Vector2(300, 30)
	return l

func _ready() -> void:
	enter_btn.grab_focus()

func _set_mode(m: StringName, play_sound: bool) -> void:
	mode = m
	mini_card.set_selected(m == &"mini_post")
	sniper_card.set_selected(m == &"sniper_post")
	if play_sound and is_inside_tree():
		Audio.play(&"ui.toggle")
	_update_summary()

func current_config() -> MatchConfig:
	return MatchConfig.new(mode, bots_toggle.bot_count, spin.value * 60, randi())

func _update_summary() -> void:
	if summary_label == null:
		return
	var mode_name := "Mini Post" if mode == &"mini_post" else "Sniper Post"
	summary_label.text = "%s · %d bots · %d min" % [mode_name, bots_toggle.bot_count, spin.value]

func _on_enter() -> void:
	start_requested.emit(current_config())

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var k := (event as InputEventKey).keycode
	match k:
		KEY_ENTER, KEY_KP_ENTER:
			Audio.play(&"ui.click")
			_on_enter()
		KEY_ESCAPE:
			quit_requested.emit()
		KEY_3, KEY_5, KEY_7, KEY_KP_3, KEY_KP_5, KEY_KP_7:
			bots_toggle.on_key_input(k)
		KEY_M:
			_set_mode(&"sniper_post" if mode == &"mini_post" else &"mini_post", true)
		KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
			spin.adjust(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			spin.adjust(-1)
		KEY_LEFT, KEY_RIGHT:
			if mini_card.has_focus() or sniper_card.has_focus():
				_set_mode(&"sniper_post" if mode == &"mini_post" else &"mini_post", true)
				(sniper_card if mode == &"sniper_post" else mini_card).grab_focus()
			else:
				return
		_:
			return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_t += delta
	# Idle pulse 1.00 <-> 1.03 at 1.2 Hz
	var s := 1.0 + 0.015 * (1.0 + sin(_t * TAU * 1.2))
	enter_btn.pivot_offset = enter_btn.size * 0.5
	enter_btn.scale = Vector2(s, s)
	_logo.queue_redraw()

func _draw() -> void:
	# Vertical gradient overlay: #0B1020 α 0.2 top -> α 0.75 bottom
	var sz := size
	var top := Color(0.043, 0.063, 0.125, 0.2)
	var bottom := Color(0.043, 0.063, 0.125, 0.75)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]),
		PackedColorArray([top, top, bottom, bottom]))

func _draw_logo(c: Control) -> void:
	var font := ThemeFactory.heading_font()
	var txt := "SKYRA"
	var fs := 120
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0 * 4.0
	var x := (c.size.x - w) * 0.5
	var y := 150.0
	# Animated jet-flame underline: two exhaust streaks (1.5 s loop)
	var k := fmod(_t, 1.5) / 1.5
	for i in range(2):
		var off := fmod(k + i * 0.5, 1.0)
		var lx := x + w * 0.12
		var streak_len := w * (0.55 + 0.2 * sin(off * TAU))
		var yy := y + 26.0 + i * 12.0
		c.draw_line(Vector2(lx, yy), Vector2(lx + streak_len, yy), Color(Palette.UI_ACCENT, 0.25 + 0.3 * (1.0 - off)), 8.0 - i * 3.0)
		c.draw_line(Vector2(lx + streak_len * off, yy), Vector2(lx + streak_len * minf(1.0, off + 0.25), yy), Color(1.0, 0.8, 0.4, 0.9), 4.0)
	# Letters with a white -> cyan vertical feel (cyan glow behind, letter spacing 12)
	var cx := x
	for ch in txt:
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string_outline(font, Vector2(cx, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, Color(Palette.UI_ACCENT, 0.25))
		c.draw_string_outline(font, Vector2(cx, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color("#0B1020"))
		c.draw_string(font, Vector2(cx, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#E8FBFF"))
		c.draw_string(font, Vector2(cx, y - fs * 0.02), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.UI_ACCENT, 0.35))
		cx += cw + 12.0
