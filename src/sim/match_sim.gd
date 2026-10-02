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
var features: MapFeatures
var director: PacingDirector
var rules: MatchRules
var motor: CharacterMotor
var loose_weapons: Array[LooseWeapon] = []
var last_bot_spawns: Dictionary = {} # socket id -> sim time of the last bot spawn there
var human_view_rect: Rect2 = Rect2() # fed by the camera; zero size = approximate from scope
var bot_respawns: int = 0          # bot respawns this match (initial spawns excluded)
var bot_spawn_fallbacks: int = 0   # ... of which needed spawn tier >= 3 (§6.7, INV-6)

const LOOSE_WEAPON_CAP: int = 12
var _next_loose_id: int = 1
var _empty_frame: InputFrame = InputFrame.new()
var _human_heard_shots: int = 0 # human.stats.shots_fired already reported to the bots
## Per-section timings of the last tick in µs (debug overlay "Sim ms / AI ms", §9.9)
var prof_us: Dictionary = {"physics": 0, "combat": 0, "pickups": 0, "director": 0, "ai": 0, "nav": 0}

var time: float = 0.0
var tick: int = 0
var bot_frames: Dictionary = {} # int id -> InputFrame
var brains: Array[BotBrain] = [] # owns the bot brains (CharacterState.brain is weak)

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
	nav.async_enabled = true
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
	brains.clear()
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
		brains.append(brain)

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

	features = MapFeatures.new()
	features.setup(Data.tuning)
	for br in brains:
		br.features_ref = features
	boost = RocketBoostManager.new()
	boost.setup(Data.map.sockets, rng_streams.rng_loot)

	director = PacingDirector.new(str(config.mode))
	director.init_bots(bot_ids)

	rules = MatchRules.new()
	rules.setup(config, human_char, bot_chars)

	# Kill / damage bookkeeping inside the Sim (rules, Director intensity, drops)
	damage_system.kill_occurred.connect(_on_character_killed)
	damage_system.damage_applied.connect(_on_damage_applied)

	place_initial_spawns()

func _on_character_killed(ev: KillEvent) -> void:
	var killer: CharacterState = character(ev.killer_id)
	var victim: CharacterState = character(ev.victim_id)
	if victim:
		_handle_death(victim)
	rules.register_kill(killer, victim, ev.weapon_id, ev.distance, ev)
	# §5.4.2 intensity / §5.4.4 token bookkeeping
	if victim and victim.is_human:
		director.register_human_death()
	elif victim:
		director.register_bot_killed(killer != null and killer.is_human, victim.id)

func _on_damage_applied(ev: DamageEvent, source_team: int) -> void:
	if ev.target_id == human_char.id and source_team == Enums.Team.BOT:
		director.register_bot_damage_to_human(ev.amount)

## Death side effects (§3.12 rule 6, §3.13, §4.10.4): drop the active weapon if it has
## ammo (never the Magnum), lose the other slot, remember where it happened.
func _handle_death(victim: CharacterState) -> void:
	victim.death_pos = victim.pos
	victim.vel = Vector2.ZERO
	victim.jet_active = false
	var drop := victim.inventory.get_death_drop(victim.centre())
	if drop:
		drop.vel = Vector2(victim.facing * 120.0, -260.0)
		drop.facing = victim.facing
		_add_loose_weapon(drop)
		EventBus.weapon_dropped.emit(victim.id, drop.def.id, drop.pos)
	victim.inventory.clear()
	EventBus.respawn_scheduled.emit(victim.id, victim.respawn_t)

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
			_spawn_at(c, s, true)

## Places `c` at socket `s` with a fresh life (§3.13). Skyra gets stealth + invulnerability.
func _spawn_at(c: CharacterState, s: SocketDef, initial: bool) -> void:
	c.reset_for_spawn(s.world)
	WeaponLogic.give_spawn_loadout(c, config.mode)
	if c.is_human:
		var r: Dictionary = Data.tuning.get("respawn", {})
		c.stealth_t = float(r.get("human_stealth_s", 2.0))
		c.invuln_t = float(r.get("human_invuln_s", 2.0))
		EventBus.stealth_started.emit(c.id, c.stealth_t)
	else:
		last_bot_spawns[s.id] = time
		if c.brain and c.brain.has_method("on_respawn"):
			c.brain.on_respawn()
	EventBus.character_spawned.emit(c.id, c.pos, initial)

