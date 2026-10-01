# Implements §8.6 Settings overlay (gear icon / pause menu): CONTROLS (remap rows grouped
# Movement / Combat / Weapons / Game), AUDIO (Master / SFX / Ambient / UI sliders with a
# preview on release) and DISPLAY (Fullscreen, VSync, Show FPS). Changes apply at once
# and are saved automatically (debounced) — there is no Save button.
class_name SettingsOverlay
extends Control

signal closed()

const GROUPS: Array[String] = ["Movement", "Combat", "Weapons", "Game"]
const AUDIO_ROWS := [["master", "Master", &"ui.click"], ["sfx", "Sound effects", &"sfx.magnum.fire"], ["ambient", "Ambience", &"amb.wind.low"], ["ui", "Interface", &"ui.click"]]

var _tabs: TabContainer
var _bind_buttons: Array[KeybindButton] = []
var _notice: Label
var _sliders: Dictionary = {}
var _checks: Dictionary = {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.dim_rect(0.8))
	var panel := UiKit.panel(Vector2(1100, 760), Color(Palette.UI_PANEL, 0.97))
	UiKit.place_center(panel, Vector2(1100, 760))
	add_child(panel)
	var title := UiKit.label("SETTINGS", 44, Palette.UI_TEXT, true)
	title.position = Vector2(40, 22)
	title.size = Vector2(400, 56)
	panel.add_child(title)

	_tabs = TabContainer.new()
	_tabs.position = Vector2(40, 90)
	_tabs.size = Vector2(1020, 560)
	_tabs.add_theme_font_override("font", ThemeFactory.heading_font())
	panel.add_child(_tabs)
	_tabs.add_child(_build_controls())
	_tabs.add_child(_build_audio())
	_tabs.add_child(_build_display())
	_tabs.set_tab_title(0, "  CONTROLS  ")
	_tabs.set_tab_title(1, "  AUDIO  ")
	_tabs.set_tab_title(2, "  DISPLAY  ")

	_notice = UiKit.label("", 22, Palette.UI_ACCENT2)
	_notice.position = Vector2(40, 670)
	_notice.size = Vector2(500, 32)
	panel.add_child(_notice)
	var reset := UiKit.button("Reset tab to defaults", Vector2(300, 56), 22)
	reset.position = Vector2(560, 668)
	reset.pressed.connect(_reset_tab)
	panel.add_child(reset)
	var back := UiKit.button("Back (Esc)", Vector2(200, 56), 22)
	back.position = Vector2(870, 668)
	back.pressed.connect(_close)
	panel.add_child(back)

func _ready() -> void:
	if not _bind_buttons.is_empty():
		_bind_buttons[0].grab_focus()

func _build_controls() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(980, 0)
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for group in GROUPS:
		var gl := UiKit.label(group.to_upper(), 22, Palette.UI_SUBTEXT, true)
		gl.custom_minimum_size = Vector2(0, 44)
		gl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		list.add_child(gl)
		for action_id in Data.input_bindings:
			var a: Dictionary = Data.input_bindings[action_id]
			if str(a.get("group", "")) != group or not bool(a.get("remappable", true)):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			var name_l := UiKit.label(str(a.get("label", action_id)), 24)
			name_l.custom_minimum_size = Vector2(440, 52)
			name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(name_l)
			for slot in range(2):
				var kb := KeybindButton.new(StringName(action_id), slot)
				kb.rebound.connect(_on_rebound)
				row.add_child(kb)
				_bind_buttons.append(kb)
			list.add_child(row)
	return scroll

func _build_audio() -> Control:
	var box := VBoxContainer.new()
	box.name = "Audio"
	box.add_theme_constant_override("separation", 26)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)
	for row_def in AUDIO_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		var l := UiKit.label(row_def[1], 26)
		l.custom_minimum_size = Vector2(260, 48)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 5
		s.custom_minimum_size = Vector2(560, 48)
		s.value = float(Settings.data.audio.get(row_def[0], 1.0)) * 100.0
		s.focus_mode = Control.FOCUS_ALL
		var pct := UiKit.label("%d %%" % int(s.value), 24)
		pct.custom_minimum_size = Vector2(100, 48)
		pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var bus: String = row_def[0]
		var preview: StringName = row_def[2]
		s.value_changed.connect(func(v: float) -> void:
			pct.text = "%d %%" % int(v)
			Settings.set_volume(bus, v / 100.0))
		s.drag_ended.connect(func(_changed: bool) -> void: _preview(preview))
		row.add_child(s)
		row.add_child(pct)
		box.add_child(row)
		_sliders[bus] = s
	return box

func _preview(cue: StringName) -> void:
	if str(cue).begins_with("amb."):
		var v := Audio.play(cue, Vector2.INF, {"bus": &"Ambient"})
		get_tree().create_timer(1.0, true, false, true).timeout.connect(func() -> void: Audio.stop(v))
	else:
		Audio.play(cue)

func _build_display() -> Control:
	var box := VBoxContainer.new()
	box.name = "Display"
	box.add_theme_constant_override("separation", 22)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)
	for item in [["fullscreen", "Fullscreen  (F11)"], ["vsync", "VSync"], ["show_fps", "Show FPS counter"]]:
		var cb := CheckButton.new()
		cb.text = item[1]
		cb.add_theme_font_size_override("font_size", 28)
		cb.button_pressed = bool(Settings.data.display.get(item[0], false))
		var key: String = item[0]
		cb.toggled.connect(func(on: bool) -> void:
			Audio.play(&"ui.toggle")
			Settings.set_display(key, on))
		box.add_child(cb)
		_checks[key] = cb
	return box

func _on_rebound(_action: StringName, swapped_with: StringName) -> void:
	for b in _bind_buttons:
		b.refresh()
	if swapped_with != &"":
		var label := str(Data.input_bindings.get(swapped_with, {}).get("label", swapped_with))
		_notice.text = "Swapped with %s" % label
	else:
		_notice.text = "Saved"

func _reset_tab() -> void:
	match _tabs.current_tab:
		0:
			Settings.reset_bindings()
			for b in _bind_buttons:
				b.refresh()
			_notice.text = "Controls reset to defaults"
		1:
			var defaults := SettingsData.new().audio
			for bus in _sliders:
				_sliders[bus].value = float(defaults[bus]) * 100.0
			_notice.text = "Audio reset to defaults"
		2:
			var defaults := SettingsData.new().display
			for key in _checks:
				_checks[key].button_pressed = bool(defaults[key])
			_notice.text = "Display reset to defaults"

func _close() -> void:
	Settings.save_now()
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	# Modal: no key reaches the screen underneath while the overlay is open
	get_viewport().set_input_as_handled()
	if event.pressed and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		for b in _bind_buttons:
			if b.listening:
				return
		Audio.play(&"ui.back")
		_close()
