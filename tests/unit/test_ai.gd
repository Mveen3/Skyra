# Implements §10.4 / Table 10.6 Bot AI unit tests (T-AI-01..06).
class_name TestAi
extends RefCounted

const DT: float = 1.0 / 60.0

func _make_flat_grid(cols: int = 40, rows: int = 20) -> TileGrid:
	var ascii: Array[String] = []
	for r in range(rows):
		var line := ""
		for c in range(cols):
			line += "#" if (r == 0 or r == rows - 1 or c == 0 or c == cols - 1 or r == rows - 2) else "."
		ascii.append(line)
	var tg := TileGrid.new()
	tg.load_from_ascii(ascii)
	return tg

func test_ai_01_reaction() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var alpha_profile: BotProfile = Data.bots[0]
	var react_mult := alpha_profile.reaction_mult

	var grid := _make_flat_grid()
	var bot := CharacterState.new()
	bot.id = 1
	bot.profile = alpha_profile
	bot.pos = Vector2(200, 1000)

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(400, 1000)
	human.life_state = Enums.LifeState.ALIVE

	for i in range(100):
		var p := Perception.new(1)
		p.update(bot, human, grid, float(i), rng)
		Assertions.assert_between(p.reaction_t, 0.27 * react_mult - 1e-4, 0.43 * react_mult + 1e-4,
			"Reaction delay in [0.27, 0.43] * reaction_mult")

func test_ai_02_stealth_honoured() -> void:
	var grid := _make_flat_grid(60, 30)
	var nav := NavGrid.new()
	nav.build(grid, [])
	var tac := TacticalQueries.new()
	tac.init_cache(nav, grid, Data.map)
	var director := PacingDirector.new()
	director.init_bots([1, 2, 3])

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(1000, 1000)
	human.stealth_t = 2.0 # 2.0 s stealth
	human.life_state = Enums.LifeState.ALIVE

	var bots: Array[CharacterState] = []
	var brains: Array[BotBrain] = []
	for i in range(1, 4):
		var b := CharacterState.new()
		b.id = i
		b.pos = human.pos + Vector2(float(i * 100), 0)
		b.profile = Data.bots[i - 1]
		var w := WeaponInstance.new(Data.weapons["mp5"])
		w.clip = 30
		w.reserve = 90
		b.inventory.set_weapon(0, w)
		b.inventory.set_active_slot(0)
		var brain := BotBrain.new(b)
		brain.has_token = true # token holding
		bots.append(b)
		brains.append(brain)

	# For first 2.0 s: no bot fires, targets or damages her
	for tick in range(120): # 2.0 s
		human.stealth_t = maxf(0.0, human.stealth_t - DT)
		for brain in brains:
			var frame := brain.step_tick(tick, DT, human, grid, nav, tac, director, [], float(tick) * DT)
			Assertions.assert_false(frame.fire_pressed, "No bot fire_pressed while stealthed")
			Assertions.assert_false(frame.fire_held, "No bot fire_held while stealthed")
			Assertions.assert_false(brain.perception.sees_human, "Stealth wipes perception")

	# After 2.0 s: stealth expired, bots acquire within reaction time
	human.stealth_t = 0.0
	var acquired := false
	for tick in range(120, 160):
		for brain in brains:
			brain.step_tick(tick, DT, human, grid, nav, tac, director, [], float(tick) * DT)
			if brain.perception.sees_human:
				acquired = true
	Assertions.assert_true(acquired, "Bots acquire Skyra after stealth ends")

func test_ai_03_fire_permission() -> void:
	# Over 120-s soak: no non-token bot fires except as single self-defender
	var grid := _make_flat_grid(60, 30)
	var nav := NavGrid.new()
	nav.build(grid, [])
	var tac := TacticalQueries.new()
	tac.init_cache(nav, grid, Data.map)
	var director := PacingDirector.new()

	var bot_ids: Array = [1, 2, 3, 4, 5, 6, 7]
	director.init_bots(bot_ids)

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(1000, 1000)
	human.life_state = Enums.LifeState.ALIVE

	var bots: Array[CharacterState] = []
	var brains: Array[BotBrain] = []
	for i in range(1, 8):
		var b := CharacterState.new()
		b.id = i
		b.pos = Vector2(float(800 + i * 50), 1000)
		b.profile = Data.bots[i - 1]
		var w := WeaponInstance.new(Data.weapons["mp5"])
		w.clip = 30
		w.reserve = 90
		b.inventory.set_weapon(0, w)
		b.inventory.set_active_slot(0)
		var brain := BotBrain.new(b)
		bots.append(b)
		brains.append(brain)

	# Simulate 120 s (7200 ticks)
	var non_token_illegal_fires := 0
	for tick in range(7200):
		var now := float(tick) * DT
		director.step(DT, bots, human, now)

		for brain in brains:
			var bid := brain.bot.id
			var binfo: Dictionary = director.bot_data.get(bid, {})
			var token: bool = bool(binfo.get("has_token", false))
			var role: int = int(binfo.get("role", Enums.DirectorRole.PATROLLER))
			var is_self_def := (director.self_defender_id == bid)
			brain.set_director_status(token, role, is_self_def)

			var frame := brain.step_tick(tick, DT, human, grid, nav, tac, director, [], now)
			var fired := (frame.fire_pressed or frame.fire_held)
			if fired and not token and not is_self_def:
				non_token_illegal_fires += 1

	Assertions.assert_eq(non_token_illegal_fires, 0, "No non-token bot fired without self-defence permission")

