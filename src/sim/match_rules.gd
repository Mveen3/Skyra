# Implements §5.2 MatchRules (scoring, multi-kill, streaks, rank, match timer and summary).
class_name MatchRules
extends RefCounted

var config: MatchConfig = null
var time_left_s: float = 420.0
var match_ended: bool = false
var warned_one_minute: bool = false
var warned_final_ten: bool = false

var human: CharacterState = null
var bots: Array = []
var characters: Array = []

func setup(p_config: MatchConfig, p_human: CharacterState, p_bots: Array) -> void:
	config = p_config
	human = p_human
	bots = p_bots
	characters.clear()
	if human:
		characters.append(human)
	for b in bots:
		characters.append(b)

	reset()

func reset() -> void:
	match_ended = false
	warned_one_minute = false
	warned_final_ten = false
	time_left_s = float(config.duration_s) if config else 420.0

static func get_multi_kill_label(count: int) -> String:
	if count == 2:
		return "DOUBLE KILL"
	elif count == 3:
		return "TRIPLE KILL"
	elif count >= 4:
		return "MULTI KILL"
	return ""

static func get_streak_label(streak_count: int) -> String:
	if streak_count == 5:
		return "RAMPAGE"
	elif streak_count == 10:
		return "UNSTOPPABLE"
	elif streak_count == 15:
		return "LEGENDARY"
	return ""

static func calculate_rank(kills: int, deaths: int, duration_minutes: float) -> Dictionary:
	var kpm := float(kills) / maxf(0.1, duration_minutes)
	var kd := float(kills) / float(maxi(1, deaths))
	var score := kpm * 10.0 + clampf(kd, 0.0, 5.0) * 4.0

	var r := "D"
	var title := "Rookie"

	if score >= 40.0:
		r = "S"
		title = "Legend"
	elif score >= 28.0:
		r = "A"
		title = "Ace"
	elif score >= 18.0:
		r = "B"
		title = "Veteran"
	elif score >= 10.0:
		r = "C"
		title = "Soldier"

	return {
		"rank": r,
		"rank_title": title,
		"score": score
	}

## Scores one kill (§8.4 streaks, §8.5.3 stats). A suicide (killer == victim) only counts
## as a death. When `ev` is given, its killer_streak / multi_kill_count are filled in for
## the HUD banner and the multi-kill sting.
func register_kill(killer: CharacterState, victim: CharacterState, weapon_id: StringName, dist: float = 0.0, ev: KillEvent = null) -> Dictionary:
	var result := {
		"multi_kill_label": "",
		"streak_label": ""
	}

	if killer == victim:
		killer = null

	if killer:
		if not killer.stats:
			killer.stats = CombatStats.new()
		killer.stats.kills += 1
		killer.stats.kills_by_weapon[weapon_id] = int(killer.stats.kills_by_weapon.get(weapon_id, 0)) + 1
		killer.stats.longest_kill_wu = maxf(killer.stats.longest_kill_wu, dist)

		# Streak tracking
		killer.streak += 1
		killer.stats.best_streak = maxi(killer.stats.best_streak, killer.streak)
		var s_lbl := get_streak_label(killer.streak)
		if s_lbl != "":
			result["streak_label"] = s_lbl

		# Multi-kill tracking within 4.0 s window (§8.4, T-RULE-01)
		if killer.multi_kill_t > 0.0:
			killer.multi_kill_count += 1
		else:
			killer.multi_kill_count = 1
		killer.multi_kill_t = 4.0

		var m_lbl := get_multi_kill_label(killer.multi_kill_count)
		if m_lbl != "":
			result["multi_kill_label"] = m_lbl

		if victim and victim.is_human and not killer.is_human:
			killer.stats.kills_on_human += 1

		if ev:
			ev.killer_streak = killer.streak
			ev.multi_kill_count = killer.multi_kill_count

	if victim:
		if not victim.stats:
			victim.stats = CombatStats.new()
		victim.stats.deaths += 1
		victim.streak = 0
		victim.multi_kill_count = 0
		victim.multi_kill_t = 0.0

	return result

func step(dt: float) -> void:
	if match_ended:
		return

	# Step timer
	time_left_s = maxf(0.0, time_left_s - dt)

	# 1 minute warning
	if not warned_one_minute and time_left_s <= 60.0:
		warned_one_minute = true
		EventBus.match_time_warning.emit(&"one_minute")

	# 10 seconds warning
	if not warned_final_ten and time_left_s <= 10.0:
		warned_final_ten = true
		EventBus.match_time_warning.emit(&"final_ten")

	# Timer end
	if time_left_s <= 0.0:
		match_ended = true
		var summary := build_summary()
		EventBus.match_ended.emit(summary)

	# Health regeneration (§3.12: 4.0 s delay, 15 HP/s)
	for obj in characters:
		var c := obj as CharacterState
		if not c: continue
		if c.regen_delay_t > 0.0:
			c.regen_delay_t = maxf(0.0, c.regen_delay_t - dt)
		elif c.life_state == Enums.LifeState.ALIVE and c.health < 100.0:
			c.health = minf(100.0, c.health + 15.0 * dt)

		# Multi-kill window decay
		if c.multi_kill_t > 0.0:
			c.multi_kill_t = maxf(0.0, c.multi_kill_t - dt)
			if c.multi_kill_t <= 0.0:
				c.multi_kill_count = 0

func build_summary() -> MatchSummary:
	var summary := MatchSummary.new()
	summary.config = config
	if human and human.stats:
		summary.human = human.stats

		var duration_mins := float(config.duration_s) / 60.0 if config else 7.0
		var rank_info := calculate_rank(human.stats.kills, human.stats.deaths, duration_mins)
		summary.rank = rank_info["rank"]
		summary.rank_title = rank_info["rank_title"]

		# Accuracy
		var fired := maxi(1, human.stats.shots_fired)
		summary.accuracy = float(human.stats.shots_hit) / float(fired)

		# Favourite weapon (most kills)
		var best_w: StringName = &"magnum"
		var best_k := -1
		for wid in human.stats.kills_by_weapon:
			var k: int = int(human.stats.kills_by_weapon[wid])
			if k > best_k:
				best_k = k
				best_w = StringName(str(wid))
		summary.favourite_weapon_id = best_w

	# Bot stats summary
	summary.bots = []
	for obj in bots:
		var b := obj as CharacterState
		if not b: continue
		var b_stats := b.stats if b.stats else CombatStats.new()
		var col: String = ("#" + b.profile.primary.to_html(false)) if b.profile else "#A0A0A0"
		summary.bots.append({
			"name": b.name,
			"color": col,
			"kills_on_human": b_stats.kills_on_human,
			"deaths": b_stats.deaths
		})

	return summary
