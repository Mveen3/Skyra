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
var burn_t: float = 0.0
var burn_tick_t: float = 0.0
var burn_source: int = -1
var inventory: Inventory = null
var stats: CombatStats = null
var streak: int = 0
var multi_kill_count: int = 0
var multi_kill_t: float = 0.0
var brain: RefCounted = null
var perception: Perception = null

func _init() -> void:
	inventory = Inventory.new()
	stats = CombatStats.new()

func aabb() -> Rect2:
	return Rect2(pos.x - 22.0, pos.y - height, 44.0, height)

func centre() -> Vector2:
	return pos + Vector2(0.0, -30.0 if crouching else -42.0)

func shoulder() -> Vector2:
	return pos + Vector2(0.0, -38.0 if crouching else -56.0)

func head_rect() -> Rect2:
	var head_h: float = 20.0 if crouching else 24.0
	return Rect2(pos.x - 22.0, pos.y - height, 44.0, head_h)
