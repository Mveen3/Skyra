# Implements the §9.9 / §10 `--bench` mode (owner-run rendering benchmark): a 7-bot match
# with the Autopilot playing an invulnerable Skyra. For the first third the camera sweeps
# the whole map at the widest view (5x scope), then it follows the bot fight. Frame times
# are measured with VSync off and written to user://bench.json (avg / p99 frame time,
# FPS); the exit code is 0 when the §10 targets hold (avg ≤ 16.6 ms, p99 ≤ 25 ms).
class_name BenchRunner
extends Node

const TARGET_AVG_MS: float = 16.6
const TARGET_P99_MS: float = 25.0
const BENCH_BOTS: int = 7
const BENCH_SEED: int = 1234
const SWEEP_SCOPE: float = 5.0
## Rectangle of camera centres that shows every tile at 5x (view ≈ 4290 × 2415 wu).
const SWEEP_PATH: Array[Vector2] = [Vector2(2150, 1210), Vector2(5530, 1210),
	Vector2(5530, 2630), Vector2(2150, 2630), Vector2(2150, 1210)]
const RESULT_PATH: String = "user://bench.json"

var flow: GameFlow
var duration_s: float
var mode: StringName
var _main: Node
var _auto: Autopilot = null
var _idle_frame: InputFrame = InputFrame.new()
var _tick: int = 0
var _path_len: float = 0.0
var _measuring: bool = false
var _done: bool = false
var _start_us: int = 0
var _last_us: int = 0
var _frames_us: PackedInt32Array = PackedInt32Array()
var _sweep_frames: int = 0
var _sim_us: PackedInt32Array = PackedInt32Array()

func _init(p_flow: GameFlow, p_main: Node, p_mode: StringName, p_duration_s: float) -> void:
	flow = p_flow
	_main = p_main
	mode = p_mode
	duration_s = maxf(1.0, p_duration_s)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(1, SWEEP_PATH.size()):
		_path_len += SWEEP_PATH[i - 1].distance_to(SWEEP_PATH[i])

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	flow.pause_on_focus_loss = false
	flow.match_built.connect(_on_match_built)
	Log.info("BENCH: %.0f s, mode=%s, bots=%d, seed=%d" % [duration_s, str(mode), BENCH_BOTS, BENCH_SEED])
	flow.start_match(MatchConfig.new(mode, BENCH_BOTS, 600, BENCH_SEED))

## Connected after main.gd's handler, so the WorldView already exists.
func _on_match_built(sim: MatchSim) -> void:
	_auto = Autopilot.new(sim.human_char, BENCH_SEED)
	flow.input_source = _bench_frame
	var wv: WorldView = _main.get("world_view")
	if wv:
		wv.camera_driver = _sweep_camera

## Skyra's InputFrame for this tick, with god mode so the fight never pauses for respawns.
func _bench_frame() -> InputFrame:
	var sim := flow.sim
	if sim == null or _auto == null:
		return _idle_frame
	var h := sim.human_char
	if h.life_state == Enums.LifeState.ALIVE:
		h.invuln_t = maxf(h.invuln_t, 0.5)
		h.health = 100.0
	_tick += 1
	return _auto.step(_tick, 1.0 / 60.0, sim)

func _sweep_s() -> float:
	return duration_s / 3.0

func _sweep_camera(cam: GameCamera, _delta: float) -> void:
	var t := float(Time.get_ticks_usec() - _start_us) / 1000000.0 if _measuring else 0.0
	if t >= _sweep_s():
		# Hand over to the follow camera, which eases from here to Skyra.
		var wv: WorldView = _main.get("world_view")
		if wv:
			wv.camera_driver = Callable()
		cam.curr_cam_pos = cam.global_position
		cam.curr_zoom = cam.zoom.x
		return
	var k := 0.5 - 0.5 * cos(PI * t / _sweep_s())
	cam.global_position = _point_on_path(k * _path_len)
	var z := GameCamera.calc_zoom_target(SWEEP_SCOPE)
	cam.zoom = Vector2(z, z)

