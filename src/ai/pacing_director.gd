# Implements §5.4 Pacing Director: phases, intensity, token lifecycle, and role assignment.
class_name PacingDirector
extends RefCounted

var phase: int = Enums.PacingPhase.WARMUP
var intensity: float = 0.0
var mode_id: String = "mini_post"

var phase_timer: float = 0.0
var time_since_skyra_damaged: float = 0.0
var breather_timer: float = 0.0
var post_grace_ramp_timer: float = 0.0
var live_bot_grenades: int = 0
var self_defender_id: int = -1

# Bot tracking data: bot_id -> Dictionary
# keys: "has_token": bool, "token_t": float, "cooldown_t": float, "time_since_had": float, "score": float, "role": int, "grenade_cooldown": float
var bot_data: Dictionary = {}

var staging_ring_min: float = 1100.0
var staging_ring_max: float = 1700.0
var bubble_radius: float = 900.0

var accum: float = 0.0
var grace_clear_t: float = 0.0 # time Skyra has been alive and un-stealthed during RESPAWN_GRACE

func _init(mode: String = "mini_post") -> void:
	mode_id = mode
	bubble_radius = 1400.0 if mode == "sniper_post" else 900.0
	_update_staging_ring()

func reset() -> void:
	phase = Enums.PacingPhase.WARMUP
	intensity = 0.0
	phase_timer = 0.0
	time_since_skyra_damaged = 0.0
	breather_timer = 0.0
	post_grace_ramp_timer = 0.0
	live_bot_grenades = 0
	self_defender_id = -1
	bot_data.clear()
	_update_staging_ring()

func init_bots(bot_ids: Array) -> void:
	bot_data.clear()
	for bid in bot_ids:
		bot_data[int(bid)] = {
			"has_token": false,
			"token_t": 0.0,
			"cooldown_t": 0.0,
			"time_since_had": 99.0,
			"score": 0.0,
			"role": Enums.DirectorRole.PATROLLER,
			"grenade_cooldown": 0.0
		}

func register_bot_damage_to_human(amount: float) -> void:
	intensity = clampf(intensity + 0.008 * amount, 0.0, 1.0)
	time_since_skyra_damaged = 0.0

func register_near_miss() -> void:
	intensity = clampf(intensity + 0.05, 0.0, 1.0)

func register_bot_killed(is_human_killer: bool, victim_id: int) -> void:
	if is_human_killer:
		intensity = clampf(intensity + 0.10, 0.0, 1.0)
	
	if bot_data.has(victim_id) and bool(bot_data[victim_id]["has_token"]):
		bot_data[victim_id]["has_token"] = false
		breather_timer = 1.5 # §5.4.4 breather moment

func register_human_death() -> void:
	intensity = 0.0
	phase = Enums.PacingPhase.RESPAWN_GRACE
	phase_timer = 0.0
	grace_clear_t = 0.0
	_update_staging_ring()
	for bid in bot_data:
		bot_data[bid]["has_token"] = false
		bot_data[bid]["token_t"] = 0.0
		bot_data[bid]["role"] = Enums.DirectorRole.PATROLLER
	EventBus.director_phase_changed.emit(phase, intensity)

func allowed_tokens() -> int:
	match phase:
		Enums.PacingPhase.WARMUP:
			return 1
		Enums.PacingPhase.BUILD_UP:
			return 1 if (post_grace_ramp_timer > 0.0) else 2
		Enums.PacingPhase.PEAK:
			return 2
		Enums.PacingPhase.RELAX:
			return 1
		Enums.PacingPhase.RESPAWN_GRACE:
			return 0
		_:
			return 1

func _update_staging_ring() -> void:
	var is_sniper := (mode_id == "sniper_post")
	match phase:
		Enums.PacingPhase.WARMUP, Enums.PacingPhase.PEAK:
			staging_ring_min = 1800.0 if is_sniper else 1100.0
			staging_ring_max = 3000.0 if is_sniper else 1700.0
		Enums.PacingPhase.BUILD_UP:
			staging_ring_min = 1600.0 if is_sniper else 1000.0
			staging_ring_max = 2600.0 if is_sniper else 1500.0
		Enums.PacingPhase.RELAX:
			staging_ring_min = 2400.0 if is_sniper else 1500.0
			staging_ring_max = 3400.0 if is_sniper else 2200.0
		Enums.PacingPhase.RESPAWN_GRACE:
			staging_ring_min = 0.0
			staging_ring_max = 0.0

func range_fit(w: WeaponInstance, d: float) -> float:
	if not w: return 0.5
	var def := w.def
	if d >= def.bot_range_min and d <= def.bot_range_max:
		return 1.0
	var band := def.bot_range_max - def.bot_range_min
	if d >= (def.bot_range_min - band * 0.3) and d <= (def.bot_range_max + band * 0.3):
		return 0.5
	return 0.0

