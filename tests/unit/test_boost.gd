# Implements §10 test requirements T-BOOST-01..04.
class_name TestBoost
extends RefCounted

const DT: float = 1.0 / 60.0

func _get_boost_sockets() -> Array[SocketDef]:
	var result: Array[SocketDef] = []
	for s in Data.map.sockets:
		if s.type == Enums.SocketType.BOOST:
			result.append(s)
	return result

func test_boost_01_single_boost() -> void:
	# Invariant: never more than 1 boost in SPAWNING_IN or AVAILABLE at any time
	var manager := RocketBoostManager.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	manager.setup(_get_boost_sockets(), rng)

	var human := CharacterState.new()
	human.pos = Vector2(0, 0) # Far away, no collection

	# Run 1000 seconds of simulation
	for _i in range(int(1000.0 / DT)):
		manager.step(DT, human, [])
		Assertions.assert_true(manager.active_boost_count() <= 1, "At most 1 active boost at any time")
		Assertions.assert_eq(manager.concurrent_boost_violations, 0, "No concurrent boost violations")

func test_boost_02_timing() -> void:
	var manager := RocketBoostManager.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	manager.setup(_get_boost_sockets(), rng)

	var human := CharacterState.new()
	human.pos = Vector2(0, 0)

	# 1. First spawn at 45.0 s ± 1 tick
	var elapsed := 0.0
	while manager.phase == RocketBoostManager.BoostPhase.WAITING:
		manager.step(DT, human, [])
		elapsed += DT

	Assertions.assert_near(elapsed, 45.0, DT * 1.5, "First spawn occurs at 45.0 s ± 1 tick")
	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.SPAWNING_IN, "Enters SPAWNING_IN")

	# Wait until it reaches AVAILABLE
	while manager.phase == RocketBoostManager.BoostPhase.SPAWNING_IN:
		manager.step(DT, human, [])

	# Simulate collection to trigger next delay
	human.pos = manager.current_pickup_pos
	manager.step(DT, human, [])
	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.WAITING, "Enters WAITING after collection")

	# Check delay is within [35.0, 50.0]
	var next_delay := manager.timer
	Assertions.assert_true(next_delay >= 35.0 and next_delay <= 50.0, "Next spawn delay in [35, 50] s (got %.2f s)" % next_delay)

func test_boost_03_lifetime_and_sockets() -> void:
	var manager := RocketBoostManager.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	manager.setup(_get_boost_sockets(), rng)

	var human := CharacterState.new()
	human.pos = Vector2(0, 0) # No collection

	# Fast-forward past initial 45s wait
	manager.timer = 0.001
	manager.step(DT, human, []) # Enters SPAWNING_IN
	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.SPAWNING_IN)

	# 0.6s beam down
	for _i in range(int(0.65 / DT)):
		manager.step(DT, human, [])
	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.AVAILABLE)

	# Check 30s lifetime on the ground before despawn
	var available_time := 0.0
	while manager.phase == RocketBoostManager.BoostPhase.AVAILABLE:
		manager.step(DT, human, [])
		available_time += DT
	Assertions.assert_near(available_time, 30.0, DT * 1.5, "Despawns after 30 s")
	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.DESPAWNING)

	# Test socket alternation ratio over 1000 cycles: ≈ 0.7 ± 0.05
	var alternations := 0
	var total_cycles := 1000
	var prev_idx := -1

	# Reset manager for socket distribution test
	manager.reset()
	for _c in range(total_cycles):
		var s := manager._pick_next_socket()
		var idx := manager.last_socket_idx
		if prev_idx != -1 and idx != prev_idx:
			alternations += 1
		prev_idx = idx

	var alt_ratio := float(alternations) / float(total_cycles - 1)
	Assertions.assert_true(alt_ratio >= 0.65 and alt_ratio <= 0.75, "Socket alternation ratio in [0.65, 0.75] (got %.3f)" % alt_ratio)