func _point_on_path(d: float) -> Vector2:
	for i in range(1, SWEEP_PATH.size()):
		var seg := SWEEP_PATH[i - 1].distance_to(SWEEP_PATH[i])
		if d <= seg:
			return SWEEP_PATH[i - 1].lerp(SWEEP_PATH[i], d / seg)
		d -= seg
	return SWEEP_PATH[SWEEP_PATH.size() - 1]

func _process(_delta: float) -> void:
	if _done:
		return
	var now := Time.get_ticks_usec()
	if not _measuring:
		if flow.state == Enums.GameState.MATCH_ACTIVE:
			_measuring = true
			_start_us = now
		_last_us = now
		return
	_frames_us.append(now - _last_us)
	_last_us = now
	var t := float(now - _start_us) / 1000000.0
	if t <= _sweep_s():
		_sweep_frames = _frames_us.size()
	if t >= duration_s:
		_finish()

func _physics_process(_delta: float) -> void:
	if _measuring and not _done and flow.state == Enums.GameState.MATCH_ACTIVE:
		_sim_us.append(flow.last_sim_us)

static func _avg_ms(samples: PackedInt32Array, from: int, to: int) -> float:
	if to <= from:
		return 0.0
	var sum := 0
	for i in range(from, to):
		sum += samples[i]
	return float(sum) / float(to - from) / 1000.0

static func _p99_ms(samples: PackedInt32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]) / 1000.0

func _finish() -> void:
	_done = true
	var n := _frames_us.size()
	var avg_ms := _avg_ms(_frames_us, 0, n)
	var p99_ms := _p99_ms(_frames_us)
	var max_us := 0
	for v in _frames_us:
		max_us = maxi(max_us, v)
	var passed := avg_ms <= TARGET_AVG_MS and p99_ms <= TARGET_P99_MS
	var size := DisplayServer.window_get_size()
	var result := {
		"version": C.VERSION,
		"date": Time.get_datetime_string_from_system(),
		"duration_s": duration_s,
		"mode": str(mode),
		"bots": BENCH_BOTS,
		"seed": BENCH_SEED,
		"resolution": "%dx%d" % [size.x, size.y],
		"fullscreen": DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN,
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"graphics_api": RenderingServer.get_video_adapter_api_version(),
		"vsync": false,
		"frames": n,
		"avg_frame_ms": snappedf(avg_ms, 0.001),
		"p99_frame_ms": snappedf(p99_ms, 0.001),
		"max_frame_ms": snappedf(max_us / 1000.0, 0.001),
		"fps": snappedf(1000.0 / avg_ms, 0.1) if avg_ms > 0.0 else 0.0,
		"sweep_avg_frame_ms": snappedf(_avg_ms(_frames_us, 0, _sweep_frames), 0.001),
		"fight_avg_frame_ms": snappedf(_avg_ms(_frames_us, _sweep_frames, n), 0.001),
		"sim_avg_tick_ms": snappedf(_avg_ms(_sim_us, 0, _sim_us.size()), 0.001),
		"sim_p99_tick_ms": snappedf(_p99_ms(_sim_us), 0.001),
		"target_avg_frame_ms": TARGET_AVG_MS,
		"target_p99_frame_ms": TARGET_P99_MS,
		"pass": passed,
	}
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "  "))
		f.close()
	else:
		Log.error("BENCH: cannot write " + RESULT_PATH)
	Log.info("BENCH %s: avg %.2f ms, p99 %.2f ms, %.0f FPS over %d frames on %s -> %s" % [
		"PASS" if passed else "FAIL", avg_ms, p99_ms, result["fps"], n, result["gpu"],
		ProjectSettings.globalize_path(RESULT_PATH)])
	flow.quit_game(0 if passed else 1)
