# Implements §3.2 and §9.5 CharacterState.
class_name CharacterState
extends RefCounted

var id: int = 0
var name: String = "Skyra"
var is_human: bool = true
var team: int = Enums.Team.HUMAN
var profile: BotProfile = null
var life_state: int = Enums.LifeState.ALIVE
var pos: Vector2 = Vector2.ZERO # feet anchor
var prev_pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var height: float = 84.0
var facing: int = 1
var aim_angle: float = 0.0
var aim_dir: Vector2 = Vector2.RIGHT
var grounded: bool = false
var ground_is_one_way: bool = false
var crouching: bool = false
var turning: bool = false
var hit_wall: bool = false
var drop_through_t: float = 0.0
var coyote_t: float = 0.0
var jump_buffer_t: float = 0.0
var since_jump_t: float = 99.0
var jet_active: bool = false
var jet_locked: bool = false
var fuel: float = 100.0
var recharge_delay_t: float = 0.0
var in_updraft: bool = false
var health: float = 100.0
var regen_delay_t: float = 0.0
var last_enemy_damager: int = -1
var last_enemy_damage_time: float = -99.0
var respawn_t: float = 0.0
var stealth_t: float = 0.0
var invuln_t: float = 0.0
var boost_t: float = 0.0
var launch_t: float = 0.0 # launch-pad flight: rise caps are suspended while > 0
var burn_t: float = 0.0
var burn_tick_t: float = 0.0
var burn_source: int = -1
var inventory: Inventory = null
var stats: CombatStats = null
var streak: int = 0
var multi_kill_count: int = 0
var multi_kill_t: float = 0.0
## The BotBrain driving this character, held weakly: the brain references its
## character, so a strong link both ways would leak every finished match. The owner
## (MatchSim.brains, the Autopilot, or a test) keeps the brain alive.
var brain: RefCounted:
	get:
		return _brain_ref.get_ref() as RefCounted if _brain_ref else null
	set(value):
		_brain_ref = weakref(value) if value else null
var _brain_ref: WeakRef = null
var perception: Perception = null
var death_pos: Vector2 = Vector2(-99999.0, -99999.0)
var landing_speed: float = 0.0
var spawn_count: int = 0

func _init() -> void:
	inventory = Inventory.new()
	stats = CombatStats.new()

## Clears every transient per-life field and places the character at `spawn_pos` (§3.13).
func reset_for_spawn(spawn_pos: Vector2) -> void:
	life_state = Enums.LifeState.ALIVE
	pos = spawn_pos
	prev_pos = spawn_pos
	vel = Vector2.ZERO
	height = 84.0
	crouching = false
	turning = false
	grounded = false
	ground_is_one_way = false
	hit_wall = false
	drop_through_t = 0.0
	coyote_t = 0.0
	jump_buffer_t = 0.0
	since_jump_t = 99.0
	jet_active = false
	jet_locked = false
	fuel = 100.0
	recharge_delay_t = 0.0
	in_updraft = false
	health = 100.0
	regen_delay_t = 0.0
	last_enemy_damager = -1
	last_enemy_damage_time = -99.0
	respawn_t = 0.0
	stealth_t = 0.0
	launch_t = 0.0
	invuln_t = 0.0
	boost_t = 0.0
	burn_t = 0.0
	burn_tick_t = 0.0
	burn_source = -1
	landing_speed = 0.0
	spawn_count += 1

func aabb() -> Rect2:
	return Rect2(pos.x - 22.0, pos.y - height, 44.0, height)

func centre() -> Vector2:
	return pos + Vector2(0.0, -30.0 if crouching else -42.0)

func shoulder() -> Vector2:
	return pos + Vector2(0.0, -38.0 if crouching else -56.0)

func head_rect() -> Rect2:
	var head_h: float = 20.0 if crouching else 24.0
	return Rect2(pos.x - 22.0, pos.y - height, 44.0, head_h)
