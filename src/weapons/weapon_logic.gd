# Implements §4.9 Weapon state machine, firing, reload, and depletion.
class_name WeaponLogic
extends RefCounted

static func step(c: CharacterState, frame: InputFrame, dt: float, grid: TileGrid,
                 proj_sys: ProjectileSystem, beam_sys: BeamSystem,
                 damage_system: DamageSystem, rng: RandomNumberGenerator) -> void:
	var inv: Inventory = c.inventory
	if not inv: return

	# Switch weapon inputs
	if frame.switch_pressed:
		inv.toggle_active()
	elif frame.slot_select == 0:
		inv.set_active_slot(0)
	elif frame.slot_select == 1:
		inv.set_active_slot(1)

	var w: WeaponInstance = inv.active_weapon()
	if not w: return

	var def: WeaponDef = w.def

	# Depletion check (clip == 0 and reserve == 0, never Magnum)
	if def.id != "magnum" and w.clip == 0 and w.reserve == 0:
		w.depletion_t += dt
		if w.depletion_t >= 0.3:
			inv.drop_active()
			return
	else:
		w.depletion_t = 0.0

	# Fire buffering
	if frame.fire_pressed:
		w.fire_buffer_t = 0.12
	else:
		w.fire_buffer_t = maxf(0.0, w.fire_buffer_t - dt)

	# Bloom decay
	w.bloom = SpreadModel.decay_bloom(def, w.bloom, dt)

	# State machine step
	if w.state == Enums.WeaponState.SWITCHING:
		w.state_t -= dt
		if w.state_t <= 0.0:
			w.state_t = 0.0
			if w.clip == 0 and (w.reserve > 0 or def.max_reserve == -1):
				w.start_reload()
			else:
				w.state = Enums.WeaponState.IDLE

	if w.state == Enums.WeaponState.COOLDOWN:
		w.state_t -= dt
		if w.state_t <= 0.0:
			w.state = Enums.WeaponState.IDLE

	if w.state == Enums.WeaponState.RELOADING:
		if def.reload_type == Enums.ReloadType.PER_SHELL:
			# Pump per-shell reload
			# Pressing fire with >= 1 shell interrupts reload immediately and fires
			if frame.fire_pressed and w.clip >= 1:
				w.state = Enums.WeaponState.IDLE
				_fire_weapon(c, w, frame, grid, proj_sys, rng)
				return

			w.shell_reload_timer -= dt
			if w.shell_reload_timer <= 0.0:
				if w.reserve > 0 or def.max_reserve == -1:
					w.clip += 1
					if def.max_reserve != -1:
						w.reserve -= 1
				w.shell_reload_timer = def.shell_reload_s # 0.45 s
				if w.clip >= def.clip_size or (w.reserve <= 0 and def.max_reserve != -1):
					w.state = Enums.WeaponState.IDLE
		else:
			# Magazine reload
			w.state_t -= dt
			if w.state_t <= 0.0:
				w.finish_reload()
				w.state = Enums.WeaponState.IDLE

	if w.state == Enums.WeaponState.IDLE:
		# Manual reload check
		if frame.reload_pressed and w.clip < def.clip_size and (w.reserve > 0 or def.max_reserve == -1):
			w.start_reload()
			return

		# Check if weapon should fire
		var wants_fire := false
		match def.fire_mode:
			Enums.FireMode.AUTO:
				wants_fire = frame.fire_held
			Enums.FireMode.SEMI, Enums.FireMode.PUMP, Enums.FireMode.BOLT:
				wants_fire = frame.fire_pressed or (w.fire_buffer_t > 0.0)
			Enums.FireMode.CONTINUOUS:
				wants_fire = frame.fire_held

		if wants_fire:
			if def.fire_mode != Enums.FireMode.CONTINUOUS:
				if w.clip > 0:
					_fire_weapon(c, w, frame, grid, proj_sys, rng)
				else:
					# Empty click & auto-reload
					if frame.fire_pressed:
						EventBus.weapon_empty_click.emit(c.id, StringName(def.id))
						if w.reserve > 0 or def.max_reserve == -1:
							w.start_reload()

	# Continuous weapon special processing (Blaze & Phaser)
	if def.id == "phasr":
		beam_sys.step_beam(c, frame, dt, grid, [c], damage_system)
	elif def.id == "flamethrower":
		_step_flamethrower(c, w, frame, dt, grid, proj_sys, rng)

