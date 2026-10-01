# Implements §3.12 Health, damage, regeneration, status effects, and kill credit.
# Damage is queued during a tick and applied in creation order by flush() (§1.4 step 2.7).
class_name DamageSystem
extends RefCounted

signal kill_occurred(ev: KillEvent)
signal damage_applied(ev: DamageEvent, source_team: int)

const MAX_HEALTH: float = 100.0
const REGEN_DELAY_S: float = 4.0
const REGEN_PER_S: float = 15.0
const KILL_CREDIT_WINDOW_S: float = 5.0
const BOT_TO_HUMAN_MULT: float = 0.85
const BURN_DPS: float = 10.0
const BURN_DURATION: float = 3.0
const BURN_TICK_S: float = 0.25
const BURN_TICK_DMG: float = 2.5 # 10.0 * 0.25
const HUMAN_RESPAWN_S: float = 2.0
const BOT_RESPAWN_S: float = 3.0

class QueuedDamage:
	var target_id: int
	var source_id: int
	var source_team: int
	var weapon_id: String
	var amount: float
	var hit_point: Vector2
	var hit_dir: Vector2
	var is_headshot: bool
	var is_explosive: bool
	var self_mult: float = 0.5
	var shot_id: int = -1

var damage_queue: Array[QueuedDamage] = []

func queue_damage(target: CharacterState, source_id: int, source_team: int, weapon_id: String,
                 amount: float, hit_point: Vector2 = Vector2.ZERO, hit_dir: Vector2 = Vector2.RIGHT,
                 is_headshot: bool = false, is_explosive: bool = false, self_mult: float = 0.5,
                 shot_id: int = -1) -> void:
	if not target or target.life_state != Enums.LifeState.ALIVE:
		return
	var q := QueuedDamage.new()
	q.target_id = target.id
	q.source_id = source_id
	q.source_team = source_team
	q.weapon_id = weapon_id
	q.amount = amount
	q.hit_point = hit_point
	q.hit_dir = hit_dir
	q.is_headshot = is_headshot
	q.is_explosive = is_explosive
	q.self_mult = self_mult
	q.shot_id = shot_id
	damage_queue.append(q)

func apply_burn(target: CharacterState, source_id: int) -> void:
	if not target or target.life_state != Enums.LifeState.ALIVE:
		return
	if target.is_human and (target.stealth_t > 0.0 or target.invuln_t > 0.0):
		return
	target.burn_t = BURN_DURATION
	target.burn_tick_t = 0.0
	target.burn_source = source_id

func flush(characters_by_id: Dictionary, now: float) -> void:
	while not damage_queue.is_empty():
		var q: QueuedDamage = damage_queue.pop_front()
		var target: CharacterState = characters_by_id.get(q.target_id)
		if not target or target.life_state != Enums.LifeState.ALIVE:
			continue

		# Rule 1: Skip if invulnerable
		if target.invuln_t > 0.0:
			continue

		# Rule 2: Bots never harm bots
		if q.source_team == Enums.Team.BOT and target.team == Enums.Team.BOT:
			continue

		# Rule 3: Self damage (explosive only, scaled by the explosion's self_damage_mult)
		if q.source_id == target.id:
			if not q.is_explosive:
				continue
			q.amount *= q.self_mult

		# Rule 4: Bot to human scaling
		if q.source_team == Enums.Team.BOT and target.is_human:
			q.amount *= BOT_TO_HUMAN_MULT

		# Rule 5: Apply health reduction
		target.health -= q.amount
		target.regen_delay_t = REGEN_DELAY_S

		var source_char: CharacterState = characters_by_id.get(q.source_id)
		var enemy_source := source_char != null and q.source_id != target.id and source_char.team != target.team
		if enemy_source:
			target.last_enemy_damager = q.source_id
			target.last_enemy_damage_time = now
			_record_hit(source_char, q)
		target.stats.damage_taken += q.amount

		var dmg_evt := DamageEvent.new()
		dmg_evt.target_id = target.id
		dmg_evt.source_id = q.source_id
		dmg_evt.weapon_id = q.weapon_id
		dmg_evt.amount = q.amount
		dmg_evt.point = q.hit_point
		dmg_evt.dir = q.hit_dir
		dmg_evt.headshot = q.is_headshot
		dmg_evt.explosive = q.is_explosive
		dmg_evt.self_mult = q.self_mult
		dmg_evt.is_burn = q.weapon_id == "flamethrower" and q.hit_dir == Vector2.ZERO
		dmg_evt.time = now
		damage_applied.emit(dmg_evt, q.source_team)
		EventBus.character_damaged.emit(dmg_evt)

		# Rule 6: Fatal damage check
		if target.health <= 0.0:
			target.health = 0.0
			target.life_state = Enums.LifeState.DEAD
			target.respawn_t = HUMAN_RESPAWN_S if target.is_human else BOT_RESPAWN_S
			target.burn_t = 0.0
			target.burn_tick_t = 0.0
			target.jet_active = false

			# Killer = enemy source; else the last enemy damager within 5 s; else suicide
			var killer_id := target.id
			if enemy_source:
				killer_id = q.source_id
			elif target.last_enemy_damager != -1 and (now - target.last_enemy_damage_time) <= KILL_CREDIT_WINDOW_S:
				killer_id = target.last_enemy_damager
			var killer: CharacterState = characters_by_id.get(killer_id)

			var kill_evt := KillEvent.new()
			kill_evt.victim_id = target.id
			kill_evt.killer_id = killer_id
			kill_evt.weapon_id = q.weapon_id
			kill_evt.headshot = q.is_headshot
			kill_evt.suicide = killer_id == target.id
			kill_evt.distance = 0.0 if (kill_evt.suicide or killer == null) else killer.centre().distance_to(target.centre())
			kill_evt.time = now
			kill_occurred.emit(kill_evt) # MatchRules fills streak / multi-kill counts
			EventBus.character_killed.emit(kill_evt)

## Accuracy / damage stats (§8.5.3): a shot counts as a hit once, however many pellets landed.
func _record_hit(source: CharacterState, q: QueuedDamage) -> void:
	var st := source.stats
	st.damage_dealt += q.amount
	if q.shot_id > 0 and st.last_hit_shot_id != q.shot_id:
		st.last_hit_shot_id = q.shot_id
		st.shots_hit += 1
		if q.is_headshot:
			st.headshots += 1

func step(characters: Array, dt: float, now: float) -> void:
	for obj in characters:
		var c: CharacterState = obj as CharacterState
		if not c: continue

		if c.life_state == Enums.LifeState.DEAD:
			c.respawn_t = maxf(0.0, c.respawn_t - dt)
			continue

		# Timers
		c.stealth_t = maxf(0.0, c.stealth_t - dt)
		c.invuln_t = maxf(0.0, c.invuln_t - dt)
		c.boost_t = maxf(0.0, c.boost_t - dt)

		# Health Regeneration
		if c.regen_delay_t > 0.0:
			c.regen_delay_t -= dt
		else:
			c.health = minf(MAX_HEALTH, c.health + REGEN_PER_S * dt)

		# Blaze Burn DoT
		if c.burn_t > 0.0:
			c.burn_t = maxf(0.0, c.burn_t - dt)
			c.burn_tick_t += dt
			while c.burn_tick_t >= (BURN_TICK_S - 1e-4):
				c.burn_tick_t -= BURN_TICK_S
				var source_team: int = Enums.Team.HUMAN
				queue_damage(c, c.burn_source, source_team, "flamethrower", BURN_TICK_DMG)
