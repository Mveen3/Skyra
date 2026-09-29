# Implements §7.11 Procedural audio synthesizer.
class_name SfxSynth
extends RefCounted

const SAMPLE_RATE: int = 22050
const TWO_PI: float = TAU

## Renders a cue recipe dictionary to an AudioStreamWAV.
static func render(recipe: Dictionary) -> AudioStreamWAV:
	var dur: float = float(recipe.get("dur", 0.5))
	var num_samples: int = max(1, int(round(dur * float(SAMPLE_RATE))))
	var gain_db: float = float(recipe.get("gain_db", -1.0))
	var is_loop: bool = bool(recipe.get("loop", false))
	var layers: Array = recipe.get("layers", [])

	# Master buffer of float samples
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(num_samples)
	buffer.fill(0.0)

	if layers.is_empty():
		# Fallback: soft beep
		for i in range(num_samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			buffer[i] = sin(t * 440.0 * TWO_PI) * exp(-t * 8.0)
	else:
		for layer in layers:
			if typeof(layer) != TYPE_DICTIONARY:
				continue
			_render_layer(layer, buffer, num_samples, dur)

	# Fading / crossfade
	if is_loop:
		# 20-ms tail-to-head crossfade
		var xfade_samples: int = min(int(round(0.020 * float(SAMPLE_RATE))), num_samples / 2)
		if xfade_samples > 0:
			for i in range(xfade_samples):
				var frac: float = float(i) / float(xfade_samples)
				var head_val: float = buffer[i]
				var tail_idx: int = num_samples - xfade_samples + i
				var tail_val: float = buffer[tail_idx]
				var blended: float = lerp(tail_val, head_val, frac)
				buffer[i] = blended
				buffer[tail_idx] = blended
	else:
		# 5-ms fade out
		var fade_samples: int = min(int(round(0.005 * float(SAMPLE_RATE))), num_samples)
		if fade_samples > 0:
			var start_idx: int = num_samples - fade_samples
			for i in range(fade_samples):
				var factor: float = 1.0 - (float(i) / float(fade_samples))
				buffer[start_idx + i] *= factor

	# Peak normalization to 10^(gain_db / 20)
	var target_peak: float = pow(10.0, gain_db / 20.0)
	var max_abs: float = 0.0
	for i in range(num_samples):
		var a: float = absf(buffer[i])
		if a > max_abs:
			max_abs = a

	if max_abs > 0.00001:
		var norm: float = target_peak / max_abs
		for i in range(num_samples):
			buffer[i] *= norm
	else:
		# If silence, generate soft carrier
		for i in range(num_samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			buffer[i] = sin(t * 220.0 * TWO_PI) * target_peak

	# Convert float samples [-1.0, 1.0] to 16-bit signed PCM little-endian byte array
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(num_samples * 2)

	for i in range(num_samples):
		var s: float = clampf(buffer[i], -1.0, 1.0)
		var val_int: int = int(round(s * 32767.0))
		if val_int < -32768:
			val_int = -32768
		elif val_int > 32767:
			val_int = 32767
		# Little endian
		var u16: int = val_int if val_int >= 0 else val_int + 65536
		var b0: int = u16 & 0xFF
		var b1: int = (u16 >> 8) & 0xFF
		byte_data[i * 2] = b0
		byte_data[i * 2 + 1] = b1

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = byte_data

	if is_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = num_samples
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	return stream

## Renders a cue recipe to a WAV file on disk.
static func render_to_file(recipe: Dictionary, path: String) -> Error:
	var stream: AudioStreamWAV = render(recipe)
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	return stream.save_to_wav(path)

static func _render_layer(layer: Dictionary, master_buf: PackedFloat32Array, total_samples: int, cue_dur: float) -> void:
	var src: String = str(layer.get("src", "noise"))
	var at_s: float = float(layer.get("at", 0.0))
	var len_s: float = float(layer.get("len", cue_dur - at_s))
	var gain: float = float(layer.get("gain", 1.0))
	
	var start_idx: int = clamp(int(round(at_s * float(SAMPLE_RATE))), 0, total_samples)
	var end_idx: int = clamp(int(round((at_s + len_s) * float(SAMPLE_RATE))), start_idx, total_samples)
	var layer_samples: int = end_idx - start_idx
	if layer_samples <= 0:
		return

	var layer_buf: PackedFloat32Array = PackedFloat32Array()
	layer_buf.resize(layer_samples)

	# Envelope parameters
	var env_data: Dictionary = layer.get("env", {})
	var has_adsr: bool = env_data.has("adsr")
	var adsr_a: float = 0.0
	var adsr_d: float = 0.0
	var adsr_s: float = 1.0
	var adsr_r: float = 0.0
	var env_a: float = 0.0
	var env_tau: float = 0.0
	if has_adsr:
		var a_arr: Array = env_data["adsr"]
		if a_arr.size() >= 4:
			adsr_a = float(a_arr[0])
			adsr_d = float(a_arr[1])
			adsr_s = float(a_arr[2])
			adsr_r = float(a_arr[3])
	else:
		env_a = float(env_data.get("a", 0.0))
		env_tau = float(env_data.get("tau", 0.0))

	# AM modulation
	var am_data: Dictionary = layer.get("am", {})
	var has_am: bool = not am_data.is_empty()
	var am_f: float = float(am_data.get("f", 0.0))
	var am_depth: float = float(am_data.get("depth", 0.0))

	# Vibrato
	var vib_data: Dictionary = layer.get("vib", {})
	var has_vib: bool = not vib_data.is_empty()
	var vib_f: float = float(vib_data.get("f", 0.0))
	var vib_depth: float = float(vib_data.get("depth_hz", 0.0))

	# Oscillators frequency / sweep
	var f_val = layer.get("f", 440.0)
	var f0: float = 440.0
	var f1: float = 440.0
	var is_sweep: bool = false
	if typeof(f_val) == TYPE_ARRAY and f_val.size() >= 2:
		f0 = float(f_val[0])
		f1 = float(f_val[1])
		is_sweep = true
	elif typeof(f_val) == TYPE_FLOAT or typeof(f_val) == TYPE_INT:
		f0 = float(f_val)
		f1 = f0

	var sweep_is_lin: bool = (str(layer.get("sweep", "exp")) == "lin")
	var sweep_dur: float = float(layer.get("sweep_t", len_s))
	if sweep_dur <= 0.001:
		sweep_dur = len_s

	# 1. Generate Raw Source
	if src == "noise":
		var color: String = str(layer.get("color", "white"))
		if color == "white":
			for i in range(layer_samples):
				layer_buf[i] = randf_range(-1.0, 1.0)
		elif color == "pink":
			# Simple 3-pole pinking filter on white noise
			var b0: float = 0.0
			var b1: float = 0.0
			var b2: float = 0.0
			for i in range(layer_samples):
				var w: float = randf_range(-1.0, 1.0)
				b0 = 0.99765 * b0 + w * 0.0990460
				b1 = 0.96300 * b1 + w * 0.2965164
				b2 = 0.57000 * b2 + w * 1.0526913
				layer_buf[i] = (b0 + b1 + b2 + w * 0.1848) * 0.3
		elif color == "brown":
			# Leaky integrated white noise
			var brown: float = 0.0
			for i in range(layer_samples):
				var w: float = randf_range(-1.0, 1.0)
				brown = 0.95 * brown + 0.05 * w
				layer_buf[i] = brown * 3.5
	elif src == "fm":
		var carrier_val = layer.get("carrier", 440.0)
		var c0: float = 440.0
		var c1: float = 440.0
		var c_sweep: bool = false
		if typeof(carrier_val) == TYPE_ARRAY and carrier_val.size() >= 2:
			c0 = float(carrier_val[0])
			c1 = float(carrier_val[1])
			c_sweep = true
		else:
			c0 = float(carrier_val)
			c1 = c0
		var ratio: float = float(layer.get("ratio", 1.0))
		var index: float = float(layer.get("index", 1.0))

		var phi_c: float = 0.0
		var phi_m: float = 0.0
		for i in range(layer_samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			var fc: float = c0
			if c_sweep:
				var st: float = clampf(t / sweep_dur, 0.0, 1.0)
				fc = c0 * pow(c1 / max(1.0, c0), st)
			var fm: float = fc * ratio
			phi_m += fm / float(SAMPLE_RATE)
			phi_c += fc / float(SAMPLE_RATE)
			layer_buf[i] = sin(TWO_PI * phi_c + index * sin(TWO_PI * phi_m))
	else:
		# Periodic oscillators: sine, square, saw, triangle
		var phase: float = 0.0
		for i in range(layer_samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			var cur_f: float = f0
			if is_sweep:
				var st: float = clampf(t / sweep_dur, 0.0, 1.0)
				if sweep_is_lin:
					cur_f = f0 + (f1 - f0) * st
				else:
					cur_f = f0 * pow(f1 / max(1.0, f0), st)
			if has_vib:
				cur_f += vib_depth * sin(TWO_PI * vib_f * t)

			phase += cur_f / float(SAMPLE_RATE)
			var p_frac: float = phase - floorf(phase)

			var val: float = 0.0
			if src == "sine":
				val = sin(TWO_PI * p_frac)
			elif src == "square":
				val = 1.0 if p_frac < 0.5 else -1.0
			elif src == "saw":
				val = 2.0 * p_frac - 1.0
			elif src == "triangle":
				val = 2.0 * absf(2.0 * p_frac - 1.0) - 1.0
			layer_buf[i] = val

	# 2. Envelopes & AM
	for i in range(layer_samples):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = 1.0
		if has_adsr:
			if t < adsr_a and adsr_a > 0.0001:
				env = t / adsr_a
			elif t < (adsr_a + adsr_d) and adsr_d > 0.0001:
				env = 1.0 - (1.0 - adsr_s) * ((t - adsr_a) / adsr_d)
			elif t < (len_s - adsr_r):
				env = adsr_s
			elif adsr_r > 0.0001:
				var r_progress: float = (t - (len_s - adsr_r)) / adsr_r
				env = adsr_s * maxf(0.0, 1.0 - r_progress)
			else:
				env = adsr_s
		else:
			if env_a > 0.0001 and t < env_a:
				env = t / env_a
			elif env_tau > 0.0001:
				env = exp(-(t - env_a) / env_tau)
			else:
				env = 1.0

		if has_am:
			env *= (1.0 - am_depth * (0.5 - 0.5 * cos(TWO_PI * am_f * t)))

		layer_buf[i] *= env

	# 3. Filters
	# High-pass one-pole filter
	if layer.has("hp"):
		var hp_fc: float = float(layer["hp"])
		var alpha_hp: float = exp(-TWO_PI * hp_fc / float(SAMPLE_RATE))
		var y_prev: float = 0.0
		var x_prev: float = 0.0
		for i in range(layer_samples):
			var x: float = layer_buf[i]
			var y: float = alpha_hp * (y_prev + x - x_prev)
			x_prev = x
			y_prev = y
			layer_buf[i] = y

	# Low-pass one-pole filter
	if layer.has("lp"):
		var lp_val = layer["lp"]
		var lp_f0: float = 2000.0
		var lp_f1: float = 2000.0
		var lp_is_sweep: bool = false
		if typeof(lp_val) == TYPE_ARRAY and lp_val.size() >= 2:
			lp_f0 = float(lp_val[0])
			lp_f1 = float(lp_val[1])
			lp_is_sweep = true
		else:
			lp_f0 = float(lp_val)
			lp_f1 = lp_f0

		var y_lp: float = 0.0
		for i in range(layer_samples):
			var cur_fc: float = lp_f0
			if lp_is_sweep:
				cur_fc = lerp(lp_f0, lp_f1, float(i) / float(layer_samples))
			var alpha_lp: float = 1.0 - exp(-TWO_PI * cur_fc / float(SAMPLE_RATE))
			y_lp += alpha_lp * (layer_buf[i] - y_lp)
			layer_buf[i] = y_lp

	# Band-pass state-variable filter
	if layer.has("bp"):
		var bp_dict: Dictionary = layer["bp"]
		var bp_val = bp_dict.get("f", 1000.0)
		var bp_q: float = maxf(0.1, float(bp_dict.get("q", 1.0)))
		var bp_f0: float = 1000.0
		var bp_f1: float = 1000.0
		var bp_sweep: bool = false
		if typeof(bp_val) == TYPE_ARRAY and bp_val.size() >= 2:
			bp_f0 = float(bp_val[0])
			bp_f1 = float(bp_val[1])
			bp_sweep = true
		else:
			bp_f0 = float(bp_val)
			bp_f1 = bp_f0

		var q_inv: float = 1.0 / bp_q
		var lp_sv: float = 0.0
		var bp_sv: float = 0.0
		for i in range(layer_samples):
			var cur_f: float = bp_f0
			if bp_sweep:
				cur_f = lerp(bp_f0, bp_f1, float(i) / float(layer_samples))
			var F: float = 2.0 * sin(PI * clampf(cur_f / float(SAMPLE_RATE), 0.001, 0.49))
			var x: float = layer_buf[i]
			var hp_sv: float = x - lp_sv - q_inv * bp_sv
			bp_sv += F * hp_sv
			lp_sv += F * bp_sv
			layer_buf[i] = bp_sv

	# 4. Effects: Drive and Bitcrush
	if layer.has("drive"):
		var drv_k: float = maxf(0.01, float(layer["drive"]))
		var tanh_k: float = tanh(drv_k)
		for i in range(layer_samples):
			layer_buf[i] = tanh(layer_buf[i] * drv_k) / tanh_k

	if layer.has("crush"):
		var crush_d: Dictionary = layer["crush"]
		var bits: int = int(crush_d.get("bits", 8))
		var hold: int = max(1, int(crush_d.get("hold", 1)))
		var steps: float = pow(2.0, float(bits - 1))
		var held_val: float = 0.0
		for i in range(layer_samples):
			if i % hold == 0:
				held_val = roundf(layer_buf[i] * steps) / steps
			layer_buf[i] = held_val

	# 5. Accumulate into master buffer with gain
	for i in range(layer_samples):
		master_buf[start_idx + i] += layer_buf[i] * gain
