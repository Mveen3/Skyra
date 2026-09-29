class_name AudioManager
extends Node

const NUM_2D_VOICES: int = 32
const NUM_UI_VOICES: int = 8

const BASE_GAINS: Dictionary = {
	&"Master": 0.0,
	&"SFX": 0.0,
	&"SFX_Interior": 0.0,
	&"Ambient": -6.0,
	&"UI": -3.0
}

# Voice tracking
class Voice2D:
	var player: AudioStreamPlayer2D
	var cue: StringName = &""
	var category: StringName = &""
	var priority: int = 0
	var start_time_ms: int = 0
	var is_loop: bool = false
	var active: bool = false

class VoiceUI:
	var player: AudioStreamPlayer
	var cue: StringName = &""
	var priority: int = 0
	var start_time_ms: int = 0
	var active: bool = false

var _voices_2d: Array[Voice2D] = []
var _voices_ui: Array[VoiceUI] = []
var _voice_counter: int = 0
var _active_voice_map: Dictionary = {} # voice_id -> Voice2D or VoiceUI

var _listener: AudioListener2D = null

func _ready() -> void:
	setup_buses()
	_create_pools()
	_create_listener()

## Sets up the audio buses and default effects per §7.9.
func setup_buses() -> void:
	# Ensure Master bus has limiter
	var master_idx: int = AudioServer.get_bus_index(&"Master")
	if master_idx >= 0:
		var has_limiter: bool = false
		for i in range(AudioServer.get_bus_effect_count(master_idx)):
			if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
				has_limiter = true
				break
		if not has_limiter:
			var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
			limiter.ceiling_db = -1.0
			AudioServer.add_bus_effect(master_idx, limiter)

	# Ensure SFX bus
	var sfx_idx: int = AudioServer.get_bus_index(&"SFX")
	if sfx_idx < 0:
		sfx_idx = AudioServer.bus_count
		AudioServer.add_bus(sfx_idx)
		AudioServer.set_bus_name(sfx_idx, &"SFX")
		AudioServer.set_bus_send(sfx_idx, &"Master")
		AudioServer.set_bus_volume_db(sfx_idx, BASE_GAINS[&"SFX"])

	# Ensure SFX_Interior bus (parent: SFX, Reverb)
	var int_idx: int = AudioServer.get_bus_index(&"SFX_Interior")
	if int_idx < 0:
		int_idx = AudioServer.bus_count
		AudioServer.add_bus(int_idx)
		AudioServer.set_bus_name(int_idx, &"SFX_Interior")
		AudioServer.set_bus_send(int_idx, &"SFX")
		AudioServer.set_bus_volume_db(int_idx, BASE_GAINS[&"SFX_Interior"])
		var reverb: AudioEffectReverb = AudioEffectReverb.new()
		reverb.room_size = 0.45
		reverb.damping = 0.6
		reverb.wet = 0.22
		reverb.dry = 1.0
		AudioServer.add_bus_effect(int_idx, reverb)

	# Ensure Ambient bus (parent: Master, LowPassFilter)
	var amb_idx: int = AudioServer.get_bus_index(&"Ambient")
	if amb_idx < 0:
		amb_idx = AudioServer.bus_count
		AudioServer.add_bus(amb_idx)
		AudioServer.set_bus_name(amb_idx, &"Ambient")
		AudioServer.set_bus_send(amb_idx, &"Master")
		AudioServer.set_bus_volume_db(amb_idx, BASE_GAINS[&"Ambient"])
		var lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb_idx, lpf)

	# Ensure UI bus (parent: Master)
	var ui_idx: int = AudioServer.get_bus_index(&"UI")
	if ui_idx < 0:
		ui_idx = AudioServer.bus_count
		AudioServer.add_bus(ui_idx)
		AudioServer.set_bus_name(ui_idx, &"UI")
		AudioServer.set_bus_send(ui_idx, &"Master")
		AudioServer.set_bus_volume_db(ui_idx, BASE_GAINS[&"UI"])

