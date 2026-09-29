# Implements §5.2 and §5.3 BotBrain FSM, input synthesis, aiming, and firing cadence.
class_name BotBrain
extends RefCounted

var bot: CharacterState
var perception: Perception
var aim_model: AimModel
var path_follower: PathFollower

var state: int = Enums.BotState.PATROL
var role: int = Enums.DirectorRole.PATROLLER
var has_token: bool = false
var is_self_defender: bool = false

var goal_pos: Vector2 = Vector2.ZERO
var goal_kind: String = "patrol" # "patrol", "investigate", "cover", "flank", "hold", "retreat", "pickup"
var goal_timer: float = 0.0
var repath_timer: float = 0.0

# Strafe & Jet hop timers (ENGAGE)
var strafe_dir: float = 1.0
var strafe_t: float = 0.0
var jet_hop_t: float = 0.0

# Cadence timers
var burst_shots_left: int = 0
var pause_t: float = 0.0
var continuous_ticks_left: int = 0
var weapon_switch_cd: float = 0.0

var rng: RandomNumberGenerator

func _init(c: CharacterState, random_seed: int = 0) -> void:
	bot = c
	perception = Perception.new(c.id)
	aim_model = AimModel.new()
	path_follower = PathFollower.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 12345 + c.id * 101 + random_seed
	c.perception = perception
	c.brain = self

func set_director_status(token: bool, new_role: int, self_def: bool) -> void:
	has_token = token
	role = new_role
	is_self_defender = self_def

func on_respawn() -> void:
	state = Enums.BotState.PATROL
	goal_pos = Vector2.ZERO
	path_follower.clear()
	aim_model.reset()
	perception.clear_memory()
	goal_timer = 999.0
	strafe_t = 0.0
	jet_hop_t = 0.0
	burst_shots_left = 0
	pause_t = 0.0
	continuous_ticks_left = 0

func step_tick(tick: int, dt: float, human: CharacterState, tile_grid: TileGrid,
               nav_grid: NavGrid, tac: TacticalQueries, director: PacingDirector,
               loose_pickups: Array, now: float) -> InputFrame:
	var frame := InputFrame.new()

	if bot.life_state != Enums.LifeState.ALIVE:
		state = Enums.BotState.DEAD
		path_follower.clear()
		return frame

	# Staggered 10 Hz perception and think (§5.2: tick % 6 == bot.id % 6)
	var think_slot := (tick % 6 == bot.id % 6)
	if think_slot:
		perception.update(bot, human, tile_grid, now, rng)
		_think_fsm(human, tile_grid, nav_grid, tac, director, loose_pickups, now)

	# Reaction time countdown
	if perception.reaction_t > 0.0:
		perception.reaction_t = maxf(0.0, perception.reaction_t - dt)

	# AimModel step (60 Hz)
	var aim_ang := aim_model.update(bot, human, dt, perception.sees_human, is_self_defender, rng)
	bot.aim_angle = aim_ang
	bot.aim_dir = Vector2(cos(aim_ang), sin(aim_ang)).normalized()
	frame.aim_world = bot.shoulder() + bot.aim_dir * 500.0

	# 60 Hz Path follower step
	goal_timer += dt
	repath_timer += dt
	weapon_switch_cd = maxf(0.0, weapon_switch_cd - dt)

	if path_follower.needs_repath or (repath_timer >= 1.0 and state == Enums.BotState.ENGAGE):
		_request_path_to(goal_pos, nav_grid, tile_grid)
		repath_timer = 0.0

	var move_frame := path_follower.step(bot, dt, nav_grid)
	frame.move_x = move_frame.move_x
	frame.jet_pressed = move_frame.jet_pressed
	frame.jet_held = move_frame.jet_held
	frame.crouch = move_frame.crouch

	# State-specific movement / fire overrides (§5.3 per-state table)
	_apply_state_movement(frame, dt, human)
	_apply_firing(frame, dt, human, tile_grid, director)
	_check_weapon_handling(frame, dt, human, loose_pickups)

	return frame

