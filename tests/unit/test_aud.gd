# Implements §10.4 T-AUD-01 to T-AUD-06.
class_name TestAud
extends RefCounted

func test_aud_01_buses() -> void:
	var am = Audio
	if am and am.has_method("setup_buses"):
		am.setup_buses()

	var expected_buses: Array[StringName] = [&"Master", &"SFX", &"SFX_Interior", &"Ambient", &"UI"]
	for b in expected_buses:
		var idx: int = AudioServer.get_bus_index(b)
		Assertions.assert_true(idx >= 0, "Bus %s exists" % str(b))

	# Parent checks
	var sfx_idx: int = AudioServer.get_bus_index(&"SFX")
	var int_idx: int = AudioServer.get_bus_index(&"SFX_Interior")
	var amb_idx: int = AudioServer.get_bus_index(&"Ambient")
	var ui_idx: int = AudioServer.get_bus_index(&"UI")

	Assertions.assert_eq(AudioServer.get_bus_send(sfx_idx), &"Master", "SFX sends to Master")
	Assertions.assert_eq(AudioServer.get_bus_send(int_idx), &"SFX", "SFX_Interior sends to SFX")
	Assertions.assert_eq(AudioServer.get_bus_send(amb_idx), &"Master", "Ambient sends to Master")
	Assertions.assert_eq(AudioServer.get_bus_send(ui_idx), &"Master", "UI sends to Master")

	# Effect checks
	var master_idx: int = AudioServer.get_bus_index(&"Master")
	var master_has_limiter: bool = false
	for i in range(AudioServer.get_bus_effect_count(master_idx)):
		var eff = AudioServer.get_bus_effect(master_idx, i)
		if eff is AudioEffectLimiter:
			master_has_limiter = true
			Assertions.assert_true(is_equal_approx(eff.ceiling_db, -1.0), "Limiter ceiling is -1 dB")
			break
	Assertions.assert_true(master_has_limiter, "Master bus has Limiter")

	var int_has_reverb: bool = false
	for i in range(AudioServer.get_bus_effect_count(int_idx)):
		var eff = AudioServer.get_bus_effect(int_idx, i)
		if eff is AudioEffectReverb:
			int_has_reverb = true
			Assertions.assert_true(is_equal_approx(eff.room_size, 0.45), "Reverb room 0.45")
			Assertions.assert_true(is_equal_approx(eff.damping, 0.6), "Reverb damping 0.6")
			Assertions.assert_true(is_equal_approx(eff.wet, 0.22), "Reverb wet 0.22")
			Assertions.assert_true(is_equal_approx(eff.dry, 1.0), "Reverb dry 1.0")
			break
	Assertions.assert_true(int_has_reverb, "SFX_Interior has Reverb")

	var amb_has_lpf: bool = false
	for i in range(AudioServer.get_bus_effect_count(amb_idx)):
		var eff = AudioServer.get_bus_effect(amb_idx, i)
		if eff is AudioEffectLowPassFilter:
			amb_has_lpf = true
			Assertions.assert_true(is_equal_approx(eff.cutoff_hz, 20000.0), "Ambient LPF cutoff 20 kHz")
			break
	Assertions.assert_true(amb_has_lpf, "Ambient has LowPassFilter")

func test_aud_02_cue_rendering() -> void:
	var cues: Dictionary = Data.cues
	Assertions.assert_true(cues.size() >= 50, "At least 50 cues in Data.cues, got %d" % cues.size())

	for cue_id in cues:
		var recipe: Dictionary = cues[cue_id]
		var stream: AudioStreamWAV = SfxSynth.render(recipe)
		Assertions.assert_true(stream != null, "Render stream not null for %s" % str(cue_id))
		if stream == null:
			continue

		var dur: float = float(recipe.get("dur", 0.5))
		var expected_samples: int = int(round(dur * 22050.0))
		var actual_samples: int = stream.data.size() / 2
		Assertions.assert_true(abs(actual_samples - expected_samples) <= 1,
			"Cue %s sample count %d approx %d (dur %.3f)" % [str(cue_id), actual_samples, expected_samples, dur])

		# Calculate peak and RMS
		var max_abs: int = 0
		var sum_sq: float = 0.0
		var byte_data: PackedByteArray = stream.data

		for i in range(actual_samples):
			var b0: int = byte_data[i * 2]
			var b1: int = byte_data[i * 2 + 1]
			var val: int = b0 | (b1 << 8)
			if val >= 32768:
				val -= 65536
			var a: int = abs(val)
			if a > max_abs:
				max_abs = a
			var s_norm: float = float(val) / 32767.0
			sum_sq += s_norm * s_norm

		var peak_linear: float = float(max_abs) / 32767.0
		var peak_db: float = 20.0 * log(max(0.00001, peak_linear)) / log(10.0)
		Assertions.assert_true(peak_db >= -1.5 and peak_db <= -0.5,
			"Cue %s peak −1 ± 0.5 dBFS, got %.2f dBFS" % [str(cue_id), peak_db])

		var rms_linear: float = sqrt(sum_sq / max(1, actual_samples))
		var rms_db: float = 20.0 * log(max(0.00001, rms_linear)) / log(10.0)
		Assertions.assert_true(rms_db > -40.0,
			"Cue %s RMS > −40 dBFS, got %.2f dBFS" % [str(cue_id), rms_db])

