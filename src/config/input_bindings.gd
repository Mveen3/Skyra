# Implements §8.7, §8.8 and §8.9 InputBindings conversion and InputMap application.
class_name InputBindings
extends RefCounted

static func to_events(binding: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	if binding.is_empty():
		return result
		
	if binding.begins_with("key:"):
		var key_str := binding.substr(4)
		var keycode := OS.find_keycode_from_string(key_str)
		if keycode != KEY_NONE:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			ev.keycode = keycode
			result.append(ev)
	elif binding.begins_with("mouse:"):
		var btn_str := binding.substr(6)
		match btn_str:
			"left":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				result.append(ev)
			"right":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_RIGHT
				result.append(ev)
			"middle":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_MIDDLE
				result.append(ev)
			"wheel":
				var ev_up := InputEventMouseButton.new()
				ev_up.button_index = MOUSE_BUTTON_WHEEL_UP
				var ev_down := InputEventMouseButton.new()
				ev_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
				result.append(ev_up)
				result.append(ev_down)
			"wheel_up":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_WHEEL_UP
				result.append(ev)
			"wheel_down":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
				result.append(ev)
			"x1":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_XBUTTON1
				result.append(ev)
			"x2":
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_XBUTTON2
				result.append(ev)
	return result

static func from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		if code != KEY_NONE:
			return "key:" + OS.get_keycode_string(code)
	elif ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "mouse:left"
			MOUSE_BUTTON_RIGHT: return "mouse:right"
			MOUSE_BUTTON_MIDDLE: return "mouse:middle"
			MOUSE_BUTTON_WHEEL_UP: return "mouse:wheel_up"
			MOUSE_BUTTON_WHEEL_DOWN: return "mouse:wheel_down"
			MOUSE_BUTTON_XBUTTON1: return "mouse:x1"
			MOUSE_BUTTON_XBUTTON2: return "mouse:x2"
	return ""

static func label(binding: String) -> String:
	if binding.is_empty():
		return "---"
	if binding.begins_with("key:"):
		var key_str := binding.substr(4)
		var keycode := OS.find_keycode_from_string(key_str)
		if keycode != KEY_NONE:
			var localized := DisplayServer.keyboard_get_keycode_from_physical(keycode)
			if localized != KEY_NONE:
				return OS.get_keycode_string(localized)
		return key_str
	if binding.begins_with("mouse:"):
		var btn := binding.substr(6)
		match btn:
			"left": return "LMB"
			"right": return "RMB"
			"middle": return "MMB"
			"wheel": return "Wheel"
			"wheel_up": return "Wheel Up"
			"wheel_down": return "Wheel Down"
			"x1": return "Mouse 4"
			"x2": return "Mouse 5"
		return btn.capitalize()
	return binding

static func apply_all(bindings: Dictionary) -> void:
	for action in bindings:
		var action_name := StringName(action)
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)
		var slots: PackedStringArray = bindings[action]
		for b in slots:
			for ev in to_events(b):
				InputMap.action_add_event(action_name, ev)
				
	# Always ensure debug_overlay is registered (not remappable)
	if not InputMap.has_action(&"debug_overlay"):
		InputMap.add_action(&"debug_overlay")
	if InputMap.action_get_events(&"debug_overlay").is_empty():
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event(&"debug_overlay", ev)
