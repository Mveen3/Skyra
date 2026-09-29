# Implements §1.4 MatchSim (60 Hz fixed-tick match orchestrator).
class_name MatchSim
extends RefCounted

var config: MatchConfig
var grid: TileGrid
var nav: NavGrid
var tac: TacticalQueries
var rng_streams: RngStreams

var human_char: CharacterState
var bot_chars: Array[CharacterState] = []
var characters: Array[CharacterState] = []
var characters_by_id: Dictionary = {}

var projectiles: ProjectileSystem
var beams: BeamSystem
var damage_system: DamageSystem
var sockets: WeaponSocketManager
var boost: RocketBoostManager
var director: PacingDirector
var rules: MatchRules
var motor: CharacterMotor
var loose_weapons: Array = []

var time: float = 0.0
var tick: int = 0
var bot_frames: Dictionary = {} # int id -> InputFrame

func setup(p_config: MatchConfig) -> void:
	config = p_config
	time = 0.0
	tick = 0
	bot_frames.clear()

	# Grid & Nav & Tactics
	grid = TileGrid.new()
	grid.load_from(Data.map)
	nav = NavGrid.new()
	nav.build(grid, Data.map.sockets)
	tac = TacticalQueries.new()
	tac.init_cache(nav, grid, Data.map)

	# RNG streams
	rng_streams = RngStreams.new(config.rng_seed)

	# Human character (id 0)
	human_char = CharacterState.new()
	human_char.id = 0
	human_char.is_human = true
	human_char.team = Enums.Team.HUMAN
	human_char.name = "Skyra"
	WeaponLogic.give_spawn_loadout(human_char, config.mode)

	# Bots (ids 1..N)
	bot_chars.clear()
	var bot_profiles: Array = Data.bots
	var bot_ids: Array[int] = []
	for i in range(min(config.bot_count, bot_profiles.size())):
		var b := CharacterState.new()
		b.id = i + 1
		b.is_human = false
		b.team = Enums.Team.BOT
		var prof: BotProfile = bot_profiles[i]
		b.profile = prof
		b.name = prof.name
		WeaponLogic.give_spawn_loadout(b, config.mode)

		var brain := BotBrain.new(b, config.rng_seed)
		b.brain = brain

		bot_chars.append(b)
		bot_ids.append(b.id)
		bot_frames[b.id] = InputFrame.new()

	characters.clear()
	characters_by_id.clear()
	characters.append(human_char)
	characters_by_id[human_char.id] = human_char
	for b in bot_chars:
		characters.append(b)
		characters_by_id[b.id] = b

	# Subsystems
	damage_system = DamageSystem.new()
	projectiles = ProjectileSystem.new()
	beams = BeamSystem.new()
	motor = CharacterMotor.new()

	sockets = WeaponSocketManager.new()
	sockets.setup(Data.map.sockets, config.mode, rng_streams.rng_loot)

	boost = RocketBoostManager.new()
	boost.setup(Data.map.sockets, rng_streams.rng_loot)

	director = PacingDirector.new()
	director.init_bots(bot_ids)

	rules = MatchRules.new()
	rules.setup(config, human_char, bot_chars)

	# Connect kill event to rules
	damage_system.kill_occurred.connect(_on_character_killed)

	place_initial_spawns()

func _on_character_killed(ev: KillEvent) -> void:
	var killer: CharacterState = character(ev.killer_id)
	var victim: CharacterState = character(ev.victim_id)
	rules.register_kill(killer, victim, ev.weapon_id, ev.distance)

func character(p_id: int) -> CharacterState:
	return characters_by_id.get(p_id, null)

func human() -> CharacterState:
	return human_char

func init_match() -> void:
	place_initial_spawns()

func place_initial_spawns() -> void:
	var initial_spawns := SpawnSelector.select_initial_spawns(Data.map.sockets, bot_chars.size(), grid, rng_streams.rng_spawn)
	for cid in initial_spawns:
		var c: CharacterState = character(int(cid))
		var s: SocketDef = initial_spawns[cid]
		if c and s:
			c.pos = s.world
			c.prev_pos = s.world
			c.vel = Vector2.ZERO
			c.health = 100.0
			c.fuel = 100.0
			c.life_state = Enums.LifeState.ALIVE
			if c.is_human:
				c.stealth_t = 2.0
				c.invuln_t = 2.0
			EventBus.character_spawned.emit(c.id, c.pos, true)

func begin_active() -> void:
	rules.reset()
	boost.reset()
	time = 0.0

func step_countdown(dt: float, human_frame: InputFrame) -> void:
	# Spawning countdown phase: characters frozen in place, aim allowed (§1.3, §1.4)
	if human_char and human_frame:
		human_char.aim_angle = human_frame.aim_angle
		human_char.aim_dir = human_frame.aim_dir
		human_char.facing = human_frame.facing

