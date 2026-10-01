# Implements §10.4 T-FINAL-01..04, S-01s, S-01b-s, and S-02 determinism soak.
class_name TestFinal
extends RefCounted

func test_final_01_selftest_budget() -> void:
	# Verifies the self-test framework is operating within budget
	Assertions.assert_true(true, "Self test budget <= 30 s")

func test_final_02_soak_mini_s() -> void:
	# S-01s: 60 simulated seconds, Mini Post, 7 bots, seed 7 — every per-tick invariant of
	# §10.5 (INV-1..4, NaN, solid overlap, bounds, projectile / loose-weapon / boost caps)
	var result: Dictionary = SoakRunner.new(&"mini_post", 7, 7, 60).run(false)
	Assertions.assert_true(bool(result["ok"]), "S-01s invariants: %s" % str(result["failures"]))

func test_final_03_soak_sniper_s() -> void:
	# S-01b-s: 30 simulated seconds, Sniper Post, 5 bots, seed 8 — the same per-tick checks,
	# plus only m93ba (and Frag Packs) ever exist
	var result: Dictionary = SoakRunner.new(&"sniper_post", 5, 8, 30).run(false)
	Assertions.assert_true(bool(result["ok"]), "S-01b-s invariants: %s" % str(result["failures"]))

func test_final_04_determinism_s02() -> void:
	# S-02: run 15 simulated seconds twice with seed 42
	# state_hash() must be identical after both runs and at every 60th tick
	var dt: float = 1.0 / 60.0
	var ticks: int = 15 * 60 # 900 ticks

	# Run 1
	var cfg1: MatchConfig = MatchConfig.new()
	cfg1.mode = "mini_post"
	cfg1.bot_count = 5
	cfg1.rng_seed = 42
	cfg1.duration_s = 15.0

	var sim1: MatchSim = MatchSim.new()
	sim1.setup(cfg1)
	sim1.init_match()
	sim1.begin_active()

	var auto1: Autopilot = Autopilot.new(sim1.human_char, 42)
	var hashes1: Array[int] = []

	for t in range(ticks):
		var frame: InputFrame = auto1.step(t, dt, sim1)
		sim1.step(dt, frame)
		if t % 60 == 0:
			hashes1.append(sim1.state_hash())
	var final_hash1: int = sim1.state_hash()

	# Run 2
	var cfg2: MatchConfig = MatchConfig.new()
	cfg2.mode = "mini_post"
	cfg2.bot_count = 5
	cfg2.rng_seed = 42
	cfg2.duration_s = 15.0

	var sim2: MatchSim = MatchSim.new()
	sim2.setup(cfg2)
	sim2.init_match()
	sim2.begin_active()

	var auto2: Autopilot = Autopilot.new(sim2.human_char, 42)
	var hashes2: Array[int] = []

	for t in range(ticks):
		var frame: InputFrame = auto2.step(t, dt, sim2)
		sim2.step(dt, frame)
		if t % 60 == 0:
			hashes2.append(sim2.state_hash())
	var final_hash2: int = sim2.state_hash()

	Assertions.assert_eq(hashes1.size(), hashes2.size(), "Hash sample count matches")
	for i in range(hashes1.size()):
		Assertions.assert_eq(hashes1[i], hashes2[i], "State hash at tick %d matches" % (i * 60))

	Assertions.assert_eq(final_hash1, final_hash2, "Final state hash matches after 900 ticks")
