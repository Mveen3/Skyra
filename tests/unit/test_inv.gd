# Implements §10.3 / Table 10.7 Inventory unit tests (T-INV-01..06).
class_name TestInv
extends RefCounted

const DT: float = 1.0 / 60.0

func test_inv_01_slots() -> void:
	var c := CharacterState.new()
	var inv := c.inventory
	var magnum_def: WeaponDef = Data.weapons["magnum"]
	var hornet_def: WeaponDef = Data.weapons["mp5"]
	var kalash_def: WeaponDef = Data.weapons["ak47"]

	# Mini Post starts with 1 weapon (Magnum) in slot 0, slot 1 empty
	inv.set_weapon(0, WeaponInstance.new(magnum_def))
	Assertions.assert_eq(inv.slots.size(), 2, "Inventory has exactly 2 slots")
	Assertions.assert_eq(inv.slots[1], null, "Slot 1 starts empty")

	# Pick up second weapon -> fills slot 1 and activates it
	var loose: Array = []
	var ok := PickupResolver.try_pickup_weapon(c, hornet_def, 30, 120, c.pos, loose)
	Assertions.assert_true(ok, "Picked up second weapon")
	Assertions.assert_not_null(inv.slots[1], "Slot 1 filled")
	Assertions.assert_eq(inv.active_slot, 1, "Slot 1 activated")

	# Attempt to add 3rd weapon -> cannot have > 2 slots
	Assertions.assert_eq(inv.slots.size(), 2, "Slots remain exactly 2")

func test_inv_02_merge() -> void:
	var c := CharacterState.new()
	var inv := c.inventory
	var kalash_def: WeaponDef = Data.weapons["ak47"]

	var w := WeaponInstance.new(kalash_def)
	w.clip = 15
	w.reserve = 50 # max_reserve = 150
	inv.set_weapon(0, w)
	inv.set_active_slot(0)

	var loose: Array = []
	# Pick up another Kalash with clip 30, reserve 90 (total +120 ammo)
	var ok := PickupResolver.try_pickup_weapon(c, kalash_def, 30, 90, c.pos, loose)
	Assertions.assert_true(ok, "Kalash merged")
	Assertions.assert_eq(inv.slots[1], null, "No new slot created")
	Assertions.assert_eq(w.clip, 15, "Current clip untouched")
	Assertions.assert_eq(w.reserve, 150, "Reserve capped at max_reserve 150 (50 + 120 = 170 -> 150)")

func test_inv_03_swap() -> void:
	var c := CharacterState.new()
	var inv := c.inventory
	var hornet_def: WeaponDef = Data.weapons["mp5"]
	var kalash_def: WeaponDef = Data.weapons["ak47"]
	var bazooka_def: WeaponDef = Data.weapons["rocket_launcher"]

	var w0 := WeaponInstance.new(hornet_def)
	w0.clip = 12
	w0.reserve = 45
	var w1 := WeaponInstance.new(kalash_def)
	w1.clip = 25
	w1.reserve = 60

	inv.set_weapon(0, w0)
	inv.set_weapon(1, w1)
	inv.set_active_slot(0) # Hornet is active

	var loose: Array = []
	var item_pos := Vector2(100, 200)
	c.pos = item_pos
	var ok := PickupResolver.try_pickup_weapon(c, bazooka_def, 2, 6, item_pos, loose)
	Assertions.assert_true(ok, "Swapped active weapon with Bazooka")

	# Check loose weapon spawned at item_pos with exact ammo
	Assertions.assert_eq(loose.size(), 1, "1 loose weapon dropped")
	var dropped: LooseWeapon = loose[0]
	Assertions.assert_eq(dropped.def.id, "mp5", "Dropped weapon is Hornet")
	Assertions.assert_eq(dropped.clip, 12, "Dropped clip is 12")
	Assertions.assert_eq(dropped.reserve, 45, "Dropped reserve is 45")
	Assertions.assert_eq(dropped.pos, item_pos, "Dropped at item position")

	# Check active weapon is now Bazooka
	Assertions.assert_eq(inv.active_weapon().def.id, "rocket_launcher", "Active weapon is now Bazooka")
	Assertions.assert_eq(inv.active_weapon().clip, 2, "Bazooka clip is 2")

func test_inv_04_death_drop() -> void:
	var c := CharacterState.new()
	var inv := c.inventory
	var magnum_def: WeaponDef = Data.weapons["magnum"]
	var kalash_def: WeaponDef = Data.weapons["ak47"]

	# Case 1: Active weapon is Magnum -> never drops
	var w_mag := WeaponInstance.new(magnum_def)
	inv.set_weapon(0, w_mag)
	inv.set_active_slot(0)
	var dropped_mag := inv.get_death_drop(c.pos)
	Assertions.assert_eq(dropped_mag, null, "Magnum never drops on death")

	# Case 2: Active weapon is non-Magnum with ammo -> drops
	var w_ak := WeaponInstance.new(kalash_def)
	w_ak.clip = 20
	w_ak.reserve = 40
	inv.set_weapon(0, w_ak)
	inv.set_active_slot(0)
	var dropped_ak := inv.get_death_drop(c.pos)
	Assertions.assert_not_null(dropped_ak, "Kalash drops on death")
	Assertions.assert_eq(dropped_ak.clip, 20, "Dropped clip matches")
	Assertions.assert_eq(dropped_ak.reserve, 40, "Dropped reserve matches")

func test_inv_05_frag_pack() -> void:
	var c := CharacterState.new()
	var inv := c.inventory
	inv.grenades = 2
	inv.max_grenades = 4
	c.pos = Vector2(100, 100)

	# Auto-collected on touch
	var ok := PickupResolver.try_collect_frag_pack(c, Vector2(100, 100))
	Assertions.assert_true(ok, "Frag pack collected on touch")
	Assertions.assert_eq(inv.grenades, 4, "+2 frags added (2 -> 4)")

	# Cannot collect when at max
	var ok_max := PickupResolver.try_collect_frag_pack(c, Vector2(100, 100))
	Assertions.assert_false(ok_max, "Cannot collect frag pack when at max")
	Assertions.assert_eq(inv.grenades, 4, "Grenades remain 4")

func test_inv_06_loose_weapons() -> void:
	var loose_list: Array[LooseWeapon] = []

	# Despawn at 20 s
	var lw := LooseWeapon.new()
	lw.lifetime = 20.0
	lw.age = 19.9
	lw.step(0.2, TileGrid.new())
	Assertions.assert_false(lw.active, "Loose weapon despawns at 20 s")

	# Cap 12 (oldest removed first)
	for i in range(15):
		var item := LooseWeapon.new()
		item.id = i
		loose_list.append(item)
		if loose_list.size() > 12:
			loose_list.pop_front()

	Assertions.assert_eq(loose_list.size(), 12, "Cap 12 loose weapons maintained")
	Assertions.assert_eq(loose_list[0].id, 3, "Oldest items (0, 1, 2) removed first")
