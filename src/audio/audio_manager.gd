# Implements §7.9 audio engine: buses (Master+limiter, SFX, SFX_Interior+reverb,
# Ambient+low-pass, UI), voice pools (32 positional + 8 non-positional), per-category
# voice limits with priority stealing, pitch variation, ducking, pause handling and the
# listener that follows Skyra (autoload "Audio").
class_name AudioManager
extends Node

const NUM_2D_VOICES: int = 32
const NUM_UI_VOICES: int = 10

const BASE_GAINS: Dictionary = {
	&"Master": 0.0,
	&"SFX": 0.0,
	&"SFX_Interior": 0.0,
	&"Ambient": -6.0,
	&"UI": -3.0
}
const USER_BUSES: Dictionary = {&"master": &"Master", &"sfx": &"SFX", &"ambient": &"Ambient", &"ui": &"UI"}

class Voice2D:
	var player: AudioStreamPlayer2D
	var cue: StringName = &""
	var category: StringName = &""
	var priority: int = 0
	var start_time_ms: int = 0
	var is_loop: bool = false
	var active: bool = false
	var id: int = 0

class VoiceUI:
	var player: AudioStreamPlayer
	var cue: StringName = &""
	var category: StringName = &""
	var priority: int = 0
	var start_time_ms: int = 0
	var is_loop: bool = false
	var active: bool = false
	var id: int = 0

var _voices_2d: Array[Voice2D] = []
var _voices_ui: Array[VoiceUI] = []
var _voice_counter: int = 0
var _active_voice_map: Dictionary = {} # voice_id -> Voice2D or VoiceUI

var _listener: AudioListener2D = null
var _user_db: Dictionary = {} # bus -> user volume dB
var _duck_db: Dictionary = {} # bus -> current duck offset dB
var _paused: bool = false
var interior_check: Callable = Callable() # pos -> bool, set by the match (SFX_Interior routing)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_buses()
	_create_pools()
	_create_listener()
	EventBus.pause_changed.connect(set_paused)
	# Settings loads before this autoload exists, so apply the saved volumes here
	if Settings.data:
		for key in USER_BUSES:
			set_user_volume(key, float(Settings.data.audio.get(str(key), 1.0)))

## Sets up the audio buses and default effects per §7.9.
func setup_buses() -> void:
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
	_ensure_bus(&"SFX", &"Master")
	if _ensure_bus(&"SFX_Interior", &"SFX"):
		var reverb: AudioEffectReverb = AudioEffectReverb.new()
		reverb.room_size = 0.45
		reverb.damping = 0.6
		reverb.wet = 0.22
		reverb.dry = 1.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"SFX_Interior"), reverb)
	if _ensure_bus(&"Ambient", &"Master"):
		var lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Ambient"), lpf)
	_ensure_bus(&"UI", &"Master")
	# (Re)initialising the buses also clears any pause filtering
	_paused = false
	var amb_idx: int = AudioServer.get_bus_index(&"Ambient")
	for i in range(AudioServer.get_bus_effect_count(amb_idx)):
		var eff = AudioServer.get_bus_effect(amb_idx, i)
		if eff is AudioEffectLowPassFilter:
			eff.cutoff_hz = 20000.0
	for bus in BASE_GAINS:
		_apply_bus_volume(bus)

## Creates `bus_name` (sending to `parent`) if missing; returns true when created.
func _ensure_bus(bus_name: StringName, parent: StringName) -> bool:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return false
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, parent)
	return true

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
		p.finished.connect(func(): _release(v))
	for i in range(NUM_UI_VOICES):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		var v: VoiceUI = VoiceUI.new()
		v.player = p
		_voices_ui.append(v)
		p.finished.connect(func(): _release(v))

func _release(v) -> void:
	v.active = false
	if _active_voice_map.get(v.id) == v:
		_active_voice_map.erase(v.id)

func _create_listener() -> void:
	_listener = AudioListener2D.new()
	add_child(_listener)
	_listener.make_current()

## Listener follows Skyra's render position (death position while dead), §7.9.
func set_listener_pos(pos: Vector2) -> void:
	if _listener:
		_listener.global_position = pos

