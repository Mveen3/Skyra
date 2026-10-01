# Implements §1.3, §2.3 and §9.1/§9.2 Main entry point: parses the CLI, runs the test /
# soak / tool modes, or builds the runtime node tree (GameFlow, WorldHost, HumanInput,
# ScreenFX, HUD, Menus) and drives the game-state transitions into the views.
extends Node

var cli: CliArgs
var flow: GameFlow
var world_host: Node2D
var world_view: WorldView
var human_input: HumanInput
var menu_world: WorldView
var ui_router: UiRouter
var hud: HudRoot
var screen_fx: ScreenFx
var audio_router: AudioEventRouter
var debug_overlay: DebugOverlay

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cli = CliArgs.parse()
	Log.set_level_from_string(cli.log_level)
	Log.info("Skyra v%s booting..." % C.VERSION)

	if cli.selftest:
		Log.info("Running self-test suite...")
		await get_tree().process_frame
		TestRunner.run_all(get_tree(), cli.test_filter)
		return

	if not cli.run_script.is_empty():
		await get_tree().process_frame
		_run_dev_script(cli.run_script)
		return

	if cli.gen_sfx:
		_run_gen_sfx()
		return

	if cli.soak > 0:
		await get_tree().process_frame
		_run_soak(cli.soak, cli.mode, cli.bots, cli.rng_seed)
		return

	if not Data.errors.is_empty():
		_show_fatal_error()
		return

	if cli.windowed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))

	_build_runtime()
	Log.info("INITIALIZE state complete.")

	if cli.bench:
		var bench := BenchRunner.new(flow, self, cli.mode, float(cli.bench_s))
		bench.name = "Bench"
		add_child(bench)
	elif cli.autostart:
		var cfg := MatchConfig.new(cli.mode, cli.bots, clampi(cli.duration, 5, 10) * 60, cli.rng_seed if cli.has_seed else 0)
		flow.start_match(cfg)
	else:
		flow.change_state(Enums.GameState.PRESET_MENU)

	if not cli.drive.is_empty():
		var script: GDScript = load(cli.drive)
		if script:
			var driver: Node = script.new()
			driver.name = "DevDriver"
			add_child(driver)

## Runtime node tree (§9.2).
func _build_runtime() -> void:
	flow = GameFlow.new()
	flow.name = "GameFlow"
	add_child(flow)

	world_host = Node2D.new()
	world_host.name = "WorldHost"
	world_host.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world_host)

	human_input = HumanInput.new()
	human_input.name = "HumanInput"
	human_input.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(human_input)
	flow.input_source = human_input.build_frame

	screen_fx = ScreenFx.new()
	screen_fx.name = "ScreenFX"
	add_child(screen_fx)
	hud = HudRoot.new(flow)
	hud.name = "HUD"
	add_child(hud)
	ui_router = UiRouter.new(flow)
	ui_router.name = "Menus"
	add_child(ui_router)
	audio_router = AudioEventRouter.new()
	debug_overlay = DebugOverlay.new(flow)
	debug_overlay.name = "Debug"
	add_child(debug_overlay)

	flow.match_built.connect(_on_match_built)
	flow.match_torn_down.connect(_on_match_torn_down)
	EventBus.game_state_changed.connect(_on_game_state_changed)

func _on_match_built(sim: MatchSim) -> void:
	_free_menu_world()
	world_view = WorldView.new()
	world_view.name = "WorldView"
	var grid := sim.grid
	world_view.setup(sim, grid)
	world_host.add_child(world_view)
	human_input.world_canvas = world_view
	hud.bind(sim, world_view, human_input)
	screen_fx.bind(sim)
	audio_router.bind(sim)
	Audio.interior_check = grid.is_interior

func _on_match_torn_down() -> void:
	audio_router.unbind()
	Audio.interior_check = Callable()
	hud.unbind()
	screen_fx.bind(null)
	if world_view:
		world_view.queue_free()
		world_view = null
	human_input.world_canvas = null

