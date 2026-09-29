# Implements §4.5 Projectile System (capacity 512, straight-line, rocket, circle movers).
class_name ProjectileSystem
extends RefCounted

const MAX_PROJECTILES: int = 512

var pool: Array[Projectile] = []
var active_projectiles: Array[Projectile] = []
var projectiles: Array[Projectile]:
	get: return active_projectiles
var next_id: int = 1

func _init() -> void:
	for i in range(MAX_PROJECTILES):
		pool.append(Projectile.new())

func _alloc() -> Projectile:
	var p: Projectile = null
	if not pool.is_empty():
		p = pool.pop_back()
	else:
		# Recycle oldest non-grenade projectile
		for i in range(active_projectiles.size()):
			if active_projectiles[i].kind != Projectile.Kind.GRENADE:
				p = active_projectiles[i]
				active_projectiles.remove_at(i)
				p.reset()
				break
		if not p and not active_projectiles.is_empty():
			p = active_projectiles.pop_front()
			p.reset()
		elif not p:
			p = Projectile.new()

	p.reset()
	p.id = next_id
	next_id += 1
	p.active = true
	active_projectiles.append(p)
	return p

func _despawn(p: Projectile) -> void:
	p.active = false
	active_projectiles.erase(p)
	p.reset()
	if pool.size() < MAX_PROJECTILES:
		pool.append(p)

static func is_headshot(c: CharacterState, hit_y: float) -> bool:
	var head_h := 20.0 if c.crouching else 24.0
	var top_y := c.pos.y - c.height
	return hit_y >= top_y and hit_y <= top_y + head_h

static func is_eligible(owner_id: int, owner_team: int, c: CharacterState) -> bool:
	if not c or c.life_state != Enums.LifeState.ALIVE:
		return false
	if c.id == owner_id:
		return false
	if c.is_human and (c.stealth_t > 0.0 or c.invuln_t > 0.0):
		return false
	if owner_team == Enums.Team.BOT:
		return c.is_human
	else:
		return not c.is_human

static func check_muzzle_occlusion(shoulder: Vector2, muzzle: Vector2, grid: TileGrid) -> Dictionary:
	return grid.raycast(shoulder, muzzle, C.MASK_PROJECTILE)

func spawn_bullet(owner_id: int, owner_team: int, def: WeaponDef, start_pos: Vector2, angle: float) -> Projectile:
	var p := _alloc()
	p.owner_id = owner_id
	p.owner_team = owner_team
	p.weapon_id = def.id
	
	if def.id == "shotgun":
		p.kind = Projectile.Kind.PELLET
	elif def.id == "m93ba":
		p.kind = Projectile.Kind.SLUG
	else:
		p.kind = Projectile.Kind.BULLET

	p.pos = start_pos
	p.prev_pos = start_pos
	p.dir = Vector2(cos(angle), sin(angle)).normalized()
	p.speed = def.speed
	p.vel = p.dir * p.speed
	p.damage = def.damage
	p.headshot_mult = def.headshot_mult
	p.knockback = def.knockback
	p.range_limit = def.max_range
	p.pierces_left = def.pierce_count
	p.pierce_damage_mult = def.pierce_damage_mult
	p.falloff_start = def.falloff_start
	p.falloff_end = def.falloff_end
	p.falloff_min_mult = def.falloff_min_mult
	return p

func spawn_rocket(owner_id: int, owner_team: int, def: WeaponDef, start_pos: Vector2, angle: float) -> Projectile:
	var p := _alloc()
	p.owner_id = owner_id
	p.owner_team = owner_team
	p.weapon_id = def.id
	p.kind = Projectile.Kind.ROCKET
	p.pos = start_pos
	p.prev_pos = start_pos
	p.dir = Vector2(cos(angle), sin(angle)).normalized()
	p.speed = def.speed
	p.vel = p.dir * p.speed
	p.accel = def.accel
	p.max_speed = def.max_speed
	p.radius = 8.0
	p.damage = def.damage # direct hit bonus 25
	p.range_limit = def.max_range
	p.lifetime = 3.0
	return p

