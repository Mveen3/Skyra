# Implements §1.3 GameFlow state machine: transitions, countdown, pause, restart
# shortcut, match end slow-motion and score summary. Owns the MatchSim during a match
# and advances it at the fixed 60 Hz tick (§1.4).
class_name GameFlow
extends Node

## A new MatchSim was built (MATCH_LOADING): the view layer must (re)build the world.
signal match_built(sim: MatchSim)
## The current match was torn down (restart, quit to menu).
signal match_torn_down()
## Esc on the preset menu: the UI shows "Quit Skyra?" (T5).
signal quit_confirm_requested()

const COUNTDOWN_S: float = 3.0
const MATCH_ENDED_S: float = 2.5 # real time (T14)
const SLOWMO_S: float = 1.2 # real time at Engine.time_scale 0.25 (T13)
const SLOWMO_SCALE: float = 0.25
const RESTART_PROMPT_S: float = 3.0

var state: int = Enums.GameState.INITIALIZE
var current_config: MatchConfig = null
var last_config: MatchConfig = null
var sim: MatchSim = null
var summary: MatchSummary = null

var countdown_timer: float = COUNTDOWN_S
var match_ended_timer: float = MATCH_ENDED_S
var slowmo_timer: float = 0.0
var restart_prompt_active: bool = false
var restart_prompt_timer: float = 0.0
var _last_countdown_second: int = 4

## Supplies the human InputFrame each tick (HumanInput); tests leave it unset.
var input_source: Callable = Callable()
var _idle_frame: InputFrame = InputFrame.new()
## Duration of the last Sim tick in microseconds (measured outside the Sim, §10.5).
var last_sim_us: int = 0
## T8 auto-pause on focus loss; `--bench` turns it off so a focus change cannot stall it.
var pause_on_focus_loss: bool = true
## Process exit code used by QUITTING (`--bench` reports pass / fail through it).
var quit_exit_code: int = 0

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
			_teardown_match()
			_set_tree_paused(false)
			_restore_time_scale()
			EventBus.pause_changed.emit(false)
		Enums.GameState.MATCH_LOADING:
			_teardown_match()
			_set_tree_paused(false)
			_restore_time_scale()
			EventBus.pause_changed.emit(false)
			if not current_config:
				current_config = MatchConfig.new(&"mini_post", 5, 420, randi())
			summary = null
			sim = MatchSim.new()
			sim.setup(current_config)
			match_built.emit(sim)
		Enums.GameState.SPAWNING:
			countdown_timer = COUNTDOWN_S
			_last_countdown_second = 4
			_emit_countdown()
		Enums.GameState.MATCH_ACTIVE:
			_set_tree_paused(false)
			EventBus.pause_changed.emit(false)
			# Only a fresh match starts the clock; resuming from PAUSED must not reset it.
			if prev == Enums.GameState.SPAWNING and sim:
				sim.begin_active()
				EventBus.countdown_tick.emit(0)
				EventBus.match_started.emit(current_config)
		Enums.GameState.PAUSED:
			_set_tree_paused(true)
			EventBus.pause_changed.emit(true)
		Enums.GameState.MATCH_ENDED:
			match_ended_timer = MATCH_ENDED_S
			slowmo_timer = SLOWMO_S
			Engine.time_scale = SLOWMO_SCALE
		Enums.GameState.SCORE_SUMMARY:
			_restore_time_scale()
			if sim and sim.rules:
				summary = sim.rules.build_summary()
		Enums.GameState.QUITTING:
			_restore_time_scale()
			Settings.save_if_dirty()
			# Break the Sim's reference cycles so nothing leaks at exit.
			_teardown_match()
			var tree := get_tree()
			if tree:
				tree.quit(quit_exit_code)

	EventBus.game_state_changed.emit(prev, new_state)

func _teardown_match() -> void:
	if sim:
		sim.teardown()
		sim = null
		match_torn_down.emit()

func _set_tree_paused(p: bool) -> void:
	if is_inside_tree():
		get_tree().paused = p

func _restore_time_scale() -> void:
	Engine.time_scale = 1.0

func start_match(config: MatchConfig = null) -> void:
	if config:
		current_config = config
	elif not current_config:
		current_config = MatchConfig.new(&"mini_post", 5, 420, randi())
	if current_config.rng_seed == 0:
		current_config.rng_seed = randi()
	last_config = current_config
	change_state(Enums.GameState.MATCH_LOADING)

func pause_match() -> void:
	if state == Enums.GameState.MATCH_ACTIVE:
		change_state(Enums.GameState.PAUSED)

func resume_match() -> void:
	if state == Enums.GameState.PAUSED:
		change_state(Enums.GameState.MATCH_ACTIVE)

## T10 / T11 / T15: same config, new seed.
func restart_match() -> void:
	if current_config:
		current_config = MatchConfig.new(current_config.mode, current_config.bot_count, current_config.duration_s, randi())
		last_config = current_config
	change_state(Enums.GameState.MATCH_LOADING)

