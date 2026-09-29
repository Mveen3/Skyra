# Implements §4.4 Spread, bloom and recoil model.
class_name SpreadModel
extends RefCounted

static func calc_spread_deg(def: WeaponDef, bloom: float, vx: float, grounded: bool, crouching: bool) -> float:
	var moving: bool = absf(vx) > 60.0 # moving_threshold
	var base: float = def.spread_base_deg + bloom
	if moving:
		base += def.move_spread_add_deg
	if not grounded:
		base += def.air_spread_add_deg
	if crouching:
		base *= def.crouch_spread_mult
	return base

static func add_bloom(def: WeaponDef, current_bloom: float) -> float:
	return minf(def.max_bloom_deg, current_bloom + def.bloom_per_shot_deg)

static func decay_bloom(def: WeaponDef, current_bloom: float, dt: float) -> float:
	return maxf(0.0, current_bloom - def.bloom_recovery_dps * dt)

static func sample_shot_angle(aim_angle: float, spread_deg: float, rng: RandomNumberGenerator) -> float:
	if spread_deg <= 1e-4:
		return aim_angle
	var half_deg := spread_deg * 0.5
	var offset_deg := clampf(rng.randfn(0.0, half_deg), -spread_deg, spread_deg)
	return aim_angle + deg_to_rad(offset_deg)

static func sample_shotgun_pellet_angles(aim_angle: float, spread_deg: float, rng: RandomNumberGenerator, count: int = 8) -> Array[float]:
	var angles: Array[float] = []
	if count <= 1:
		angles.append(sample_shot_angle(aim_angle, spread_deg, rng))
		return angles

	# Evenly spaced across [-spread_deg, +spread_deg] with ±1.5° random jitter each
	var step_deg := (2.0 * spread_deg) / float(count - 1)
	for i in range(count):
		var base_offset := -spread_deg + float(i) * step_deg
		var jitter := rng.randf_range(-1.5, 1.5)
		var pellet_offset := base_offset + jitter
		angles.append(aim_angle + deg_to_rad(pellet_offset))
	return angles

static func crosshair_ring_radius_px(mouse_dist_px: float, spread_rad: float) -> float:
	return maxf(6.0, mouse_dist_px * tan(spread_rad))