func _respawn(c: CharacterState) -> void:
	var s: SocketDef = null
	if c.is_human:
		s = SpawnSelector.select_human_spawn(Data.map.sockets, bot_chars, c.death_pos, grid, rng_streams.rng_spawn)
	else:
		# While Skyra is dead, bot spawns use her death position as "Skyra" (§6.7).
		var skyra_pos := human_char.pos if human_char.life_state == Enums.LifeState.ALIVE else human_char.death_pos
		s = SpawnSelector.select_bot_spawn(Data.map.sockets, skyra_pos, _human_view_rect(skyra_pos), last_bot_spawns, time, grid, rng_streams.rng_spawn)
		bot_respawns += 1
		if SpawnSelector.last_bot_tier >= 3:
			bot_spawn_fallbacks += 1
	if s:
		_spawn_at(c, s, false)

## Skyra's camera view in world space. The view layer feeds the real camera rect via
## `human_view_rect`; headless runs approximate it from the held weapon's scope (§3.10).
func _human_view_rect(centre: Vector2) -> Rect2:
	if human_view_rect.size != Vector2.ZERO:
		return human_view_rect
	var scope := 1.0
	var w := human_char.inventory.active_weapon()
	if w:
		scope = w.def.scope
	var half := Vector2(960.0, 540.0) * sqrt(scope)
	return Rect2(centre - half, half * 2.0)

func begin_active() -> void:
	rules.reset()
	boost.reset()
	time = 0.0

## SPAWNING countdown: characters are frozen, only aiming is allowed (§1.3, §1.4).
func step_countdown(_dt: float, human_frame: InputFrame) -> void:
	if human_char and human_frame and human_frame.aim_world != Vector2.ZERO:
		var aim_v := human_frame.aim_world - human_char.shoulder()
		if aim_v.length_squared() > 1e-4:
			human_char.aim_angle = aim_v.angle()
			human_char.aim_dir = aim_v.normalized()
			if absf(aim_v.x) > 1.0:
				human_char.facing = 1 if aim_v.x > 0.0 else -1
	for c in characters:
		c.prev_pos = c.pos

func _frame_for(c: CharacterState, human_frame: InputFrame) -> InputFrame:
	if c.is_human:
		return human_frame
	return bot_frames.get(c.id, _empty_frame)

func step(dt: float, human_frame: InputFrame) -> void:
	# ── 1. INPUT ──────────────────────────────────────────────────────────────
	# 1.1 human_frame passed in
	# 1.2 bot_frames produced by previous tick (§1.4)

	# ── 2. PHYSICS & COMBAT ───────────────────────────────────────────────────
	# 2.1 Status effects & respawns
	for c in characters:
		if c.life_state == Enums.LifeState.DEAD:
			c.prev_pos = c.pos
			c.respawn_t = maxf(0.0, c.respawn_t - dt)
			if c.respawn_t <= 0.0:
				_respawn(c)
			continue
		if c.stealth_t > 0.0:
			c.stealth_t = maxf(0.0, c.stealth_t - dt)
			if c.stealth_t <= 0.0:
				EventBus.stealth_ended.emit(c.id)
		if c.invuln_t > 0.0:
			c.invuln_t = maxf(0.0, c.invuln_t - dt)
		damage_system.step_burn(c, dt)

	var _t0 := Time.get_ticks_usec()
	# 2.2 CharacterMotor.step (id order, human first); the dead don't move
	for c in characters:
		if c.life_state == Enums.LifeState.ALIVE:
			motor.step(c, _frame_for(c, human_frame), dt, grid)

	var _t1 := Time.get_ticks_usec()
	# 2.3 WeaponLogic.step
	for c in characters:
		if c.life_state == Enums.LifeState.ALIVE:
			WeaponLogic.step(c, _frame_for(c, human_frame), dt, grid, projectiles, beams, damage_system, rng_streams.rng_combat)

	# 2.4 ProjectileSystem.step
	projectiles.step(dt, grid, characters, damage_system, time)
	for _i in range(projectiles.near_misses_this_tick):
		director.register_near_miss()
	projectiles.near_misses_this_tick = 0

	# 2.5 BeamSystem.step_beam
	for c in characters:
		beams.step_beam(c, _frame_for(c, human_frame), dt, grid, characters, damage_system)

	# 2.7 DamageSystem.flush
	damage_system.flush(characters_by_id, time)

	# 2.7b Bot hearing (§5.5): Skyra's shots and explosions this tick
	_step_hearing()

	var _t2 := Time.get_ticks_usec()
	# 2.8 Pickups, sockets, Rocket Boost, loose weapons
	_step_pickups(human_frame)
	sockets.step(dt, characters, rng_streams.rng_loot)
	boost.step(dt, human_char, bot_chars)
	features.step(dt, characters)
	_step_loose_weapons(dt)

	# 2.9 MatchRules.step
	rules.step(dt)

	# ── 3. AI ─────────────────────────────────────────────────────────────────
	var _t3 := Time.get_ticks_usec()
	# 3.1 PacingDirector.step
	director.live_bot_grenades = _count_live_bot_grenades()
	director.step(dt, bot_chars, human_char, time)
	_sync_director_to_brains()

	var _t4 := Time.get_ticks_usec()
	# 3.2 Bots update frames for NEXT tick
	for b in bot_chars:
		var brain: BotBrain = b.brain as BotBrain
		if brain:
			var frame: InputFrame = brain.step_tick(tick, dt, human_char, grid, nav, tac, director, loose_weapons, time, sockets)
			bot_frames[b.id] = frame

	var _t5 := Time.get_ticks_usec()
	# 3.3 NavGrid.process_queue: time-sliced A* for the queued path requests
	nav.process_queue(grid)
	var _t6 := Time.get_ticks_usec()
	prof_us["physics"] = _t1 - _t0
	prof_us["combat"] = _t2 - _t1
	prof_us["pickups"] = _t3 - _t2
	prof_us["director"] = _t4 - _t3
	prof_us["ai"] = _t5 - _t4
	prof_us["nav"] = _t6 - _t5

	time += dt
	tick += 1