## Categorizes a cue for voice limits and priority (§7.9).
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
	elif s == "sfx.grenade.bounce":
		return &"grenade_bounce"
	elif s == "sfx.saw.spin_loop":
		return &"saw_loop"
	elif s.contains(".fire"):
		return &"fire"
	elif s.begins_with("ui."):
		return &"ui"
	elif s.begins_with("amb."):
		return &"ambience"
	return &"other"

func get_cue_priority(cue: StringName, is_skyra: bool = false) -> int:
	match get_cue_category(cue):
		&"sting": return 10
		&"fire": return 8 if is_skyra else 5
		&"explosion": return 7
		&"impact": return 3
		&"footstep": return 1
		&"ambience": return 6
	return 4

## Max concurrent voices for a category (weapon fire is per shooter class, see play()).
func get_category_limit(cat: StringName, is_skyra: bool = false) -> int:
	match cat:
		&"impact": return 6
		&"explosion": return 4
		&"footstep": return 3
		&"grenade_bounce": return 4
		&"saw_loop": return 4
		&"fire": return 4 if is_skyra else 3
	return 32

## Plays a cue. `pos` = Vector2.INF for non-positional. opts: is_skyra, pitch_scale,
## volume_db, bus, interior, loop. Returns a voice id (0 = not played).
func play(cue: StringName, pos: Vector2 = Vector2.INF, opts: Dictionary = {}) -> int:
	var stream: AudioStream = CueLibrary.get_stream(cue)
	if stream == null:
		return 0
	var cat: StringName = get_cue_category(cue)
	var is_skyra: bool = bool(opts.get("is_skyra", false))
	var priority: int = get_cue_priority(cue, is_skyra)
	var now: int = Time.get_ticks_msec()
	var is_loop: bool = bool(opts.get("loop", false))

	var pitch_var: float = 0.0
	if cat == &"fire": pitch_var = 0.04
	elif cat == &"impact": pitch_var = 0.08
	elif cat == &"footstep": pitch_var = 0.10
	var pitch: float = float(opts.get("pitch_scale", 1.0))
	if pitch_var > 0.0:
		pitch *= randf_range(1.0 - pitch_var, 1.0 + pitch_var)

	# Non-positional voices: UI, stings, low-health loop, boost loops…
	if pos == Vector2.INF or cat == &"ui" or cat == &"sting":
		var bus_name: StringName = opts.get("bus", &"UI" if cat == &"ui" else (&"Ambient" if cat == &"ambience" else &"SFX"))
		var v_ui: VoiceUI = _find_available_ui_voice(priority)
		if v_ui == null:
			return 0
		v_ui.cue = cue
		v_ui.category = cat
		v_ui.priority = priority
		v_ui.start_time_ms = now
		v_ui.active = true
		v_ui.is_loop = is_loop
		v_ui.player.bus = bus_name
		v_ui.player.stream = stream
		v_ui.player.pitch_scale = pitch
		v_ui.player.volume_db = float(opts.get("volume_db", 0.0))
		v_ui.player.play()
		return _register(v_ui)

	# Positional voices: enforce the per-category limit by stealing the oldest
	var cat_limit: int = get_category_limit(cat, is_skyra)
	var cat_active: int = 0
	var oldest_cat_voice: Voice2D = null
	for v in _voices_2d:
		if v.active and v.category == cat:
			cat_active += 1
			if oldest_cat_voice == null or v.start_time_ms < oldest_cat_voice.start_time_ms:
				oldest_cat_voice = v
	if cat_active >= cat_limit:
		if oldest_cat_voice == null or oldest_cat_voice.is_loop:
			return 0
		oldest_cat_voice.player.stop()
		_release(oldest_cat_voice)

	var voice_2d: Voice2D = _find_available_2d_voice(priority)
	if voice_2d == null:
		return 0
	voice_2d.cue = cue
	voice_2d.category = cat
	voice_2d.priority = priority
	voice_2d.start_time_ms = now
	voice_2d.active = true
	voice_2d.is_loop = is_loop
	var interior: bool = bool(opts.get("interior", interior_check.is_valid() and bool(interior_check.call(pos))))
	voice_2d.player.bus = opts.get("bus", &"SFX_Interior" if interior else &"SFX")
	voice_2d.player.global_position = pos
	voice_2d.player.stream = stream
	voice_2d.player.max_distance = 3000.0 if is_skyra else 2600.0
	voice_2d.player.pitch_scale = pitch
	voice_2d.player.volume_db = float(opts.get("volume_db", 0.0))
	voice_2d.player.play()
	return _register(voice_2d)

