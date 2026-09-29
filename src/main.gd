# Implements §1.3, §2.3 and §9.1 Main entry point.
extends Node

var cli: CliArgs

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cli = CliArgs.parse()
	Log.set_level_from_string(cli.log_level)
	Log.info("Skyra v%s booting..." % C.VERSION)
	
	if cli.selftest:
		Log.info("Running self-test suite...")
		await get_tree().process_frame
		TestRunner.run_all(get_tree())
		return

	if cli.gen_sfx:
		_run_gen_sfx()
		return

	if cli.soak > 0:
		await get_tree().process_frame
		_run_soak(cli.soak, cli.mode, cli.bots, cli.rng_seed)
		return

	# Handle windowed flag
	if cli.windowed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))

	Log.info("INITIALIZE state complete.")

func _run_gen_sfx() -> void:
	Log.info("Generating procedural audio files to assets/audio/generated/...")
	var cues: Dictionary = Data.cues
	var count: int = 0
	for cue_id in cues:
		var path: String = "res://assets/audio/generated/%s.wav" % str(cue_id)
		SfxSynth.render_to_file(cues[cue_id], path)
		count += 1
	Log.info("Generated %d WAV files." % count)
	get_tree().quit(0)

func _run_soak(seconds: int, mode: StringName, bots: int, seed_val: int) -> void:
	Log.info("Running soak test: %d seconds, mode=%s, bots=%d, seed=%d" % [seconds, str(mode), bots, seed_val])
	var start_wall_us: int = Time.get_ticks_usec()
	var cfg: MatchConfig = MatchConfig.new()
	cfg.mode = mode
	cfg.bot_count = bots
	cfg.rng_seed = seed_val
	cfg.duration_s = float(seconds)

	var sim: MatchSim = MatchSim.new()
	sim.setup(cfg)
	sim.init_match()
	sim.begin_active()

	var auto: Autopilot = Autopilot.new(sim.human_char, seed_val)
	var dt: float = 1.0 / 60.0
	var total_ticks: int = seconds * 60

	var total_sim_time_us: int = 0
	var tick_times_us: Array[int] = []

	var world_w: float = float(sim.grid.cols) * float(sim.grid.tile_size)
	var world_h: float = float(sim.grid.rows) * float(sim.grid.tile_size)

	for t in range(total_ticks):
		var t0: int = Time.get_ticks_usec()
		var frame: InputFrame = auto.step(t, dt, sim)
		sim.step(dt, frame)
		var t1: int = Time.get_ticks_usec()
		var step_us: int = t1 - t0
		total_sim_time_us += step_us
		tick_times_us.append(step_us)

		# Per-tick invariant checks (§10.5)
		if sim.projectiles.projectiles.size() > 512:
			Log.error("Invariants violated: projectiles > 512 at tick %d" % t)
			get_tree().quit(1)
			return

		if sim.loose_weapons.size() > 12:
			Log.error("Invariants violated: loose weapons > 12 at tick %d" % t)
			get_tree().quit(1)
			return

		for c in sim.characters:
			if is_nan(c.pos.x) or is_nan(c.pos.y) or is_inf(c.pos.x) or is_inf(c.pos.y):
				Log.error("Invariants violated: NaN/INF pos at tick %d" % t)
				get_tree().quit(1)
				return
			if c.pos.x < 0 or c.pos.x > world_w or c.pos.y < 0 or c.pos.y > world_h:
				Log.error("Invariants violated: out of bounds at tick %d" % t)
				get_tree().quit(1)
				return

	var elapsed_wall_s: float = float(Time.get_ticks_usec() - start_wall_us) / 1000000.0
	var mean_tick_ms: float = (float(total_sim_time_us) / float(total_ticks)) / 1000.0
	tick_times_us.sort()
	var p99_idx: int = int(float(total_ticks) * 0.99)
	var p99_tick_ms: float = float(tick_times_us[p99_idx]) / 1000.0

	Log.info("SOAK PASS: %d ticks in %.2f s wall-clock (mean tick: %.3f ms, p99: %.3f ms)" % [
		total_ticks, elapsed_wall_s, mean_tick_ms, p99_tick_ms
	])

	if elapsed_wall_s > 30.0:
		Log.error("Soak failed: wall clock time %.2f > 30 s" % elapsed_wall_s)
		get_tree().quit(1)
		return

	get_tree().quit(0)
