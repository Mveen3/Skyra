# Implements §9.5 SettingsData and §8.9 Profile persistence.
class_name SettingsData
extends RefCounted

var schema_version: int = 1
var keybindings: Dictionary = {} # StringName -> PackedStringArray
var audio: Dictionary = {
	"master": 0.9,
	"sfx": 1.0,
	"ambient": 0.7,
	"ui": 0.8
}
var display: Dictionary = {
	"fullscreen": true,
	"vsync": true,
	"show_fps": false
}

func get_default_keybindings() -> Dictionary:
	return {
		&"move_left": PackedStringArray(["key:A", "key:Left"]),
		&"move_right": PackedStringArray(["key:D", "key:Right"]),
		&"jetpack": PackedStringArray(["key:W", "key:Space"]),
		&"crouch": PackedStringArray(["key:S", "key:Down"]),
		&"fire": PackedStringArray(["mouse:left", ""]),
		&"throw_grenade": PackedStringArray(["mouse:right", "key:G"]),
		&"reload": PackedStringArray(["key:R", ""]),
		&"switch_weapon": PackedStringArray(["key:Q", "mouse:wheel"]),
		&"weapon_slot_1": PackedStringArray(["key:1", ""]),
		&"weapon_slot_2": PackedStringArray(["key:2", ""]),
		&"pickup_swap": PackedStringArray(["key:E", ""]),
		&"drop_weapon": PackedStringArray(["key:X", ""]),
		&"scoreboard": PackedStringArray(["key:Tab", ""]),
		&"pause": PackedStringArray(["key:Escape", "key:P"]),
		&"restart_match": PackedStringArray(["key:F5", ""]),
		&"toggle_fullscreen": PackedStringArray(["key:F11", ""])
	}

func _init() -> void:
	keybindings = get_default_keybindings()