func _think_fsm(human: CharacterState, tile_grid: TileGrid, nav_grid: NavGrid,
                tac: TacticalQueries, director: PacingDirector, loose_pickups: Array, now: float) -> void:
	# Rule G1: health <= 0 -> DEAD
	if bot.health <= 0.0:
		state = Enums.BotState.DEAD
		path_follower.clear()
		return

	# Rule G2: human DEAD or stealth_t > 0 -> PATROL
	if not human or human.life_state != Enums.LifeState.ALIVE or human.stealth_t > 0.0:
		if state != Enums.BotState.PATROL:
			state = Enums.BotState.PATROL
			_pick_new_patrol(tac, nav_grid, tile_grid)
		return

	# Rule D1: from DEAD to PATROL on respawn
	if state == Enums.BotState.DEAD:
		state = Enums.BotState.PATROL
		_pick_new_patrol(tac, nav_grid, tile_grid)
		return

	# State-specific transition checks (§5.3 transition table)
	match state:
		Enums.BotState.PATROL:
			if perception.sees_human:
				state = Enums.BotState.TARGET_ACQUIRE
				path_follower.clear()
			elif role == Enums.DirectorRole.FLANKER:
				state = Enums.BotState.FLANK
				_pick_flank_point(human, tac, director, nav_grid, tile_grid)
			elif role == Enums.DirectorRole.HOLDER:
				state = Enums.BotState.HOLD
				_pick_hold_point(human, tac, director, nav_grid, tile_grid)
			elif goal_timer >= 12.0 or not path_follower.has_path():
				_pick_new_patrol(tac, nav_grid, tile_grid)

		Enums.BotState.TARGET_ACQUIRE:
			if perception.reaction_t <= 0.0:
				if has_token and perception.sees_human:
					state = Enums.BotState.ENGAGE
					aim_model.t_track = 0.0
					_update_engage_goal(human)
					_request_path_to(goal_pos, nav_grid, tile_grid)
				elif not has_token:
					state = Enums.BotState.FLANK if (role == Enums.DirectorRole.FLANKER) else Enums.BotState.HOLD
					if state == Enums.BotState.FLANK:
						_pick_flank_point(human, tac, director, nav_grid, tile_grid)
					else:
						_pick_hold_point(human, tac, director, nav_grid, tile_grid)
			elif not perception.sees_human and (now - perception.last_seen_time) > 0.5:
				state = Enums.BotState.PATROL
				goal_pos = perception.last_known_pos
				_request_path_to(goal_pos, nav_grid, tile_grid)

		Enums.BotState.ENGAGE:
			if not has_token:
				state = Enums.BotState.HOLD
				_pick_hold_point(human, tac, director, nav_grid, tile_grid)
			elif bot.health < 35.0:
				var cover_pt := tac.find_cover(bot, human, tile_grid, nav_grid)
				if cover_pt.distance_to(bot.pos) > 10.0:
					state = Enums.BotState.SEEK_COVER
					goal_pos = cover_pt
					_request_path_to(goal_pos, nav_grid, tile_grid)
			elif bot.inventory and bot.inventory.active_weapon() and bot.inventory.active_weapon().clip == 0 and bot.inventory.active_weapon().reserve > 0 and bot.pos.distance_to(human.pos) < 600.0:
				state = Enums.BotState.RETREAT_RELOAD
				goal_pos = tac.retreat_point(bot, human, nav_grid, tile_grid)
				_request_path_to(goal_pos, nav_grid, tile_grid)
			elif (now - perception.last_seen_time) > 2.5:
				state = Enums.BotState.PATROL
				goal_pos = perception.last_known_pos
				_request_path_to(goal_pos, nav_grid, tile_grid)
			else:
				_update_engage_goal(human)

		Enums.BotState.SEEK_COVER:
			if not perception.sees_human and bot.health >= 70.0:
				state = Enums.BotState.ENGAGE if has_token else Enums.BotState.HOLD
				if state == Enums.BotState.HOLD:
					_pick_hold_point(human, tac, director, nav_grid, tile_grid)
			elif goal_timer >= 6.0 or not path_follower.has_path():
				state = Enums.BotState.ENGAGE if has_token else Enums.BotState.HOLD

		Enums.BotState.RETREAT_RELOAD:
			var active_w := bot.inventory.active_weapon() if bot.inventory else null
			var reloaded := (active_w != null and active_w.clip > 0)
			if reloaded or goal_timer >= 4.0:
				state = Enums.BotState.ENGAGE if (has_token and perception.has_known_target(now)) else Enums.BotState.PATROL

		Enums.BotState.FLANK:
			if has_token:
				state = Enums.BotState.TARGET_ACQUIRE
				perception.reaction_t = 0.12 * (bot.profile.reaction_mult if bot.profile else 1.0)
			elif not path_follower.has_path() or bot.pos.distance_to(goal_pos) < 60.0:
				state = Enums.BotState.HOLD
			elif role == Enums.DirectorRole.PATROLLER:
				state = Enums.BotState.PATROL
				_pick_new_patrol(tac, nav_grid, tile_grid)

		Enums.BotState.HOLD:
			if has_token:
				state = Enums.BotState.TARGET_ACQUIRE
				perception.reaction_t = 0.12 * (bot.profile.reaction_mult if bot.profile else 1.0)
			elif goal_timer >= 8.0 or perception.sees_human:
				state = Enums.BotState.FLANK
				_pick_flank_point(human, tac, director, nav_grid, tile_grid)
			elif role == Enums.DirectorRole.PATROLLER:
				state = Enums.BotState.PATROL
				_pick_new_patrol(tac, nav_grid, tile_grid)

