# Implements §7.11 / §9.6 CueLibrary: cue resolution and caching.
class_name CueLibrary
extends RefCounted

static var _cache: Dictionary = {}

static func get_stream(cue_id: StringName) -> AudioStreamWAV:
	if _cache.has(cue_id):
		return _cache[cue_id]

	# 1. Check committed generated wav
	var gen_path: String = "res://assets/audio/generated/%s.wav" % str(cue_id)
	if FileAccess.file_exists(gen_path):
		var s = load(gen_path)
		if s is AudioStreamWAV:
			_cache[cue_id] = s
			return s

	# 2. Check user sfx cache
	var user_path: String = "user://sfx_cache/%s.wav" % str(cue_id)
	if FileAccess.file_exists(user_path):
		var s = load(user_path)
		if s is AudioStreamWAV:
			_cache[cue_id] = s
			return s

	# 3. Synthesize on the fly from recipe
	var cues_dict: Dictionary = Data.cues
	var recipe: Dictionary = cues_dict.get(str(cue_id), {})
	if recipe.is_empty():
		recipe = cues_dict.get(cue_id, {})

	if not recipe.is_empty():
		var synthesized: AudioStreamWAV = SfxSynth.render(recipe)
		_cache[cue_id] = synthesized
		return synthesized

	return null

static func preload_cues(cues: Array) -> void:
	for c in cues:
		get_stream(StringName(c))

static func clear_cache() -> void:
	_cache.clear()
