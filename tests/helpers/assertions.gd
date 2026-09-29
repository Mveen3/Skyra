# Implements §10.2 Test assertions.
class_name Assertions
extends RefCounted

static var current_failures: Array[String] = []

static func clear_failures() -> void:
	current_failures.clear()

static func has_failed() -> bool:
	return not current_failures.is_empty()

static func assert_true(cond: bool, msg: String = "Expected condition to be true") -> void:
	if not cond:
		current_failures.append("assert_true failed: %s" % msg)

static func assert_false(cond: bool, msg: String = "Expected condition to be false") -> void:
	if cond:
		current_failures.append("assert_false failed: %s" % msg)

static func assert_not_null(val, msg: String = "Expected value not to be null") -> void:
	if val == null:
		current_failures.append("assert_not_null failed: %s" % msg)

static func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		var detail := "Expected '%s', got '%s'" % [str(expected), str(actual)]
		if not msg.is_empty():
			detail = "%s (%s)" % [msg, detail]
		current_failures.append("assert_eq failed: %s" % detail)

static func assert_near(actual: float, expected: float, rel_tol: float = 0.03, msg: String = "") -> void:
	var diff := absf(actual - expected)
	var max_diff := maxf(absf(expected) * rel_tol, 0.0001)
	if diff > max_diff:
		var detail := "Expected ~%f ±%.1f%%, got %f (diff: %f > %f)" % [expected, rel_tol * 100.0, actual, diff, max_diff]
		if not msg.is_empty():
			detail = "%s (%s)" % [msg, detail]
		current_failures.append("assert_near failed: %s" % detail)

static func assert_between(val: float, lo: float, hi: float, msg: String = "") -> void:
	if val < lo or val > hi:
		var detail := "Expected %f in [%f, %f]" % [val, lo, hi]
		if not msg.is_empty():
			detail = "%s (%s)" % [msg, detail]
		current_failures.append("assert_between failed: %s" % detail)
