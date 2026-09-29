# Implements §10.4 T-MOV-01..12 Character movement and physics tests.
class_name TestMov
extends RefCounted

const DT: float = 1.0 / 60.0

func _make_empty_grid() -> TileGrid:
	var rows: Array[String] = []
	for r in range(60):
		var line := ""
		for c in range(120):
			line += "."
		rows.append(line)
	var tg := TileGrid.new()
	tg.load_from_ascii(rows)
	return tg

func _make_floor_grid() -> TileGrid:
	var rows: Array[String] = []
	for r in range(59):
		var line := ""
		for c in range(120):
			line += "."
		rows.append(line)
	var floor_line := ""
	for c in range(120):
		floor_line += "#"
	rows.append(floor_line)
	var tg := TileGrid.new()
	tg.load_from_ascii(rows)
	return tg

func test_mov_01_free_fall() -> void:
	var grid := _make_empty_grid()
	var c := CharacterState.new()
	c.pos = Vector2(1000, 1000)
	c.vel = Vector2.ZERO
	c.grounded = false
	var frame := InputFrame.new()

	for t in range(30):
		CharacterMotor.step(c, frame, DT, grid)

	Assertions.assert_near(c.vel.y, 900.0, 0.03, "After 30 ticks vy = 900 ± 3%")

func test_mov_02_terminal_velocity() -> void:
	var grid := _make_empty_grid()
	var c := CharacterState.new()
	c.pos = Vector2(1000, 500)
	c.vel = Vector2.ZERO
	c.grounded = false
	var frame := InputFrame.new()

	for t in range(60):
		CharacterMotor.step(c, frame, DT, grid)

	Assertions.assert_eq(c.vel.y, 1100.0, "After 60 ticks vy = 1100 (clamped)")

	# Dive clamps at 1300
	var c_dive := CharacterState.new()
	c_dive.pos = Vector2(1000, 500)
	c_dive.vel = Vector2.ZERO
	c_dive.grounded = false
	var frame_dive := InputFrame.new()
	frame_dive.crouch = true

	for t in range(60):
		CharacterMotor.step(c_dive, frame_dive, DT, grid)

	Assertions.assert_eq(c_dive.vel.y, 1300.0, "Dive clamps at 1300")

func test_mov_03_jump_apex() -> void:
	var grid := _make_floor_grid()
	var floor_y := 59 * 64.0
	var c := CharacterState.new()
	c.pos = Vector2(500, floor_y)
	c.vel = Vector2.ZERO
	c.grounded = true

	var frame := InputFrame.new()
	frame.jet_pressed = true
	CharacterMotor.step(c, frame, DT, grid)
	frame.clear_edges()

	var min_y: float = c.pos.y
	for t in range(40):
		CharacterMotor.step(c, frame, DT, grid)
		if c.pos.y < min_y:
			min_y = c.pos.y

	var apex_height := floor_y - min_y
	Assertions.assert_near(apex_height, 87.1, 0.03, "Jump apex height 87.1 ± 3%")

func test_mov_04_ground_accel_friction_turn() -> void:
	var grid := _make_floor_grid()
	var floor_y := 59 * 64.0

	# 0 -> 420 in 0.14 s (8.4 ticks -> 8 or 9 ticks)
	var c := CharacterState.new()
	c.pos = Vector2(500, floor_y)
	c.grounded = true
	var frame := InputFrame.new()
	frame.move_x = 1

	var ticks_accel := 0
	while c.vel.x < 420.0 and ticks_accel < 30:
		CharacterMotor.step(c, frame, DT, grid)
		ticks_accel += 1

	var time_accel := ticks_accel * DT
	Assertions.assert_between(time_accel, 0.14 - DT * 1.5, 0.14 + DT * 1.5, "0 -> 420 in 0.14 s ± 1 tick")

	# 420 -> 0 in 0.117 s (7 ticks)
	frame.move_x = 0
	var ticks_friction := 0
	while c.vel.x > 0.0 and ticks_friction < 30:
		CharacterMotor.step(c, frame, DT, grid)
		ticks_friction += 1

	var time_friction := ticks_friction * DT
	Assertions.assert_between(time_friction, 0.117 - DT * 1.5, 0.117 + DT * 1.5, "420 -> 0 in 0.117 s ± 1 tick")

	# +420 -> -420 in 0.156 s (9.3 ticks)
	c.vel.x = 420.0
	frame.move_x = -1
	var ticks_turn := 0
	while c.vel.x > -420.0 and ticks_turn < 30:
		CharacterMotor.step(c, frame, DT, grid)
		ticks_turn += 1

	var time_turn := ticks_turn * DT
	Assertions.assert_between(time_turn, 0.156 - DT * 1.5, 0.156 + DT * 1.5, "+420 -> -420 in 0.156 s ± 1 tick")

