# Implements §10 test requirements T-RULE-01..04.
class_name TestRule
extends RefCounted

const DT: float = 1.0 / 60.0

func test_rule_01_scoring_and_labels() -> void:
	var rules := MatchRules.new()
	var config := MatchConfig.new(&"mini_post", 5, 420)
	var human := CharacterState.new()
	human.id = 0
	human.is_human = true

	var bot := CharacterState.new()
	bot.id = 1
	bot.is_human = false

	rules.setup(config, human, [bot])

	# Test multi-kill at 2, 3, 4 within 4.0 s
	var res1 := rules.register_kill(human, bot, &"magnum", 300.0)
	Assertions.assert_eq(res1["multi_kill_label"], "", "First kill: no multi-kill label")
	Assertions.assert_eq(human.stats.kills, 1)
	Assertions.assert_eq(human.streak, 1)

	# 2nd kill 1.0 s later -> "DOUBLE KILL"
	rules.step(1.0)
	var res2 := rules.register_kill(human, bot, &"magnum", 400.0)
	Assertions.assert_eq(res2["multi_kill_label"], "DOUBLE KILL", "2 kills in 4 s -> DOUBLE KILL")

	# 3rd kill 1.5 s later -> "TRIPLE KILL"
	rules.step(1.5)
	var res3 := rules.register_kill(human, bot, &"magnum", 450.0)
	Assertions.assert_eq(res3["multi_kill_label"], "TRIPLE KILL", "3 kills in 4 s -> TRIPLE KILL")

	# 4th kill 1.0 s later -> "MULTI KILL"
	rules.step(1.0)
	var res4 := rules.register_kill(human, bot, &"magnum", 500.0)
	Assertions.assert_eq(res4["multi_kill_label"], "MULTI KILL", "4 kills in 4 s -> MULTI KILL")

	# 5th kill: streak label at 5 -> "RAMPAGE"
	rules.step(1.0)
	var res5 := rules.register_kill(human, bot, &"magnum", 550.0)
	Assertions.assert_eq(res5["streak_label"], "RAMPAGE", "5 streak -> RAMPAGE")

	# Advance 5 more kills -> 10 streak -> "UNSTOPPABLE"
	for _i in range(4):
		rules.register_kill(human, bot, &"magnum")
	var res10 := rules.register_kill(human, bot, &"magnum")
	Assertions.assert_eq(res10["streak_label"], "UNSTOPPABLE", "10 streak -> UNSTOPPABLE")

	# Advance 5 more kills -> 15 streak -> "LEGENDARY"
	for _i in range(4):
		rules.register_kill(human, bot, &"magnum")
	var res15 := rules.register_kill(human, bot, &"magnum")
	Assertions.assert_eq(res15["streak_label"], "LEGENDARY", "15 streak -> LEGENDARY")

	# Bot kills human -> human streak resets, bot gets kills_on_human
	var res_death := rules.register_kill(bot, human, &"ak47")
	Assertions.assert_eq(human.streak, 0, "Human streak resets to 0 on death")
	Assertions.assert_eq(human.stats.deaths, 1, "Human death counted")
	Assertions.assert_eq(bot.stats.kills_on_human, 1, "Bot kills_on_human counted")

	# Multi-kill window expiration
	human.multi_kill_t = 3.0
	human.multi_kill_count = 2
	rules.step(3.5)
	Assertions.assert_eq(human.multi_kill_count, 0, "Multi-kill window expired after > 4 s")

func test_rule_02_rank() -> void:
	# Test §8.5.3 and T-RULE-02:
	# 30 kills/5 deaths/7 min → 62.9 → S
	# 5 kills/10 deaths/7 min → 9.1 → D
	var rank_s := MatchRules.calculate_rank(30, 5, 7.0)
	Assertions.assert_near(float(rank_s["score"]), 62.86, 0.1, "30 kills/5 deaths/7 min score ≈ 62.9")
	Assertions.assert_eq(str(rank_s["rank"]), "S", "Score 62.9 yields S rank")
	Assertions.assert_eq(str(rank_s["rank_title"]), "Legend", "S rank title is Legend")

	var rank_d := MatchRules.calculate_rank(5, 10, 7.0)
	Assertions.assert_near(float(rank_d["score"]), 9.14, 0.1, "5 kills/10 deaths/7 min score ≈ 9.1")
	Assertions.assert_eq(str(rank_d["rank"]), "D", "Score 9.1 yields D rank")
	Assertions.assert_eq(str(rank_d["rank_title"]), "Rookie", "D rank title is Rookie")

	# Check intermediate thresholds:
	# score >= 28 -> A
	var rank_a := MatchRules.calculate_rank(15, 3, 7.0) # 15/7*10 + 4*5 = 21.4 + 20 = 41.4 -> S; let's check exact A
	# kpm*10 + kd*4 = 28 -> 14 kills in 7 min (kpm 2) + kd 2 -> 20 + 8 = 28 -> A
	var rank_a_exact := MatchRules.calculate_rank(14, 7, 7.0)
	Assertions.assert_eq(str(rank_a_exact["rank"]), "A", "Score 28 yields A rank")

	# score >= 18 -> B
	var rank_b_exact := MatchRules.calculate_rank(9, 9, 7.0) # 9/7*10 + 1*4 = 12.85 + 4 = 16.85 (C); 10 kills -> 10/7*10 + 4 = 14.28 + 4 = 18.28 -> B
	var rank_b := MatchRules.calculate_rank(10, 10, 7.0)
	Assertions.assert_eq(str(rank_b["rank"]), "B", "Score >= 18 yields B rank")

	# score >= 10 -> C
	var rank_c := MatchRules.calculate_rank(5, 5, 7.0) # 5/7*10 + 4 = 7.14 + 4 = 11.14 -> C
	Assertions.assert_eq(str(rank_c["rank"]), "C", "Score >= 10 yields C rank")

func test_rule_03_sniper_loadout() -> void:
	# T-RULE-03: Sniper loadout: Black Arrow + 3 Frags, max 5
	var c := CharacterState.new()
	WeaponLogic.give_spawn_loadout(c, &"sniper_post")

	var active_w := c.inventory.active_weapon()
	Assertions.assert_true(active_w != null, "Active weapon assigned")
	Assertions.assert_eq(active_w.def.id, "m93ba", "Black Arrow (m93ba) is the slot 1 weapon")
	Assertions.assert_eq(c.inventory.get_weapon(1), null, "Slot 2 is empty")
	Assertions.assert_eq(c.inventory.grenades, 3, "Spawns with 3 frags")
	Assertions.assert_eq(c.inventory.max_grenades, 5, "Max grenades cap is 5")

func test_rule_04_mini_loadout() -> void:
	# T-RULE-04: Mini loadout: Magnum + 2 Frags, max 4
	var c := CharacterState.new()
	WeaponLogic.give_spawn_loadout(c, &"mini_post")

	var active_w := c.inventory.active_weapon()
	Assertions.assert_true(active_w != null, "Active weapon assigned")
	Assertions.assert_eq(active_w.def.id, "magnum", "Magnum is the slot 1 weapon")
	Assertions.assert_eq(c.inventory.get_weapon(1), null, "Slot 2 is empty")
	Assertions.assert_eq(c.inventory.grenades, 2, "Spawns with 2 frags")
	Assertions.assert_eq(c.inventory.max_grenades, 4, "Max grenades cap is 4")