func test_boost_04_buff_and_collection() -> void:
	var manager := RocketBoostManager.new()
	manager.setup(_get_boost_sockets())

	# Put into AVAILABLE
	manager.phase = RocketBoostManager.BoostPhase.AVAILABLE
	manager.current_pickup_pos = Vector2(3808, 472)

	var bot := CharacterState.new()
	bot.id = 1
	bot.is_human = false
	bot.pos = manager.current_pickup_pos

	# 1. Bots cannot collect (§3.11.1)
	manager.step(DT, null, [bot])
	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.AVAILABLE, "Bot standing on pickup cannot collect it")
	Assertions.assert_eq(bot.boost_t, 0.0, "Bot does not receive boost buff")

	# 2. Human collects when distance <= 56 wu
	var human := CharacterState.new()
	human.id = 0
	human.is_human = true
	human.pos = manager.current_pickup_pos
	manager.step(DT, human, [bot])

	Assertions.assert_eq(manager.phase, RocketBoostManager.BoostPhase.WAITING, "Collected by human")
	Assertions.assert_near(human.boost_t, 10.0, 0.01, "Human receives 10.0 s boost buff")
	Assertions.assert_eq(human.stats.boosts_collected, 1, "Boosts collected statistic incremented")

	# 3. Test infinite jetpack (fuel constant while boosted)
	var motor := CharacterMotor.new()
	var grid := TileGrid.new()
	grid.load_from(Data.map)

	human.pos = Vector2(50 * 64, 20 * 64)
	human.fuel = 80.0
	human.grounded = false
	human.jet_active = true
	human.since_jump_t = 1.0

	var frame := InputFrame.new()
	frame.jet_held = true

	# Step motor with active boost
	motor.step(human, frame, DT, grid)
	Assertions.assert_near(human.fuel, 80.0, 0.001, "Fuel remains constant (infinite jetpack) while boosted")

	# 4. Buff cleared on death
	human.life_state = Enums.LifeState.DEAD
	manager.step(DT, human, [])
	Assertions.assert_eq(human.boost_t, 0.0, "Boost buff cleared on death")

## Map features (DEV-009): a launch pad throws a character from its floor to the
## catwalk/islands above; a med station heals +45 (capped at 100) and respawns in 25 s.
func test_boost_05_map_features() -> void:
	var cfg := MatchConfig.new()
	cfg.mode = &"mini_post"
	cfg.bot_count = 3
	cfg.rng_seed = 1
	var sim := MatchSim.new()
	sim.setup(cfg)
	sim.init_match()
	sim.begin_active()
	for b in sim.bot_chars:
		b.pos = Vector2(7000, 600)
	var h := sim.human_char
	var pad: MapFeatures.Pad = sim.features.pads[0]
	h.pos = pad.pos
	h.vel = Vector2.ZERO
	var f := InputFrame.new()
	f.aim_world = h.pos + Vector2(300, 0)
	var peak := h.pos.y
	for i in range(90):
		sim.step(1.0 / 60.0, f)
		peak = minf(peak, h.pos.y)
	Assertions.assert_true(pad.pos.y - peak > 448.0, "Launch pad lifts above the catwalk 448 wu up (got %.0f)" % (pad.pos.y - peak))

	var med: MapFeatures.Med = sim.features.meds[0]
	h.pos = med.pos
	h.vel = Vector2.ZERO
	h.health = 30.0
	h.regen_delay_t = 99.0
	sim.step(1.0 / 60.0, f)
	Assertions.assert_near(h.health, 75.0, 0.5, "Med station heals +45")
	Assertions.assert_true(not med.active, "Med station is used up")
	h.health = 90.0
	for i in range(int(25.0 * 60.0) + 2):
		sim.features.step(1.0 / 60.0, [])
	Assertions.assert_true(med.active, "Med station respawns after 25 s")
	sim.teardown()
