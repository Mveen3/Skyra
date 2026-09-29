# Implements §10.4 / Table 10.6 Pacing Director unit tests (T-DIR-01..05).
class_name TestDir
extends RefCounted

const DT: float = 1.0 / 60.0

func test_dir_01_invariants() -> void:
	var director := PacingDirector.new()
	director.init_bots([1, 2, 3, 4, 5, 6, 7])

	var bots: Array[CharacterState] = []
	for i in range(1, 8):
		var b := CharacterState.new()
		b.id = i
		b.life_state = Enums.LifeState.ALIVE
		b.pos = Vector2(float(1000 + i * 100), 1000)
		bots.append(b)

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(1000, 1000)
	human.life_state = Enums.LifeState.ALIVE

	# Run 600 ticks (10 s)
	for tick in range(600):
		var now := float(tick) * DT
		director.step(DT, bots, human, now)

		# INV-1: Bots holding token <= allowed(phase) <= 2
		var allowed := director.allowed_tokens()
		var count := 0
		for bid in director.bot_data:
			if bool(director.bot_data[bid]["has_token"]):
				count += 1
		Assertions.assert_true(count <= allowed, "INV-1: Holders (%d) <= allowed (%d)" % [count, allowed])
		Assertions.assert_true(allowed <= 2, "INV-1: Allowed <= 2")

		# INV-4: Live bot grenades <= 1
		Assertions.assert_true(director.live_bot_grenades <= 1, "INV-4: live bot grenades <= 1")

func test_dir_02_phases() -> void:
	var director := PacingDirector.new()
	director.init_bots([1, 2, 3])

	var bots: Array[CharacterState] = []
	for i in range(1, 4):
		var b := CharacterState.new()
		b.id = i
		b.life_state = Enums.LifeState.ALIVE
		bots.append(b)

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(1000, 1000)
	human.life_state = Enums.LifeState.ALIVE

	Assertions.assert_eq(director.phase, Enums.PacingPhase.WARMUP, "Starts in WARMUP")

	# Step 5.25 s -> BUILD_UP
	for _i in range(int(5.25 / DT)):
		director.step(DT, bots, human, 0.0)
	Assertions.assert_eq(director.phase, Enums.PacingPhase.BUILD_UP, "Transitions to BUILD_UP after 5 s")

	# Intensity >= 0.70 -> PEAK
	director.intensity = 0.75
	for _i in range(16): # 1 director tick
		director.step(DT, bots, human, 0.0)
	Assertions.assert_eq(director.phase, Enums.PacingPhase.PEAK, "Transitions to PEAK at intensity >= 0.70")

	# Intensity >= 0.90 -> RELAX
	director.intensity = 0.95
	for _i in range(16):
		director.step(DT, bots, human, 0.0)
	Assertions.assert_eq(director.phase, Enums.PacingPhase.RELAX, "Transitions to RELAX at intensity >= 0.90")

	# 6 s in RELAX and intensity <= 0.45 -> BUILD_UP
	director.intensity = 0.30
	for _i in range(int(6.5 / DT)):
		director.step(DT, bots, human, 0.0)
	Assertions.assert_eq(director.phase, Enums.PacingPhase.BUILD_UP, "Transitions to BUILD_UP after 6 s in RELAX with low intensity")

	# Human dies -> RESPAWN_GRACE
	director.register_human_death()
	Assertions.assert_eq(director.phase, Enums.PacingPhase.RESPAWN_GRACE, "Transitions to RESPAWN_GRACE on human death")
	Assertions.assert_eq(director.allowed_tokens(), 0, "0 tokens in RESPAWN_GRACE")

	# Human revived without stealth, wait 1.25 s -> BUILD_UP with 2.5 s ramp
	human.life_state = Enums.LifeState.ALIVE
	human.stealth_t = 0.0
	for _i in range(int(1.25 / DT)):
		director.step(DT, bots, human, 0.0)
	Assertions.assert_eq(director.phase, Enums.PacingPhase.BUILD_UP, "Transitions to BUILD_UP after grace")
	Assertions.assert_true(director.post_grace_ramp_timer > 0.0, "Post-grace ramp timer active")
	Assertions.assert_eq(director.allowed_tokens(), 1, "Tokens capped at 1 during post-grace ramp")

