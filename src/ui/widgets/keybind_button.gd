# Implements §8.8 remapping: click (or focus + Enter) -> "Press a key or mouse button…",
# captures the next key / mouse button (wheel only for switch_weapon), Esc cancels,
# Backspace clears (never the pause primary). Conflicts swap through SettingsStore.
class_name KeybindButton
extends Button

signal rebound(action: StringName, swapped_with: StringName)

var action: StringName
var slot: int
var listening: bool = false

func _init(p_action: StringName, p_slot: int) -> void:
	action = p_action
	slot = p_slot
	custom_minimum_size = Vector2(230, 52)
	focus_mode = Control.FOCUS_ALL
	add_theme_font_size_override("font_size", 22)
	toggle_mode = false
	refresh()
	pressed.connect(_start_listening)

func refresh() -> void:
	listening = false
	var b: String = Settings.binding(action)[slot]
	text = InputBindings.label(b)
	modulate = Color.WHITE if not b.is_empty() else Color(1, 1, 1, 0.55)

func _start_listening() -> void:
	if listening:
		return
	listening = true
	text = "Press a key…"
	tooltip_text = "Esc = cancel · Backspace = clear"
	Audio.play(&"ui.remap.listen")

func _input(event: InputEvent) -> void:
	if not listening:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		var ke := event as InputEventKey
		var code := ke.physical_keycode if ke.physical_keycode != KEY_NONE else ke.keycode
		get_viewport().set_input_as_handled()
		if code == KEY_ESCAPE:
			Audio.play(&"ui.back")
			refresh()
			return
		if code == KEY_BACKSPACE:
			if action == &"pause" and slot == 0:
				Audio.play(&"ui.error")
				refresh()
				return
			_apply("")
			return
		_apply("key:" + OS.get_keycode_string(code))
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var b := ""
		match mb.button_index:
			MOUSE_BUTTON_LEFT: b = "mouse:left"
			MOUSE_BUTTON_RIGHT: b = "mouse:right"
			MOUSE_BUTTON_MIDDLE: b = "mouse:middle"
			MOUSE_BUTTON_XBUTTON1: b = "mouse:x1"
			MOUSE_BUTTON_XBUTTON2: b = "mouse:x2"
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if action == &"switch_weapon":
					b = "mouse:wheel"
		get_viewport().set_input_as_handled()
		if b.is_empty():
			Audio.play(&"ui.error")
			return
		_apply(b)

func _apply(binding: String) -> void:
	# Escape is reserved for pause; the pause primary can never be cleared (§8.7, §8.8)
	if action == &"pause" and slot == 0 and binding != "key:Escape":
		Audio.play(&"ui.error")
		refresh()
		return
	if binding == "key:Escape" and action != &"pause":
		Audio.play(&"ui.error")
		refresh()
		return
	var swapped := Settings.set_binding(action, slot, binding)
	Audio.play(&"ui.remap.bound")
	refresh()
	rebound.emit(action, swapped)
