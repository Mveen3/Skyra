# Implements §10 test requirements T-FLOW-01..05.
class_name TestFlow
extends RefCounted

const DT: float = 1.0 / 60.0

func _simulate_key(flow: GameFlow, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	flow.handle_input(ev)

func test_flow_01_full_flow() -> void:
	var flow := GameFlow.new()
	flow.change_state(Enums.GameState.PRESET_MENU)
	Assertions.assert_eq(flow.state, Enums.GameState.PRESET_MENU, "Starts in PRESET_MENU")

	# Enter battle -> MATCH_LOADING
	_simulate_key(flow, KEY_ENTER)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_LOADING, "Enter triggers MATCH_LOADING")

	# Loading step -> SPAWNING
	flow.step(0.1)
	Assertions.assert_eq(flow.state, Enums.GameState.SPAWNING, "Step transitions to SPAWNING")

	# 3.0 s countdown -> MATCH_ACTIVE
	for _i in range(int(3.1 / DT)):
		flow.step(DT)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ACTIVE, "Countdown finishes -> MATCH_ACTIVE")

	# Pause key (Esc) -> PAUSED
	_simulate_key(flow, KEY_ESCAPE)
	Assertions.assert_eq(flow.state, Enums.GameState.PAUSED, "Esc in MATCH_ACTIVE triggers PAUSED")

	# Resume key (Esc) -> MATCH_ACTIVE
	_simulate_key(flow, KEY_ESCAPE)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ACTIVE, "Esc in PAUSED triggers MATCH_ACTIVE")

	# Fast forward to match end
	flow.sim.rules.time_left_s = 0.001
	flow.step(DT)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ENDED, "Timer end triggers MATCH_ENDED")

	# 2.5 s in MATCH_ENDED -> SCORE_SUMMARY
	for _i in range(int(2.6 / DT)):
		flow.step(DT)
	Assertions.assert_eq(flow.state, Enums.GameState.SCORE_SUMMARY, "2.5 s real time -> SCORE_SUMMARY")
	Assertions.assert_true(flow.summary != null, "Summary is built")

	# "Play Again" (Enter) in SCORE_SUMMARY -> MATCH_LOADING
	_simulate_key(flow, KEY_ENTER)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_LOADING, "Enter in summary triggers MATCH_LOADING (Play Again)")

	# Complete loading again to get to SCORE_SUMMARY for "Change Setup" test
	flow.step(0.1) # SPAWNING
	flow.change_state(Enums.GameState.SCORE_SUMMARY)

	# "Change Setup" (Esc) in SCORE_SUMMARY -> PRESET_MENU
	_simulate_key(flow, KEY_ESCAPE)
	Assertions.assert_eq(flow.state, Enums.GameState.PRESET_MENU, "Esc in summary triggers PRESET_MENU (Change Setup)")
	flow.free()

func test_flow_02_one_key_start() -> void:
	# T-FLOW-02: Enter on preset screen yields MatchConfig(mini_post, 5, 420)
	var flow := GameFlow.new()
	flow.change_state(Enums.GameState.PRESET_MENU)

	_simulate_key(flow, KEY_ENTER)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_LOADING)
	Assertions.assert_true(flow.current_config != null, "Config created")
	Assertions.assert_eq(flow.current_config.mode, &"mini_post", "Default mode is mini_post")
	Assertions.assert_eq(flow.current_config.bot_count, 5, "Default bot count is 5")
	Assertions.assert_eq(flow.current_config.duration_s, 420, "Default duration is 420 s (7 min)")
	flow.free()

func test_flow_03_timer_durations() -> void:
	# T-FLOW-03: accelerated matches of 5 and 10 minutes end at duration_s ± 1 tick
	for duration in [300, 600]:
		var flow := GameFlow.new()
		var config := MatchConfig.new(&"mini_post", 3, duration, 42)
		flow.start_match(config)
		flow.step(0.1) # SPAWNING
		flow.change_state(Enums.GameState.MATCH_ACTIVE)

		var total_active_time := 0.0
		while flow.state == Enums.GameState.MATCH_ACTIVE:
			var remaining := flow.sim.rules.time_left_s
			var dt_curr := DT if remaining <= 1.0 else 0.5
			flow.step(dt_curr)
			total_active_time += dt_curr

		Assertions.assert_near(total_active_time, float(duration), DT * 1.5, "Match of %d s ends within ±1 tick" % duration)
		Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ENDED, "Transitions to MATCH_ENDED")
		flow.free()

func test_flow_04_restart_shortcut() -> void:
	# T-FLOW-04: F5 then F5/Enter restarts; Esc cancels
	var flow := GameFlow.new()
	flow.start_match(MatchConfig.new(&"mini_post", 5, 420, 100))
	flow.step(0.1)
	flow.change_state(Enums.GameState.MATCH_ACTIVE)

	# 1. First F5 shows prompt, does not restart immediately
	_simulate_key(flow, KEY_F5)
	Assertions.assert_true(flow.restart_prompt_active, "Restart prompt is active")
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ACTIVE, "Remains in MATCH_ACTIVE")

	# 2. Esc cancels prompt
	_simulate_key(flow, KEY_ESCAPE)
	Assertions.assert_false(flow.restart_prompt_active, "Esc cancels restart prompt")
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ACTIVE, "Remains in MATCH_ACTIVE")

	# 3. F5 then F5 restarts
	_simulate_key(flow, KEY_F5)
	Assertions.assert_true(flow.restart_prompt_active)
	_simulate_key(flow, KEY_F5)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_LOADING, "Second F5 restarts match")

	# 4. F5 then Enter restarts
	flow.step(0.1)
	flow.change_state(Enums.GameState.MATCH_ACTIVE)
	_simulate_key(flow, KEY_F5)
	Assertions.assert_true(flow.restart_prompt_active)
	_simulate_key(flow, KEY_ENTER)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_LOADING, "Enter confirms restart prompt")
	flow.free()

func test_flow_05_focus_loss() -> void:
	# T-FLOW-05: focus-out notification pauses
	var flow := GameFlow.new()
	flow.start_match()
	flow.step(0.1)
	flow.change_state(Enums.GameState.MATCH_ACTIVE)
	Assertions.assert_eq(flow.state, Enums.GameState.MATCH_ACTIVE)

	flow.on_focus_lost()
	Assertions.assert_eq(flow.state, Enums.GameState.PAUSED, "Focus loss triggers PAUSED")
	flow.free()