func _process(delta: float) -> void:
	if audio_router:
		audio_router.process(delta)

func _ensure_menu_world() -> void:
	if menu_world or world_view:
		return
	var grid := TileGrid.new()
	grid.load_from(Data.map)
	menu_world = WorldView.new()
	menu_world.name = "MenuWorld"
	menu_world.setup(null, grid)
	world_host.add_child(menu_world)

func _free_menu_world() -> void:
	if menu_world:
		menu_world.queue_free()
		menu_world = null

func _on_game_state_changed(_from: int, to: int) -> void:
	human_input.enabled = to == Enums.GameState.SPAWNING or to == Enums.GameState.MATCH_ACTIVE
	match to:
		Enums.GameState.PRESET_MENU:
			_ensure_menu_world()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Enums.GameState.SPAWNING, Enums.GameState.MATCH_ACTIVE:
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
		_:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if flow == null:
		return
	if event.is_action_pressed(&"toggle_fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		Settings.set_display("fullscreen", not fs)
		get_viewport().set_input_as_handled()
		return
	if ui_router and ui_router.modal_open():
		return
	if flow.handle_input(event):
		get_viewport().set_input_as_handled()

## T3: data validation error -> full-screen message; any key quits with exit code 2.
func _show_fatal_error() -> void:
	var layer := CanvasLayer.new()
	layer.layer = C.LAYER_MENUS
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Palette.UI_PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = "Skyra could not start - data validation failed:\n\n" + "\n".join(Data.errors) + "\n\nPress any key to quit."
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(label)
	set_process_unhandled_input(false)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if flow == null and not Data.errors.is_empty() and event.is_pressed():
		get_tree().quit(2)

## Dev hook (`--run-script=res://path.gd`): runs a probe script after boot so it
## sees the autoloads. The script must define `run(tree: SceneTree) -> int`.
func _run_dev_script(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		Log.error("Cannot load dev script: " + path)
		get_tree().quit(1)
		return
	var probe = script.new()
	var code: int = await probe.run(get_tree())
	get_tree().quit(code)

func _run_gen_sfx() -> void:
	Log.info("Generating procedural audio files to assets/audio/generated/...")
	var cues: Dictionary = Data.cues
	var count: int = 0
	for cue_id in cues:
		var path: String = "res://assets/audio/generated/%s.wav" % str(cue_id)
		SfxSynth.render_to_file(cues[cue_id], path)
		count += 1
	Log.info("Generated %d WAV files." % count)
	get_tree().quit(0)

## `--soak` (§9.9, §10.5 S-01 / S-01b): per-tick invariants + end-of-run statistics.
func _run_soak(seconds: int, mode: StringName, bots: int, seed_val: int) -> void:
	Log.info("Running soak test: %d seconds, mode=%s, bots=%d, seed=%d" % [seconds, str(mode), bots, seed_val])
	var result: Dictionary = SoakRunner.new(mode, bots, seed_val, seconds).run(true)
	var s: Dictionary = result["stats"]
	Log.info("Skyra kills %d, deaths %d · bot kills on Skyra %d · boosts %d · weapons picked %s" % [
		s["skyra_kills"], s["skyra_deaths"], s["bot_kills_on_skyra"], s["boost_spawns"], str(s["weapons_picked"])])
	Log.info("INV-5 %.3f · max tokens %d · max bots firing per 1 s %d · bot spawn fallbacks %d/%d" % [
		s["inv5"], s["max_tokens"], s["inv2_worst"], s["spawn_fallbacks"], s["bot_respawns"]])
	Log.info("%d ticks in %.2f s wall-clock (mean tick %.3f ms, p99 %.3f ms)" % [
		seconds * 60, s["wall_s"], s["mean_ms"], s["p99_ms"]])
	if not bool(result["ok"]):
		for f in result["failures"]:
			Log.error("SOAK: " + str(f))
		Log.error("SOAK FAIL")
		get_tree().quit(1)
		return
	Log.info("SOAK PASS")
	get_tree().quit(0)
