# Implements §4.9 Weapon state machine (switch, reload, fire, depletion), §4.4 spread,
# §4.5.4 muzzle occlusion, §4.7 Blaze emission and the §4.3 (10) grenade throw.
class_name WeaponLogic
extends RefCounted

const ARM_LENGTH: float = 18.0
const FIRE_BUFFER_S: float = 0.12
const AUTO_RELOAD_DELAY_S: float = 0.15
const DEPLETED_DISCARD_S: float = 0.3
const CONTINUOUS_SHOT_WINDOW_S: float = 0.25 # accuracy: continuous fire counts one shot per window (§8.5.3)
const FLAME_PUFF_INTERVAL_S: float = 0.04

static func step(c: CharacterState, frame: InputFrame, dt: float, grid: TileGrid,
                 proj_sys: ProjectileSystem, _beam_sys: BeamSystem,
                 _damage_system: DamageSystem, rng: RandomNumberGenerator) -> void:
	var inv: Inventory = c.inventory
	if not inv: return

	# Switch weapon inputs
	if frame.switch_pressed:
		inv.toggle_active()
	elif frame.slot_select == 0:
		inv.set_active_slot(0)
	elif frame.slot_select == 1:
		inv.set_active_slot(1)

	# Grenades are independent of the weapon slots (an unarmed character can still throw).
	step_grenade(c, frame, dt, grid, proj_sys)

	var w: WeaponInstance = inv.active_weapon()
	if not w: return
	var def: WeaponDef = w.def
	w.cycle_t += dt

	# Depleted weapon (clip 0 and reserve 0, never the Magnum): discarded after 0.3 s
	if w.is_depleted():
		w.depletion_t += dt
		if w.depletion_t >= DEPLETED_DISCARD_S:
			_set_flaming(c, w, false)
			inv.drop_active()
			EventBus.weapon_dropped.emit(c.id, def.id, c.centre())
			return
	else:
		w.depletion_t = 0.0

	# Fire press buffer (SEMI / PUMP / BOLT)
	if frame.fire_pressed:
		w.fire_buffer_t = FIRE_BUFFER_S
	else:
		w.fire_buffer_t = maxf(0.0, w.fire_buffer_t - dt)

	w.bloom = SpreadModel.decay_bloom(def, w.bloom, dt)

	match w.state:
		Enums.WeaponState.SWITCHING:
			_set_flaming(c, w, false)
			w.state_t -= dt
			if w.state_t <= 0.0:
				w.state_t = 0.0
				w.state = Enums.WeaponState.IDLE
				if w.clip <= 0.0 and w.can_reload():
					w.start_reload(c.id)
		Enums.WeaponState.COOLDOWN:
			w.state_t -= dt
			if w.state_t <= 0.0:
				w.state = Enums.WeaponState.IDLE
		Enums.WeaponState.RELOADING:
			_set_flaming(c, w, false)
			w.reload_elapsed_s += dt
			if def.reload_type == Enums.ReloadType.PER_SHELL:
				# Pressing fire with >= 1 shell loaded interrupts the reload and fires (§4.3 Pump)
				if frame.fire_pressed and w.clip >= 1.0:
					w.state = Enums.WeaponState.IDLE
					w.reload_elapsed_s = 0.0
					_fire_weapon(c, w, grid, proj_sys, rng)
					return
				w.shell_reload_timer -= dt
				if w.shell_reload_timer <= 0.0:
					if w.reserve > 0.0 or w.has_infinite_reserve():
						w.clip += 1.0
						if not w.has_infinite_reserve():
							w.reserve -= 1.0
					w.shell_reload_timer = def.shell_reload_s
					if w.clip >= float(def.clip_size) or (w.reserve <= 0.0 and not w.has_infinite_reserve()):
						w.state = Enums.WeaponState.IDLE
						w.reload_elapsed_s = 0.0
						EventBus.weapon_reload_finished.emit(c.id, def.id)
			else:
				w.state_t -= dt
				if w.state_t <= 0.0:
					w.finish_reload(c.id)
					w.state = Enums.WeaponState.IDLE
					w.reload_elapsed_s = 0.0

	# Auto-reload 0.15 s after the clip ran dry (§4.9)
	if w.auto_reload_t >= 0.0:
		w.auto_reload_t -= dt
		if w.auto_reload_t < 0.0 and w.state == Enums.WeaponState.IDLE and w.clip <= 0.0 and w.can_reload():
			w.start_reload(c.id)

	if w.state != Enums.WeaponState.IDLE:
		return

	# Manual reload
	if frame.reload_pressed and w.can_reload():
		w.start_reload(c.id)
		return

	match def.fire_mode:
		Enums.FireMode.CONTINUOUS:
			if def.delivery == Enums.Delivery.FLAME:
				_step_flamethrower(c, w, frame, dt, grid, proj_sys, rng)
			# Phaser beams are advanced by BeamSystem (MatchSim step 2.5)
			if frame.fire_pressed and w.clip <= 0.0:
				_empty_click(c, w)
		Enums.FireMode.AUTO:
			if frame.fire_held:
				if w.clip >= 1.0:
					_fire_weapon(c, w, grid, proj_sys, rng)
				elif frame.fire_pressed:
					_empty_click(c, w)
		_:
			if frame.fire_pressed or w.fire_buffer_t > 0.0:
				if w.clip >= 1.0:
					_fire_weapon(c, w, grid, proj_sys, rng)
				elif frame.fire_pressed:
					_empty_click(c, w)