# ── Pickups & loose weapons (§4.10.3, §4.10.4) ──────────────────────────────

func _step_pickups(human_frame: InputFrame) -> void:
	for c in characters:
		if c.life_state != Enums.LifeState.ALIVE:
			continue
		_collect_frag_packs(c)
		var frame := _frame_for(c, human_frame)
		if frame.pickup_pressed:
			_resolve_pickup(c)
		elif frame.drop_pressed:
			_drop_active_weapon(c)

func _collect_frag_packs(c: CharacterState) -> void:
	if c.inventory.grenades >= c.inventory.max_grenades:
		return
	for s in sockets.sockets:
		if s.is_available and s.current_item == "frag_pack":
			if PickupResolver.try_collect_frag_pack(c, WeaponSocketManager.item_pos_of(s)):
				sockets.take(s.def.id, c.id)
				return

## The weapon item `c` would interact with on E: the nearest socket weapon or loose
## weapon within reach. Returns {} or {def, clip, reserve, pos, socket_id | loose}.
func find_pickup_target(c: CharacterState) -> Dictionary:
	var best := {}
	var best_d := PickupResolver.PICKUP_REACH
	var centre := c.centre()
	for s in sockets.sockets:
		if not s.is_available or not WeaponSocketManager.is_weapon_item(s.current_item):
			continue
		var p := WeaponSocketManager.item_pos_of(s)
		var d := centre.distance_to(p)
		if d <= best_d and Data.weapons.has(s.current_item):
			var def: WeaponDef = Data.weapons[s.current_item]
			var ammo := WeaponSocketManager.fresh_ammo(def)
			best_d = d
			best = {"def": def, "clip": ammo.x, "reserve": ammo.y, "pos": p, "socket_id": s.def.id}
	for lw in loose_weapons:
		if not lw.active:
			continue
		var p := lw.centre()
		var d := centre.distance_to(p)
		if d <= best_d:
			best_d = d
			best = {"def": lw.def, "clip": lw.clip, "reserve": lw.reserve, "pos": p, "loose": lw}
	return best

func _resolve_pickup(c: CharacterState) -> void:
	var target := find_pickup_target(c)
	if target.is_empty():
		return
	var before := loose_weapons.size()
	var socket_id: StringName = target.get("socket_id", &"")
	var ok := PickupResolver.try_pickup_weapon(c, target["def"], target["clip"], target["reserve"], target["pos"], loose_weapons, socket_id)
	if not ok:
		return
	# A swap appended the previously held weapon; give it an id and let it fall.
	for i in range(before, loose_weapons.size()):
		_register_loose_weapon(loose_weapons[i])
	if socket_id != &"":
		sockets.take(socket_id, c.id)
	elif target.has("loose"):
		var taken: LooseWeapon = target["loose"]
		taken.active = false
		loose_weapons.erase(taken)
	_enforce_loose_cap()

