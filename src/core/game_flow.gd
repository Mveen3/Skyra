# Implements §1.3 GameFlow state machine, transitions, pause, restart shortcut, and countdown.
class_name GameFlow
extends Node

var state: int = Enums.GameState.INITIALIZE
var current_config: MatchConfig = null
var last_config: MatchConfig = null
var sim: MatchSim = null
var summary: MatchSummary = null

var countdown_timer: float = 3.0
var match_ended_timer: float = 2.5
var restart_prompt_active: bool = false
var restart_prompt_timer: float = 0.0
var _last_countdown_second: int = 4

func _init() -> void:
	current_config = MatchConfig.new(&"mini_post", 5, 420, 0)
	last_config = current_config

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func change_state(new_state: int) -> void:
	if state == new_state:
		return
	var prev := state
	state = new_state
	restart_prompt_active = false
	restart_prompt_timer = 0.0

	match state:
		Enums.GameState.PRESET_MENU:
			EventBus.pause_changed.emit(false)
		Enums.GameState.MATCH_LOADING:
			EventBus.pause_changed.emit(false)
			# Re-instantiate / setup sim
			if not current_config:
				current_config = MatchConfig.new(&"mini_post", 5, 420, randi())
			sim = MatchSim.new()
			sim.setup(current_config)
		Enums.GameState.SPAWNING:
			countdown_timer = 3.0
			_last_countdown_second = 4
		Enums.GameState.MATCH_ACTIVE:
			EventBus.pause_changed.emit(false)
			if sim:
				sim.begin_active()
		Enums.GameState.PAUSED:
			EventBus.pause_changed.emit(true)
		Enums.GameState.MATCH_ENDED:
			match_ended_timer = 2.5
		Enums.GameState.SCORE_SUMMARY:
			if sim and sim.rules:
				summary = sim.rules.build_summary()
		Enums.GameState.QUITTING:
			var tree := get_tree()
			if tree:
				tree.quit(0)

	EventBus.game_state_changed.emit(prev, new_state)

func start_match(config: MatchConfig = null) -> void:
	if config:
		current_config = config
	elif not current_config:
		current_config = MatchConfig.new(&"mini_post", 5, 420, randi())
	last_config = current_config
	change_state(Enums.GameState.MATCH_LOADING)

func pause_match() -> void:
	if state == Enums.GameState.MATCH_ACTIVE:
		change_state(Enums.GameState.PAUSED)

func resume_match() -> void:
	if state == Enums.GameState.PAUSED:
		change_state(Enums.GameState.MATCH_ACTIVE)

func restart_match() -> void:
	# Same config, new seed (§1.3 T10, T11)
	if current_config:
		var new_seed := randi()
		current_config = MatchConfig.new(current_config.mode, current_config.bot_count, current_config.duration_s, new_seed)
	change_state(Enums.GameState.MATCH_LOADING)

func quit_to_menu() -> void:
	change_state(Enums.GameState.PRESET_MENU)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		on_focus_lost()

func on_focus_lost() -> void:
	# Focus loss pauses in MATCH_ACTIVE (§1.3 T8, T-FLOW-05)
	if state == Enums.GameState.MATCH_ACTIVE:
		pause_match()

func handle_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	var key_event := event as InputEventKey

	match state:
		Enums.GameState.PRESET_MENU:
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
				start_match()
			elif key_event.keycode == KEY_ESCAPE:
				change_state(Enums.GameState.QUITTING)

		Enums.GameState.MATCH_ACTIVE:
			if restart_prompt_active:
				if key_event.keycode == KEY_F5 or key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
					restart_match()
				elif key_event.keycode == KEY_ESCAPE:
					restart_prompt_active = false
					restart_prompt_timer = 0.0
			elif key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_P:
				pause_match()
			elif key_event.keycode == KEY_F5:
				restart_prompt_active = true
				restart_prompt_timer = 3.0

		Enums.GameState.PAUSED:
			if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_P:
				resume_match()

		Enums.GameState.SCORE_SUMMARY:
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
				# Play Again (§1.3 T15)
				restart_match()
			elif key_event.keycode == KEY_ESCAPE:
				# Change Setup (§1.3 T16)
				quit_to_menu()

func step(dt: float) -> void:
	match state:
		Enums.GameState.MATCH_LOADING:
			# Loading completes immediately in sim/tests (§1.3 T6)
			change_state(Enums.GameState.SPAWNING)

		Enums.GameState.SPAWNING:
			countdown_timer -= dt
			var current_sec := int(ceilf(countdown_timer))
			if current_sec > 0 and current_sec < _last_countdown_second:
				_last_countdown_second = current_sec
				EventBus.countdown_tick.emit(current_sec)

			if countdown_timer <= 0.0:
				change_state(Enums.GameState.MATCH_ACTIVE)

		Enums.GameState.MATCH_ACTIVE:
			# Restart prompt countdown
			if restart_prompt_active:
				restart_prompt_timer -= dt
				if restart_prompt_timer <= 0.0:
					restart_prompt_active = false

			# Sim step
			if sim:
				sim.step(dt, InputFrame.new())
				if sim.rules and sim.rules.match_ended:
					change_state(Enums.GameState.MATCH_ENDED)

		Enums.GameState.MATCH_ENDED:
			match_ended_timer -= dt
			if match_ended_timer <= 0.0:
				change_state(Enums.GameState.SCORE_SUMMARY)
