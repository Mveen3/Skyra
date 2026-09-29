# Implements §4.10.3 Pickup resolution engine.
class_name PickupResolver
extends RefCounted

static func try_collect_frag_pack(c: CharacterState, item_pos: Vector2, item_size: Vector2 = Vector2(40, 40)) -> bool:
	if not c or c.life_state != Enums.LifeState.ALIVE:
		return false
	var inv: Inventory = c.inventory
	if not inv or inv.grenades >= inv.max_grenades:
		return false

	var item_box := Rect2(item_pos.x - item_size.x * 0.5, item_pos.y - item_size.y * 0.5, item_size.x, item_size.y)
	if c.aabb().intersects(item_box):
		inv.grenades = mini(inv.max_grenades, inv.grenades + 2)
		EventBus.frag_pack_collected.emit(c.id, 2)
		return true
	return false

static func try_pickup_weapon(c: CharacterState, item_def: WeaponDef, item_clip: int,
                             item_reserve: int, item_pos: Vector2,
                             loose_weapons: Array) -> bool:
	if not c or c.life_state != Enums.LifeState.ALIVE:
		return false
	var inv: Inventory = c.inventory
	if not inv:
		return false

	if c.centre().distance_to(item_pos) > 72.0:
		return false

	# 1. Merge check (same ID held in either slot)
	for i in range(2):
		var held: WeaponInstance = inv.slots[i]
		if held and held.def.id == item_def.id:
			if held.def.max_reserve != -1:
				held.reserve = mini(held.def.max_reserve, held.reserve + item_clip + item_reserve)
			EventBus.weapon_picked_up.emit(c.id, item_def.id, &"")
			return true

	# 2. Empty slot check
	var empty_idx := -1
	for i in range(2):
		if inv.slots[i] == null:
			empty_idx = i
			break

	if empty_idx != -1:
		var new_w := WeaponInstance.new(item_def)
		new_w.clip = item_clip
		new_w.reserve = item_reserve
		inv.set_weapon(empty_idx, new_w)
		inv.set_active_slot(empty_idx)
		EventBus.weapon_picked_up.emit(c.id, item_def.id, &"")
		return true

	# 3. Swap with active weapon
	var active_w: WeaponInstance = inv.active_weapon()
	if active_w:
		# Spawn loose weapon with dropped weapon's ammo
		var dropped := LooseWeapon.new()
		dropped.def = active_w.def
		dropped.clip = active_w.clip
		dropped.reserve = active_w.reserve
		dropped.pos = item_pos
		loose_weapons.append(dropped)

		# New weapon replaces active slot
		var new_w := WeaponInstance.new(item_def)
		new_w.clip = item_clip
		new_w.reserve = item_reserve
		new_w.state = Enums.WeaponState.SWITCHING
		new_w.state_t = item_def.switch_s
		inv.slots[inv.active_slot] = new_w
		EventBus.weapon_picked_up.emit(c.id, item_def.id)
		return true

	return false
