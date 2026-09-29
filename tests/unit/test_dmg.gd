# Implements §10.3 / Table 10.6 Damage & lifecycle unit tests (T-DMG-01..04).
class_name TestDmg
extends RefCounted

const DT: float = 1.0 / 60.0

func test_dmg_01_team_rules() -> void:
	var dmg_sys := DamageSystem.new()

	var skyra := CharacterState.new()
	skyra.id = 0
	skyra.is_human = true
	skyra.team = Enums.Team.HUMAN
	skyra.health = 100.0

	var bot_alpha := CharacterState.new()
	bot_alpha.id = 1
	bot_alpha.is_human = false
	bot_alpha.team = Enums.Team.BOT
	bot_alpha.health = 100.0

	var bot_beta := CharacterState.new()
	bot_beta.id = 2
	bot_beta.is_human = false
	bot_beta.team = Enums.Team.BOT
	bot_beta.health = 100.0

	var chars := {skyra.id: skyra, bot_alpha.id: bot_alpha, bot_beta.id: bot_beta}

	# 1. Bot bullet -> bot: deals 0
	dmg_sys.queue_damage(bot_beta, bot_alpha.id, bot_alpha.team, "mp5", 20.0)
	dmg_sys.flush(chars, 0.0)
	Assertions.assert_eq(bot_beta.health, 100.0, "Bot bullet deals 0 to bot")

	# 2. Bot rocket -> its owner: deals 0
	dmg_sys.queue_damage(bot_alpha, bot_alpha.id, bot_alpha.team, "rocket_launcher", 50.0, Vector2.ZERO, Vector2.UP, false, true, 0.5)
	dmg_sys.flush(chars, 0.0)
	Assertions.assert_eq(bot_alpha.health, 100.0, "Bot rocket deals 0 to its owner")

	# 3. Skyra's rocket -> Skyra: deals x0.5 self damage
	dmg_sys.queue_damage(skyra, skyra.id, skyra.team, "rocket_launcher", 50.0, Vector2.ZERO, Vector2.UP, false, true, 0.5)
	dmg_sys.flush(chars, 0.0)
	Assertions.assert_near(skyra.health, 100.0 - 25.0, 1e-4, "Skyra's rocket deals x0.5 self-damage (50 -> 25)")

	# 4. Bot -> Skyra: deals x0.85
	skyra.health = 100.0
	dmg_sys.queue_damage(skyra, bot_alpha.id, bot_alpha.team, "ak47", 20.0)
	dmg_sys.flush(chars, 0.0)
	Assertions.assert_near(skyra.health, 100.0 - (20.0 * 0.85), 1e-4, "Bot deals 85% damage to Skyra (20 -> 17)")

func test_dmg_02_regeneration() -> void:
	var dmg_sys := DamageSystem.new()
	var c := CharacterState.new()
	c.id = 0
	c.is_human = true
	c.health = 50.0
	c.regen_delay_t = 4.0 # damaged just now

	# First 3.9 s: no regen
	for t in range(234): # 3.9 s
		dmg_sys.step([c], DT, float(t) * DT)
	Assertions.assert_eq(c.health, 50.0, "No health regen before 4.0 s")

	# Pass 4.0 s threshold (another 10 ticks = 0.166 s)
	for t in range(10):
		dmg_sys.step([c], DT, 3.9 + float(t) * DT)
	Assertions.assert_true(c.health > 50.0, "Regen started after 4.0 s delay")

	# 1 second of regen at 15 HP/s
	var h_before := c.health
	for t in range(60):
		dmg_sys.step([c], DT, 5.0 + float(t) * DT)
	Assertions.assert_near(c.health - h_before, 15.0, 0.05, "Regenerates at 15 HP/s")

func test_dmg_03_kill_credit() -> void:
	var dmg_sys := DamageSystem.new()

	var skyra := CharacterState.new()
	skyra.id = 0
	skyra.is_human = true
	skyra.team = Enums.Team.HUMAN
	skyra.health = 100.0

	var beta := CharacterState.new()
	beta.id = 2
	beta.is_human = false
	beta.team = Enums.Team.BOT

	var chars := {skyra.id: skyra, beta.id: beta}

	var last_killer_box: Array[int] = [-1]
	var on_kill := func(evt: KillEvent) -> void:
		last_killer_box[0] = evt.killer_id

	EventBus.character_killed.connect(on_kill)

	# Case 1: Beta hits Skyra at t=1.0. Skyra dies to her own rocket at t=3.0 (within 5 s)
	dmg_sys.queue_damage(skyra, beta.id, beta.team, "mp5", 10.0)
	dmg_sys.flush(chars, 1.0)

	dmg_sys.queue_damage(skyra, skyra.id, skyra.team, "rocket_launcher", 200.0, Vector2.ZERO, Vector2.UP, false, true, 0.5)
	dmg_sys.flush(chars, 3.0)

	Assertions.assert_eq(last_killer_box[0], beta.id, "Killer credited to Beta within 5.0 s of damage")

	# Case 2: Skyra respawns. Dies to her own rocket at t=10.0 (> 5 s since Beta's hit)
	skyra.health = 100.0
	skyra.life_state = Enums.LifeState.ALIVE
	dmg_sys.queue_damage(skyra, skyra.id, skyra.team, "rocket_launcher", 200.0, Vector2.ZERO, Vector2.UP, false, true, 0.5)
	dmg_sys.flush(chars, 10.0)

	Assertions.assert_eq(last_killer_box[0], skyra.id, "Killer credited to self (suicide) after 5.0 s")

	EventBus.character_killed.disconnect(on_kill)

func test_dmg_04_invulnerability() -> void:
	var dmg_sys := DamageSystem.new()
	var skyra := CharacterState.new()
	skyra.id = 0
	skyra.is_human = true
	skyra.team = Enums.Team.HUMAN
	skyra.health = 100.0
	skyra.invuln_t = 2.0 # Invulnerable

	var bot := CharacterState.new()
	bot.id = 1
	bot.is_human = false
	bot.team = Enums.Team.BOT

	var chars := {skyra.id: skyra, bot.id: bot}

	# Check Projectile eligibility ignores invulnerable human
	Assertions.assert_false(ProjectileSystem.is_eligible(bot.id, bot.team, skyra), "Projectiles ignore invulnerable human")

	# Even if damage was queued, flush ignores it
	dmg_sys.queue_damage(skyra, bot.id, bot.team, "ak47", 50.0)
	dmg_sys.flush(chars, 0.0)
	Assertions.assert_eq(skyra.health, 100.0, "Invulnerable human takes 0 damage")