static func _empty_click(c: CharacterState, w: WeaponInstance) -> void:
	EventBus.weapon_empty_click.emit(c.id, w.def.id)
	if w.can_reload() and w.auto_reload_t < 0.0:
		w.auto_reload_t = AUTO_RELOAD_DELAY_S

static func _fire_weapon(c: CharacterState, w: WeaponInstance, grid: TileGrid,
                         proj_sys: ProjectileSystem, rng: RandomNumberGenerator) -> void:
	var def := w.def
	w.fire_buffer_t = 0.0
	w.clip -= 1.0
	w.cycle_t = 0.0
	w.state = Enums.WeaponState.COOLDOWN
	w.state_t = maxf(0.0, def.fire_interval_s + minf(0.0, w.state_t))
	if w.clip <= 0.0:
		w.clip = 0.0
		w.auto_reload_t = AUTO_RELOAD_DELAY_S
	c.stats.shots_fired += 1
	var shot_id := c.stats.shots_fired

	# Spread & bloom (§4.4)
	var current_spread := SpreadModel.calc_spread_deg(def, w.bloom, c.vel.x, c.grounded, c.crouching)
	w.bloom = SpreadModel.add_bloom(def, w.bloom)

	var shoulder := c.shoulder()
	var muzzle := muzzle_of(c)
	EventBus.weapon_fired.emit(c.id, def.id, muzzle, c.aim_dir)

	# Muzzle occlusion (§4.5.4): the shot resolves at the blocked point
	var occ := ProjectileSystem.check_muzzle_occlusion(shoulder, muzzle, grid)
	if bool(occ["hit"]):
		var blocked: Vector2 = occ["point"]
		if def.projectile_kind == Enums.ProjectileKind.ROCKET:
			var rocket := proj_sys.spawn_rocket(c.id, c.team, def, blocked - c.aim_dir, c.aim_angle)
			rocket.shot_id = shot_id
			rocket.age = rocket.lifetime # detonates on its first step, at the wall
		else:
			var kind := Projectile.Kind.PELLET if def.projectile_kind == Enums.ProjectileKind.PELLET else Projectile.Kind.BULLET
			EventBus.projectile_impact.emit(kind, blocked, occ["normal"], grid.surface_at(blocked + (occ["normal"] as Vector2) * -2.0), def.id, false, false)
		return

	match def.projectile_kind:
		Enums.ProjectileKind.PELLET:
			var angles := SpreadModel.sample_shotgun_pellet_angles(c.aim_angle, current_spread, rng, def.pellets)
			for a in angles:
				proj_sys.spawn_bullet(c.id, c.team, def, muzzle, a).shot_id = shot_id
		Enums.ProjectileKind.ROCKET:
			var a := SpreadModel.sample_shot_angle(c.aim_angle, current_spread, rng)
			proj_sys.spawn_rocket(c.id, c.team, def, muzzle, a).shot_id = shot_id
		Enums.ProjectileKind.SAW_BLADE:
			var a := SpreadModel.sample_shot_angle(c.aim_angle, current_spread, rng)
			proj_sys.spawn_saw(c.id, c.team, def, muzzle, a).shot_id = shot_id
		_:
			var a := SpreadModel.sample_shot_angle(c.aim_angle, current_spread, rng)
			proj_sys.spawn_bullet(c.id, c.team, def, muzzle, a).shot_id = shot_id

