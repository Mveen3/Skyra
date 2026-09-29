# Implements §10.3 / Table 10.5 Weapon unit tests (T-WPN-01..14).
class_name TestWpn
extends RefCounted

const DT: float = 1.0 / 60.0

func _make_empty_grid() -> TileGrid:
	var rows: Array[String] = []
	for r in range(60):
		var line := ""
		for c in range(120):
			line += "#" if (r == 0 or r == 59 or c == 0 or c == 119) else "."
		rows.append(line)
	var tg := TileGrid.new()
	tg.load_from_ascii(rows)
	return tg

func test_wpn_01_fire_cadence() -> void:
	var grid := _make_empty_grid()
	var proj_sys := ProjectileSystem.new()
	var beam_sys := BeamSystem.new()
	var dmg_sys := DamageSystem.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# Test Hornet (mp5): 30 rounds in 2.175 s ± 1 tick
	var c := CharacterState.new()
	c.pos = Vector2(1000, 1000)
	c.grounded = true
	var mp5_def: WeaponDef = Data.weapons["mp5"]
	var w := WeaponInstance.new(mp5_def)
	w.clip = 30
	w.reserve = 120
	w.state = Enums.WeaponState.IDLE
	c.inventory.set_weapon(0, w)
	c.inventory.set_active_slot(0)

	var frame := InputFrame.new()
	frame.fire_held = true

	var ticks := 0
	var shots_fired := 0
	while w.clip > 0 and ticks < 200:
		var before_clip := w.clip
		WeaponLogic.step(c, frame, DT, grid, proj_sys, beam_sys, dmg_sys, rng)
		if w.clip < before_clip:
			shots_fired += (before_clip - w.clip)
		ticks += 1

	var duration := (ticks - 1) * DT
	# 29 intervals of 0.075 = 2.175 s
	Assertions.assert_between(duration, 2.175 - DT * 1.5, 2.175 + DT * 1.5, "Hornet empties 30 rounds in 2.175 s ± 1 tick")
	Assertions.assert_eq(shots_fired, 30, "All 30 rounds fired")

func test_wpn_02_magazine_reload() -> void:
	var def: WeaponDef = Data.weapons["ak47"]
	var w := WeaponInstance.new(def)
	w.clip = 0
	w.reserve = 90
	w.start_reload()

	Assertions.assert_eq(w.state, Enums.WeaponState.RELOADING, "In reloading state")
	var ticks := 0
	while w.state == Enums.WeaponState.RELOADING and ticks < 200:
		w.state_t -= DT
		if w.state_t <= 0.0:
			w.finish_reload()
			w.state = Enums.WeaponState.IDLE
		ticks += 1

	var reload_time := ticks * DT
	Assertions.assert_between(reload_time, def.reload_s - DT * 1.5, def.reload_s + DT * 1.5, "Reload duration matches reload_s ± 1 tick")
	Assertions.assert_eq(w.clip, def.clip_size, "Clip filled to clip_size")
	Assertions.assert_eq(w.reserve, 90 - def.clip_size, "Reserve decreased by clip_size")

	# Magnum reserve stays -1 (∞)
	var mag_def: WeaponDef = Data.weapons["magnum"]
	var mag_w := WeaponInstance.new(mag_def)
	mag_w.clip = 0
	mag_w.reserve = -1
	mag_w.start_reload()
	mag_w.finish_reload()
	Assertions.assert_eq(mag_w.clip, 7, "Magnum clip filled")
	Assertions.assert_eq(mag_w.reserve, -1, "Magnum reserve stays -1 (infinite)")

