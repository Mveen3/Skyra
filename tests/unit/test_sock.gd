# Implements §10.3 / Table 10.8 Weapon socket unit tests (T-SOCK-01..03).
class_name TestSock
extends RefCounted

const DT: float = 1.0 / 60.0

func test_sock_01_drop_table() -> void:
	var mode_data: Dictionary = Data.modes["mini_post"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 334455

	var expected_probs := {
		"ridge": {
			"mp5": 0.126, "ak47": 0.190, "shotgun": 0.051, "m93ba": 0.197,
			"flamethrower": 0.027, "phasr": 0.142, "rocket_launcher": 0.059,
			"saw_gun": 0.079, "frag_pack": 0.128
		},
		"mid": {
			"mp5": 0.154, "ak47": 0.154, "shotgun": 0.125, "m93ba": 0.077,
			"flamethrower": 0.087, "phasr": 0.087, "rocket_launcher": 0.075,
			"saw_gun": 0.116, "frag_pack": 0.125
		},
		"bunker": {
			"mp5": 0.177, "ak47": 0.114, "shotgun": 0.227, "m93ba": 0.016,
			"flamethrower": 0.157, "phasr": 0.043, "rocket_launcher": 0.024,
			"saw_gun": 0.119, "frag_pack": 0.124
		}
	}

	for tag in ["ridge", "mid", "bunker"]:
		var counts := {}
		var last_item := ""
		var n := 20000
		var immediate_repeats := 0

		for i in range(n):
			var item := WeaponSocketManager.roll_item(tag, "", {}, mode_data, rng, false)
			counts[item] = counts.get(item, 0) + 1

		var test_last := ""
		for i in range(2000):
			var item := WeaponSocketManager.roll_item(tag, test_last, {}, mode_data, rng, false)
			if item == test_last and not test_last.is_empty():
				immediate_repeats += 1
			test_last = item

		Assertions.assert_eq(immediate_repeats, 0, "No immediate repeats for tag %s" % tag)

		var tag_expected: Dictionary = expected_probs[tag]
		for item_id in tag_expected.keys():
			var freq := float(counts.get(item_id, 0)) / float(n)
			var exp_p: float = tag_expected[item_id]
			var diff := absf(freq - exp_p)
			# Frequencies within ±1.5% (absolute)
			Assertions.assert_true(diff <= 0.015, "Tag %s item %s freq %.3f within ±1.5%% of %.3f (diff: %.4f)" % [tag, item_id, freq, exp_p, diff])

func test_sock_02_caps() -> void:
	var mgr := WeaponSocketManager.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 667788
	mgr.init_sockets(Data.map, "mini_post", rng)

	# 30 simulated minutes of churn (1800 simulated seconds)
	# At each 1-second step, simulate players picking up items occasionally
	var violated_caps := false
	var max_bazooka := 0
	var max_black_arrow := 0

	for sec in range(1800):
		# Random pickups: each available socket has 5% chance of being collected
		for s in mgr.sockets:
			if s.is_available and rng.randf() < 0.05:
				s.is_available = false
				s.respawn_timer = 15.0

		# Step socket manager by 1.0 s
		mgr.step(1.0, [], rng)

		# Check caps
		var counts := mgr.count_items_on_sockets()
		var bazookas: int = counts.get("rocket_launcher", 0)
		var black_arrows: int = counts.get("m93ba", 0)

		max_bazooka = maxi(max_bazooka, bazookas)
		max_black_arrow = maxi(max_black_arrow, black_arrows)

		if bazookas > 1 or black_arrows > 2:
			violated_caps = true
			break

	Assertions.assert_false(violated_caps, "Caps never exceeded: Bazooka <= 1 (max %d), Black Arrow <= 2 (max %d)" % [max_bazooka, max_black_arrow])

func test_sock_03_timers_and_sniper_table() -> void:
	var mini_mode: Dictionary = Data.modes["mini_post"]
	var sniper_mode: Dictionary = Data.modes["sniper_post"]

	Assertions.assert_eq(mini_mode.get("socket_respawn_s"), 15.0, "Mini Post respawn is 15.0 s")
	Assertions.assert_eq(sniper_mode.get("socket_respawn_s"), 10.0, "Sniper Post respawn is 10.0 s")

	# Sniper Post only yields m93ba and frag_pack
	var rng := RandomNumberGenerator.new()
	rng.seed = 112233
	for i in range(1000):
		var item := WeaponSocketManager.roll_item("mid", "", {}, sniper_mode, rng, true)
		Assertions.assert_true(item == "m93ba" or item == "frag_pack", "Sniper post roll %d was %s" % [i, item])
