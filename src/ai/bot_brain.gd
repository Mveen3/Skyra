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
# HOLD shuffles (§5.3: ±32 wu every 2–3 s)
var shuffle_t: float = 2.0
var shuffle_move_t: float = 0.0
var shuffle_dir: int = 1

# Cadence timers
var burst_shots_left: int = 0
var _burst_seen_shots: int = 0 # bot.stats.shots_fired when the burst was last counted
var pause_t: float = 0.0
var continuous_ticks_left: int = 0
var weapon_switch_cd: float = 0.0

# Grenade intent (§5.6), decided at think rate and emitted on the next frame
var pending_grenade: bool = false
var pending_grenade_angle: float = 0.0
var pending_grenade_speed: float = 1.0
var human_slow_t: float = 0.0 # how long the visible Skyra has moved < 100 wu/s (camping)

# Item seeking (§5.9)
var sockets_ref: WeaponSocketManager = null
var item_goal_active: bool = false
var item_goal_pos: Vector2 = Vector2.ZERO
var item_goal_id: StringName = &""

# Autopilot (§10.5): ignores Director tokens for item decisions
var ignores_tokens: bool = false

# Path requests deferred by the per-tick A* budget
var _tick: int = 0
var _pending_path: bool = false
var _pending_goal: Vector2 = Vector2.ZERO

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
	_pending_path = false
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
               loose_pickups: Array, now: float, sockets: WeaponSocketManager = null) -> InputFrame:
	var frame := InputFrame.new()
	sockets_ref = sockets
	_tick = tick

	if bot.life_state != Enums.LifeState.ALIVE:
		state = Enums.BotState.DEAD
		path_follower.clear()
		return frame

	# Staggered 10 Hz perception and think (§5.2: tick % 6 == bot.id % 6)
	if human and perception.sees_human and human.vel.length() < 100.0:
		human_slow_t += dt
	else:
		human_slow_t = 0.0

	var think_slot := (tick % 6 == bot.id % 6)
	if think_slot:
		perception.update(bot, human, tile_grid, now, rng)
		_think_fsm(human, tile_grid, nav_grid, tac, director, loose_pickups, now)
		_consider_items(human, nav_grid, tile_grid, loose_pickups)
		_consider_grenade(human, tile_grid, director, now)

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

	if _pending_path:
		_request_path_to(_pending_goal, nav_grid, tile_grid)
	elif path_follower.needs_repath or (repath_timer >= 1.0 and state == Enums.BotState.ENGAGE):
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

	# Reached the item we were going for: take it (§5.9 "press pickup_swap within 60 wu")
	if item_goal_active and bot.centre().distance_to(item_goal_pos) <= 60.0:
		frame.pickup_pressed = true
		item_goal_active = false
		goal_timer = 99.0

	if pending_grenade:
		pending_grenade = false
		frame.grenade_pressed = true
		frame.grenade_released = true
		frame.grenade_use_angle = true
		frame.grenade_angle = pending_grenade_angle
		frame.grenade_speed_mult = pending_grenade_speed

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

	# Heading for a weapon item: keep going unless Skyra shows up or a token arrives
	if item_goal_active and state in [Enums.BotState.PATROL, Enums.BotState.HOLD, Enums.BotState.FLANK] \
			and (not has_token or ignores_tokens) and not perception.sees_human:
		return
	item_goal_active = false

	# State-specific transition checks (§5.3 transition table)
	match state:
		Enums.BotState.PATROL:
			if perception.sees_human:
				state = Enums.BotState.TARGET_ACQUIRE
				path_follower.clear()
			elif has_token:
				# F1: a token holder that cannot see Skyra paths toward her position
				_hunt(human, nav_grid, tile_grid)
			elif role == Enums.DirectorRole.FLANKER:
				state = Enums.BotState.FLANK
				_pick_flank_point(human, tac, director, nav_grid, tile_grid)
			elif role == Enums.DirectorRole.HOLDER:
				state = Enums.BotState.HOLD
				_pick_hold_point(human, tac, director, nav_grid, tile_grid)
			elif perception.has_known_target(now) and (goal_kind != "investigate" or goal_pos.distance_to(perception.last_known_pos) > 300.0):
				# PATROL goal priority (1): investigate a last known position younger than 8 s
				_investigate(human, nav_grid, tile_grid)
			elif goal_timer >= 12.0 or not path_follower.has_path():
				_pick_new_patrol(tac, nav_grid, tile_grid)

		Enums.BotState.TARGET_ACQUIRE:
			if not perception.sees_human and (now - perception.last_seen_time) > 0.5:
				# A3: lost sight early -> investigate the last known position
				state = Enums.BotState.PATROL
				_investigate(human, nav_grid, tile_grid)
			elif perception.reaction_t <= 0.0:
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
				# E4: unseen for 2.5 s -> hunt the last known position
				state = Enums.BotState.PATROL
				_investigate(human, nav_grid, tile_grid)
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
				_on_token_granted(human, nav_grid, tile_grid)
			elif not path_follower.has_path() or bot.pos.distance_to(goal_pos) < 60.0:
				state = Enums.BotState.HOLD
			elif role == Enums.DirectorRole.PATROLLER:
				state = Enums.BotState.PATROL
				_pick_new_patrol(tac, nav_grid, tile_grid)

		Enums.BotState.HOLD:
			if has_token:
				_on_token_granted(human, nav_grid, tile_grid)
			elif goal_timer >= 8.0 or perception.sees_human:
				state = Enums.BotState.FLANK
				_pick_flank_point(human, tac, director, nav_grid, tile_grid)
			elif role == Enums.DirectorRole.PATROLLER:
				state = Enums.BotState.PATROL
				_pick_new_patrol(tac, nav_grid, tile_grid)