## §4.7 Blaze: while fire is held, one flame puff every 0.04 s (0.8 fuel each).
static func _step_flamethrower(c: CharacterState, w: WeaponInstance, frame: InputFrame,
                              dt: float, grid: TileGrid, proj_sys: ProjectileSystem, rng: RandomNumberGenerator) -> void:
	if not (frame.fire_held and w.clip > 0.0):
		w.flame_accum = 0.0
		_set_flaming(c, w, false)
		return
	_set_flaming(c, w, true)
	_count_continuous_shot(c, w, dt)
	var ammo_per_puff := float(w.def.special.get("puff", {}).get("ammo_per_puff", 0.8))
	w.flame_accum += dt
	while w.flame_accum >= FLAME_PUFF_INTERVAL_S and w.clip > 0.0:
		w.flame_accum -= FLAME_PUFF_INTERVAL_S
		w.clip = maxf(0.0, w.clip - ammo_per_puff)
		var shoulder := c.shoulder()
		var muzzle := muzzle_of(c)
		var occ := ProjectileSystem.check_muzzle_occlusion(shoulder, muzzle, grid)
		if bool(occ["hit"]):
			continue # flames spawned inside a wall die immediately (§4.5.4)
		var angle := c.aim_angle + deg_to_rad(rng.randf_range(-7.0, 7.0))
		var puff := proj_sys.spawn_flame_puff(c.id, c.team, muzzle, angle, c.vel)
		puff.speed += rng.randf_range(-60.0, 60.0)
		puff.vel = puff.dir * puff.speed + c.vel * 0.3
		puff.shot_id = c.stats.shots_fired
	if w.clip <= 0.0:
		w.clip = 0.0
		_set_flaming(c, w, false)
		w.start_reload(c.id)

## Continuous weapons count one "shot" per 0.25 s of firing for the accuracy stat.
static func _count_continuous_shot(c: CharacterState, w: WeaponInstance, dt: float) -> void:
	w.emit_accum -= dt
	if w.emit_accum <= 0.0:
		w.emit_accum += CONTINUOUS_SHOT_WINDOW_S
		c.stats.shots_fired += 1

static func _set_flaming(c: CharacterState, w: WeaponInstance, on: bool) -> void:
	if w.flaming == on:
		return
	w.flaming = on
	if not on:
		w.emit_accum = 0.0
	EventBus.flame_state_changed.emit(c.id, on)

## Hand / grip point: front shoulder + aim_dir · arm length (§4.4).
static func hand_of(c: CharacterState) -> Vector2:
	return c.shoulder() + c.aim_dir * ARM_LENGTH

## Weapon-local art offset → world, mirrored vertically when aiming left so the
## weapon stays upright (the view draws it the same way).
static func weapon_local_to_world(c: CharacterState, local: Vector2) -> Vector2:
	var flip := 1.0 if c.aim_dir.x >= 0.0 else -1.0
	return hand_of(c) + Vector2(local.x, local.y * flip).rotated(c.aim_angle)

static func muzzle_offset(weapon_id: StringName) -> Vector2:
	var art: Dictionary = Data.weapon_art.get(str(weapon_id), {})
	var m: Array = art.get("muzzle", [0, 0])
	return Vector2(float(m[0]), float(m[1]))

## Muzzle point = shoulder + aim_dir · 18 + rotate(muzzle_offset, aim_angle) (§4.4).
static func muzzle_of(c: CharacterState) -> Vector2:
	var w: WeaponInstance = c.inventory.active_weapon() if c.inventory else null
	if w == null:
		return hand_of(c)
	return weapon_local_to_world(c, muzzle_offset(w.def.id))