## X drops the active weapon, refused when it is the only weapon held (§4.10.2).
func _drop_active_weapon(c: CharacterState) -> void:
	if c.inventory.slot_count() < 2:
		if c.is_human:
			EventBus.toast_requested.emit("Can't drop your only weapon", &"hint", 1.5)
		return
	var w := c.inventory.active_weapon()
	var dropped := c.inventory.drop_active()
	if dropped == null:
		return
	dropped.pos = c.centre()
	dropped.vel = Vector2(c.facing * 260.0, -240.0) + c.vel * 0.5
	dropped.facing = c.facing
	_add_loose_weapon(dropped)
	EventBus.weapon_dropped.emit(c.id, w.def.id, dropped.pos)

func _add_loose_weapon(lw: LooseWeapon) -> void:
	loose_weapons.append(lw)
	_register_loose_weapon(lw)
	_enforce_loose_cap()

func _register_loose_weapon(lw: LooseWeapon) -> void:
	if lw.id == 0:
		lw.id = _next_loose_id
		_next_loose_id += 1
	lw.prev_pos = lw.pos
	lw.active = true

## At most 12 loose weapons in the world, oldest removed first (§4.10.4).
func _enforce_loose_cap() -> void:
	while loose_weapons.size() > LOOSE_WEAPON_CAP:
		var oldest: LooseWeapon = loose_weapons.pop_front()
		oldest.active = false

func _step_loose_weapons(dt: float) -> void:
	for lw in loose_weapons:
		lw.step(dt, grid)
	for i in range(loose_weapons.size() - 1, -1, -1):
		if not loose_weapons[i].active:
			loose_weapons.remove_at(i)

## §5.5 hearing: every bot within the hearing radius of a shot or explosion by Skyra
## learns an approximate position (never while she is stealthed or dead).
func _step_hearing() -> void:
	var h := human_char
	var shots := h.stats.shots_fired if h.stats else 0
	var sources: Array = []
	if h.life_state == Enums.LifeState.ALIVE and h.stealth_t <= 0.0:
		if shots != _human_heard_shots:
			var w := h.inventory.active_weapon()
			sources.append([h.centre(), w.def.id if w else &"magnum"])
		for p in projectiles.human_explosions_this_tick:
			sources.append([p, &"explosion"])
	_human_heard_shots = shots
	projectiles.human_explosions_this_tick.clear()
	if sources.is_empty():
		return
	for b in bot_chars:
		var brain := b.brain as BotBrain
		if b.life_state != Enums.LifeState.ALIVE or brain == null:
			continue
		for src in sources:
			b.perception.hear(b.centre(), src[0], src[1], time, brain.rng)

## Breaks the CharacterState <-> BotBrain reference cycles so a finished match is freed.
func teardown() -> void:
	nav.clear_queue()
	for c in characters:
		c.brain = null
		c.perception = null
	bot_frames.clear()
	characters_by_id.clear()

## INV-4 bookkeeping: grenades thrown by bots that are still in flight.
func _count_live_bot_grenades() -> int:
	var n := 0
	for p in projectiles.active_projectiles:
		if p.kind == Projectile.Kind.GRENADE and p.owner_team == Enums.Team.BOT:
			n += 1
	return n

## Pushes the Director's token/role/self-defence decisions into each bot brain and
## keeps the nav engagement bubble centred on Skyra (§5.4.4–5.4.6).
func _sync_director_to_brains() -> void:
	for b in bot_chars:
		var brain: BotBrain = b.brain as BotBrain
		var info: Dictionary = director.bot_data.get(b.id, {})
		if brain == null or info.is_empty():
			continue
		brain.set_director_status(bool(info["has_token"]), int(info["role"]), director.self_defender_id == b.id)
	if human_char.life_state == Enums.LifeState.ALIVE:
		nav.bubble_center = human_char.pos
		nav.bubble_radius = director.bubble_radius
	else:
		nav.bubble_radius = 0.0

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