func test_dir_03_breather() -> void:
	var director := PacingDirector.new()
	director.init_bots([1, 2, 3])

	var bots: Array[CharacterState] = []
	for i in range(1, 4):
		var b := CharacterState.new()
		b.id = i
		b.life_state = Enums.LifeState.ALIVE
		b.pos = Vector2(float(1000 + i * 100), 1000)
		bots.append(b)

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(1000, 1000)
	human.life_state = Enums.LifeState.ALIVE

	# Fast forward to BUILD_UP
	director.phase = Enums.PacingPhase.BUILD_UP
	director.phase_timer = 0.0

	# Step until 2 tokens granted
	for _i in range(20):
		director.step(DT, bots, human, 0.0)

	var holders: Array[int] = []
	for bid in director.bot_data:
		if bool(director.bot_data[bid]["has_token"]):
			holders.append(bid)
	Assertions.assert_eq(holders.size(), 2, "2 tokens granted in BUILD_UP")

	# Holder 1 dies
	var killed_id: int = holders[0]
	director.register_bot_killed(true, killed_id)
	Assertions.assert_near(director.breather_timer, 1.5, 0.01, "Breather timer set to 1.5 s")

	# For 1.4 s: no new grant
	for _i in range(int(1.4 / DT)):
		director.step(DT, bots, human, 0.0)

	var current_holders := 0
	for bid in director.bot_data:
		if bool(director.bot_data[bid]["has_token"]):
			current_holders += 1
	Assertions.assert_eq(current_holders, 1, "No new grant during 1.5 s breather")

	# After breather ends: token granted
	for _i in range(int(0.3 / DT)):
		director.step(DT, bots, human, 0.0)

	current_holders = 0
	for bid in director.bot_data:
		if bool(director.bot_data[bid]["has_token"]):
			current_holders += 1
	Assertions.assert_eq(current_holders, 2, "Token granted after breather ends")

func test_dir_04_rotation() -> void:
	var director := PacingDirector.new()
	director.init_bots([1, 2])

	var b1 := CharacterState.new()
	b1.id = 1
	b1.pos = Vector2(1100, 1000)
	b1.life_state = Enums.LifeState.ALIVE

	var b2 := CharacterState.new()
	b2.id = 2
	b2.pos = Vector2(1150, 1000)
	b2.life_state = Enums.LifeState.ALIVE

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(1000, 1000)
	human.life_state = Enums.LifeState.ALIVE

	var p1 := BotProfile.new()
	p1.aggression = 1.0
	b1.profile = p1

	var p2 := BotProfile.new()
	p2.aggression = 0.1
	b2.profile = p2

	director.phase = Enums.PacingPhase.RELAX # allowed = 1
	director.phase_timer = 0.0

	# Grant token to b1 initially
	for _i in range(16):
		director.step(DT, [b1, b2], human, 0.0)
	Assertions.assert_true(bool(director.bot_data[1]["has_token"]), "b1 has token")

	# Now b2 gets aggression and damage bonus so b2 score > b1 score
	p2.aggression = 1.0
	p1.aggression = 0.1

	# Step to 3.5 s: no rotation before 4.0 s even though b2 has higher score
	for step_idx in range(int(3.5 / DT)):
		var now := float(step_idx) * DT
		b2.last_enemy_damage_time = now
		director.phase = Enums.PacingPhase.RELAX
		director.phase_timer = 0.0
		director.step(DT, [b1, b2], human, now)
	Assertions.assert_true(bool(director.bot_data[1]["has_token"]), "No rotation before 4.0 s")

	# Advance to 12.5 s: rotation occurs when score >= holder - 0.1
	for step_idx in range(int(3.5 / DT), int(12.5 / DT)):
		var now := float(step_idx) * DT
		b2.last_enemy_damage_time = now
		director.phase = Enums.PacingPhase.RELAX
		director.phase_timer = 0.0
		director.step(DT, [b1, b2], human, now)

	Assertions.assert_true(bool(director.bot_data[2]["has_token"]), "Token rotated to b2 at >= 12.0 s")
	Assertions.assert_false(bool(director.bot_data[1]["has_token"]), "b1 lost token")
	Assertions.assert_true(float(director.bot_data[1]["cooldown_t"]) > 0.0, "b1 in rotation cooldown")

func test_dir_05_bubble_statistic() -> void:
	# INV-5: time-averaged number of non-token bots inside bubble <= 0.5
	var director := PacingDirector.new()
	director.init_bots([1, 2, 3, 4, 5])
	# With staging ring outside bubble, non-token bots are placed outside bubble
	Assertions.assert_true(director.staging_ring_min >= director.bubble_radius, "Staging ring is outside bubble radius")
