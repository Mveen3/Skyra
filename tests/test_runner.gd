# Implements §10.2 Test harness and runner.
class_name TestRunner
extends RefCounted

static func run_all(tree: SceneTree) -> void:
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
		var instance = script.new()
		var methods: Array = script.get_script_method_list()
		var file_name: String = script.resource_path.get_file()

		for m in methods:
			var m_name: String = m["name"]
			if m_name.begins_with("test_"):
				total_tests += 1
				Assertions.clear_failures()
				var t0 := Time.get_ticks_usec()
				
				instance.call(m_name)
				
				var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
				var failed := Assertions.has_failed()

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

	var report_text := "\n".join(report_lines)
	var fa := FileAccess.open("res://docs/TEST_REPORT.md", FileAccess.WRITE)
	if fa:
		fa.store_string(report_text)
		fa.close()

	var exit_code := 0 if failed_tests == 0 else 1
	tree.quit(exit_code)