func calc_token_score(bot: CharacterState, human: CharacterState, now: float) -> float:
	var d := bot.centre().distance_to(human.centre())
	var d_score := 1.2 * (1.0 - clampf(d / 3000.0, 0.0, 1.0))

	# Sees human?
	var sees := 0.6 if (bot.perception and bot.perception.sees_human) else 0.0

	# Range fit
	var active_w := bot.inventory.active_weapon() if bot.inventory else null
	var r_score := 0.4 * range_fit(active_w, d)

	# Health
	var hp_score := 0.3 * (bot.health / 100.0)

	# Time since last had token
	var binfo: Dictionary = bot_data.get(bot.id, {})
	var time_since: float = float(binfo.get("time_since_had", 99.0))
	var time_score := 0.4 * minf(1.0, time_since / 20.0)

	# Aggression
	var agg := bot.profile.aggression if bot.profile else 0.5
	var agg_score := 0.3 * agg

	# Damaged by Skyra in last 2.0 s
	var dmg_bonus := 0.0
	if (now - bot.last_enemy_damage_time) <= 2.0:
		dmg_bonus = 1.5

	return d_score + sees + r_score + hp_score + time_score + agg_score + dmg_bonus

func step(dt: float, bots: Array, human: CharacterState, now: float) -> void:
	# Tick per-frame timers
	phase_timer += dt
	breather_timer = maxf(0.0, breather_timer - dt)
	post_grace_ramp_timer = maxf(0.0, post_grace_ramp_timer - dt)
	time_since_skyra_damaged += dt

	for bid in bot_data:
		var info: Dictionary = bot_data[bid]
		if bool(info["has_token"]):
			info["token_t"] = float(info["token_t"]) + dt
		else:
			info["time_since_had"] = float(info["time_since_had"]) + dt
		info["cooldown_t"] = maxf(0.0, float(info["cooldown_t"]) - dt)
		info["grenade_cooldown"] = maxf(0.0, float(info["grenade_cooldown"]) - dt)

	# Logic runs at 4 Hz (§5.4.7)
	accum += dt
	if accum < 0.25:
		return
	var step_dt := accum
	accum = 0.0

	# Update intensity decay: no damage for 2.5 s -> -0.10 / s
	if time_since_skyra_damaged >= 2.5:
		intensity = clampf(intensity - 0.10 * step_dt, 0.0, 1.0)

	# Update phase transitions (§5.4.1)
	var prev_phase := phase
	match phase:
		Enums.PacingPhase.WARMUP:
			if phase_timer >= 5.0:
				phase = Enums.PacingPhase.BUILD_UP
				phase_timer = 0.0
		Enums.PacingPhase.BUILD_UP:
			if intensity >= 0.70:
				phase = Enums.PacingPhase.PEAK
				phase_timer = 0.0
		Enums.PacingPhase.PEAK:
			var skyra_hp: float = human.health if (human and human.life_state == Enums.LifeState.ALIVE) else 0.0
			if intensity >= 0.90 or skyra_hp <= 30.0 or phase_timer >= 12.0:
				phase = Enums.PacingPhase.RELAX
				phase_timer = 0.0
		Enums.PacingPhase.RELAX:
			if phase_timer >= 6.0 and intensity <= 0.45:
				phase = Enums.PacingPhase.BUILD_UP
				phase_timer = 0.0
		Enums.PacingPhase.RESPAWN_GRACE:
			# Leave 1.0 s after Skyra's post-respawn stealth has ended (§5.4.1)
			if human and human.life_state == Enums.LifeState.ALIVE and human.stealth_t <= 0.0:
				grace_clear_t += step_dt
				if grace_clear_t >= 1.0:
					phase = Enums.PacingPhase.BUILD_UP
					phase_timer = 0.0
					post_grace_ramp_timer = 2.5 # cap tokens at 1 for first 2.5 s
			else:
				grace_clear_t = 0.0

	if phase != prev_phase:
		_update_staging_ring()
		EventBus.director_phase_changed.emit(phase, intensity)

	var allowed := allowed_tokens()

	# Score all alive bots
	var alive_bots: Array = []
	for obj in bots:
		var b: CharacterState = obj as CharacterState
		if b and b.life_state == Enums.LifeState.ALIVE and bot_data.has(b.id):
			alive_bots.append(b)
			bot_data[b.id]["score"] = calc_token_score(b, human, now) if human else 0.0

	# Revoke tokens from dead bots
	for bid in bot_data:
		var info: Dictionary = bot_data[bid]
		if bool(info["has_token"]):
			var is_alive := false
			for b in alive_bots:
				if (b as CharacterState).id == bid:
					is_alive = true
					break
			if not is_alive:
				info["has_token"] = false
				breather_timer = 1.5

	# Count holders and candidates
	var holders: Array = []
	for b in alive_bots:
		var bid: int = (b as CharacterState).id
		if bool(bot_data[bid]["has_token"]):
			holders.append(b)

	# While holders > allowed: revoke from lowest scoring holder
	holders.sort_custom(func(a: CharacterState, b: CharacterState) -> bool:
		var s_a: float = float(bot_data[a.id]["score"])
		var s_b: float = float(bot_data[b.id]["score"])
		if not is_equal_approx(s_a, s_b):
			return s_a < s_b
		return a.id < b.id
	)
	while holders.size() > allowed:
		var lowest: CharacterState = holders.pop_front()
		bot_data[lowest.id]["has_token"] = false
		bot_data[lowest.id]["cooldown_t"] = 5.0
		EventBus.bot_token_changed.emit(lowest.id, false)

	# Token rotation (§5.4.4: >= 12.0 s held and best candidate score >= holder.score - 0.1)
	for h in holders:
		var h_char: CharacterState = h as CharacterState
		var h_info: Dictionary = bot_data[h_char.id]
		if float(h_info["token_t"]) >= 12.0:
			var best_cand: CharacterState = null
			var best_s := -999.0
			for cand in alive_bots:
				var c_char: CharacterState = cand as CharacterState
				if not bool(bot_data[c_char.id]["has_token"]) and float(bot_data[c_char.id]["cooldown_t"]) <= 0.0:
					var s: float = float(bot_data[c_char.id]["score"])
					if s > best_s:
						best_s = s
						best_cand = c_char
			if best_cand and best_s >= (float(h_info["score"]) - 0.1):
				# Rotate!
				h_info["has_token"] = false
				h_info["cooldown_t"] = 5.0
				EventBus.bot_token_changed.emit(h_char.id, false)

				bot_data[best_cand.id]["has_token"] = true
				bot_data[best_cand.id]["token_t"] = 0.0
				bot_data[best_cand.id]["time_since_had"] = 0.0
				EventBus.bot_token_changed.emit(best_cand.id, true)
				break

	# Grant tokens while holders < allowed and no breather
	var current_holder_count := 0
	for bid in bot_data:
		if bool(bot_data[bid]["has_token"]):
			current_holder_count += 1

	while current_holder_count < allowed and breather_timer <= 0.0:
		var best_cand: CharacterState = null
		var best_s := -999.0
		for cand in alive_bots:
			var c_char: CharacterState = cand as CharacterState
			if not bool(bot_data[c_char.id]["has_token"]) and float(bot_data[c_char.id]["cooldown_t"]) <= 0.0:
				var s: float = float(bot_data[c_char.id]["score"])
				if s > best_s:
					best_s = s
					best_cand = c_char
				elif s == best_s and best_cand != null and c_char.id < best_cand.id:
					best_cand = c_char # tie break lower id

		if best_cand:
			bot_data[best_cand.id]["has_token"] = true
			bot_data[best_cand.id]["token_t"] = 0.0
			bot_data[best_cand.id]["time_since_had"] = 0.0
			current_holder_count += 1
			EventBus.bot_token_changed.emit(best_cand.id, true)
		else:
			break

	# Assign non-token roles (§5.4.5)
	if phase == Enums.PacingPhase.RESPAWN_GRACE:
		for b in alive_bots:
			var bid: int = (b as CharacterState).id
			bot_data[bid]["role"] = Enums.DirectorRole.PATROLLER
	else:
		var non_token_bots: Array = []
		for b in alive_bots:
			var bid: int = (b as CharacterState).id
			if not bool(bot_data[bid]["has_token"]):
				non_token_bots.append(b)

		non_token_bots.sort_custom(func(a: CharacterState, b: CharacterState) -> bool:
			var s_a: float = float(bot_data[a.id]["score"])
			var s_b: float = float(bot_data[b.id]["score"])
			if not is_equal_approx(s_a, s_b):
				return s_a > s_b
			return a.id < b.id
		)

		for idx in range(non_token_bots.size()):
			var b_char: CharacterState = non_token_bots[idx] as CharacterState
			if idx < 2:
				bot_data[b_char.id]["role"] = Enums.DirectorRole.FLANKER
			elif idx < 4:
				bot_data[b_char.id]["role"] = Enums.DirectorRole.HOLDER
			else:
				bot_data[b_char.id]["role"] = Enums.DirectorRole.PATROLLER

	# Pick at most one self-defender (§5.4.6)
	self_defender_id = -1
	for b in alive_bots:
		var b_char: CharacterState = b as CharacterState
		if not bool(bot_data[b_char.id]["has_token"]):
			var damaged_recently := (now - b_char.last_enemy_damage_time) <= 1.5
			var near := human and b_char.pos.distance_to(human.pos) <= 700.0
			var has_los := b_char.perception and b_char.perception.sees_human
			if damaged_recently and near and has_los:
				self_defender_id = b_char.id
				break
