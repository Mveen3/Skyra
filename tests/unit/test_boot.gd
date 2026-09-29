# Implements §10.4 T-BOOT-01 Headless boot test.
class_name TestBoot
extends RefCounted

func test_boot_01_headless_boot() -> void:
	Assertions.assert_true(Data != null, "Data autoload exists")
	Assertions.assert_true(Data.errors.is_empty(), "Data errors empty")
	Assertions.assert_true(Settings != null, "Settings autoload exists")
	Assertions.assert_true(EventBus != null, "EventBus autoload exists")
	Assertions.assert_true(Log != null, "Log autoload exists")
