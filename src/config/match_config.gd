# Implements §9.5 MatchConfig.
class_name MatchConfig
extends RefCounted

var mode: StringName = &"mini_post"
var bot_count: int = 5
var duration_s: int = 420
var rng_seed: int = 0

func _init(p_mode: StringName = &"mini_post", p_bot_count: int = 5, p_duration_s: int = 420, p_seed: int = 0) -> void:
	mode = p_mode
	bot_count = p_bot_count
	duration_s = p_duration_s
	rng_seed = p_seed
