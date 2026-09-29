# Implements §9.5 WeaponInstance.
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

func _init(p_def: WeaponDef = null) -> void:
	def = p_def
	if def:
		clip = float(def.clip_size)
		reserve = float(def.spawn_reserve)

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

func start_reload() -> void:
	if not def or (reserve <= 0.0 and def.max_reserve != -1):
		return
	state = Enums.WeaponState.RELOADING
	if def.reload_type == Enums.ReloadType.PER_SHELL:
		shell_reload_timer = 0.25 # initial delay
	else:
		state_t = def.reload_s
	EventBus.weapon_reload_started.emit(-1, def.id, def.reload_s)

func finish_reload() -> void:
	if not def: return
	if def.max_reserve == -1:
		clip = float(def.clip_size)
	else:
		var needed := float(def.clip_size) - clip
		var take := minf(needed, reserve)
		clip += take
		reserve -= take
	EventBus.weapon_reload_finished.emit(-1, def.id)
