# Implements §4.10.3 Pickup resolution engine: Frag Pack touch pickup and the
# E-key take / merge / swap rules for weapon items within reach.
class_name PickupResolver
extends RefCounted

const PICKUP_REACH: float = 72.0

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

## Returns what pressing E on `item_def` would do: &"take", &"merge" or &"swap".
static func pickup_action(c: CharacterState, item_def: WeaponDef) -> StringName:
	var inv: Inventory = c.inventory
	for i in range(2):
		var held: WeaponInstance = inv.slots[i]
		if held and held.def.id == item_def.id:
			return &"merge"
	if inv.empty_slot() != -1:
		return &"take"
	return &"swap"

static func try_pickup_weapon(c: CharacterState, item_def: WeaponDef, item_clip: float,
                             item_reserve: float, item_pos: Vector2,
                             loose_weapons: Array, socket_id: StringName = &"") -> bool:
	if not c or c.life_state != Enums.LifeState.ALIVE:
		return false
	var inv: Inventory = c.inventory
	if not inv:
		return false

	if c.centre().distance_to(item_pos) > PICKUP_REACH:
		return false

	# 1. Merge check (same ID held in either slot): clip + reserve go to the reserve
	for i in range(2):
		var held: WeaponInstance = inv.slots[i]
		if held and held.def.id == item_def.id:
			if held.def.max_reserve != -1:
				held.reserve = minf(float(held.def.max_reserve), held.reserve + item_clip + item_reserve)
			EventBus.weapon_picked_up.emit(c.id, item_def.id, socket_id)
			return true

	# 2. Empty slot: put it there and make it active
	var empty_idx := inv.empty_slot()
	if empty_idx != -1:
		var new_w := WeaponInstance.new(item_def)
		new_w.clip = item_clip
		new_w.reserve = item_reserve
		inv.set_weapon(empty_idx, new_w)
		inv.set_active_slot(empty_idx, true)
		EventBus.weapon_picked_up.emit(c.id, item_def.id, socket_id)
		return true

	# 3. Swap: the active weapon drops at the item position with its exact ammo state
	var active_w: WeaponInstance = inv.active_weapon()
	if active_w:
		var dropped := LooseWeapon.new()
		dropped.def = active_w.def
		dropped.clip = active_w.clip
		dropped.reserve = active_w.reserve
		dropped.pos = item_pos
		dropped.prev_pos = item_pos
		dropped.facing = c.facing
		loose_weapons.append(dropped)
		EventBus.weapon_dropped.emit(c.id, active_w.def.id, item_pos)

		var new_w := WeaponInstance.new(item_def)
		new_w.clip = item_clip
		new_w.reserve = item_reserve
		new_w.state = Enums.WeaponState.SWITCHING
		new_w.state_t = item_def.switch_s
		inv.slots[inv.active_slot] = new_w
		EventBus.weapon_picked_up.emit(c.id, item_def.id, socket_id)
		return true

	return false