func spawn_saw(owner_id: int, owner_team: int, def: WeaponDef, start_pos: Vector2, angle: float) -> Projectile:
	var p := _alloc()
	p.owner_id = owner_id
	p.owner_team = owner_team
	p.weapon_id = def.id
	p.kind = Projectile.Kind.SAW_BLADE
	p.pos = start_pos
	p.prev_pos = start_pos
	p.dir = Vector2(cos(angle), sin(angle)).normalized()
	p.speed = def.speed
	p.vel = p.dir * p.speed
	p.radius = 14.0
	p.damage = def.damage # 20 un-armed, 45 armed
	p.knockback = def.knockback # 60
	p.bounces_left = def.bounces # 4
	p.bounce_speed_mult = def.bounce_speed_mult # 0.95
	p.pierces_left = def.pierce_count # 2
	p.lifetime = 2.2
	p.armed = false
	return p

func spawn_grenade(owner_id: int, owner_team: int, start_pos: Vector2, init_vel: Vector2) -> Projectile:
	var p := _alloc()
	p.owner_id = owner_id
	p.owner_team = owner_team
	p.weapon_id = "frag_grenade"
	p.kind = Projectile.Kind.GRENADE
	p.pos = start_pos
	p.prev_pos = start_pos
	p.vel = init_vel
	p.radius = 8.0
	p.fuse = 3.0
	p.lifetime = 5.0
	return p

func spawn_flame_puff(owner_id: int, owner_team: int, start_pos: Vector2, dir_angle: float, shooter_vel: Vector2) -> Projectile:
	var p := _alloc()
	p.owner_id = owner_id
	p.owner_team = owner_team
	p.weapon_id = "flamethrower"
	p.kind = Projectile.Kind.FLAME_PUFF
	p.pos = start_pos
	p.prev_pos = start_pos
	var d := Vector2(cos(dir_angle), sin(dir_angle)).normalized()
	p.dir = d
	p.speed = 720.0
	p.vel = d * p.speed + shooter_vel * 0.3
	p.radius = 10.0
	p.damage = 3.0
	p.lifetime = 0.52
	return p

func step(dt: float, grid: TileGrid, characters: Array, damage_system: DamageSystem, now: float) -> void:
	var to_process := active_projectiles.duplicate()

	for p in to_process:
		if not p.active:
			continue

		p.age += dt

		match p.kind:
			Projectile.Kind.BULLET, Projectile.Kind.PELLET, Projectile.Kind.SLUG:
				_step_straight(p, dt, grid, characters, damage_system)
			Projectile.Kind.ROCKET:
				_step_rocket(p, dt, grid, characters, damage_system)
			Projectile.Kind.GRENADE, Projectile.Kind.SAW_BLADE, Projectile.Kind.FLAME_PUFF:
				_step_circle(p, dt, grid, characters, damage_system, now)

func _step_straight(p: Projectile, dt: float, grid: TileGrid, characters: Array, damage_system: DamageSystem) -> void:
	p.prev_pos = p.pos
	var step_dist := p.speed * dt
	var remaining := p.range_limit - p.travelled
	var expire := false
	if step_dist >= remaining:
		step_dist = remaining
		expire = true

	var seg_end := p.pos + p.dir * step_dist
	var wall: Dictionary = grid.raycast(p.pos, seg_end, C.MASK_PROJECTILE)
	var limit_t: float = float(wall["t"]) if bool(wall["hit"]) else 1.0

	# Find all character hits
	var hits: Array[Dictionary] = []
	for obj in characters:
		var c: CharacterState = obj as CharacterState
		if not is_eligible(p.owner_id, p.owner_team, c):
			continue
		if p.hit_ids.has(c.id):
			continue
		var h: Dictionary = Shapes.segment_intersects_rect(p.pos, seg_end, c.aabb())
		if bool(h["hit"]) and float(h["t"]) <= limit_t:
			hits.append({"t": float(h["t"]), "char": c, "point": h["point"]})

	# Sort hits by t with deterministic tie-break
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var t_a: float = float(a["t"])
		var t_b: float = float(b["t"])
		if not is_equal_approx(t_a, t_b):
			return t_a < t_b
		return (a["char"] as CharacterState).id < (b["char"] as CharacterState).id
	)

	for hit_info in hits:
		var c: CharacterState = hit_info["char"]
		var point: Vector2 = hit_info["point"]
		var t_val: float = hit_info["t"]

		var d := p.travelled + t_val * step_dist
		var hs := (p.kind != Projectile.Kind.PELLET) and is_headshot(c, point.y)
		var hs_mult := p.headshot_mult if hs else 1.0
		var amount := p.damage * p.calc_falloff(d) * hs_mult * p.pierce_mult

		damage_system.queue_damage(c, p.owner_id, p.owner_team, p.weapon_id, amount, point, p.dir, hs)
		CharacterMotor.apply_impulse(c, p.dir, p.knockback)
		p.hit_ids[c.id] = true

		if p.pierces_left > 0:
			p.pierces_left -= 1
			p.pierce_mult *= p.pierce_damage_mult
			continue
		else:
			_despawn(p)
			return

	if wall.hit:
		_despawn(p)
		return

	p.travelled += step_dist
	p.pos = seg_end

	# Near miss check (bot-owned only)
	if p.owner_team == Enums.Team.BOT and not p.near_miss_checked:
		for obj in characters:
			var c: CharacterState = obj as CharacterState
			if c and c.is_human and not p.hit_ids.has(c.id):
				var q: Vector2 = Shapes.closest_point_on_segment(c.centre(), p.prev_pos, p.pos)
				if c.centre().distance_to(q) < 64.0:
					p.near_miss_checked = true
					EventBus.near_miss.emit(c.id, p.pos)
					break

	if expire:
		_despawn(p)

