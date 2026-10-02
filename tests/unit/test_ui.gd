# Implements §10 test requirements T-UI-01..04.
class_name TestUi
extends RefCounted

const DT: float = 1.0 / 60.0

func test_ui_01_spin_wheel() -> void:
	# T-UI-01: Spin wheel: wheel ±1, drag, keys; clamped 5..10; default 7
	var wheel := SpinWheel.new()
	Assertions.assert_eq(wheel.value, 7, "Default duration is 7")

	# Mouse wheel
	wheel.on_mouse_wheel(true) # Down -> +1
	Assertions.assert_eq(wheel.value, 8, "Wheel down increments to 8")
	wheel.on_mouse_wheel(false) # Up -> -1
	Assertions.assert_eq(wheel.value, 7, "Wheel up decrements to 7")

	# Keys: Up/Down and +/-
	wheel.on_key_input(KEY_UP)
	Assertions.assert_eq(wheel.value, 8, "Up arrow increments to 8")
	wheel.on_key_input(KEY_DOWN)
	Assertions.assert_eq(wheel.value, 7, "Down arrow decrements to 7")
	wheel.on_key_input(KEY_EQUAL) # '+'
	Assertions.assert_eq(wheel.value, 8, "+ increments to 8")
	wheel.on_key_input(KEY_MINUS) # '-'
	Assertions.assert_eq(wheel.value, 7, "- decrements to 7")

	# Drag
	wheel.on_drag(-56.0) # Drag up 56 px -> +1
	Assertions.assert_eq(wheel.value, 8, "Drag up increments to 8")
	wheel.on_drag(56.0) # Drag down 56 px -> -1
	Assertions.assert_eq(wheel.value, 7, "Drag down decrements to 7")

	# Clamped 5..10
	for _i in range(10):
		wheel.on_key_input(KEY_UP)
	Assertions.assert_eq(wheel.value, 10, "Upper clamp is 10")

	for _i in range(15):
		wheel.on_key_input(KEY_DOWN)
	Assertions.assert_eq(wheel.value, 5, "Lower clamp is 5")
	wheel.free()

func test_ui_02_bots_toggle() -> void:
	# T-UI-02: Bots toggle: default 5; keys 3/5/7 select
	var toggle := BotsToggle.new()
	Assertions.assert_eq(toggle.bot_count, 5, "Default bot count is 5")

	# Key 3
	toggle.on_key_input(KEY_3)
	Assertions.assert_eq(toggle.bot_count, 3, "Key 3 selects 3 bots")

	# Key 7
	toggle.on_key_input(KEY_7)
	Assertions.assert_eq(toggle.bot_count, 7, "Key 7 selects 7 bots")

	# Key 5
	toggle.on_key_input(KEY_5)
	Assertions.assert_eq(toggle.bot_count, 5, "Key 5 selects 5 bots")
	toggle.free()

func test_ui_03_hud_model() -> void:
	# T-UI-03: HUD model: HudModel equals Sim values every frame of a scripted run
	var sim := MatchSim.new()
	var config := MatchConfig.new(&"mini_post", 3, 300, 42)
	sim.setup(config)
	sim.begin_active()

	for step_idx in range(60): # 1 second run
		var frame := InputFrame.new()
		frame.jet_held = (step_idx % 10 < 5)
		sim.step(DT, frame)

		var model := HudModel.snapshot(sim)
		Assertions.assert_eq(model.alive, sim.human_char.life_state == Enums.LifeState.ALIVE)
		Assertions.assert_near(model.health, sim.human_char.health, 0.001)
		Assertions.assert_near(model.fuel, sim.human_char.fuel, 0.001)
		Assertions.assert_eq(model.jet_locked, sim.human_char.jet_locked)
		Assertions.assert_near(model.time_left_s, sim.rules.time_left_s, 0.001)
		Assertions.assert_eq(model.kills, sim.human_char.stats.kills)
		Assertions.assert_eq(model.deaths, sim.human_char.stats.deaths)

func test_ui_04_kill_feed() -> void:
	# T-UI-04: Kill feed: ≤ 5 rows; each lives 5 s
	var feed := KillFeed.new()
	Assertions.assert_eq(feed.row_count(), 0)

	# Add 6 entries: max 5 rows maintained
	for i in range(6):
		feed.add_entry("Killer %d" % i, "#FF0000", &"magnum", "Victim %d" % i, "#00FF00")
	Assertions.assert_eq(feed.row_count(), 5, "Kill feed caps at 5 rows")
	Assertions.assert_eq(feed.rows[0].killer_name, "Killer 1", "Oldest entry 0 popped when 6 added")

	# Step 4.0 s: still 5 rows
	feed.step(4.0)
	Assertions.assert_eq(feed.row_count(), 5, "Rows still present after 4 s")

	# Step 1.2 s more (total 5.2 s): all rows expired
	feed.step(1.2)
	Assertions.assert_eq(feed.row_count(), 0, "All rows expired and removed after > 5 s")
	feed.free()