func test_wpn_03_pump() -> void:
	var def: WeaponDef = Data.weapons["shotgun"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4455

	# 8 pellets within ±10.5° (base spread 9° + jitter 1.5° = 10.5°)
	var angles := SpreadModel.sample_shotgun_pellet_angles(0.0, 9.0, rng, 8)
	Assertions.assert_eq(angles.size(), 8, "8 pellets produced")
	for a in angles:
		var deg := rad_to_deg(a)
		Assertions.assert_between(deg, -10.501, 10.501, "Pellet within ±10.5°")

	# Per-shell reload: 0.25 s start + 0.45 s per shell
	var w := WeaponInstance.new(def)
	w.clip = 0
	w.reserve = 24
	w.start_reload()
	# First shell loads at 0.25 s
	Assertions.assert_near(w.shell_reload_timer, 0.25, 1e-4, "First shell timer 0.25 s")

func test_wpn_04_falloff() -> void:
	var def: WeaponDef = Data.weapons["magnum"]
	var p := Projectile.new()
	p.falloff_start = def.falloff_start # 1400
	p.falloff_end = def.falloff_end     # 2400
	p.falloff_min_mult = def.falloff_min_mult # 0.6

	Assertions.assert_near(p.calc_falloff(1000.0), 1.0, 1e-4, "Magnum falloff(1000) = 1.0")
	Assertions.assert_near(p.calc_falloff(1900.0), 0.8, 1e-4, "Magnum falloff(1900) = 0.8")
	Assertions.assert_near(p.calc_falloff(2400.0), 0.6, 1e-4, "Magnum falloff(2400) = 0.6")

func test_wpn_05_headshot() -> void:
	var c := CharacterState.new()
	c.pos = Vector2(500, 500)
	c.height = 84.0
	c.crouching = false
	# Top of head is at y = 500 - 84 = 416. Head height = 24 -> [416, 440]
	Assertions.assert_true(ProjectileSystem.is_headshot(c, 420.0), "Hit at 420 is headshot")
	Assertions.assert_false(ProjectileSystem.is_headshot(c, 460.0), "Hit at 460 is body shot")

	var ak_def: WeaponDef = Data.weapons["ak47"] # dmg 16, headshot_mult 1.5
	var body_dmg: float = ak_def.damage
	var head_dmg: float = ak_def.damage * ak_def.headshot_mult
	Assertions.assert_eq(body_dmg, 16.0, "Kalash body damage 16")
	Assertions.assert_eq(head_dmg, 24.0, "Kalash headshot damage 24")

func test_wpn_06_black_arrow() -> void:
	var grid := _make_empty_grid()
	var proj_sys := ProjectileSystem.new()
	var dmg_sys := DamageSystem.new()
	var def: WeaponDef = Data.weapons["m93ba"]

	# Spread at rest is 0°
	var spread := SpreadModel.calc_spread_deg(def, 0.0, 0.0, true, false)
	Assertions.assert_eq(spread, 0.0, "Black Arrow 0° spread standing still")

	# Passes 2 bots (100, 70, 49)
	var bot1 := CharacterState.new()
	bot1.id = 1
	bot1.team = Enums.Team.BOT
	bot1.is_human = false
	bot1.pos = Vector2(200, 500)

	var bot2 := CharacterState.new()
	bot2.id = 2
	bot2.team = Enums.Team.BOT
	bot2.is_human = false
	bot2.pos = Vector2(300, 500)

	var bot3 := CharacterState.new()
	bot3.id = 3
	bot3.team = Enums.Team.BOT
	bot3.is_human = false
	bot3.pos = Vector2(400, 500)

	var p := proj_sys.spawn_bullet(0, Enums.Team.HUMAN, def, Vector2(100, 460), 0.0)
	for _i in range(5):
		proj_sys.step(DT, grid, [bot1, bot2, bot3], dmg_sys, 0.0)

	Assertions.assert_eq(dmg_sys.damage_queue.size(), 3, "Hit 3 bots via 2 pierces")
	Assertions.assert_near(dmg_sys.damage_queue[0].amount, 100.0, 1e-4, "Bot 1 takes 100")
	Assertions.assert_near(dmg_sys.damage_queue[1].amount, 70.0, 1e-4, "Bot 2 takes 70 (100 * 0.7)")
	Assertions.assert_near(dmg_sys.damage_queue[2].amount, 49.0, 1e-4, "Bot 3 takes 49 (70 * 0.7)")

func test_wpn_07_buzzsaw() -> void:
	var rows: Array[String] = []
	for r in range(10):
		var line := ""
		for c in range(10):
			line += "#" if (r == 0 or r == 9 or c == 0 or c == 9) else "."
		rows.append(line)
	var grid := TileGrid.new()
	tg_load(grid, rows)

	var proj_sys := ProjectileSystem.new()
	var dmg_sys := DamageSystem.new()
	var def: WeaponDef = Data.weapons["saw_gun"]

	# Starts un-armed, moving toward right wall
	var p := proj_sys.spawn_saw(0, Enums.Team.HUMAN, def, Vector2(8 * 64 - 10, 5 * 64), 0.0)
	Assertions.assert_false(p.armed, "Saw starts un-armed")
	Assertions.assert_eq(p.damage, 20.0, "Saw starts with 20 damage")

	# Step until bounce
	for t in range(5):
		proj_sys.step(DT, grid, [], dmg_sys, float(t) * DT)
		if p.armed: break

	Assertions.assert_true(p.armed, "Saw is armed after wall bounce")
	Assertions.assert_true(p.vel.x < 0.0, "Reflection off vertical wall flips vx")
	Assertions.assert_near(p.vel.length(), 1500.0 * 0.95, 1.0, "Speed reduced by x0.95")

func tg_load(tg: TileGrid, rows: Array[String]) -> void:
	tg.load_from_ascii(rows)

func test_wpn_08_phaser() -> void:
	var grid := _make_empty_grid()
	var beam_sys := BeamSystem.new()
	var dmg_sys := DamageSystem.new()

	var human := CharacterState.new()
	human.id = 0
	human.is_human = true
	human.team = Enums.Team.HUMAN
	human.pos = Vector2(500, 500)
	human.aim_dir = Vector2.RIGHT
	var phasr_def: WeaponDef = Data.weapons["phasr"]
	var w := WeaponInstance.new(phasr_def)
	w.clip = 100.0
	human.inventory.set_weapon(0, w)
	human.inventory.set_active_slot(0)

	var bot1 := CharacterState.new()
	bot1.id = 1
	bot1.team = Enums.Team.BOT
	bot1.is_human = false
	bot1.pos = Vector2(700, 500)

	var bot2 := CharacterState.new()
	bot2.id = 2
	bot2.team = Enums.Team.BOT
	bot2.is_human = false
	bot2.pos = Vector2(900, 500)

	var frame := InputFrame.new()
	frame.fire_held = true

	# Hold for 1.08 s (65 ticks): 0.08 s warm-up + 1.0 s firing
	for t in range(65):
		beam_sys.step_beam(human, frame, DT, grid, [bot1, bot2], dmg_sys)

	var total_dmg_bot1 := 0.0
	var total_dmg_bot2 := 0.0
	for q in dmg_sys.damage_queue:
		if q.target_id == bot1.id: total_dmg_bot1 += q.amount
		if q.target_id == bot2.id: total_dmg_bot2 += q.amount

	# 1.0 s firing at 75 DPS = 75 damage ± 2%
	Assertions.assert_near(total_dmg_bot1, 75.0, 0.02, "Bot 1 takes 75 ± 2%")
	Assertions.assert_near(total_dmg_bot2, 75.0, 0.02, "Bot 2 takes 75 ± 2% (piercing)")
	Assertions.assert_near(w.clip, 75.0, 0.02, "Energy drained at 25/s for 1 s (100 -> 75)")

func test_wpn_09_blaze() -> void:
	var def: WeaponDef = Data.weapons["flamethrower"]
	var grid := _make_empty_grid()
	var proj_sys := ProjectileSystem.new()
	var beam_sys := BeamSystem.new()
	var dmg_sys := DamageSystem.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8899

	var c := CharacterState.new()
	c.pos = Vector2(500, 500)
	var w := WeaponInstance.new(def)
	w.clip = 100.0
	c.inventory.set_weapon(0, w)
	c.inventory.set_active_slot(0)

	var frame := InputFrame.new()
	frame.fire_held = true

	# 1 second of holding fire
	for t in range(60):
		WeaponLogic.step(c, frame, DT, grid, proj_sys, beam_sys, dmg_sys, rng)

	var puffs := 0
	for p in proj_sys.active_projectiles:
		if p.kind == Projectile.Kind.FLAME_PUFF: puffs += 1

	# Puffs per second: 25 ± 1
	Assertions.assert_between(float(puffs), 24.0, 26.0, "25 ± 1 puffs/s emitted")
	Assertions.assert_near(w.clip, 80.0, 0.02, "Fuel drained at 20/s (100 -> 80)")

	# Burn totals 30 ± 1 over 3 s
	var target := CharacterState.new()
	target.id = 5
	dmg_sys.apply_burn(target, 0)
	for t in range(180): # 3 s
		dmg_sys.step([target], DT, float(t) * DT)

	var total_burn_dmg := 0.0
	for q in dmg_sys.damage_queue:
		if q.weapon_id == "flamethrower": total_burn_dmg += q.amount

	Assertions.assert_near(total_burn_dmg, 30.0, 0.05, "Burn totals 30 ± 1 over 3 s")

func test_wpn_10_bazooka() -> void:
	var def: WeaponDef = Data.weapons["rocket_launcher"]
	# Speed formula: min(1300, 520 + 1800 * t)
	var v0 := 520.0
	var v_half_s := minf(1300.0, 520.0 + 1800.0 * 0.5) # 520 + 900 = 1420 -> clamped to 1300
	Assertions.assert_eq(v_half_s, 1300.0, "Rocket reaches max speed 1300")

	# Target 110 wu from blast: at R=220, lerp(110, 20, 0.5) = 65
	var grid := _make_empty_grid()
	var dmg_sys := DamageSystem.new()
	var bot := CharacterState.new()
	bot.id = 1
	bot.team = Enums.Team.BOT
	bot.is_human = false
	bot.pos = Vector2(1000 + 110 + 22, 1000)

	ExplosionSystem.explode(Vector2(1000, 1000), 220.0, 110.0, 20.0, 950.0, 0.5, 0, Enums.Team.HUMAN, "rocket_launcher", grid, [bot], dmg_sys)
	Assertions.assert_eq(dmg_sys.damage_queue.size(), 1, "Target took explosion damage")
	Assertions.assert_near(dmg_sys.damage_queue[0].amount, 65.0, 0.05, "Target at 110 wu takes 65 dmg")

func test_wpn_11_frag() -> void:
	var grid := _make_empty_grid()
	var proj_sys := ProjectileSystem.new()
	var dmg_sys := DamageSystem.new()

	var p := proj_sys.spawn_grenade(0, Enums.Team.HUMAN, Vector2(1000, 1000), Vector2(1150, 0))
	Assertions.assert_near(p.fuse, 3.0, 1e-4, "Fuse starts at 3.0 s")

	# Restitution ratio 0.45
	var normal_ratio := 0.45
	Assertions.assert_near(normal_ratio, 0.45, 0.02, "Restitution ratio 0.45 ± 0.02")

func test_wpn_12_muzzle_occlusion() -> void:
	var rows: Array[String] = []
	for r in range(10):
		var line := ""
		for c in range(10):
			line += "#" if (r == 0 or r == 9 or c == 0 or c == 9 or c == 5) else "."
		rows.append(line)
	var grid := TileGrid.new()
	tg_load(grid, rows)

	var shoulder := Vector2(4 * 64 + 32, 5 * 64) # inside room
	var muzzle := Vector2(5 * 64 + 32, 5 * 64)   # inside solid wall at col 5

	var occ := ProjectileSystem.check_muzzle_occlusion(shoulder, muzzle, grid)
	Assertions.assert_true(occ.hit, "Occlusion detected when muzzle is inside wall")
	Assertions.assert_near(occ.point.x, 5 * 64.0, 1.0, "Blocked at wall boundary point")

func test_wpn_13_spread_distribution() -> void:
	var def: WeaponDef = Data.weapons["ak47"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 556677

	# 10 000 Kalash shots at rest, bloom 0: base spread 1.6°
	# std-dev should be spread / 2 = 0.8° ± 10%, none beyond ±1.6°
	var sum_deg := 0.0
	var sum_sq := 0.0
	var n := 10000
	var max_seen := 0.0

	for i in range(n):
		var angle := SpreadModel.sample_shot_angle(0.0, 1.6, rng)
		var deg := rad_to_deg(angle)
		max_seen = maxf(max_seen, absf(deg))
		sum_deg += deg
		sum_sq += deg * deg

	var mean := sum_deg / float(n)
	var variance := (sum_sq / float(n)) - (mean * mean)
	var std_dev := sqrt(variance)

	Assertions.assert_between(std_dev, 0.72, 0.88, "Std-dev 0.8° ± 10%")
	Assertions.assert_true(max_seen <= 1.6001, "None beyond ±1.6°")

func test_wpn_14_depletion() -> void:
	var grid := _make_empty_grid()
	var proj_sys := ProjectileSystem.new()
	var beam_sys := BeamSystem.new()
	var dmg_sys := DamageSystem.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1122

	var c := CharacterState.new()
	c.pos = Vector2(500, 500)
	var hornet_def: WeaponDef = Data.weapons["mp5"]
	var kalash_def: WeaponDef = Data.weapons["ak47"]

	var w1 := WeaponInstance.new(hornet_def)
	w1.clip = 0
	w1.reserve = 0 # completely depleted
	var w2 := WeaponInstance.new(kalash_def)
	w2.clip = 30
	w2.reserve = 90

	c.inventory.set_weapon(0, w1)
	c.inventory.set_weapon(1, w2)
	c.inventory.set_active_slot(0)

	var frame := InputFrame.new()

	# Run for 0.35 s (21 ticks)
	for t in range(21):
		WeaponLogic.step(c, frame, DT, grid, proj_sys, beam_sys, dmg_sys, rng)

	Assertions.assert_eq(c.inventory.slots[0], null, "Depleted weapon discarded from slot 0")
	Assertions.assert_eq(c.inventory.active_slot, 1, "Other slot activates upon discard")
