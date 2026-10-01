# Implements §4.5 Projectile data model.
class_name Projectile
extends RefCounted

enum Kind {
	BULLET,
	PELLET,
	SLUG,
	ROCKET,
	SAW_BLADE,
	FLAME_PUFF,
	GRENADE
}

var id: int = 0
var owner_id: int = -1
var owner_team: int = Enums.Team.BOT
var weapon_id: String = ""
var kind: int = Kind.BULLET

var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var accel: float = 0.0
var max_speed: float = 0.0
var radius: float = 0.0

var damage: float = 0.0
var headshot_mult: float = 1.0
var knockback: float = 0.0
var range_limit: float = 2000.0
var travelled: float = 0.0

var bounces_left: int = 0
var bounce_speed_mult: float = 1.0
var pierces_left: int = 0
var pierce_mult: float = 1.0
var pierce_damage_mult: float = 1.0

var falloff_start: float = 0.0
var falloff_end: float = 0.0
var falloff_min_mult: float = 1.0

var age: float = 0.0
var lifetime: float = 5.0
var fuse: float = 3.0
var armed: bool = false
var resting: bool = false

var hit_ids: Dictionary = {}
var last_hit_times: Dictionary = {}
var near_miss_checked: bool = false
var active: bool = false
var shot_id: int = -1 # owner's shot counter, for the accuracy stat
var armed_damage: float = 0.0 # Buzzsaw damage after its first bounce
var spin: float = 0.0 # visual rotation (saw blades, grenades)
var explosion: Dictionary = {}

func reset() -> void:
	id = 0
	owner_id = -1
	owner_team = Enums.Team.BOT
	weapon_id = ""
	kind = Kind.BULLET
	pos = Vector2.ZERO
	prev_pos = Vector2.ZERO
	vel = Vector2.ZERO
	dir = Vector2.RIGHT
	speed = 0.0
	accel = 0.0
	max_speed = 0.0
	radius = 0.0
	damage = 0.0
	headshot_mult = 1.0
	knockback = 0.0
	range_limit = 2000.0
	travelled = 0.0
	bounces_left = 0
	bounce_speed_mult = 1.0
	pierces_left = 0
	pierce_mult = 1.0
	pierce_damage_mult = 1.0
	falloff_start = 0.0
	falloff_end = 0.0
	falloff_min_mult = 1.0
	age = 0.0
	lifetime = 5.0
	fuse = 3.0
	armed = false
	resting = false
	hit_ids.clear()
	last_hit_times.clear()
	near_miss_checked = false
	active = false
	shot_id = -1
	armed_damage = 0.0
	spin = 0.0
	explosion = {}

func calc_falloff(d: float) -> float:
	if falloff_start <= 0.0 or falloff_end <= falloff_start:
		return 1.0
	if d <= falloff_start:
		return 1.0
	if d >= falloff_end:
		return falloff_min_mult
	var t := (d - falloff_start) / (falloff_end - falloff_start)
	return lerpf(1.0, falloff_min_mult, t)
