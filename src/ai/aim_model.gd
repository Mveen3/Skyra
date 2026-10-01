# Implements §5.6 Aiming and firing model: lead, error decay, wandering, and grenade solver.
class_name AimModel
extends RefCounted

var t_track: float = 0.0
var lost_los_t: float = 0.0
var aim_angle: float = 0.0
var wander_t: float = 0.0
var e_target: float = 0.0
var e_current: float = 0.0
var aim_head: bool = false
var aim_goal: float = 0.0 # desired angle + wandering error (§5.6); the fire gate compares against it

func reset() -> void:
	t_track = 0.0
	lost_los_t = 0.0
	wander_t = 0.0
	e_target = 0.0
	e_current = 0.0
	aim_head = false

static func calc_sigma_deg(t_track_s: float, human_speed: float, bot_airborne: bool,
                          dist: float, accuracy_mult: float, self_defence: bool) -> float:
	# Base tracking decay (§5.6, reaching <= 1.3 deg at 3.0 s)
	var base := 1.2 + (8.0 - 1.2) * exp(-t_track_s / 0.7)
	var add := (1.5 if human_speed > 350.0 else 0.0) + (1.5 if bot_airborne else 0.0) + 0.5 * maxf(0.0, (dist - 1500.0) / 1000.0)
	var s := (base + add) * accuracy_mult * (1.6 if self_defence else 1.0)
	return s

func update(bot: CharacterState, human: CharacterState, dt: float,
            sees_human: bool, self_defence: bool, rng: RandomNumberGenerator) -> float:
	if sees_human and human and human.life_state == Enums.LifeState.ALIVE and human.stealth_t <= 0.0:
		t_track += dt
		lost_los_t = 0.0
	else:
		lost_los_t += dt
		if lost_los_t > 0.5:
			t_track = 0.0

	var shoulder := bot.shoulder()
	var target_pos := human.centre() if human else (shoulder + Vector2.RIGHT * 300.0)
	var human_vel := human.vel if human else Vector2.ZERO
	var dist := shoulder.distance_to(target_pos)

	var active_w := bot.inventory.active_weapon() if bot.inventory else null
	var w_id: String = active_w.def.id if active_w else ""

	# Black Arrow headshot aim
	if w_id == "m93ba" and sees_human and human:
		if aim_head:
			target_pos = Vector2(human.pos.x, human.pos.y - human.height + 12.0)

	# Lead calculation
	var proj_speed := 3000.0
	var is_hitscan := (w_id == "phasr")
	if w_id == "blaze" or w_id == "flamethrower":
		proj_speed = 720.0
	elif w_id == "rocket_launcher":
		proj_speed = 1000.0
	elif active_w:
		proj_speed = float(active_w.def.speed)

	var lead_t := 0.0 if (is_hitscan or proj_speed <= 0.0) else (dist / proj_speed)
	var predicted := target_pos + human_vel * lead_t * 0.7
	var desired := (predicted - shoulder).angle()

	# Aim error wandering
	var acc_mult := bot.profile.accuracy_mult if bot.profile else 1.0
	var sigma_deg := calc_sigma_deg(t_track, human_vel.length(), not bot.grounded, dist, acc_mult, self_defence)
	var sigma_rad := deg_to_rad(sigma_deg)

	wander_t += dt
	if wander_t >= 0.35:
		wander_t -= 0.35
		var raw_err := rng.randfn(0.0, sigma_rad)
		e_target = clampf(raw_err, -2.0 * sigma_rad, 2.0 * sigma_rad)

	# Exponential smoothing (rate = 6.0)
	var blend := 1.0 - exp(-6.0 * dt)
	e_current = lerpf(e_current, e_target, blend)

	aim_goal = desired + e_current

	# Max turn rate: 300 deg/s for Black Arrow, 420 deg/s for others
	var max_turn_deg := 300.0 if (w_id == "m93ba") else 420.0
	var max_turn_rad := deg_to_rad(max_turn_deg)

	aim_angle = rotate_toward(aim_angle, aim_goal, max_turn_rad * dt)
	return aim_angle

static func solve_grenade_angle(origin: Vector2, target: Vector2, tile_grid: TileGrid) -> Dictionary:
	var v: float = 1150.0
	var g: float = 1800.0
	var dx: float = target.x - origin.x
	var dy: float = origin.y - target.y # positive when target is higher

	var abs_dx := absf(dx)
	if abs_dx < 10.0:
		return {"success": false, "angle": 0.0}

	var v2 := v * v
	var v4 := v2 * v2
	var disc := v4 - g * (g * abs_dx * abs_dx + 2.0 * dy * v2)

	var dir_x := 1.0 if dx >= 0.0 else -1.0
	var candidate_thetas: Array[float] = []

	if disc >= 0.0:
		var root_disc := sqrt(disc)
		candidate_thetas.append(atan((v2 - root_disc) / (g * abs_dx)))
		candidate_thetas.append(atan((v2 + root_disc) / (g * abs_dx)))
	
	# Extended bounce candidate angles for distances beyond direct ballistic range
	candidate_thetas.append(deg_to_rad(35.0))
	candidate_thetas.append(deg_to_rad(40.0))
	candidate_thetas.append(deg_to_rad(30.0))
	candidate_thetas.append(deg_to_rad(45.0))

	# Try candidate arcs
	for theta in candidate_thetas:
		var vx := v * cos(theta) * dir_x
		var vy := -v * sin(theta)

		# Simulate 3.0 s arc with bounces (§4.5.3: restitution 0.45, friction 0.80)
		var sim_pos := origin
		var sim_vel := Vector2(vx, vy)
		var dt := 1.0 / 60.0

		for _step in range(180): # 3.0 s
			var next_pos := sim_pos + sim_vel * dt
			sim_vel.y += g * dt
			var hit: Dictionary = tile_grid.raycast(sim_pos, next_pos, C.MASK_GRENADE)
			if bool(hit["hit"]):
				sim_pos = hit["point"] as Vector2
				var n: Vector2 = hit["normal"] as Vector2
				var vn: float = sim_vel.dot(n)
				if vn < 0.0:
					var vt := sim_vel - n * vn
					sim_vel = vt * 0.80 - n * (vn * 0.45)
					if sim_vel.length() < 40.0 and absf(n.y) > 0.7:
						sim_vel = Vector2.ZERO
			else:
				sim_pos = next_pos

			if sim_pos.distance_to(target) <= 120.0:
				var launch_angle := atan2(-v * sin(theta), v * cos(theta) * dir_x)
				return {"success": true, "angle": launch_angle}

	return {"success": false, "angle": 0.0}
