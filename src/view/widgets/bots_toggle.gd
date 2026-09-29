# Implements §8.2 Bots count segmented toggle widget (default 5, options 3, 5, 7).
class_name BotsToggle
extends Control

signal bot_count_changed(new_count: int)

const VALID_COUNTS: Array[int] = [3, 5, 7]
const DEFAULT_COUNT: int = 5

var bot_count: int = DEFAULT_COUNT

func _init(initial_count: int = DEFAULT_COUNT) -> void:
	set_bot_count(initial_count)

func set_bot_count(count: int) -> void:
	if count in VALID_COUNTS and count != bot_count:
		bot_count = count
		bot_count_changed.emit(bot_count)

func on_key_input(keycode: Key) -> void:
	match keycode:
		KEY_3, KEY_KP_3:
			set_bot_count(3)
		KEY_5, KEY_KP_5:
			set_bot_count(5)
		KEY_7, KEY_KP_7:
			set_bot_count(7)
