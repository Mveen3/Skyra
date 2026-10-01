# Implements §4.8 Explosion model.
class_name ExplosionSystem
extends RefCounted

static func upward_biased_dir(centre: Vector2, target_pos: Vector2) -> Vector2:
	var diff := target_pos - centre
	var dir := diff.normalized() if diff.length_squared() > 1e-4 else Vector2.UP
	dir.y = minf(dir.y, -0.3)
	return dir.normalized()

static func is_eligible(owner_id: int, owner_team: int, c: CharacterState) -> bool:
	if not c or c.life_state != Enums.LifeState.ALIVE:
		return false
	if c.is_human and (c.stealth_t > 0.0 or c.invuln_t > 0.0):
		return false
	if owner_team == Enums.Team.BOT:
		return c.is_human
	else: # HUMAN
		return not c.is_human or c.id == owner_id

static func explode(centre: Vector2, radius: float, max_dmg: float, min_dmg: float,
                    kb: float, self_mult: float, owner_id: int, owner_team: int,
                    weapon_id: String, grid: TileGrid, characters: Array,
                    damage_system: DamageSystem, shot_id: int = -1) -> void:
	for obj in characters:
		var c: CharacterState = obj as CharacterState
		if not is_eligible(owner_id, owner_team, c):
			continue

		var c_aabb := c.aabb()
		var q: Vector2 = Shapes.closest_point_on_rect(centre, c_aabb)
		var d := centre.distance_to(q)
		if d > radius:
			continue

		# 3-probe exposure check
		var top_p := Vector2(c_aabb.position.x + c_aabb.size.x * 0.5, c_aabb.position.y + 4.0)
		var mid_p := c.centre()
		var bot_p := Vector2(c_aabb.position.x + c_aabb.size.x * 0.5, c_aabb.end.y - 4.0)
		var probes: Array[Vector2] = [top_p, mid_p, bot_p]

		var unblocked := 0
		for p in probes:
			var ray: Dictionary = grid.raycast(centre, p, C.MASK_LOS)
			if not bool(ray["hit"]) or float(ray["t"]) >= 0.999:
				unblocked += 1

		var exposure := float(unblocked) / 3.0
		if exposure <= 0.0:
			continue

		var frac := clampf(d / radius, 0.0, 1.0)
		var amount := lerpf(max_dmg, min_dmg, frac) * exposure
		var imp_dir := upward_biased_dir(centre, c.centre())

		damage_system.queue_damage(c, owner_id, owner_team, weapon_id, amount, centre, imp_dir, false, true, self_mult, shot_id)
		CharacterMotor.apply_impulse(c, imp_dir, kb * (1.0 - frac) * exposure)

	var evt := ExplosionEvent.new()
	evt.pos = centre
	evt.radius = radius
	evt.max_damage = max_dmg
	evt.min_damage = min_dmg
	evt.knockback = kb
	evt.self_mult = self_mult
	evt.weapon_id = weapon_id
	evt.owner_id = owner_id
	EventBus.explosion.emit(evt)
