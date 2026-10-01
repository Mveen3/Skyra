# Implements §9.2 Menus layer (CanvasLayer 20, always processing): shows / hides the preset
# menu, loading + countdown overlays, pause menu, restart prompt, "TIME!" banner, score
# summary, settings overlay and quit confirmation for each GameState (§1.3).
class_name UiRouter
extends CanvasLayer

var flow: GameFlow
var root: Control
var screen: Control = null
var settings: SettingsOverlay = null
var loading: LoadingOverlay = null
var countdown: CountdownOverlay
var restart_prompt: RestartPrompt
var _confirm: ConfirmDialog = null

func _init(p_flow: GameFlow) -> void:
	flow = p_flow
	layer = C.LAYER_MENUS
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "MenusRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeFactory.get_theme()
	add_child(root)
	countdown = CountdownOverlay.new()
	root.add_child(countdown)
	restart_prompt = RestartPrompt.new(flow)
	root.add_child(restart_prompt)

func _ready() -> void:
	EventBus.game_state_changed.connect(_on_state_changed)
	flow.quit_confirm_requested.connect(_confirm_quit)

func _clear_screen() -> void:
	if screen:
		screen.queue_free()
		screen = null
	if settings:
		settings.queue_free()
		settings = null

func _on_state_changed(from: int, to: int) -> void:
	match to:
		Enums.GameState.PRESET_MENU:
			_clear_screen()
			if loading:
				loading.queue_free()
				loading = null
			var menu := PresetMenu.new(flow.last_config)
			menu.start_requested.connect(func(cfg: MatchConfig) -> void: flow.start_match(cfg))
			menu.settings_requested.connect(_open_settings)
			menu.quit_requested.connect(_confirm_quit)
			_show(menu)
		Enums.GameState.MATCH_LOADING:
			_clear_screen()
			if loading == null:
				loading = LoadingOverlay.new()
				root.add_child(loading)
				root.move_child(loading, 0)
		Enums.GameState.SPAWNING:
			if loading:
				loading.fade_out()
				loading = null
		Enums.GameState.MATCH_ACTIVE:
			if from == Enums.GameState.PAUSED:
				_clear_screen()
				Audio.play(&"ui.pause.close")
		Enums.GameState.PAUSED:
			_clear_screen()
			var h := flow.sim.human_char
			var pm := PauseMenu.new(h.stats.kills, h.stats.deaths, flow.sim.rules.time_left_s)
			pm.resume_requested.connect(flow.resume_match)
			pm.restart_requested.connect(flow.restart_match)
			pm.settings_requested.connect(_open_settings)
			pm.menu_requested.connect(flow.quit_to_menu)
			pm.quit_requested.connect(_confirm_quit)
			_show(pm)
			Audio.play(&"ui.pause.open")
		Enums.GameState.MATCH_ENDED:
			_clear_screen()
			countdown.show_text("TIME!", Palette.UI_ACCENT2, 2.4)
			Audio.play(&"ui.match.end_horn")
		Enums.GameState.SCORE_SUMMARY:
			_clear_screen()
			if flow.summary:
				var ss := ScoreSummary.new(flow.summary)
				ss.play_again_requested.connect(flow.restart_match)
				ss.change_setup_requested.connect(flow.quit_to_menu)
				ss.quit_requested.connect(_confirm_quit)
				_show(ss)

func _show(c: Control) -> void:
	screen = c
	root.add_child(c)

func _open_settings() -> void:
	if settings:
		return
	settings = SettingsOverlay.new()
	settings.closed.connect(func() -> void:
		settings = null
		_refocus())
	root.add_child(settings)

func _refocus() -> void:
	if screen and screen.has_method("_ready"):
		screen.call_deferred("_ready")

func _confirm_quit() -> void:
	if _confirm:
		return
	_confirm = ConfirmDialog.new("Quit Skyra?")
	_confirm.answered.connect(func(yes: bool) -> void:
		_confirm = null
		if yes:
			flow.quit_game()
		else:
			_refocus())
	root.add_child(_confirm)

## True while a modal (settings / confirm) owns the keyboard.
func modal_open() -> bool:
	return settings != null or _confirm != null