func _update_engage_goal(human: CharacterState) -> void:
	var active_w := bot.inventory.active_weapon() if bot.inventory else null
	var r_mult := bot.profile.range_mult if bot.profile else 1.0
	var min_r := (active_w.def.bot_range_min * r_mult) if active_w else 200.0
	var max_r := (active_w.def.bot_range_max * r_mult) if active_w else 600.0

	var d := bot.pos.distance_to(human.pos)
	if d > max_r:
		# Approach
		goal_pos = human.pos
	elif d < min_r:
		# Back off
		var away := (bot.pos - human.pos).normalized()
		goal_pos = bot.pos + away * 200.0
	else:
		# Inside band
		goal_pos = bot.pos

func _pick_new_patrol(tac: TacticalQueries, nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	goal_pos = tac.patrol_point(bot, rng)
	goal_kind = "patrol"
	goal_timer = 0.0
	_request_path_to(goal_pos, nav_grid, tile_grid)

func _pick_hold_point(human: CharacterState, tac: TacticalQueries, director: PacingDirector,
                      nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	goal_pos = tac.find_hold_point(bot, human, director.staging_ring_min, director.staging_ring_max, [], nav_grid, tile_grid, rng)
	goal_kind = "hold"
	goal_timer = 0.0
	_request_path_to(goal_pos, nav_grid, tile_grid)

func _pick_flank_point(human: CharacterState, tac: TacticalQueries, director: PacingDirector,
                       nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	goal_pos = tac.find_flank_point(bot, human, director.staging_ring_min, director.staging_ring_max, [], nav_grid, tile_grid, rng)
	goal_kind = "flank"
	goal_timer = 0.0
	_request_path_to(goal_pos, nav_grid, tile_grid)

func _request_path_to(target_pos: Vector2, nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	var start_cell := tile_grid.cell_of(bot.pos)
	var end_cell := tile_grid.cell_of(target_pos)

	# Find closest nodes if outside
	if not nav_grid.nodes.has(start_cell):
		var best_d := 9999.0
		for c in nav_grid.nodes:
			var d: float = Vector2(start_cell).distance_to(Vector2(c))
			if d < best_d:
				best_d = d
				start_cell = c

	if not nav_grid.nodes.has(end_cell):
		var best_d := 9999.0
		for c in nav_grid.nodes:
			var d: float = Vector2(end_cell).distance_to(Vector2(c))
			if d < best_d:
				best_d = d
				end_cell = c

	var raw_path := nav_grid.find_path(start_cell, end_cell, not has_token, tile_grid)
	var smoothed := nav_grid.smooth_path(raw_path, tile_grid)
	path_follower.set_path(smoothed)

func _apply_state_movement(frame: InputFrame, dt: float, human: CharacterState) -> void:
	match state:
		Enums.BotState.TARGET_ACQUIRE:
			# §5.3: grounded: stop; airborne: hover
			if bot.grounded:
				frame.move_x = 0
				frame.jet_held = false
			else:
				frame.jet_held = (bot.vel.y > 10.0)

		Enums.BotState.ENGAGE:
			# Strafe & jet hops inside combat band
			var active_w := bot.inventory.active_weapon() if bot.inventory else null
			var d := bot.pos.distance_to(human.pos) if human else 500.0
			var r_mult := bot.profile.range_mult if bot.profile else 1.0
			var min_r := (active_w.def.bot_range_min * r_mult) if active_w else 200.0
			var max_r := (active_w.def.bot_range_max * r_mult) if active_w else 600.0

			if d >= min_r and d <= max_r:
				strafe_t -= dt
				if strafe_t <= 0.0:
					strafe_dir = 1.0 if rng.randf() > 0.5 else -1.0
					strafe_t = rng.randf_range(0.6, 1.4)
				frame.move_x = int(strafe_dir)

				# Jet hops
				var hops_per_min := bot.profile.jet_hop_per_min if bot.profile else 15.0
				var p_hop := (hops_per_min / 60.0) * dt
				if rng.randf() < p_hop and bot.fuel > 40.0 and jet_hop_t <= 0.0:
					jet_hop_t = rng.randf_range(0.2, 0.5)

				if jet_hop_t > 0.0:
					jet_hop_t -= dt
					frame.jet_held = true

		Enums.BotState.RETREAT_RELOAD:
			frame.reload_pressed = true

func _apply_firing(frame: InputFrame, dt: float, human: CharacterState,
                   tile_grid: TileGrid, director: PacingDirector) -> void:
	# Rule INV-3: While Skyra's stealth is active: 0 bot shots
	if not human or human.life_state != Enums.LifeState.ALIVE or human.stealth_t > 0.0:
		return

	# Rule INV-2 / §5.4.6: Fire permission
	var may_fire := has_token or is_self_defender
	if not may_fire:
		return

	# Can only fire in ENGAGE or SEEK_COVER or self-defence
	if state != Enums.BotState.ENGAGE and state != Enums.BotState.SEEK_COVER and not is_self_defender:
		return

	if not perception.sees_human or perception.reaction_t > 0.0:
		return

	var active_w := bot.inventory.active_weapon() if bot.inventory else null
	if not active_w or active_w.clip <= 0:
		return

	var def := active_w.def
	var d := bot.pos.distance_to(human.pos)

	# Fire gate check (§5.6)
	var max_range_allowed := def.bot_range_max * (bot.profile.range_mult if bot.profile else 1.0) * 1.25
	if d > max_range_allowed:
		return

	# Bazooka safety check (§5.6)
	if def.id == "rocket_launcher" and d < 280.0:
		return

	var angle_diff := rad_to_deg(absf(angle_difference(bot.aim_angle, (human.centre() - bot.shoulder()).angle())))
	if angle_diff > def.bot_fire_gate_deg:
		return

	# Cadence & Pause timers
	pause_t = maxf(0.0, pause_t - dt)
	if pause_t > 0.0:
		return

	var cadence_mult := 2.0 if is_self_defender else 1.0

	match def.fire_mode:
		Enums.FireMode.AUTO:
			if burst_shots_left <= 0:
				burst_shots_left = rng.randi_range(def.bot_burst_min, def.bot_burst_max)
			frame.fire_held = true
			burst_shots_left -= 1
			if burst_shots_left <= 0:
				pause_t = rng.randf_range(def.bot_pause_min, def.bot_pause_max) * cadence_mult

		Enums.FireMode.SEMI, Enums.FireMode.PUMP, Enums.FireMode.BOLT:
			frame.fire_pressed = true
			pause_t = maxf(def.fire_interval_s, rng.randf_range(def.bot_pause_min, def.bot_pause_max)) * cadence_mult

		Enums.FireMode.CONTINUOUS:
			if continuous_ticks_left <= 0:
				continuous_ticks_left = rng.randi_range(def.bot_burst_min, def.bot_burst_max)
			frame.fire_held = true
			continuous_ticks_left -= 1
			if continuous_ticks_left <= 0:
				pause_t = rng.randf_range(def.bot_pause_min, def.bot_pause_max) * cadence_mult

	# Grenade check (§5.6 / §5.4.6 / INV-4)
	if has_token and director.live_bot_grenades < 1 and bot.inventory.frag_count > 0:
		var binfo: Dictionary = director.bot_data.get(bot.id, {})
		var g_cooldown: float = float(binfo.get("grenade_cooldown", 0.0))
		if g_cooldown <= 0.0 and d >= 350.0 and d <= 900.0:
			var p_grenade := 0.3 * (bot.profile.grenade_affinity if bot.profile else 0.5)
			if rng.randf() < p_grenade:
				var solved := AimModel.solve_grenade_angle(bot.shoulder(), human.pos, tile_grid)
				if bool(solved["success"]):
					frame.grenade_pressed = true
					frame.grenade_angle = float(solved["angle"])
					binfo["grenade_cooldown"] = 10.0
					director.live_bot_grenades += 1

func _check_weapon_handling(frame: InputFrame, dt: float, human: CharacterState, loose_pickups: Array) -> void:
	if not bot.inventory:
		return

	# Weapon switch preference (§5.9)
	if weapon_switch_cd <= 0.0 and human and bot.inventory.slot_count() > 1:
		var d: float = bot.pos.distance_to(human.pos)
		var w0: WeaponInstance = bot.inventory.get_weapon(0)
		var w1: WeaponInstance = bot.inventory.get_weapon(1)
		if w0 and w1:
			var fit0: bool = (d >= w0.def.bot_range_min and d <= w0.def.bot_range_max)
			var fit1: bool = (d >= w1.def.bot_range_min and d <= w1.def.bot_range_max)
			if bot.inventory.active_slot == 0 and not fit0 and fit1:
				frame.switch_pressed = true
				weapon_switch_cd = 3.0
			elif bot.inventory.active_slot == 1 and not fit1 and fit0:
				frame.switch_pressed = true
				weapon_switch_cd = 3.0

	# Pickup handling within 60 wu
	for p_obj in loose_pickups:
		var p: LooseWeapon = p_obj as LooseWeapon
		if p and p.active:
			if bot.pos.distance_to(p.pos) <= 60.0:
				# Rule §5.9 / T-AI-06: Never grab if Skyra is closer
				var d_bot := bot.pos.distance_to(p.pos)
				var d_human := human.pos.distance_to(p.pos) if (human and human.life_state == Enums.LifeState.ALIVE) else 9999.0
				if d_bot < d_human:
					frame.pickup_pressed = true
					break