func test_aud_03_loops() -> void:
	var cues: Dictionary = Data.cues
	var loop_count: int = 0

	for cue_id in cues:
		var recipe: Dictionary = cues[cue_id]
		if not recipe.get("loop", false):
			continue

		loop_count += 1
		var stream: AudioStreamWAV = SfxSynth.render(recipe)
		var actual_samples: int = stream.data.size() / 2

		Assertions.assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD,
			"Loop cue %s has LOOP_FORWARD" % str(cue_id))
		Assertions.assert_eq(stream.loop_end, actual_samples,
			"Loop cue %s loop_end equals length (%d)" % [str(cue_id), actual_samples])

		# Check periodic frequencies * loop length are integers
		var dur: float = float(recipe.get("dur", 1.0))
		var layers: Array = recipe.get("layers", [])
		for l in layers:
			var src: String = str(l.get("src", ""))
			if src in ["sine", "square", "saw", "triangle"]:
				var f_val = l.get("f", 0.0)
				if typeof(f_val) == TYPE_FLOAT or typeof(f_val) == TYPE_INT:
					var f: float = float(f_val)
					var cycles: float = f * dur
					var is_int: bool = is_equal_approx(cycles, roundf(cycles))
					Assertions.assert_true(is_int,
						"Periodic freq %.1f * dur %.2f = %.2f in %s is integer" % [f, dur, cycles, str(cue_id)])

	Assertions.assert_true(loop_count >= 10, "At least 10 loop cues found, got %d" % loop_count)

func test_aud_04_kill_stings() -> void:
	# Test kill router decisions
	var played_cues: Array[StringName] = []
	var mock_audio = MockAudio.new(played_cues)
	var router = AudioEventRouter.new(mock_audio)

	# Skyra kills bot (normal)
	played_cues.clear()
	router.on_character_killed(1, 0, false, 1, Vector2(100, 200))
	Assertions.assert_true(played_cues.has(&"sting.kill_confirm"), "Skyra normal kill plays sting.kill_confirm")
	Assertions.assert_true(played_cues.has(&"sfx.bot.derez"), "Skyra kill plays sfx.bot.derez")

	# Skyra kills bot (headshot)
	played_cues.clear()
	router.on_character_killed(2, 0, true, 1, Vector2(100, 200))
	Assertions.assert_true(played_cues.has(&"sting.kill_headshot"), "Skyra headshot plays sting.kill_headshot")

	# Skyra kills bot (multikill)
	played_cues.clear()
	router.on_character_killed(3, 0, false, 3, Vector2(100, 200))
	Assertions.assert_true(played_cues.has(&"sting.multikill"), "Skyra multikill plays sting.multikill")

	# Bot kills Skyra
	played_cues.clear()
	router.on_character_killed(0, 1, false, 1, Vector2(100, 200))
	Assertions.assert_true(played_cues.has(&"sting.player_defeated"), "Bot kills Skyra plays sting.player_defeated")
	Assertions.assert_true(played_cues.has(&"sfx.player.death"), "Bot kills Skyra plays sfx.player.death")

	# Skyra suicide
	played_cues.clear()
	router.on_character_killed(0, 0, false, 1, Vector2(100, 200))
	Assertions.assert_true(played_cues.has(&"sting.suicide"), "Skyra suicide plays sting.suicide")

func test_aud_05_unique_fire_sounds() -> void:
	var weapons: Array[StringName] = [
		&"magnum", &"mp5", &"ak47", &"shotgun", &"m93ba",
		&"flame", &"phasr", &"rocket_launcher", &"saw_gun"
	]
	var fire_cues: Dictionary = {}

	for w in weapons:
		var cue: StringName = AudioEventRouter.get_weapon_fire_cue(w)
		Assertions.assert_true(cue != &"", "Weapon %s has a fire cue" % str(w))
		Assertions.assert_true(Data.cues.has(cue) or Data.cues.has(str(cue)), "Cue %s exists in Data.cues" % str(cue))
		Assertions.assert_true(not fire_cues.has(cue), "Cue %s is distinct (not reused)" % str(cue))
		fire_cues[cue] = w

	Assertions.assert_eq(fire_cues.size(), 9, "9 distinct fire cue IDs for 9 weapons")

	# Grenade explosion cue exists
	Assertions.assert_true(Data.cues.has(&"sfx.explosion.large") or Data.cues.has("sfx.explosion.large"),
		"sfx.explosion.large exists for grenades")

func test_aud_06_voice_limits() -> void:
	var am = Audio
	if am == null:
		return

	# Fire 40 simultaneous impact requests
	for i in range(40):
		am.play(&"sfx.impact.rock", Vector2(100.0 + float(i), 100.0))

	# Count concurrent active impact voices
	var active_impacts: int = 0
	for v in am._voices_2d:
		if v.active and v.category == &"impact":
			active_impacts += 1

	Assertions.assert_true(active_impacts <= 6,
		"40 simultaneous impact requests -> <= 6 concurrent impact voices (got %d)" % active_impacts)

# Mock audio class for unit testing event router
class MockAudio:
	var played: Array[StringName]
	func _init(arr: Array[StringName]) -> void:
		played = arr
	func play(cue: StringName, _pos: Vector2 = Vector2.INF, _opts: Dictionary = {}) -> int:
		played.append(cue)
		return 1
	func play_loop(cue: StringName, _pos: Vector2 = Vector2.INF) -> int:
		played.append(cue)
		return 1
	func duck(_bus: StringName, _db: float, _sec: float) -> void:
		pass