## F1: token granted while flanking/holding -> acquire if Skyra is visible, else hunt her.
func _on_token_granted(human: CharacterState, nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	if perception.sees_human:
		state = Enums.BotState.TARGET_ACQUIRE
		perception.reaction_t = 0.12 * (bot.profile.reaction_mult if bot.profile else 1.0)
		path_follower.clear()
	else:
		state = Enums.BotState.PATROL
		_hunt(human, nav_grid, tile_grid)

## Token holders path toward Skyra's true position (the Director is omniscient, §5.4);
## repathed every 1 s while she moves (§5.7.1 repath triggers).
func _hunt(human: CharacterState, nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	if goal_kind == "hunt" and repath_timer < 1.0 and path_follower.has_path():
		return
	goal_kind = "hunt"
	goal_pos = human.pos
	goal_timer = 0.0
	repath_timer = 0.0
	_request_path_to(goal_pos, nav_grid, tile_grid)

## PATROL goal priority (1): investigate the last known position if it is fresh.
func _investigate(human: CharacterState, nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	if perception.last_known_pos.x > -9000.0:
		goal_pos = perception.last_known_pos
	else:
		goal_pos = human.pos
	goal_kind = "investigate"
	goal_timer = 0.0
	_request_path_to(goal_pos, nav_grid, tile_grid)

## §5.9 weapon value: mode value x personality preference (0 without ammo).
func weapon_value(def: WeaponDef, has_ammo: bool = true) -> float:
	if def == null or not has_ammo:
		return 0.0
	var sniper := sockets_ref != null and sockets_ref.mode_id == "sniper_post"
	var base := def.bot_value_sniper if sniper else def.bot_value_mini
	var pref := float(bot.profile.weapon_pref.get(str(def.id), 1.0)) if bot.profile else 1.0
	return base * pref

func _best_held_value() -> float:
	var best := 0.0
	for w in bot.inventory.slots:
		if w:
			var has_ammo := w.clip > 0.0 or w.reserve > 0.0 or w.has_infinite_reserve()
			best = maxf(best, weapon_value(w.def, has_ammo))
	return best

## §5.9 pickup decisions (PATROL / HOLD / FLANK): socket or loose weapons within 1200 wu
## worth >= 10 more than the best held weapon, skipping items Skyra is closer to.
func _consider_items(human: CharacterState, nav_grid: NavGrid, tile_grid: TileGrid, loose_pickups: Array) -> void:
	if bot.life_state != Enums.LifeState.ALIVE or (has_token and not ignores_tokens):
		item_goal_active = false
		return
	if not (state in [Enums.BotState.PATROL, Enums.BotState.HOLD, Enums.BotState.FLANK]):
		item_goal_active = false
		return
	if item_goal_active:
		if not _item_still_there(loose_pickups):
			item_goal_active = false
			goal_timer = 99.0
		return
	var held := _best_held_value()
	var me := bot.centre()
	# The autopilot's "human" is the bot it hunts, so the fairness rule does not apply.
	var human_alive := human != null and human.life_state == Enums.LifeState.ALIVE and not ignores_tokens
	var best_gain := 9.999
	var best_pos := Vector2.ZERO
	var best_id := &""
	var candidates: Array = []
	if sockets_ref:
		for s in sockets_ref.sockets:
			if s.is_available and WeaponSocketManager.is_weapon_item(s.current_item) and Data.weapons.has(s.current_item):
				candidates.append([Data.weapons[s.current_item], WeaponSocketManager.item_pos_of(s)])
	for lw in loose_pickups:
		var l := lw as LooseWeapon
		if l and l.active and l.def:
			candidates.append([l.def, l.centre()])
	for cand in candidates:
		var def: WeaponDef = cand[0]
		var pos: Vector2 = cand[1]
		var d := me.distance_to(pos)
		if d > 1200.0:
			continue
		if human_alive and human.centre().distance_to(pos) < d:
			continue # bots don't snatch items from under the player
		var gain := weapon_value(def) - held
		if bot.inventory.find(def.id) != -1:
			gain = 0.0 # already held: merging ammo is not worth a detour
		if gain > best_gain:
			best_gain = gain
			best_pos = pos
			best_id = def.id
	if best_id != &"":
		item_goal_active = true
		item_goal_pos = best_pos
		item_goal_id = best_id
		goal_pos = best_pos
		goal_kind = "item"
		goal_timer = 0.0
		_request_path_to(goal_pos, nav_grid, tile_grid)

func _item_still_there(loose_pickups: Array) -> bool:
	if sockets_ref:
		for s in sockets_ref.sockets:
			if s.is_available and s.current_item == str(item_goal_id) and WeaponSocketManager.item_pos_of(s).distance_to(item_goal_pos) < 1.0:
				return true
	for lw in loose_pickups:
		var l := lw as LooseWeapon
		if l and l.active and l.def.id == item_goal_id and l.centre().distance_to(item_goal_pos) < 80.0:
			item_goal_pos = l.centre()
			return true
	return false

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
	# Feet sit exactly on the floor tile's top edge, so sample just above them.
	var start_cell := nav_grid.nearest_node_cell(bot.pos + Vector2(0.0, -2.0))
	var end_cell := nav_grid.nearest_node_cell(target_pos + Vector2(0.0, -2.0))
	if start_cell.x < 0 or end_cell.x < 0:
		path_follower.clear()
		return

	if nav_grid.async_enabled:
		# Time-sliced A* (MatchSim): the path arrives within a few ticks
		_pending_path = false
		nav_grid.request_path(bot.id, start_cell, end_cell, not has_token, _on_path_ready.bind(nav_grid, tile_grid))
		return
	if not nav_grid.try_reserve_search(_tick):
		_pending_path = true
		_pending_goal = target_pos
		return
	_pending_path = false
	var raw_path := nav_grid.find_path(start_cell, end_cell, not has_token, tile_grid)
	var smoothed := nav_grid.smooth_path(raw_path, tile_grid)
	path_follower.set_path(smoothed)

func _on_path_ready(raw_path: Array[Vector2i], nav_grid: NavGrid, tile_grid: TileGrid) -> void:
	if bot.life_state != Enums.LifeState.ALIVE:
		return
	path_follower.set_path(nav_grid.smooth_path(raw_path, tile_grid))

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

		Enums.BotState.HOLD:
			# Small shuffles on the staging point once it is reached (~32 wu at run speed)
			if not path_follower.has_path() and bot.grounded:
				shuffle_t -= dt
				if shuffle_t <= 0.0:
					shuffle_t = rng.randf_range(2.0, 3.0)
					shuffle_move_t = 0.12
					shuffle_dir = -shuffle_dir if rng.randf() < 0.7 else shuffle_dir
				if shuffle_move_t > 0.0:
					shuffle_move_t -= dt
					frame.move_x = shuffle_dir

		Enums.BotState.RETREAT_RELOAD:
			frame.reload_pressed = true

## Pause multiplier: self-defenders (§5.4.6) and SEEK_COVER (§5.3) fire at half cadence.
func _cadence_mult() -> float:
	if ignores_tokens:
		return 1.0 # autopilot (§10.5) is not paced by the Director
	return 2.0 if (is_self_defender and not has_token) or state == Enums.BotState.SEEK_COVER else 1.0

func _apply_firing(frame: InputFrame, dt: float, human: CharacterState,
                   tile_grid: TileGrid, director: PacingDirector) -> void:
	# AUTO bursts count rounds actually fired (the weapon steps before the AI each tick)
	var shots_now := bot.stats.shots_fired if bot.stats else 0
	if burst_shots_left > 0 and shots_now > _burst_seen_shots:
		burst_shots_left -= shots_now - _burst_seen_shots
		if burst_shots_left <= 0:
			var w := bot.inventory.active_weapon() if bot.inventory else null
			if w:
				pause_t = rng.randf_range(w.def.bot_pause_min, w.def.bot_pause_max) * _cadence_mult()
	_burst_seen_shots = shots_now

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

	# §5.6 fire gate: the aim has caught up with its goal (true direction + aim error)
	var angle_diff := rad_to_deg(absf(angle_difference(bot.aim_angle, aim_model.aim_goal)))
	if angle_diff > def.bot_fire_gate_deg:
		return

	# Cadence & Pause timers
	pause_t = maxf(0.0, pause_t - dt)
	if pause_t > 0.0:
		return

	var cadence_mult := _cadence_mult()

	match def.fire_mode:
		Enums.FireMode.AUTO:
			# Burst of N rounds (counted at the top of this function), then a pause
			if burst_shots_left <= 0:
				burst_shots_left = rng.randi_range(def.bot_burst_min, def.bot_burst_max)
			frame.fire_held = true

		Enums.FireMode.SEMI, Enums.FireMode.PUMP, Enums.FireMode.BOLT:
			frame.fire_pressed = true
			# §5.6: Black Arrow bots aim at the head with p = 0.35, re-rolled per shot
			aim_model.aim_head = def.id == &"m93ba" and rng.randf() < 0.35
			pause_t = maxf(def.fire_interval_s, rng.randf_range(def.bot_pause_min, def.bot_pause_max)) * cadence_mult

		Enums.FireMode.CONTINUOUS:
			if continuous_ticks_left <= 0:
				continuous_ticks_left = rng.randi_range(def.bot_burst_min, def.bot_burst_max)
			frame.fire_held = true
			continuous_ticks_left -= 1
			if continuous_ticks_left <= 0:
				pause_t = rng.randf_range(def.bot_pause_min, def.bot_pause_max) * cadence_mult

## §5.6 bot grenade throw, considered once per think tick by token holders only (§5.4.6):
## 350–900 wu away and Skyra is camping (visible, < 100 wu/s for ≥ 1.5 s) or LOS was
## lost < 2 s ago. INV-4: at most one live bot grenade in the world.
func _consider_grenade(human: CharacterState, tile_grid: TileGrid, director: PacingDirector, now: float) -> void:
	pending_grenade = false
	if not has_token or director.live_bot_grenades >= 1 or bot.inventory.grenades <= 0:
		return
	if not human or human.life_state != Enums.LifeState.ALIVE or human.stealth_t > 0.0:
		return
	var binfo: Dictionary = director.bot_data.get(bot.id, {})
	if float(binfo.get("grenade_cooldown", 0.0)) > 0.0:
		return
	var d := bot.pos.distance_to(human.pos)
	if d < 350.0 or d > 900.0:
		return
	var camping := perception.sees_human and human_slow_t >= 1.5
	var lost_recently := not perception.sees_human and (now - perception.last_seen_time) < 2.0
	if not camping and not lost_recently:
		return
	var p_grenade := 0.3 * (bot.profile.grenade_affinity if bot.profile else 0.5)
	if rng.randf() >= p_grenade:
		return
	var target := human.pos if perception.sees_human else perception.last_known_pos
	var solved := AimModel.solve_grenade_angle(bot.shoulder(), target, tile_grid)
	if not bool(solved["success"]):
		return
	pending_grenade = true
	pending_grenade_angle = float(solved["angle"]) + deg_to_rad(rng.randf_range(-4.0, 4.0))
	pending_grenade_speed = rng.randf_range(0.92, 1.08)
	binfo["grenade_cooldown"] = 10.0
	director.live_bot_grenades += 1

func _check_weapon_handling(frame: InputFrame, dt: float, human: CharacterState, loose_pickups: Array) -> void:
	if not bot.inventory:
		return

	# Reload (§5.9): PATROL/HOLD/FLANK whenever the clip is not full; ENGAGE when the clip
	# is below 25 % and Skyra has been out of sight for 1.0 s
	var aw := bot.inventory.active_weapon()
	if aw and aw.def.clip_size > 0 and aw.clip < aw.def.clip_size and (aw.reserve > 0.0 or aw.has_infinite_reserve()):
		var calm := state in [Enums.BotState.PATROL, Enums.BotState.HOLD, Enums.BotState.FLANK]
		var engage_low := state == Enums.BotState.ENGAGE and aw.clip < aw.def.clip_size * 0.25 \
			and not perception.sees_human and aim_model.lost_los_t >= 1.0
		if calm or engage_low:
			frame.reload_pressed = true

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

	# Opportunistic pickup of a loose weapon within 60 wu, only when it is worth >= 10
	# more than the best held weapon (§5.9) — otherwise a bot would keep re-taking the
	# weapon it just swapped out.
	var held := _best_held_value()
	for p_obj in loose_pickups:
		var p: LooseWeapon = p_obj as LooseWeapon
		if p and p.active and p.def:
			if bot.pos.distance_to(p.pos) <= 60.0:
				# Rule §5.9 / T-AI-06: Never grab if Skyra is closer
				var d_bot := bot.pos.distance_to(p.pos)
				var d_human := human.pos.distance_to(p.pos) if (human and human.life_state == Enums.LifeState.ALIVE) else 9999.0
				var has_ammo := p.clip > 0.0 or p.reserve != 0.0
				if d_bot < d_human and bot.inventory.find(p.def.id) == -1 and weapon_value(p.def, has_ammo) - held >= 10.0:
					frame.pickup_pressed = true
					break
