# Implements §7.11 / §9.6 CueLibrary: cue id -> AudioStream. Lookup order: optional
# override (assets/overrides/audio) -> committed generated WAV -> synthesized on the fly.
# Loop cues get LOOP_FORWARD over their full length (imported WAVs carry no loop points).
class_name CueLibrary
extends RefCounted

static var _cache: Dictionary = {}

static func get_stream(cue_id: StringName) -> AudioStream:
	if _cache.has(cue_id):
		return _cache[cue_id]
	var recipe: Dictionary = Data.cues.get(str(cue_id), {})
	var stream: AudioStream = null

	for path in ["res://assets/overrides/audio/%s.ogg" % str(cue_id), "res://assets/overrides/audio/%s.wav" % str(cue_id),
			"res://assets/audio/generated/%s.wav" % str(cue_id)]:
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStream:
				stream = s
				break

	if stream == null and not recipe.is_empty():
		stream = SfxSynth.render(recipe)

	if stream != null and bool(recipe.get("loop", false)):
		_make_loop(stream)
	if stream != null:
		_cache[cue_id] = stream
	return stream

static func _make_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(round(w.get_length() * float(w.mix_rate)))
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

static func preload_cues(cues: Array) -> void:
	for c in cues:
		get_stream(StringName(c))

static func clear_cache() -> void:
	_cache.clear()
