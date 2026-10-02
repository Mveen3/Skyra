# Implements §3.3–3.9 CharacterMotor physics and movement.
class_name CharacterMotor
extends RefCounted

static func step(c: CharacterState, frame: InputFrame, dt: float, grid: TileGrid) -> void:
	c.prev_pos = c.pos
	
	# Aiming and facing
	if frame.aim_world != Vector2.ZERO:
		var aim_v := frame.aim_world - c.shoulder()
		c.aim_angle = atan2(aim_v.y, aim_v.x)
		c.aim_dir = aim_v.normalized() if aim_v.length_squared() > 1e-4 else Vector2.RIGHT
		if absf(aim_v.x) > 1.0:
			c.facing = 1 if aim_v.x > 0 else -1
	elif frame.move_x != 0:
		c.facing = frame.move_x

	# Crouch and drop-through
	if c.grounded and c.ground_is_one_way and frame.crouch:
		c.drop_through_t = 0.25
		c.grounded = false
		c.ground_is_one_way = false

	var wants_crouch: bool = c.grounded and frame.crouch and not c.ground_is_one_way
	if wants_crouch:
		c.crouching = true
		c.height = 60.0
	else:
		if c.crouching:
			# Check headroom to stand up (height 84)
			var stand_box := Rect2(c.pos.x - 22.0, c.pos.y - 84.0, 44.0, 84.0)
			var rects := grid.solid_rects_in(stand_box, false)
			if rects.is_empty():
				c.crouching = false
				c.height = 84.0
		else:
			c.height = 84.0

	# Rocket boost multipliers
	var boost_run := 1.35 if c.boost_t > 0 else 1.0
	var boost_air := 1.4 if c.boost_t > 0 else 1.0
	var boost_air_accel := 1.4 if c.boost_t > 0 else 1.0
	var boost_thrust := 1.5 if c.boost_t > 0 else 1.0
	var boost_rise := 1.45 if c.boost_t > 0 else 1.0
	var boost_fuel_burn := 0.0 if c.boost_t > 0 else 1.0

	# Horizontal movement
	var max_v: float = 210.0 if c.crouching else (420.0 * boost_run if c.grounded else 460.0 * boost_air)
	var target_vx := float(frame.move_x) * max_v
	var ax: float
	if c.grounded:
		if frame.move_x == 0:
			ax = 3600.0 # ground_friction
			c.turning = false
		elif sign(frame.move_x) != sign(c.vel.x) and absf(c.vel.x) > 1.0:
			ax = 5400.0 # ground_turn_accel
			c.turning = true
		elif c.turning:
			if (frame.move_x > 0 and c.vel.x >= target_vx) or (frame.move_x < 0 and c.vel.x <= target_vx):
				c.turning = false
				ax = 3000.0 # ground_accel
			else:
				ax = 5400.0 # continue turn acceleration until reverse target reached
		else:
			ax = 3000.0 # ground_accel
	else:
		c.turning = false
		if frame.move_x == 0:
			ax = 350.0 # air_drag
		else:
			ax = 1500.0 * boost_air_accel
			
	c.vel.x = move_toward(c.vel.x, target_vx, ax * dt)

	# Jump buffer and coyote time
	c.since_jump_t += dt
	if frame.jet_pressed:
		c.jump_buffer_t = 0.10
	else:
		c.jump_buffer_t = maxf(0.0, c.jump_buffer_t - dt)

	if c.grounded:
		c.coyote_t = 0.08
	else:
		c.coyote_t = maxf(0.0, c.coyote_t - dt)

	if c.jump_buffer_t > 0.0 and c.coyote_t > 0.0:
		c.vel.y = -560.0 # jump_velocity
		c.grounded = false
		c.coyote_t = 0.0
		c.jump_buffer_t = 0.0
		c.since_jump_t = 0.0

	# Jetpack engagement
	var jet_active: bool = frame.jet_held and not c.grounded and not c.jet_locked and c.fuel > 0.0 and c.since_jump_t >= 0.12
	if jet_active != c.jet_active:
		c.jet_active = jet_active
		EventBus.jetpack_state_changed.emit(c.id, jet_active, c.jet_locked)

	# Updraft and diving
	c.in_updraft = grid.is_updraft(c.centre())
	var diving: bool = not c.grounded and frame.crouch

	# Vertical acceleration
	var ay: float = 1800.0 * (1.4 if diving else 1.0)
	if c.in_updraft and not diving:
		ay -= 2100.0
	if jet_active:
		ay -= 3300.0 * boost_thrust
		
	c.vel.y += ay * dt

	# Speed caps
	var rise_cap: float = 520.0 * boost_rise
	if c.in_updraft and not diving:
		rise_cap = (680.0 * boost_rise) if jet_active else 380.0
	c.launch_t = maxf(0.0, c.launch_t - dt)
	if (jet_active or (c.in_updraft and not diving)) and c.launch_t <= 0.0:
		c.vel.y = maxf(c.vel.y, -rise_cap)
		
	c.vel.y = minf(c.vel.y, 1300.0 if diving else 1100.0)

	# Fuel management
	if jet_active:
		c.fuel -= 28.0 * boost_fuel_burn * dt
		c.recharge_delay_t = 0.6
	else:
		c.recharge_delay_t -= dt
		if c.recharge_delay_t <= 0.0:
			var rate: float = 40.0 if c.grounded else (30.0 if c.in_updraft else 12.0)
			c.fuel += rate * dt
			
	c.fuel = clampf(c.fuel, 0.0, 100.0)
	if c.fuel <= 0.0 and not c.jet_locked:
		c.jet_locked = true
		EventBus.jetpack_state_changed.emit(c.id, false, true)
	if c.jet_locked and c.fuel >= 15.0:
		c.jet_locked = false

	# Position integration via AABB mover (midpoint velocity for exact parabolic apex)
	var move_delta := Vector2(c.vel.x, c.vel.y - 0.5 * ay * dt) * dt
	AabbMover.move(c, move_delta, grid, dt)

static func apply_impulse(c: CharacterState, dir: Vector2, magnitude: float) -> void:
	if dir.length_squared() > 1e-4:
		c.vel += dir.normalized() * magnitude
	if c.vel.length() > 1400.0:
		c.vel = c.vel.normalized() * 1400.0
	if c.vel.y < -150.0 and c.grounded:
		c.grounded = false