func _create_pools() -> void:
	for i in range(NUM_2D_VOICES):
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.max_distance = 2600.0
		p.attenuation = 1.2
		p.panning_strength = 0.7
		add_child(p)
		
		var v: Voice2D = Voice2D.new()
		v.player = p
		_voices_2d.append(v)
		p.finished.connect(func(): v.active = false)

	for i in range(NUM_UI_VOICES):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)

		var v: VoiceUI = VoiceUI.new()
		v.player = p
		_voices_ui.append(v)
		p.finished.connect(func(): v.active = false)

func _create_listener() -> void:
	_listener = AudioListener2D.new()
	add_child(_listener)
	_listener.make_current()

## Updates listener position to follow Skyra render position.
func set_listener_pos(pos: Vector2) -> void:
	if _listener:
		_listener.global_position = pos

## Categorizes cue for voice limiting and priority (§7.9).
func get_cue_category(cue: StringName) -> StringName:
	var s: String = str(cue)
	if s.begins_with("sting."):
		return &"sting"
	elif s.begins_with("sfx.impact."):
		return &"impact"
	elif s.begins_with("sfx.explosion."):
		return &"explosion"
	elif s.begins_with("sfx.foot."):
		return &"footstep"
	elif s.contains(".fire"):
		return &"fire"
	elif s.begins_with("ui."):
		return &"ui"
	elif s.begins_with("amb."):
		return &"ambience"
	return &"other"

func get_cue_priority(cue: StringName, is_skyra: bool = false) -> int:
	var cat: StringName = get_cue_category(cue)
	match cat:
		&"sting": return 10
		&"fire": return 8 if is_skyra else 5
		&"explosion": return 7
		&"impact": return 3
		&"footstep": return 1
		_: return 2

## Returns max concurrent voices allowed for a category.
func get_category_limit(cat: StringName) -> int:
	match cat:
		&"impact": return 6
		&"explosion": return 4
		&"footstep": return 3
		_: return 32

## Plays a one-shot audio cue.
func play(cue: StringName, pos: Vector2 = Vector2.INF, opts: Dictionary = {}) -> int:
	var stream: AudioStreamWAV = CueLibrary.get_stream(cue)
	if stream == null:
		return 0

	var cat: StringName = get_cue_category(cue)
	var is_skyra: bool = bool(opts.get("is_skyra", false))
	var priority: int = get_cue_priority(cue, is_skyra)
	var now: int = Time.get_ticks_msec()

	# Non-positional / UI sound
	if pos == Vector2.INF or cat == &"ui" or cat == &"sting":
		var bus_name: StringName = &"UI" if cat == &"ui" else &"SFX"
		var v_ui: VoiceUI = _find_available_ui_voice(priority)
		if v_ui == null:
			return 0
		v_ui.cue = cue
		v_ui.priority = priority
		v_ui.start_time_ms = now
		v_ui.active = true
		v_ui.player.bus = bus_name
		v_ui.player.stream = stream
		v_ui.player.pitch_scale = float(opts.get("pitch_scale", 1.0))
		v_ui.player.volume_db = float(opts.get("volume_db", 0.0))
		v_ui.player.play()
		_voice_counter += 1
		_active_voice_map[_voice_counter] = v_ui
		return _voice_counter

	# Positional sound (2D)
	# Check category limit (e.g. max 6 impact voices)
	var cat_limit: int = get_category_limit(cat)
	var cat_active: int = 0
	var oldest_cat_voice: Voice2D = null
	var oldest_cat_time: int = 2147483647

	for v in _voices_2d:
		if v.active and v.category == cat:
			cat_active += 1
			if v.start_time_ms < oldest_cat_time:
				oldest_cat_time = v.start_time_ms
				oldest_cat_voice = v

	if cat_active >= cat_limit:
		# Steal oldest in same category
		if oldest_cat_voice:
			oldest_cat_voice.player.stop()
			oldest_cat_voice.active = false
		else:
			return 0

	var voice_2d: Voice2D = _find_available_2d_voice(priority)
	if voice_2d == null:
		return 0

	voice_2d.cue = cue
	voice_2d.category = cat
	voice_2d.priority = priority
	voice_2d.start_time_ms = now
	voice_2d.active = true
	voice_2d.is_loop = false

	# Bus routing: interior vs normal SFX
	var is_interior: bool = bool(opts.get("interior", false))
	voice_2d.player.bus = &"SFX_Interior" if is_interior else &"SFX"
	voice_2d.player.global_position = pos
	voice_2d.player.stream = stream
	voice_2d.player.max_distance = 3000.0 if is_skyra else 2600.0

	# Pitch variation
	var pitch_var: float = 0.0
	if cat == &"fire": pitch_var = 0.04
	elif cat == &"impact": pitch_var = 0.08
	elif cat == &"footstep": pitch_var = 0.10
	var base_pitch: float = float(opts.get("pitch_scale", 1.0))
	if pitch_var > 0.0:
		base_pitch *= randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	voice_2d.player.pitch_scale = base_pitch
	voice_2d.player.volume_db = float(opts.get("volume_db", 0.0))

	voice_2d.player.play()
	_voice_counter += 1
	_active_voice_map[_voice_counter] = voice_2d
	return _voice_counter