static func _fire_weapon(c: CharacterState, w: WeaponInstance, frame: InputFrame,
                         grid: TileGrid, proj_sys: ProjectileSystem, rng: RandomNumberGenerator) -> void:
	var def := w.def
	w.fire_buffer_t = 0.0

	if def.fire_mode == Enums.FireMode.CONTINUOUS:
		return # Handled in step_beam or step_flamethrower

	w.clip -= 1
	w.state = Enums.WeaponState.COOLDOWN
	w.state_t = maxf(0.0, def.fire_interval_s + minf(0.0, w.state_t))

	# Spread & Bloom
	var current_spread := SpreadModel.calc_spread_deg(def, w.bloom, c.vel.x, c.grounded, c.crouching)
	w.bloom = SpreadModel.add_bloom(def, w.bloom)

	var shoulder := c.shoulder()
	var muzzle := shoulder + c.aim_dir * 18.0

	# Muzzle occlusion check (§4.5.4)
	var occ := ProjectileSystem.check_muzzle_occlusion(shoulder, muzzle, grid)
	if occ.hit:
		# Shot resolves at blocked point
		EventBus.projectile_impact.emit(Projectile.Kind.BULLET, occ.point, occ.normal, 0, StringName(def.id), false, false)
		return

	# Fire weapon projectiles
	match def.id:
		"shotgun":
			var angles := SpreadModel.sample_shotgun_pellet_angles(c.aim_angle, current_spread, rng, 8)
			for a in angles:
				proj_sys.spawn_bullet(c.id, c.team, def, muzzle, a)
		"rocket_launcher":
			var a := SpreadModel.sample_shot_angle(c.aim_angle, current_spread, rng)
			proj_sys.spawn_rocket(c.id, c.team, def, muzzle, a)
		"saw_gun":
			var a := SpreadModel.sample_shot_angle(c.aim_angle, current_spread, rng)
			proj_sys.spawn_saw(c.id, c.team, def, muzzle, a)
		_:
			var a := SpreadModel.sample_shot_angle(c.aim_angle, current_spread, rng)
			proj_sys.spawn_bullet(c.id, c.team, def, muzzle, a)

	EventBus.weapon_fired.emit(c.id, StringName(def.id), muzzle, c.aim_dir)

static func _step_flamethrower(c: CharacterState, w: WeaponInstance, frame: InputFrame,
                              dt: float, grid: TileGrid, proj_sys: ProjectileSystem, rng: RandomNumberGenerator) -> void:
	if frame.fire_held and w.state == Enums.WeaponState.IDLE and w.clip > 0:
		w.flame_accum += dt
		while w.flame_accum >= 0.04 and w.clip > 0:
			w.flame_accum -= 0.04
			w.clip = maxf(0.0, w.clip - 0.8) # 20 units/s / 25 puffs/s = 0.8 per puff

			var shoulder := c.shoulder()
			var muzzle := shoulder + c.aim_dir * 18.0
			var occ := ProjectileSystem.check_muzzle_occlusion(shoulder, muzzle, grid)
			if not occ.hit:
				var jitter := rng.randf_range(-7.0, 7.0)
				var angle := c.aim_angle + deg_to_rad(jitter)
				proj_sys.spawn_flame_puff(c.id, c.team, muzzle, angle, c.vel)

		if w.clip <= 0.0:
			w.clip = 0.0
			w.start_reload()
	else:
		w.flame_accum = 0.0

static func muzzle_of(c: CharacterState) -> Vector2:
	return c.shoulder() + c.aim_dir * 18.0

static func give_spawn_loadout(c: CharacterState, mode_id: StringName = &"mini_post") -> void:
	if not c or not c.inventory:
		return
	var m_key := str(mode_id)
	var mode_data: Dictionary = Data.modes.get(m_key, {})
	if mode_data.is_empty():
		mode_data = Data.modes.get("mini_post", {})
	var loadout: Dictionary = mode_data.get("spawn_loadout", {})

	c.inventory.clear()

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

