# Implements §4.10 and §9.5 Inventory: exactly two weapon slots plus a grenade counter.
class_name Inventory
extends RefCounted

var owner_id: int = -1
var slots: Array[WeaponInstance] = [null, null]
var slot_1: WeaponInstance:
	get: return slots[0]
var slot_2: WeaponInstance:
	get: return slots[1]
var active_slot: int = 0
var grenades: int = 0
var frag_count: int:
	get: return grenades
	set(v): grenades = v
var max_grenades: int = 4
var grenade_cooldown_t: float = 0.0
var grenade_aiming: bool = false
var grenade_hold_t: float = 0.0

func get_weapon(idx: int) -> WeaponInstance:
	if idx >= 0 and idx < slots.size():
		return slots[idx]
	return null

func slot_count() -> int:
	var count := 0
	if slots[0] != null: count += 1
	if slots[1] != null: count += 1
	return count

func active_weapon() -> WeaponInstance:
	return slots[active_slot]

func other_weapon() -> WeaponInstance:
	var other_idx := 1 - active_slot
	return slots[other_idx]

func set_weapon(idx: int, w: WeaponInstance) -> void:
	if idx >= 0 and idx < 2:
		slots[idx] = w

## Makes `idx` the active slot and starts its SWITCHING state (§4.9). `force` re-arms the
## switch even when `idx` is already active (a weapon was just placed into that slot).
func set_active_slot(idx: int, force: bool = false) -> void:
	if idx < 0 or idx >= 2 or slots[idx] == null:
		return
	if idx == active_slot and not force:
		return
	var prev := slots[active_slot]
	var from_id: StringName = prev.def.id if (prev and prev != slots[idx]) else &""
	if prev and prev != slots[idx]:
		prev.cancel_reload()
	active_slot = idx
	var w := slots[active_slot]
	w.state = Enums.WeaponState.SWITCHING
	w.state_t = w.def.switch_s
	EventBus.weapon_switched.emit(owner_id, from_id, w.def.id)

func toggle_active() -> void:
	var other_idx := 1 - active_slot
	if slots[other_idx] != null:
		set_active_slot(other_idx)

## Removes the active weapon (drop or depletion) and activates the other slot if it holds one.
func drop_active() -> LooseWeapon:
	var w := active_weapon()
	if not w: return null
	var dropped := LooseWeapon.new()
	dropped.def = w.def
	dropped.clip = w.clip
	dropped.reserve = w.reserve
	slots[active_slot] = null

	var other_idx := 1 - active_slot
	if slots[other_idx] != null:
		set_active_slot(other_idx)
	return dropped

func get_death_drop(drop_pos: Vector2) -> LooseWeapon:
	var w := active_weapon()
	if not w or w.def.id == "magnum":
		return null
	if w.clip <= 0 and w.reserve <= 0:
		return null
	var dropped := LooseWeapon.new()
	dropped.def = w.def
	dropped.clip = w.clip
	dropped.reserve = w.reserve
	dropped.pos = drop_pos
	dropped.prev_pos = drop_pos
	return dropped

func empty_slot() -> int:
	if slots[0] == null: return 0
	if slots[1] == null: return 1
	return -1

func find(weapon_id: StringName) -> int:
	for i in range(slots.size()):
		if slots[i] != null and slots[i].def != null and slots[i].def.id == weapon_id:
			return i
	return -1

func clear() -> void:
	slots[0] = null
	slots[1] = null
	active_slot = 0
	grenades = 0
	grenade_cooldown_t = 0.0
	grenade_aiming = false
	grenade_hold_t = 0.0