## §4.3 (10) Frag: hold `throw_grenade` to aim (the view draws the arc), release to throw;
## a quick tap throws at once. 0.6-s cooldown; blocked while the weapon is SWITCHING.
static func step_grenade(c: CharacterState, frame: InputFrame, dt: float, grid: TileGrid, proj_sys: ProjectileSystem) -> void:
	var inv: Inventory = c.inventory
	inv.grenade_cooldown_t = maxf(0.0, inv.grenade_cooldown_t - dt)
	if frame.grenade_pressed and inv.grenades > 0 and inv.grenade_cooldown_t <= 0.0:
		inv.grenade_aiming = true
		inv.grenade_hold_t = 0.0
	if not inv.grenade_aiming:
		return
	if inv.grenades <= 0:
		inv.grenade_aiming = false
		return
	inv.grenade_hold_t += dt
	var released := frame.grenade_released or not (frame.grenade_held or frame.grenade_pressed)
	if not released:
		return
	var w := inv.active_weapon()
	if w and w.state == Enums.WeaponState.SWITCHING:
		return # keep aiming: the throw goes out as soon as the switch finishes
	inv.grenade_aiming = false
	throw_grenade(c, frame, grid, proj_sys)

## Initial grenade position and velocity for a throw along `dir` (also used by the
## view's trajectory preview so the arc matches the real throw).
static func grenade_launch(c: CharacterState, dir: Vector2, speed_mult: float = 1.0, inherit: bool = true) -> Dictionary:
	var g: GrenadeDef = Data.grenade
	var vel := dir * g.throw_speed * speed_mult
	if inherit:
		vel += c.vel * g.inherit_velocity
	return {"pos": c.shoulder() + dir * ARM_LENGTH, "vel": vel}

static func throw_grenade(c: CharacterState, frame: InputFrame, grid: TileGrid, proj_sys: ProjectileSystem) -> void:
	var g: GrenadeDef = Data.grenade
	var inv: Inventory = c.inventory
	var launch: Dictionary
	if frame.grenade_use_angle:
		# Bot throws use the solved arc (§5.6) and do not inherit velocity.
		launch = grenade_launch(c, Vector2.from_angle(frame.grenade_angle), frame.grenade_speed_mult, false)
	else:
		launch = grenade_launch(c, c.aim_dir)
	var shoulder := c.shoulder()
	var hand: Vector2 = launch["pos"]
	var vel: Vector2 = launch["vel"]
	# Muzzle occlusion (§4.5.4): a throw into a wall drops the grenade at the wall.
	var occ: Dictionary = grid.raycast(shoulder, hand, C.MASK_PROJECTILE)
	if bool(occ["hit"]):
		hand = (occ["point"] as Vector2) - (hand - shoulder).normalized() * (g.radius + 1.0)
		vel = Vector2.ZERO
	proj_sys.spawn_grenade(c.id, c.team, hand, vel)
	inv.grenades -= 1
	inv.grenade_cooldown_t = g.throw_cooldown_s
	EventBus.grenade_thrown.emit(c.id, hand, vel)

static func give_spawn_loadout(c: CharacterState, mode_id: StringName = &"mini_post") -> void:
	if not c or not c.inventory:
		return
	var m_key := str(mode_id)
	var mode_data: Dictionary = Data.modes.get(m_key, {})
	if mode_data.is_empty():
		mode_data = Data.modes.get("mini_post", {})
	var loadout: Dictionary = mode_data.get("spawn_loadout", {})

	c.inventory.clear()
	c.inventory.owner_id = c.id

	var slot_1: String = str(loadout.get("slot_1", "magnum"))
	if slot_1 != "" and slot_1 != "null" and Data.weapons.has(slot_1):
		var w1 := WeaponInstance.new(Data.weapons[slot_1])
		c.inventory.set_weapon(0, w1)
		c.inventory.set_active_slot(0)

	var slot_2 = loadout.get("slot_2", null)
	if slot_2 != null and str(slot_2) != "" and str(slot_2) != "null" and Data.weapons.has(str(slot_2)):
		var w2 := WeaponInstance.new(Data.weapons[str(slot_2)])
		c.inventory.set_weapon(1, w2)

	var g_count: int = int(loadout.get("grenades", 2))
	var max_g: int = int(mode_data.get("max_grenades", 4))
	c.inventory.grenades = g_count
	c.inventory.max_grenades = max_g