func test_mov_05_jetpack_endurance() -> void:
	var grid := _make_empty_grid()
	var c := CharacterState.new()
	c.pos = Vector2(1000, 3000)
	c.vel = Vector2.ZERO
	c.grounded = false
	c.since_jump_t = 99.0
	var start_y := c.pos.y

	var frame := InputFrame.new()
	frame.jet_held = true

	var ticks := 0
	while c.fuel > 0.0 and ticks < 300:
		CharacterMotor.step(c, frame, DT, grid)
		ticks += 1

	var burnout_time := ticks * DT
	Assertions.assert_between(burnout_time, 3.571 - DT * 1.5, 3.571 + DT * 1.5, "Burnout at 3.571 s ± 1 tick")
	var height_gained := start_y - c.pos.y
	Assertions.assert_near(height_gained, 1767.0, 0.03, "Height gained 1767 ± 3%")

func test_mov_06_fuel_recharge() -> void:
	var grid := _make_floor_grid()
	var floor_y := 59 * 64.0
	var c := CharacterState.new()
	c.pos = Vector2(500, floor_y)
	c.grounded = true
	c.fuel = 0.0
	c.recharge_delay_t = 0.6
	var frame := InputFrame.new()

	var ticks := 0
	while c.fuel < 100.0 and ticks < 300:
		CharacterMotor.step(c, frame, DT, grid)
		ticks += 1

	var recharge_time := ticks * DT
	Assertions.assert_between(recharge_time, 3.1 - DT * 1.5, 3.1 + DT * 1.5, "Grounded 0 -> 100 in 3.1 s ± 1 tick")

	# Airborne rate: 12 / s
	var c_air := CharacterState.new()
	c_air.pos = Vector2(500, 1000)
	c_air.grounded = false
	c_air.fuel = 50.0
	c_air.recharge_delay_t = 0.0
	for t in range(60):
		CharacterMotor.step(c_air, frame, DT, grid)
	Assertions.assert_near(c_air.fuel - 50.0, 12.0, 0.05, "Airborne recharge rate 12/s")

func test_mov_07_burnout_lock() -> void:
	var grid := _make_empty_grid()
	var c := CharacterState.new()
	c.pos = Vector2(500, 1000)
	c.grounded = false
	c.fuel = 0.0
	c.jet_locked = true
	c.recharge_delay_t = 0.0
	var frame := InputFrame.new()
	frame.jet_held = true

	# When fuel < 15, jet must not activate
	for t in range(30):
		CharacterMotor.step(c, frame, DT, grid)
		if c.fuel < 15.0:
			Assertions.assert_false(c.jet_active, "Jet cannot activate while fuel < 15 after burnout")

func test_mov_08_one_way_platforms() -> void:
	var rows: Array[String] = []
	for r in range(10):
		rows.append("==========" if r == 5 else "..........")
	var grid := TileGrid.new()
	grid.load_from_ascii(rows)

	var c := CharacterState.new()
	c.pos = Vector2(300, 200) # above row 5 (row 5 top is at y = 320)
	c.vel = Vector2(0, 300)
	var frame := InputFrame.new()

	# Landing from above
	for t in range(40):
		CharacterMotor.step(c, frame, DT, grid)
	Assertions.assert_true(c.grounded, "Landed on one-way platform")
	Assertions.assert_eq(c.pos.y, 320.0, "Feet at platform top y = 320")

	# Crouch on catwalk causes drop-through within 0.25 s
	frame.crouch = true
	for t in range(20):
		CharacterMotor.step(c, frame, DT, grid)
	Assertions.assert_false(c.grounded, "Dropped through catwalk")
	Assertions.assert_true(c.pos.y > 320.0, "Fallen below platform")
	Assertions.assert_false(c.crouching, "Crouch state impossible on catwalk")

	# Passing from below
	var c_up := CharacterState.new()
	c_up.pos = Vector2(300, 400)
	c_up.vel = Vector2(0, -600)
	var frame_up := InputFrame.new()
	var passed_through := false
	for t in range(40):
		CharacterMotor.step(c_up, frame_up, DT, grid)
		if c_up.pos.y < 320.0:
			passed_through = true
	Assertions.assert_true(passed_through, "Passed through one-way from below")