func test_ai_04_aim_error() -> void:
	var acc_mult := 1.0
	# σ(0) = 8° × accuracy_mult
	var s0 := AimModel.calc_sigma_deg(0.0, 0.0, false, 500.0, acc_mult, false)
	Assertions.assert_near(s0, 8.0, 1e-3, "Aim error sigma(0) = 8.0 deg")

	# ≤ 1.3° after 3 s tracking a static target
	var s3 := AimModel.calc_sigma_deg(3.0, 0.0, false, 500.0, acc_mult, false)
	Assertions.assert_true(s3 <= 1.3, "Aim error sigma(3.0) <= 1.3 deg (got %.3f)" % s3)

func test_ai_05_bot_grenades() -> void:
	var rows: Array[String] = []
	for r in range(25):
		var line := ""
		for c in range(50):
			line += "#" if (r == 0 or r == 24 or c == 0 or c == 49 or r == 20) else "."
		rows.append(line)
	var grid := TileGrid.new()
	grid.load_from_ascii(rows)

	var origin := Vector2(200.0, 19.0 * 64.0)

	for dist in [400.0, 700.0, 900.0]:
		var target := Vector2(origin.x + dist, origin.y)
		var solved := AimModel.solve_grenade_angle(origin, target, grid)
		Assertions.assert_true(bool(solved["success"]), "Grenade solver found angle at %.0f wu" % dist)

func test_ai_06_fair_pickups() -> void:
	var bot := CharacterState.new()
	bot.id = 1
	bot.pos = Vector2(500, 1000)

	var human := CharacterState.new()
	human.id = 0
	human.pos = Vector2(700, 1000) # distance to item = 100
	human.life_state = Enums.LifeState.ALIVE

	var loose_item := LooseWeapon.new()
	loose_item.id = 1
	loose_item.def = Data.weapons["ak47"]
	loose_item.clip = 30 # §5.9: a weapon without ammo is worth 0, so give it a full magazine
	loose_item.reserve = 90
	loose_item.pos = Vector2(800, 1000) # distance to bot = 300, distance to human = 100
	loose_item.active = true

	var brain := BotBrain.new(bot)
	var frame := InputFrame.new()

	brain._check_weapon_handling(frame, DT, human, [loose_item])
	Assertions.assert_false(frame.pickup_pressed, "Bot does not pick up item when Skyra is closer")

	# Now move Skyra far away (1500 wu)
	human.pos = Vector2(2000, 1000)
	bot.pos = Vector2(780, 1000) # within 60 wu
	brain._check_weapon_handling(frame, DT, human, [loose_item])
	Assertions.assert_true(frame.pickup_pressed, "Bot picks up item when closer than Skyra")

## §5.5 hearing: Skyra's Magnum shot is heard within 1800 wu (no LOS needed) and gives an
## approximate last known position; nothing is heard while she is stealthed.
func test_ai_07_hearing() -> void:
	var cfg := MatchConfig.new()
	cfg.mode = &"mini_post"
	cfg.bot_count = 3
	cfg.rng_seed = 5
	var sim := MatchSim.new()
	sim.setup(cfg)
	sim.init_match()
	sim.begin_active()
	var h := sim.human_char
	var near_bot := sim.bot_chars[0]
	var far_bot := sim.bot_chars[1]
	near_bot.pos = h.pos + Vector2(1500.0, 0.0)
	far_bot.pos = h.pos + Vector2(-2400.0, 0.0)
	var frame := InputFrame.new()
	frame.aim_world = h.shoulder() + Vector2(0.0, -300.0)

	# Stealthed: the shot is not heard
	h.stealth_t = 1.0
	frame.fire_pressed = true
	sim.step(1.0 / 60.0, frame)
	Assertions.assert_true(not near_bot.perception.has_known_target(sim.time), "No hearing while Skyra is stealthed")

	# Visible again: the next shot is heard by the near bot only
	h.stealth_t = 0.0
	h.invuln_t = 0.0
	frame.fire_pressed = false
	for i in range(30):
		sim.step(1.0 / 60.0, frame)
	frame.fire_pressed = true
	sim.step(1.0 / 60.0, frame)
	Assertions.assert_true(near_bot.perception.has_known_target(sim.time), "Bot within 1800 wu hears the Magnum")
	Assertions.assert_true(near_bot.perception.last_known_pos.distance_to(h.centre()) <= 151.0, "Heard position within 150 wu of Skyra")
	Assertions.assert_true(not far_bot.perception.has_known_target(sim.time), "Bot beyond 1800 wu does not hear it")
	sim.teardown()
