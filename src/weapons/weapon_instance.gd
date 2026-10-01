# Implements §9.5 WeaponInstance: one held/dropped weapon with its ammo and §4.9 state.
class_name WeaponInstance
extends RefCounted

var def: WeaponDef
var clip: float = 0.0
var reserve: float = 0.0 # -1 = infinite
var state: int = Enums.WeaponState.IDLE
var state_t: float = 0.0
var bloom: float = 0.0
var bloom_deg: float = 0.0
var fire_buffer_t: float = 0.0
var emit_accum: float = 0.0
var flame_accum: float = 0.0
var warmup_t: float = 0.0
var beam_time: float = 0.0
var auto_reload_t: float = -1.0
var depletion_t: float = 0.0
var depleted_t: float = -1.0
var shell_reload_timer: float = 0.0
var reload_total_s: float = 0.0 # duration of the current reload, for HUD progress
var reload_elapsed_s: float = 0.0
var cycle_t: float = 0.0 # visual: time since the last shot (pump/bolt/recoil animation)
var flaming: bool = false # Blaze is currently emitting puffs (for flame_state_changed)

func _init(p_def: WeaponDef = null) -> void:
	def = p_def
	if def:
		clip = float(def.clip_size)
		reserve = float(def.spawn_reserve)

func has_infinite_reserve() -> bool:
	return def != null and (def.max_reserve == -1 or reserve < 0.0)

func is_depleted() -> bool:
	if def == null:
		return false
	if def.spawn_reserve == -1 or def.max_reserve == -1:
		return false
	return clip <= 0.0 and reserve <= 0.0

func ammo_total() -> float:
	if def == null:
		return 0.0
	if reserve == -1:
		return INF
	return clip + reserve

func can_reload() -> bool:
	return def != null and clip < float(def.clip_size) and (reserve > 0.0 or has_infinite_reserve())

func start_reload(owner_id: int = -1) -> void:
	if not def or not (reserve > 0.0 or has_infinite_reserve()):
		return
	state = Enums.WeaponState.RELOADING
	auto_reload_t = -1.0
	reload_elapsed_s = 0.0
	if def.reload_type == Enums.ReloadType.PER_SHELL:
		shell_reload_timer = 0.25 # initial delay
		var shells_needed := float(def.clip_size) - clip
		reload_total_s = 0.25 + def.shell_reload_s * shells_needed
	else:
		state_t = def.reload_s
		reload_total_s = def.reload_s
	EventBus.weapon_reload_started.emit(owner_id, def.id, reload_total_s)

func finish_reload(owner_id: int = -1) -> void:
	if not def: return
	if has_infinite_reserve():
		clip = float(def.clip_size)
	else:
		var needed := float(def.clip_size) - clip
		var take := minf(needed, reserve)
		clip += take
		reserve -= take
	EventBus.weapon_reload_finished.emit(owner_id, def.id)

## Switching away cancels a reload: magazine progress is lost, loaded shells are kept (§4.9).
func cancel_reload() -> void:
	if state == Enums.WeaponState.RELOADING:
		state = Enums.WeaponState.IDLE
		state_t = 0.0
		reload_elapsed_s = 0.0