func _register(v) -> int:
	_voice_counter += 1
	v.id = _voice_counter
	_active_voice_map[_voice_counter] = v
	return _voice_counter

## Plays a looping cue (positional when `pos` is given); stop it with stop(id).
func play_loop(cue: StringName, pos: Vector2 = Vector2.INF, opts: Dictionary = {}) -> int:
	var o := opts.duplicate()
	o["loop"] = true
	return play(cue, pos, o)

func _find_available_2d_voice(req_priority: int) -> Voice2D:
	for v in _voices_2d:
		if not v.active:
			return v
	var victim: Voice2D = null
	for v in _voices_2d:
		if v.is_loop:
			continue
		if v.priority <= req_priority and (victim == null or v.priority < victim.priority or (v.priority == victim.priority and v.start_time_ms < victim.start_time_ms)):
			victim = v
	if victim:
		victim.player.stop()
		_release(victim)
	return victim

func _find_available_ui_voice(req_priority: int) -> VoiceUI:
	for v in _voices_ui:
		if not v.active:
			return v
	var victim: VoiceUI = null
	for v in _voices_ui:
		if v.is_loop:
			continue
		if v.priority <= req_priority and (victim == null or v.priority < victim.priority or (v.priority == victim.priority and v.start_time_ms < victim.start_time_ms)):
			victim = v
	if victim:
		victim.player.stop()
		_release(victim)
	return victim

func is_playing(voice: int) -> bool:
	return _active_voice_map.has(voice)

func set_voice_pos(voice: int, pos: Vector2) -> void:
	var v = _active_voice_map.get(voice)
	if v is Voice2D:
		v.player.global_position = pos

func set_voice_volume(voice: int, linear: float) -> void:
	var v = _active_voice_map.get(voice)
	if v != null:
		v.player.volume_db = linear_to_db(maxf(linear, 0.0001))

func set_voice_pitch(voice: int, pitch: float) -> void:
	var v = _active_voice_map.get(voice)
	if v != null:
		v.player.pitch_scale = maxf(0.01, pitch)

func stop(voice: int, _fade_s: float = 0.05) -> void:
	var v = _active_voice_map.get(voice)
	if v != null:
		v.player.stop()
		_release(v)

func stop_all() -> void:
	for id in _active_voice_map.keys():
		stop(id)

## Sets user volume v in [0, 1] for a bus (§7.9: base gain + linear_to_db(v); 0 mutes).
func set_user_volume(bus: StringName, v: float) -> void:
	var b: StringName = USER_BUSES.get(bus, bus)
	if AudioServer.get_bus_index(b) < 0:
		return
	_user_db[b] = linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0
	AudioServer.set_bus_mute(AudioServer.get_bus_index(b), v <= 0.0)
	_apply_bus_volume(b)

func _apply_bus_volume(bus: StringName) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var db: float = float(BASE_GAINS.get(bus, 0.0)) + float(_user_db.get(bus, 0.0)) + float(_duck_db.get(bus, 0.0))
	if _paused and bus == &"SFX":
		db = -80.0
	AudioServer.set_bus_volume_db(idx, db)

## Temporarily ducks a bus by `db` for `seconds`, returning over 0.5 s (§7.9 ducking).
func duck(bus: StringName, db: float, seconds: float) -> void:
	_duck_db[bus] = -absf(db)
	_apply_bus_volume(bus)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(seconds)
	tw.tween_method(func(x: float) -> void:
		_duck_db[bus] = x
		_apply_bus_volume(bus), -absf(db), 0.0, 0.5)

## Pause: SFX bus silent (UI unaffected), Ambient low-pass at 900 Hz (§1.3 T8, §7.9).
func set_paused(p: bool) -> void:
	_paused = p
	_apply_bus_volume(&"SFX")
	var amb_idx: int = AudioServer.get_bus_index(&"Ambient")
	if amb_idx >= 0 and AudioServer.get_bus_effect_count(amb_idx) > 0:
		var eff = AudioServer.get_bus_effect(amb_idx, 0)
		if eff is AudioEffectLowPassFilter:
			eff.cutoff_hz = 900.0 if p else 20000.0