func _step_rocket(p: Projectile, dt: float, grid: TileGrid, characters: Array, damage_system: DamageSystem) -> void:
	p.prev_pos = p.pos
	p.speed = minf(p.max_speed, p.speed + p.accel * dt)
	p.vel = p.dir * p.speed
	var seg_end := p.pos + p.vel * dt

	if p.age >= p.lifetime:
		_detonate_rocket(p, p.pos, null, grid, characters, damage_system)
		return

	var wall: Dictionary = grid.raycast(p.pos, seg_end, C.MASK_PROJECTILE)
	var limit_t: float = float(wall["t"]) if bool(wall["hit"]) else 1.0

	var nearest_t: float = limit_t
	var hit_char: CharacterState = null
	var hit_pt: Vector2 = wall["point"] if bool(wall["hit"]) else seg_end

	for obj in characters:
		var c: CharacterState = obj as CharacterState
		if not is_eligible(p.owner_id, p.owner_team, c):
			continue
		var inflated: Rect2 = c.aabb().grow(p.radius)
		var h: Dictionary = Shapes.segment_intersects_rect(p.pos, seg_end, inflated)
		if bool(h["hit"]) and float(h["t"]) < nearest_t:
			nearest_t = float(h["t"])
			hit_char = c
			hit_pt = h["point"]

	if nearest_t < 1.0:
		_detonate_rocket(p, hit_pt, hit_char, grid, characters, damage_system)
	else:
		p.pos = seg_end

func _detonate_rocket(p: Projectile, centre: Vector2, hit_char: CharacterState, grid: TileGrid, characters: Array, damage_system: DamageSystem) -> void:
	if hit_char:
		# Direct hit bonus +25
		damage_system.queue_damage(hit_char, p.owner_id, p.owner_team, p.weapon_id, 25.0, centre, p.dir)

	ExplosionSystem.explode(centre, 220.0, 110.0, 20.0, 950.0, 0.5, p.owner_id, p.owner_team, p.weapon_id, grid, characters, damage_system)
	_despawn(p)

