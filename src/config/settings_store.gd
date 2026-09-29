# Implements §8.9 SettingsStore, profile persistence and conflict swapping.
class_name SettingsStore
extends Node

var data: SettingsData = null
var _debounce_timer: Timer

func _ready() -> void:
	data = SettingsData.new()
	_setup_debounce_timer()
	load_settings()

func _setup_debounce_timer() -> void:
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = 0.5
	_debounce_timer.timeout.connect(save_now)
	add_child(_debounce_timer)

func config_dir() -> String:
	var override := OS.get_environment("SKYRA_CONFIG_DIR")
	if not override.is_empty():
		return override
	var xdg := OS.get_environment("XDG_CONFIG_HOME")
	if not xdg.is_empty() and xdg.is_absolute_path():
		return xdg.path_join("skyra")
	return OS.get_config_dir().path_join("skyra")

func config_path() -> String:
	return config_dir().path_join("settings.json")

func load_settings() -> void:
	var path := config_path()
	var dir := config_dir()
	
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(dir)
		data = SettingsData.new()
		save_now()
		apply_all()
		return
		
	var fa := FileAccess.open(path, FileAccess.READ)
	if not fa:
		data = SettingsData.new()
		apply_all()
		return
		
	var txt := fa.get_as_text()
	fa.close()
	
	var json = JSON.parse_string(txt)
	if typeof(json) != TYPE_DICTIONARY:
		var ts := int(Time.get_unix_time_from_system())
		var corrupt_path := path + ".corrupt-" + str(ts)
		DirAccess.rename_absolute(path, corrupt_path)
		data = SettingsData.new()
		save_now()
		apply_all()
		EventBus.toast_requested.emit("Settings were reset (file was unreadable)", &"warning", 3.0)
		return
		
	var dict: Dictionary = json
	data = SettingsData.new()
	var defaults := data.get_default_keybindings()
	
	# Keybindings
	var loaded_kb: Dictionary = dict.get("keybindings", {})
	for action in defaults:
		if loaded_kb.has(str(action)):
			var raw_slots: Array = loaded_kb[str(action)]
			var s0: String = str(raw_slots[0]) if raw_slots.size() > 0 else ""
			var s1: String = str(raw_slots[1]) if raw_slots.size() > 1 else ""
			data.keybindings[action] = PackedStringArray([s0, s1])
		else:
			data.keybindings[action] = defaults[action]
			
	# Remove cross-action duplicates
	var seen_bindings := {}
	for action in data.keybindings:
		var slots: PackedStringArray = data.keybindings[action]
		for i in range(slots.size()):
			var b := slots[i]
			if b.is_empty():
				continue
			if seen_bindings.has(b):
				slots[i] = ""
			else:
				seen_bindings[b] = true
		data.keybindings[action] = slots

	# Audio
	var loaded_audio: Dictionary = dict.get("audio", {})
	for bus in ["master", "sfx", "ambient", "ui"]:
		if loaded_audio.has(bus):
			data.audio[bus] = clampf(float(loaded_audio[bus]), 0.0, 1.0)
			
	# Display
	var loaded_disp: Dictionary = dict.get("display", {})
	if loaded_disp.has("fullscreen"): data.display["fullscreen"] = bool(loaded_disp["fullscreen"])
	if loaded_disp.has("vsync"): data.display["vsync"] = bool(loaded_disp["vsync"])
	if loaded_disp.has("show_fps"): data.display["show_fps"] = bool(loaded_disp["show_fps"])
	
	apply_all()

func save_debounced() -> void:
	if _debounce_timer and _debounce_timer.is_inside_tree():
		_debounce_timer.start()
	else:
		save_now()

func save_now() -> void:
	if _debounce_timer and _debounce_timer.is_inside_tree():
		_debounce_timer.stop()
		
	var path := config_path()
	var dir := config_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	
	var out_dict := {
		"schema_version": data.schema_version,
		"keybindings": {},
		"audio": data.audio,
		"display": data.display
	}
	for action in data.keybindings:
		var arr: PackedStringArray = data.keybindings[action]
		out_dict["keybindings"][str(action)] = [arr[0], arr[1]]
		
	var json_str := JSON.stringify(out_dict, "  ")
	var tmp_path := path + ".tmp"
	var fa := FileAccess.open(tmp_path, FileAccess.WRITE)
	if fa:
		fa.store_string(json_str)
		fa.flush()
		fa.close()
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(tmp_path, path)

func binding(action: StringName) -> PackedStringArray:
	if data and data.keybindings.has(action):
		return data.keybindings[action]
	return PackedStringArray(["", ""])

func set_binding(action: StringName, slot: int, new_binding: String) -> StringName:
	var swapped_action: StringName = &""
	if not data or not data.keybindings.has(action):
		return swapped_action
		
	var old_binding: String = data.keybindings[action][slot]
	
	# Conflict check: check if new_binding is already bound elsewhere
	if not new_binding.is_empty():
		for other_action in data.keybindings:
			if other_action == action:
				continue
			var other_slots: PackedStringArray = data.keybindings[other_action]
			for s in range(other_slots.size()):
				if other_slots[s] == new_binding:
					# Swap
					other_slots[s] = old_binding
					data.keybindings[other_action] = other_slots
					swapped_action = other_action
					EventBus.keybinding_changed.emit(other_action)
					break
			if not swapped_action.is_empty():
				break
				
	var my_slots: PackedStringArray = data.keybindings[action]
	my_slots[slot] = new_binding
	data.keybindings[action] = my_slots
	
	InputBindings.apply_all(data.keybindings)
	EventBus.keybinding_changed.emit(action)
	save_debounced()
	return swapped_action

func reset_bindings() -> void:
	if data:
		data.keybindings = data.get_default_keybindings()
		InputBindings.apply_all(data.keybindings)
		for a in data.keybindings:
			EventBus.keybinding_changed.emit(a)
		save_debounced()

func set_volume(bus: String, v: float) -> void:
	if data and data.audio.has(bus):
		data.audio[bus] = clampf(v, 0.0, 1.0)
		apply_audio()
		EventBus.settings_changed.emit(&"audio")
		save_debounced()

func set_display(key: String, value) -> void:
	if data and data.display.has(key):
		data.display[key] = value
		apply_display()
		EventBus.settings_changed.emit(&"display")
		save_debounced()

func apply_all() -> void:
	apply_input()
	apply_audio()
	apply_display()

func apply_input() -> void:
	if data:
		InputBindings.apply_all(data.keybindings)

func apply_audio() -> void:
	if not data: return
	# Audio manager will also connect to settings_changed and apply bus volumes
	if is_inside_tree() and has_node("/root/Audio"):
		var audio_mgr = get_node("/root/Audio")
		for bus in ["master", "sfx", "ambient", "ui"]:
			if audio_mgr.has_method("set_user_volume"):
				audio_mgr.set_user_volume(StringName(bus), data.audio[bus])

func apply_display() -> void:
	if not data: return
	var fs: bool = data.display.get("fullscreen", true)
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
	var vs: bool = data.display.get("vsync", true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vs else DisplayServer.VSYNC_DISABLED)
