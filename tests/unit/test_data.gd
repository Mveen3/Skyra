# Implements §10.4 T-DATA-01 and T-DATA-02.
class_name TestData
extends RefCounted

func test_data_01_load_all() -> void:
	var success := Data.load_all()
	Assertions.assert_true(success, "Data.load_all() should succeed")
	Assertions.assert_true(Data.errors.is_empty(), "Data.errors should be empty, got: " + str(Data.errors))

func test_data_02_transcription_spot_check() -> void:
	var ak47: WeaponDef = Data.weapons.get(&"ak47")
	Assertions.assert_true(ak47 != null, "ak47 def exists")
	if ak47:
		Assertions.assert_eq(ak47.damage, 16.0, "ak47.damage == 16")
		Assertions.assert_eq(ak47.fire_interval_s, 0.11, "ak47.fire_interval_s == 0.11")

	var m93ba: WeaponDef = Data.weapons.get(&"m93ba")
	Assertions.assert_true(m93ba != null, "m93ba def exists")
	if m93ba:
		Assertions.assert_eq(m93ba.scope, 5.0, "m93ba.scope == 5.0")

	var magnum: WeaponDef = Data.weapons.get(&"magnum")
	Assertions.assert_true(magnum != null, "magnum def exists")
	if magnum:
		Assertions.assert_eq(magnum.spawn_reserve, -1, "magnum.spawn_reserve == -1")

	var phasr: WeaponDef = Data.weapons.get(&"phasr")
	Assertions.assert_true(phasr != null, "phasr def exists")
	if phasr:
		Assertions.assert_eq(phasr.ammo_per_second, 25.0, "phasr.ammo_per_second == 25")

	var saw_gun: WeaponDef = Data.weapons.get(&"saw_gun")
	Assertions.assert_true(saw_gun != null, "saw_gun def exists")
	if saw_gun:
		Assertions.assert_eq(saw_gun.special.get("armed_damage", 0), 45, "saw_gun.special.armed_damage == 45")

	var shotgun: WeaponDef = Data.weapons.get(&"shotgun")
	Assertions.assert_true(shotgun != null, "shotgun def exists")
	if shotgun:
		Assertions.assert_eq(shotgun.pellets, 8, "shotgun.pellets == 8")

	var rlaunch: WeaponDef = Data.weapons.get(&"rocket_launcher")
	Assertions.assert_true(rlaunch != null, "rocket_launcher def exists")
	if rlaunch:
		var expl: Dictionary = rlaunch.special.get("explosion", {})
		Assertions.assert_eq(expl.get("radius", 0), 220, "rocket_launcher.special.explosion.radius == 220")

	var gren: GrenadeDef = Data.grenade
	Assertions.assert_true(gren != null, "grenade def exists")
	if gren:
		Assertions.assert_eq(gren.fuse_s, 3.0, "grenade.fuse_s == 3.0")

	Assertions.assert_eq(Data.tuning.jetpack.fuel_burn_per_s, 28, "tuning.jetpack.fuel_burn_per_s == 28")
	Assertions.assert_eq(Data.tuning.respawn.human_delay_s, 2.0, "tuning.respawn.human_delay_s == 2.0")
	Assertions.assert_eq(Data.tuning.respawn.human_stealth_s, 2.0, "tuning.respawn.human_stealth_s == 2.0")
	Assertions.assert_eq(Data.tuning.rocket_boost.first_spawn_s, 45.0, "tuning.rocket_boost.first_spawn_s == 45")

	Assertions.assert_eq(Data.modes.mini_post.drop_weights.mp5, 16, "modes.mini_post.drop_weights.mp5 == 16")
	Assertions.assert_eq(Data.modes.sniper_post.spawn_loadout.slot_1, "m93ba", "modes.sniper_post.spawn_loadout.slot_1 == m93ba")

	Assertions.assert_true(Data.bots.size() >= 7, "bots count >= 7")
	if Data.bots.size() >= 7:
		Assertions.assert_eq(Data.bots[0].name, "Alpha", "bots[0].name == Alpha")
		Assertions.assert_eq(Data.bots[6].name, "Chi", "bots[6].name == Chi")

	Assertions.assert_true(Data.map != null, "map loaded")
	if Data.map:
		Assertions.assert_eq(Data.map.width, 120, "map.width == 120")