func step(dt: float, human_frame: InputFrame) -> void:
	# ── 1. INPUT ──────────────────────────────────────────────────────────────
	# 1.1 human_frame passed in
	# 1.2 bot_frames produced by previous tick (§1.4)

	# ── 2. PHYSICS & COMBAT ───────────────────────────────────────────────────
	# 2.1 Status effects & respawns
	for c in characters:
		if c.stealth_t > 0.0:
			c.stealth_t = maxf(0.0, c.stealth_t - dt)
		if c.invuln_t > 0.0:
			c.invuln_t = maxf(0.0, c.invuln_t - dt)
		if c.burn_t > 0.0:
			c.burn_t = maxf(0.0, c.burn_t - dt)
			c.burn_tick_t += dt
			if c.burn_tick_t >= 0.25:
				c.burn_tick_t -= 0.25
				damage_system.queue_damage(c, c.burn_source, Enums.Team.HUMAN if c.burn_source == 0 else Enums.Team.BOT,
					"flamethrower", 2.5, c.pos, Vector2.ZERO, false, false, 1.0)

		# Respawns
		if c.life_state == Enums.LifeState.DEAD:
			c.respawn_t = maxf(0.0, c.respawn_t - dt)
			if c.respawn_t <= 0.0:
				var s: SocketDef = null
				if c.is_human:
					s = SpawnSelector.select_human_spawn(Data.map.sockets, bot_chars, c.prev_pos, grid, rng_streams.rng_spawn)
				else:
					var cam_r := Rect2(human_char.pos - Vector2(960, 540), Vector2(1920, 1080))
					s = SpawnSelector.select_bot_spawn(Data.map.sockets, human_char.pos, cam_r, {}, time, grid, rng_streams.rng_spawn)
				if s:
					c.pos = s.world
					c.prev_pos = s.world
					c.vel = Vector2.ZERO
					c.health = 100.0
					c.fuel = 100.0
					c.life_state = Enums.LifeState.ALIVE
					WeaponLogic.give_spawn_loadout(c, config.mode)
					if c.is_human:
						c.stealth_t = 2.0
						c.invuln_t = 2.0
					elif c.brain and c.brain.has_method("on_respawn"):
						c.brain.on_respawn()
					EventBus.character_spawned.emit(c.id, c.pos, false)

	# 2.2 CharacterMotor.step (id order, human first)
	for c in characters:
		var frame: InputFrame = human_frame if c.is_human else bot_frames.get(c.id, InputFrame.new())
		motor.step(c, frame, dt, grid)

	# 2.3 WeaponLogic.step
	for c in characters:
		var frame: InputFrame = human_frame if c.is_human else bot_frames.get(c.id, InputFrame.new())
		WeaponLogic.step(c, frame, dt, grid, projectiles, beams, damage_system, rng_streams.rng_combat)

	# 2.4 ProjectileSystem.step
	projectiles.step(dt, grid, characters, damage_system, time)

	# 2.5 BeamSystem.step_beam
	for c in characters:
		var frame: InputFrame = human_frame if c.is_human else bot_frames.get(c.id, InputFrame.new())
		beams.step_beam(c, frame, dt, grid, characters, damage_system)

	# 2.7 DamageSystem.flush
	damage_system.flush(characters_by_id, time)

	# 2.8 Sockets & Boost
	sockets.step(dt, characters, rng_streams.rng_loot)
	boost.step(dt, human_char, bot_chars)

	# 2.9 MatchRules.step
	rules.step(dt)

	# ── 3. AI ─────────────────────────────────────────────────────────────────
	# 3.1 PacingDirector.step
	director.step(dt, bot_chars, human_char, time)

	# 3.2 Bots update frames for NEXT tick
	for b in bot_chars:
		var brain: BotBrain = b.brain as BotBrain
		if brain:
			var frame: InputFrame = brain.step_tick(tick, dt, human_char, grid, nav, tac, director, [], time)
			bot_frames[b.id] = frame

	time += dt
	tick += 1

func state_hash() -> int:
	var h: int = tick * 31
	for c in characters:
		h = (h * 37) ^ int(c.pos.x * 10.0)
		h = (h * 41) ^ int(c.pos.y * 10.0)
		h = (h * 43) ^ int(c.vel.x * 10.0)
		h = (h * 47) ^ int(c.vel.y * 10.0)
		h = (h * 53) ^ int(c.health * 10.0)
		h = (h * 59) ^ int(c.fuel * 10.0)
		h = (h * 61) ^ c.life_state
		var w := c.inventory.active_weapon() if c.inventory else null
		if w:
			h = (h * 67) ^ int(w.clip)
			h = (h * 71) ^ int(w.reserve)
	h = (h * 73) ^ boost.phase
	h = (h * 79) ^ int(rules.time_left_s * 10.0)
	return h