func test_mov_09_step_up() -> void:
	var rows: Array[String] = []
	for r in range(10):
		var line := ""
		for col in range(10):
			if r == 5 and col >= 5:
				line += "h"
			elif r == 5:
				line += "."
			elif r == 6:
				line += "#"
			else:
				line += "."
		rows.append(line)
	var grid := TileGrid.new()
	grid.load_from_ascii(rows)

	var floor_y := 6 * 64.0 # 384
	var c := CharacterState.new()
	c.pos = Vector2(4 * 64 + 32, floor_y) # standing on floor before half tile
	c.grounded = true
	c.vel.x = 420.0

	var frame := InputFrame.new()
	frame.move_x = 1

	for t in range(30):
		CharacterMotor.step(c, frame, DT, grid)

	# Stepped up onto half tile (top is 384 - 32 = 352)
	Assertions.assert_eq(c.pos.y, 352.0, "Stepped up onto HALF tile")
	Assertions.assert_true(c.vel.x > 0.0, "Maintained forward motion without stopping")

func test_mov_10_updraft() -> void:
	var grid := TileGrid.new()
	grid.load_from(Data.map)

	# West updraft is around col 18, row 30 (world x ≈ 18*64+32 = 1184)
	var c := CharacterState.new()
	c.pos = Vector2(1184, 2500)
	c.vel = Vector2.ZERO
	c.grounded = false
	var frame := InputFrame.new()

	for t in range(85):
		CharacterMotor.step(c, frame, DT, grid)

	Assertions.assert_near(c.vel.y, -380.0, 0.03, "In updraft without input vy -> -380")

	# With jetpack held, vy -> -680
	frame.jet_held = true
	c.since_jump_t = 99.0
	for t in range(60):
		CharacterMotor.step(c, frame, DT, grid)

	Assertions.assert_near(c.vel.y, -680.0, 0.03, "In updraft with jetpack vy -> -680")

	# Holding crouch dives down
	frame.jet_held = false
	frame.crouch = true
	for t in range(60):
		CharacterMotor.step(c, frame, DT, grid)

	Assertions.assert_true(c.vel.y > 0.0, "Holding crouch in updraft descends")

func test_mov_11_anti_tunnelling() -> void:
	var grid := TileGrid.new()
	grid.load_from(Data.map)
	var c := CharacterState.new()
	c.pos = Vector2(352, 704) # Spawn P01
	var rng := RandomNumberGenerator.new()
	rng.seed = 445566
	var frame := InputFrame.new()

	for t in range(2000):
		frame.move_x = rng.randi_range(-1, 1)
		frame.jet_held = rng.randf() > 0.4
		frame.jet_pressed = rng.randf() > 0.7
		frame.crouch = rng.randf() > 0.6

		CharacterMotor.step(c, frame, DT, grid)

		# Check bounds
		Assertions.assert_between(c.pos.x, 22.0, 7680.0 - 22.0, "Within X bounds")
		Assertions.assert_between(c.pos.y, c.height, 3840.0, "Within Y bounds")

		# Check solid overlap
		var solid_rects := grid.solid_rects_in(c.aabb(), false)
		for r in solid_rects:
			var overlap := c.aabb().intersection(r)
			var max_dim := minf(overlap.size.x, overlap.size.y)
			Assertions.assert_true(max_dim <= 0.5, "Overlap <= 0.5 wu")

func test_mov_12_coyote_and_buffer() -> void:
	var grid := _make_floor_grid()
	var floor_y := 59 * 64.0
	var c := CharacterState.new()
	c.pos = Vector2(500, floor_y)
	c.grounded = true

	var frame := InputFrame.new()
	# Step off floor into air (e.g. set grounded = false)
	c.grounded = false
	c.coyote_t = 0.08 # Coyote time active

	# Jump within 0.08 s
	frame.jet_pressed = true
	CharacterMotor.step(c, frame, DT, grid)
	Assertions.assert_near(c.vel.y, -530.0, 0.05, "Coyote jump succeeds <= 0.08 s after leaving ledge")

	# Jump buffer: press <= 0.10 s before landing
	var c_buf := CharacterState.new()
	c_buf.pos = Vector2(500, floor_y - 5.0)
	c_buf.vel = Vector2(0, 400.0)
	c_buf.grounded = false
	var frame_buf := InputFrame.new()
	frame_buf.jet_pressed = true # press while falling

	CharacterMotor.step(c_buf, frame_buf, DT, grid)
	frame_buf.clear_edges()
	# Next step lands and consumes buffer to jump
	CharacterMotor.step(c_buf, frame_buf, DT, grid)
	Assertions.assert_near(c_buf.vel.y, -530.0, 0.05, "Jump buffer executes jump upon landing")