## Plays a looping cue attached to a position.
func play_loop(cue: StringName, pos: Vector2 = Vector2.INF) -> int:
	return play(cue, pos, {"is_loop": true})

func _find_available_2d_voice(req_priority: int) -> Voice2D:
	# 1. Search for inactive voice
	for v in _voices_2d:
		if not v.active:
			return v

	# 2. Search for voice to steal: lowest priority, oldest start time
	var lowest_pri: int = req_priority
	var oldest_time: int = 2147483647
	var victim: Voice2D = null

	for v in _voices_2d:
		if v.priority < lowest_pri or (v.priority == lowest_pri and v.start_time_ms < oldest_time):
			lowest_pri = v.priority
			oldest_time = v.start_time_ms
			victim = v

	if victim:
		victim.player.stop()
		victim.active = false
		return victim

	return null

func _find_available_ui_voice(req_priority: int) -> VoiceUI:
	for v in _voices_ui:
		if not v.active:
			return v

	var lowest_pri: int = req_priority
	var oldest_time: int = 2147483647
	var victim: VoiceUI = null

	for v in _voices_ui:
		if v.priority < lowest_pri or (v.priority == lowest_pri and v.start_time_ms < oldest_time):
			lowest_pri = v.priority
			oldest_time = v.start_time_ms
			victim = v

	if victim:
		victim.player.stop()
		victim.active = false
		return victim

	return null

func set_voice_pos(voice: int, pos: Vector2) -> void:
	if _active_voice_map.has(voice):
		var v = _active_voice_map[voice]
		if v is Voice2D and v.active:
			v.player.global_position = pos

func set_voice_volume(voice: int, linear: float) -> void:
	if _active_voice_map.has(voice):
		var v = _active_voice_map[voice]
		if v.active:
			v.player.volume_db = linear_to_db(maxf(linear, 0.0001))

func stop(voice: int, _fade_s: float = 0.05) -> void:
	if _active_voice_map.has(voice):
		var v = _active_voice_map[voice]
		if v.active:
			v.player.stop()
			v.active = false
		_active_voice_map.erase(voice)

## Sets user volume v in [0, 1] for a bus.
func set_user_volume(bus: StringName, v: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	if v <= 0.0:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		var base: float = BASE_GAINS.get(bus, 0.0)
		AudioServer.set_bus_volume_db(idx, base + linear_to_db(maxf(v, 0.0001)))

## Temporarily ducks bus volume by db for seconds.
func duck(bus: StringName, db: float, seconds: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var cur_db: float = AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, cur_db - db)
	get_tree().create_timer(seconds).timeout.connect(func():
		var tween: Tween = create_tween()
		tween.tween_property(AudioServer, "bus_volume_db", cur_db, 0.5)
	)

func set_paused(p: bool) -> void:
	var sfx_idx: int = AudioServer.get_bus_index(&"SFX")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, -80.0 if p else BASE_GAINS[&"SFX"])
	
	var amb_idx: int = AudioServer.get_bus_index(&"Ambient")
	if amb_idx >= 0 and AudioServer.get_bus_effect_count(amb_idx) > 0:
		var eff = AudioServer.get_bus_effect(amb_idx, 0)
		if eff is AudioEffectLowPassFilter:
			eff.cutoff_hz = 900.0 if p else 20000.0