## T12 / T16: the last MatchConfig stays in memory to pre-select it on the menu.
func quit_to_menu() -> void:
	change_state(Enums.GameState.PRESET_MENU)

func quit_game(exit_code: int = 0) -> void:
	quit_exit_code = exit_code
	change_state(Enums.GameState.QUITTING)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		on_focus_lost()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func on_focus_lost() -> void:
	# Focus loss pauses in MATCH_ACTIVE (§1.3 T8, T-FLOW-05)
	if state == Enums.GameState.MATCH_ACTIVE and pause_on_focus_loss:
		pause_match()

## True when `ev` triggers `action`. Synthetic key events without a physical keycode
## (tests) fall back to the default keys.
static func _is_action(ev: InputEventKey, action: StringName, fallback_keys: Array) -> bool:
	if InputMap.has_action(action) and ev.is_action_pressed(action, false, true):
		return true
	return ev.physical_keycode == KEY_NONE and ev.keycode in fallback_keys

static func _is_confirm(ev: InputEventKey) -> bool:
	var k := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	return k == KEY_ENTER or k == KEY_KP_ENTER

static func _is_escape(ev: InputEventKey) -> bool:
	var k := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	return k == KEY_ESCAPE

func handle_input(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return false
	var key_event := event as InputEventKey

	match state:
		Enums.GameState.PRESET_MENU:
			if _is_confirm(key_event):
				start_match()
				return true
			if _is_escape(key_event):
				quit_confirm_requested.emit()
				return true

		Enums.GameState.MATCH_ACTIVE:
			if restart_prompt_active:
				if _is_action(key_event, &"restart_match", [KEY_F5]) or _is_confirm(key_event):
					restart_match()
					return true
				if _is_escape(key_event):
					restart_prompt_active = false
					restart_prompt_timer = 0.0
					return true
			elif _is_action(key_event, &"pause", [KEY_ESCAPE, KEY_P]):
				pause_match()
				return true
			elif _is_action(key_event, &"restart_match", [KEY_F5]):
				restart_prompt_active = true
				restart_prompt_timer = RESTART_PROMPT_S
				return true

		Enums.GameState.PAUSED:
			if _is_action(key_event, &"pause", [KEY_ESCAPE, KEY_P]):
				resume_match()
				return true
			if _is_action(key_event, &"restart_match", [KEY_F5]):
				restart_match()
				return true

		Enums.GameState.SCORE_SUMMARY:
			if _is_confirm(key_event):
				restart_match() # Play Again (§1.3 T15)
				return true
			if _is_escape(key_event):
				quit_to_menu() # Change Setup (§1.3 T16)
				return true
	return false

func _physics_process(delta: float) -> void:
	# Timers in MATCH_ENDED run on real time while Engine.time_scale is reduced.
	var real_dt := delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
	var frame: InputFrame = input_source.call() if input_source.is_valid() else _idle_frame
	step(delta, frame, real_dt)

## Advances the flow by one tick. `frame` is the human InputFrame (idle when null);
## `real_dt` is unscaled time for the slow-motion end sequence (defaults to dt).
func step(dt: float, frame: InputFrame = null, real_dt: float = -1.0) -> void:
	if frame == null:
		frame = _idle_frame
	if real_dt < 0.0:
		real_dt = dt
	match state:
		Enums.GameState.INITIALIZE:
			pass

		Enums.GameState.MATCH_LOADING:
			# The world is built synchronously on entry (§1.3 T6)
			change_state(Enums.GameState.SPAWNING)

		Enums.GameState.SPAWNING:
			if sim:
				sim.step_countdown(dt, frame)
			countdown_timer -= dt
			_emit_countdown()
			if countdown_timer <= 0.0:
				change_state(Enums.GameState.MATCH_ACTIVE)

		Enums.GameState.MATCH_ACTIVE:
			if restart_prompt_active:
				restart_prompt_timer -= dt
				if restart_prompt_timer <= 0.0:
					restart_prompt_active = false
			if sim:
				var t0 := Time.get_ticks_usec()
				sim.step(dt, frame)
				last_sim_us = Time.get_ticks_usec() - t0
				if sim.rules and sim.rules.match_ended:
					change_state(Enums.GameState.MATCH_ENDED)

		Enums.GameState.MATCH_ENDED:
			# Views keep animating; the Sim is frozen (damage & input stopped, T13)
			if slowmo_timer > 0.0:
				slowmo_timer -= real_dt
				if slowmo_timer <= 0.0:
					_restore_time_scale()
			match_ended_timer -= real_dt
			if match_ended_timer <= 0.0:
				change_state(Enums.GameState.SCORE_SUMMARY)

func _emit_countdown() -> void:
	var current_sec := int(ceilf(countdown_timer))
	if current_sec > 0 and current_sec < _last_countdown_second:
		_last_countdown_second = current_sec
		EventBus.countdown_tick.emit(current_sec)
