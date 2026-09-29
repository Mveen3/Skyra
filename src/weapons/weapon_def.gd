# Implements §9.5 WeaponDef and §4.2 Weapon parameter matrix.
class_name WeaponDef
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var hud_name: String = ""
var say: String = ""
var basis: String = ""
var weapon_class: int = 0
var fire_mode: int = 0
var delivery: int = 0
var projectile_kind: int = 0
var damage: float = 0.0
var pellets: int = 1
var headshot_mult: float = 1.0
var fire_interval_s: float = 0.1
var clip_size: int = 1
var spawn_reserve: int = 0
var max_reserve: int = 0
var reload_type: int = 0
var reload_s: float = 1.0
var shell_reload_s: float = 0.0
var ammo_per_second: float = 0.0
var speed: float = 0.0
var max_speed: float = 0.0
var accel: float = 0.0
var gravity: float = 0.0
var max_range: float = 0.0
var radius: float = 0.0
var pierce_count: int = 0
var pierce_damage_mult: float = 1.0
var bounces: int = 0
var bounce_speed_mult: float = 1.0
var falloff_start: float = 0.0
var falloff_end: float = 0.0
var falloff_min_mult: float = 1.0
var spread_base_deg: float = 0.0
var bloom_per_shot_deg: float = 0.0
var max_bloom_deg: float = 0.0
var bloom_recovery_dps: float = 0.0
var move_spread_add_deg: float = 0.0
var air_spread_add_deg: float = 0.0
var crouch_spread_mult: float = 1.0
var knockback: float = 0.0
var scope: float = 1.0
var switch_s: float = 0.2
var camera_trauma: float = 0.0
var recoil_kick_wu: float = 0.0
var laser_sight: bool = false
var special: Dictionary = {}
var bot_range_min: float = 0.0
var bot_range_max: float = 0.0
var bot_fire_gate_deg: float = 0.0
var bot_burst_min: int = 1
var bot_burst_max: int = 1
var bot_pause_min_s: float = 0.0
var bot_pause_max_s: float = 0.0
var bot_pause_min: float:
	get: return bot_pause_min_s
	set(v): bot_pause_min_s = v
var bot_pause_max: float:
	get: return bot_pause_max_s
	set(v): bot_pause_max_s = v
var bot_value_mini: float = 0.0
var bot_value_sniper: float = 0.0

func falloff(distance: float) -> float:
	if distance <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return falloff_min_mult
	var span: float = falloff_end - falloff_start
	if span <= 0.0001:
		return falloff_min_mult
	var t: float = (distance - falloff_start) / span
	return lerp(1.0, falloff_min_mult, t)
