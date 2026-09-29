# Implements §5.5 Perception model: vision, hearing, memory, and stealth handling.
class_name Perception
extends RefCounted

var bot_id: int = 0
var bot_team: int = Enums.Team.BOT
var last_known_pos: Vector2 = Vector2(-9999, -9999)
var last_seen_time: float = -999.0
var sees_human: bool = false
var reaction_t: float = 0.0
var recently_seen: bool = false

func _init(id: int = 0) -> void:
	bot_id = id

func clear_memory() -> void:
	last_known_pos = Vector2(-9999, -9999)
	last_seen_time = -999.0
	sees_human = false
	reaction_t = 0.0
	recently_seen = false

func has_known_target(now: float) -> bool:
	return (now - last_seen_time) <= 8.0 and last_known_pos.x > -9000

func get_hearing_radius(weapon_id: String) -> float:
	match weapon_id:
		"m93ba", "rocket_launcher", "frag_grenade":
			return 2600.0
		"blaze", "phasr", "flamethrower":
			return 1200.0
		_:
			return 1800.0

func on_sound_heard(sound_pos: Vector2, weapon_id: String, now: float, rng: RandomNumberGenerator, human_stealthed: bool) -> void:
	if human_stealthed:
		return
	var r := get_hearing_radius(weapon_id)
	if sound_pos.distance_to(last_known_pos) <= r or sound_pos.distance_to(sound_pos) <= r:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(0.0, 150.0)
		last_known_pos = sound_pos + Vector2(cos(angle), sin(angle)) * dist
		last_seen_time = now

func update(bot: CharacterState, human: CharacterState, tile_grid: TileGrid, now: float, rng: RandomNumberGenerator) -> void:
	if not human or human.life_state != Enums.LifeState.ALIVE or human.stealth_t > 0.0:
		clear_memory()
		return

	# Forget after 8.0 s
	if (now - last_seen_time) > 8.0:
		last_known_pos = Vector2(-9999, -9999)

	var active_w := bot.inventory.active_weapon() if bot.inventory else null
	var scope: float = active_w.def.scope if active_w else 1.0
	var vis_radius := 1400.0 * sqrt(scope)

	var dx := human.pos.x - bot.pos.x
	if signf(dx) != float(bot.facing) and absf(dx) > 1.0:
		vis_radius *= 0.6 # Rear penalty

	var dist := bot.pos.distance_to(human.pos)
	if dist > vis_radius:
		sees_human = false
		return

	# 3 LOS rays from bot's shoulder: head, centre, feet
	var shoulder := bot.shoulder()
	var head_target := Vector2(human.pos.x, human.pos.y - human.height + 12.0)
	var centre_target := human.centre()
	var feet_target := Vector2(human.pos.x, human.pos.y - 10.0)

	var r1: Dictionary = tile_grid.raycast(shoulder, head_target, C.MASK_LOS)
	var r2: Dictionary = tile_grid.raycast(shoulder, centre_target, C.MASK_LOS)
	var r3: Dictionary = tile_grid.raycast(shoulder, feet_target, C.MASK_LOS)

	var can_see: bool = (not bool(r1["hit"]) or not bool(r2["hit"]) or not bool(r3["hit"]))
	if can_see:
		if not sees_human:
			# Just acquired sight
			var react_mult := bot.profile.reaction_mult if bot.profile else 1.0
			if recently_seen:
				reaction_t = 0.12 * react_mult
			else:
				reaction_t = rng.randf_range(0.27, 0.43) * react_mult
		sees_human = true
		last_known_pos = human.pos
		last_seen_time = now
		recently_seen = true
	else:
		sees_human = false
		if (now - last_seen_time) > 1.5:
			recently_seen = false
