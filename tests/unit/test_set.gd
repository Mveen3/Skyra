# Implements §10 test requirements T-SET-01..07.
class_name TestSet
extends RefCounted

func _setup_test_dir(sub_name: String) -> String:
	var path := "/tmp/skyra_test_settings_" + sub_name + "_" + str(int(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(path)
	return path

func test_set_01_round_trip() -> void:
	var dir := _setup_test_dir("roundtrip")
	OS.set_environment("SKYRA_CONFIG_DIR", dir)

	var store := SettingsStore.new()
	store._ready()

	# Modify settings
	store.data.audio["master"] = 0.42
	store.data.audio["sfx"] = 0.88
	store.data.display["fullscreen"] = true
	store.data.display["show_fps"] = true
	store.set_binding(&"fire", 0, "Mouse:Left")
	store.set_binding(&"jetpack", 0, "Key:Space")
	store.save_now()

	# Re-load in a fresh store
	var store2 := SettingsStore.new()
	store2._ready()

	Assertions.assert_near(float(store2.data.audio["master"]), 0.42, 0.001, "Master volume preserved")
	Assertions.assert_near(float(store2.data.audio["sfx"]), 0.88, 0.001, "SFX volume preserved")
	Assertions.assert_true(bool(store2.data.display["fullscreen"]), "Fullscreen setting preserved")
	Assertions.assert_true(bool(store2.data.display["show_fps"]), "Show FPS preserved")
	Assertions.assert_eq(store2.binding(&"jetpack")[0], "Key:Space", "Keybinding preserved")

	OS.set_environment("SKYRA_CONFIG_DIR", "")
	store.free()
	store2.free()

func test_set_02_missing_file() -> void:
	var dir := _setup_test_dir("missing")
	OS.set_environment("SKYRA_CONFIG_DIR", dir)

	var store := SettingsStore.new()
	store._ready()

	var file_path := store.config_path()
	Assertions.assert_true(FileAccess.file_exists(file_path), "Defaults file was written when missing")
	Assertions.assert_near(float(store.data.audio["master"]), 0.9, 0.01, "Default master volume is 0.9")

	OS.set_environment("SKYRA_CONFIG_DIR", "")
	store.free()

func test_set_03_corrupt_file() -> void:
	var dir := _setup_test_dir("corrupt")
	OS.set_environment("SKYRA_CONFIG_DIR", dir)

	var file_path := dir.path_join("settings.json")
	var fa := FileAccess.open(file_path, FileAccess.WRITE)
	fa.store_string("{ INVALID JSON CORRUPTED ...")
	fa.close()

	var store := SettingsStore.new()
	store._ready()

	# Default should be loaded
	Assertions.assert_near(float(store.data.audio["master"]), 0.9, 0.01, "Default loaded after corruption")

	# Check that backup was created
	var dir_acc := DirAccess.open(dir)
	var found_backup := false
	if dir_acc:
		dir_acc.list_dir_begin()
		var fname := dir_acc.get_next()
		while fname != "":
			if fname.begins_with("settings.json.corrupt-"):
				found_backup = true
				break
			fname = dir_acc.get_next()
	Assertions.assert_true(found_backup, "Backup settings.json.corrupt-<ts> was created")

	OS.set_environment("SKYRA_CONFIG_DIR", "")
	store.free()

func test_set_04_path_resolution() -> void:
	# 1. SKYRA_CONFIG_DIR override
	OS.set_environment("SKYRA_CONFIG_DIR", "/custom/override/dir")
	var s1 := SettingsStore.new()
	Assertions.assert_eq(s1.config_dir(), "/custom/override/dir", "SKYRA_CONFIG_DIR override honored")
	OS.set_environment("SKYRA_CONFIG_DIR", "")

	# 2. XDG_CONFIG_HOME
	var orig_xdg := OS.get_environment("XDG_CONFIG_HOME")
	OS.set_environment("XDG_CONFIG_HOME", "/custom/xdg")
	var s2 := SettingsStore.new()
	Assertions.assert_eq(s2.config_dir(), "/custom/xdg/skyra", "XDG_CONFIG_HOME honored")
	if orig_xdg.is_empty():
		OS.set_environment("XDG_CONFIG_HOME", "/home/mveen/.config")
	else:
		OS.set_environment("XDG_CONFIG_HOME", orig_xdg)

	# 3. Default path ends with /.config/skyra/settings.json
	var s3 := SettingsStore.new()
	var default_path := s3.config_path()
	Assertions.assert_true(default_path.ends_with("/.config/skyra/settings.json"), "Default path ends with /.config/skyra/settings.json")
	s1.free()
	s2.free()
	s3.free()

func test_set_05_conflict_swap() -> void:
	var dir := _setup_test_dir("conflict")
	OS.set_environment("SKYRA_CONFIG_DIR", dir)

	var store := SettingsStore.new()
	store._ready()

	# By default: reload is key:R, pickup_swap is key:E (§8.7)
	# Rebind reload (slot 0) to key:E
	var swapped := store.set_binding(&"reload", 0, "key:E")
	Assertions.assert_eq(swapped, &"pickup_swap", "Swapped with pickup_swap")
	Assertions.assert_eq(store.binding(&"reload")[0], "key:E", "reload is now key:E")
	Assertions.assert_eq(store.binding(&"pickup_swap")[0], "key:R", "pickup_swap moved to key:R")

	OS.set_environment("SKYRA_CONFIG_DIR", "")
	store.free()

func test_set_06_input_map() -> void:
	var dir := _setup_test_dir("inputmap")
	OS.set_environment("SKYRA_CONFIG_DIR", dir)

	var store := SettingsStore.new()
	store._ready()
	store.apply_all()

	# After applying, a physical W key event triggers jetpack
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = true

	var triggers_jetpack := InputMap.event_is_action(ev, &"jetpack")
	Assertions.assert_true(triggers_jetpack, "Physical W key event triggers jetpack action")

	OS.set_environment("SKYRA_CONFIG_DIR", "")
	store.free()

func test_set_07_atomic_write() -> void:
	var dir := _setup_test_dir("atomic")
	OS.set_environment("SKYRA_CONFIG_DIR", dir)

	var store := SettingsStore.new()
	store._ready()
	store.save_now()

	# Check no .tmp file left behind
	var tmp_path := store.config_path() + ".tmp"
	Assertions.assert_false(FileAccess.file_exists(tmp_path), "No .tmp file left behind after save")

	# Check file is valid JSON
	var fa := FileAccess.open(store.config_path(), FileAccess.READ)
	Assertions.assert_true(fa != null, "Settings file readable")
	var txt := fa.get_as_text()
	fa.close()
	var json = JSON.parse_string(txt)
	Assertions.assert_true(typeof(json) == TYPE_DICTIONARY, "Settings file contains valid JSON")

	OS.set_environment("SKYRA_CONFIG_DIR", "")
	store.free()