func _step_circle(p: Projectile, dt: float, grid: TileGrid, characters: Array, damage_system: DamageSystem, now: float) -> void:
	var vel_len := p.vel.length()
	var substeps := maxi(1, int(ceil(vel_len * dt / maxf(8.0, p.radius))))
	var sdt := dt / float(substeps)

	for s in range(substeps):
		p.prev_pos = p.pos

		# Updraft check
		var in_updraft := grid.is_updraft(p.pos)

		match p.kind:
			Projectile.Kind.GRENADE:
				var ay := -1200.0 if in_updraft else 1800.0
				p.vel.y += ay * sdt
			Projectile.Kind.FLAME_PUFF:
				var ay := -600.0 if in_updraft else -200.0
				p.vel.y += ay * sdt
				p.vel *= exp(-1.8 * sdt)
			Projectile.Kind.SAW_BLADE:
				pass

		p.pos += p.vel * sdt

		# Collision with terrain
		var circle_box := Rect2(p.pos.x - p.radius, p.pos.y - p.radius, p.radius * 2.0, p.radius * 2.0)
		var solid_rects := grid.solid_rects_in(circle_box, false)

		if p.kind == Projectile.Kind.GRENADE and p.vel.y > 0.0:
			var ow_rects := grid.one_way_rects_in(circle_box)
			for ow in ow_rects:
				if p.prev_pos.y + p.radius <= ow.position.y + 0.5:
					solid_rects.append(ow)

		for r in solid_rects:
			var pen: Dictionary = Shapes.circle_intersects_rect(p.pos, p.radius, r)
			if not bool(pen["hit"]):
				continue

			var pen_normal: Vector2 = pen["normal"]
			var pen_depth: float = float(pen["depth"])
			p.pos += pen_normal * pen_depth

			match p.kind:
				Projectile.Kind.GRENADE:
					var vn: float = p.vel.dot(pen_normal)
					if vn < 0.0:
						p.vel -= (1.0 + 0.45) * vn * pen_normal
						var vt: Vector2 = p.vel - p.vel.dot(pen_normal) * pen_normal
						p.vel = p.vel.dot(pen_normal) * pen_normal + 0.80 * vt
						if -vn > 80.0:
							EventBus.grenade_bounced.emit(p.pos, -vn)
					if pen_normal.y < -0.7 and p.vel.length() < 40.0:
						p.vel = Vector2.ZERO
						p.resting = true
				Projectile.Kind.SAW_BLADE:
					p.vel = p.vel - 2.0 * p.vel.dot(pen_normal) * pen_normal
					p.vel *= p.bounce_speed_mult # 0.95
					p.bounces_left -= 1
					p.armed = true
					EventBus.projectile_bounced.emit(p.pos, pen_normal)
					if p.bounces_left < 0:
						_despawn(p)
						return
				Projectile.Kind.FLAME_PUFF:
					_despawn(p)
					return

		# Character hits
		for obj in characters:
			var c: CharacterState = obj as CharacterState
			if not is_eligible(p.owner_id, p.owner_team, c):
				continue
			var hit_pen: Dictionary = Shapes.circle_intersects_rect(p.pos, p.radius, c.aabb())
			if bool(hit_pen["hit"]):
				if p.kind == Projectile.Kind.SAW_BLADE:
					var last_hit: float = p.last_hit_times.get(c.id, -99.0)
					if (now - last_hit) >= 0.3:
						p.last_hit_times[c.id] = now
						var dmg := 45.0 if p.armed else 20.0
						var saw_dir := p.vel.normalized() if p.vel.length_squared() > 1e-4 else Vector2.RIGHT
						damage_system.queue_damage(c, p.owner_id, p.owner_team, p.weapon_id, dmg, p.pos, saw_dir)
						CharacterMotor.apply_impulse(c, saw_dir, p.knockback)
						if not p.hit_ids.has(c.id):
							p.hit_ids[c.id] = true
							p.pierces_left -= 1
							if p.pierces_left < 0:
								_despawn(p)
								return
				elif p.kind == Projectile.Kind.FLAME_PUFF:
					if not p.hit_ids.has(c.id):
						p.hit_ids[c.id] = true
						damage_system.queue_damage(c, p.owner_id, p.owner_team, p.weapon_id, p.damage, p.pos, p.dir)
						damage_system.apply_burn(c, p.owner_id)

	# Post-substep updates
	if p.kind == Projectile.Kind.FLAME_PUFF:
		p.radius = lerpf(10.0, 36.0, clampf(p.age / 0.52, 0.0, 1.0))

	if p.kind == Projectile.Kind.GRENADE:
		p.fuse -= dt
		if p.fuse <= 0.0:
			ExplosionSystem.explode(p.pos, 260.0, 120.0, 15.0, 1000.0, 0.5, p.owner_id, p.owner_team, "frag_grenade", grid, characters, damage_system)
			_despawn(p)
			return

	if p.age >= p.lifetime:
		_despawn(p)
