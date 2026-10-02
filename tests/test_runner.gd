# Implements §10.2 Test harness and runner.
class_name TestRunner
extends RefCounted

## `filter` (from `--only=<substr>`) restricts the run to matching test files and
## skips writing the report, so partial runs never overwrite docs/TEST_REPORT.md.
static func run_all(tree: SceneTree, filter: String = "") -> void:
	print("========================================")
	print("           SKYRA TEST RUNNER            ")
	print("========================================")

	var start_time_usec := Time.get_ticks_usec()
	var report_lines: PackedStringArray = []
	report_lines.append("# Skyra Test Report")
	report_lines.append("")
	report_lines.append("| Status | Test File | Test Method | Duration | Failure |")
	report_lines.append("|---|---|---|---|---|")

	var test_classes: Array[GDScript] = [
		preload("res://tests/unit/test_boot.gd"),
		preload("res://tests/unit/test_data.gd"),
		preload("res://tests/unit/test_map.gd"),
		preload("res://tests/unit/test_ray.gd"),
		preload("res://tests/unit/test_grid.gd"),
		preload("res://tests/unit/test_mov.gd"),
		preload("res://tests/unit/test_cam.gd"),
		preload("res://tests/unit/test_wpn.gd"),
		preload("res://tests/unit/test_dmg.gd"),
		preload("res://tests/unit/test_inv.gd"),
		preload("res://tests/unit/test_sock.gd"),
		preload("res://tests/unit/test_nav.gd"),
		preload("res://tests/unit/test_ai.gd"),
		preload("res://tests/unit/test_dir.gd"),
		preload("res://tests/unit/test_spawn.gd"),
		preload("res://tests/unit/test_boost.gd"),
		preload("res://tests/unit/test_rule.gd"),
		preload("res://tests/unit/test_flow.gd"),
		preload("res://tests/unit/test_set.gd"),
		preload("res://tests/unit/test_ui.gd"),
		preload("res://tests/unit/test_aud.gd"),
		preload("res://tests/unit/test_fx.gd"),
		preload("res://tests/unit/test_final.gd")
	]

	var total_tests := 0
	var passed_tests := 0
	var failed_tests := 0

	for script in test_classes:
		var file_name: String = script.resource_path.get_file()
		if not filter.is_empty() and not file_name.contains(filter):
			continue
		var instance = script.new()
		var methods: Array = script.get_script_method_list()

		for m in methods:
			var m_name: String = m["name"]
			if m_name.begins_with("test_"):
				total_tests += 1
				Assertions.clear_failures()
				var t0 := Time.get_ticks_usec()
				
				var log_mark := _log_length()
				instance.call(m_name)

				var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
				# A script error aborts the test function silently; treat it as a failure
				var script_err := _script_error_since(log_mark)
				if not script_err.is_empty():
					Assertions.current_failures.append("script error: " + script_err)
				var failed := Assertions.has_failed() or not script_err.is_empty()

				if failed:
					failed_tests += 1
					var fail_str := "; ".join(Assertions.current_failures)
					print("FAIL: %s :: %s (%.1f ms) - %s" % [file_name, m_name, dt_ms, fail_str])
					report_lines.append("| ❌ FAIL | `%s` | `%s` | %.1f ms | %s |" % [file_name, m_name, dt_ms, fail_str.replace("|", "/")])
				else:
					passed_tests += 1
					print("PASS: %s :: %s (%.1f ms)" % [file_name, m_name, dt_ms])
					report_lines.append("| ✅ PASS | `%s` | `%s` | %.1f ms | - |" % [file_name, m_name, dt_ms])

	var total_elapsed_s := (Time.get_ticks_usec() - start_time_usec) / 1000000.0
	print("----------------------------------------")
	print("RESULTS: %d Total | %d Passed | %d Failed (%.2f s)" % [total_tests, passed_tests, failed_tests, total_elapsed_s])
	print("========================================")

	report_lines.append("")
	report_lines.append("## Summary")
	report_lines.append("- **Total:** %d" % total_tests)
	report_lines.append("- **Passed:** %d" % passed_tests)
	report_lines.append("- **Failed:** %d" % failed_tests)
	report_lines.append("- **Duration:** %.2f s" % total_elapsed_s)
	report_lines.append("- **Status:** %s" % ("ALL PASSED" if failed_tests == 0 else "FAILURES DETECTED"))

	if filter.is_empty():
		var report_text := "\n".join(report_lines)
		var fa := FileAccess.open("res://docs/TEST_REPORT.md", FileAccess.WRITE)
		if fa:
			fa.store_string(report_text)
			fa.close()

	var exit_code := 0 if failed_tests == 0 else 1
	tree.quit(exit_code)

const _LOG_PATH := "user://logs/godot.log"

static func _log_length() -> int:
	var f := FileAccess.open(_LOG_PATH, FileAccess.READ)
	return f.get_length() if f else -1

## First "SCRIPT ERROR" line Godot logged after `mark` (file logging is on by default).
static func _script_error_since(mark: int) -> String:
	if mark < 0:
		return ""
	var f := FileAccess.open(_LOG_PATH, FileAccess.READ)
	if f == null or f.get_length() <= mark:
		return ""
	f.seek(mark)
	var text := f.get_buffer(f.get_length() - mark).get_string_from_utf8()
	var i := text.find("SCRIPT ERROR:")
	if i < 0:
		return ""
	var line_end := text.find("\n", i)
	return text.substr(i + 14, (line_end - i - 14) if line_end > 0 else 200).strip_edges()
