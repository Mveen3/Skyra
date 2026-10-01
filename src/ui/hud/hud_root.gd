# Implements §8.4 HUD root (CanvasLayer 10, visible in SPAWNING / MATCH_ACTIVE /
# MATCH_ENDED): reads a HudModel snapshot every frame and reacts to EventBus events for
# discrete widgets (kill feed, hit markers, streak banner, toasts, damage direction).
class_name HudRoot
extends CanvasLayer

var flow: GameFlow
var sim: MatchSim = null
var world_view: WorldView = null
var human_input: HumanInput = null
var model: HudModel = HudModel.new()

var root: Control
var canvas: HudCanvas
var cross: Crosshair
var kill_feed: KillFeed
var pause_btn: Button
var restart_btn: Button

# Transient widget state
var ghost_health: float = 100.0
var ghost_delay: float = 0.0
var hit_marker_t: float = 0.0
var hit_marker_kill: bool = false
var streak_text: String = ""
var streak_t: float = 0.0
var toasts: Array = [] # {text, t, life}
var damage_dirs: Array = [] # {world_pos, t}
var attackers: Dictionary = {} # bot id -> time left of the "firing at you" arrow
var killer_name: String = ""
var killer_color: Color = Palette.UI_TEXT
var killer_weapon: StringName = &""
var low_health_loop: int = 0
var _last_tick_second: int = -1

func _init(p_flow: GameFlow) -> void:
	flow = p_flow
	layer = C.LAYER_HUD
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeFactory.get_theme()
	add_child(root)
	canvas = HudCanvas.new(self)
	root.add_child(canvas)
	kill_feed = KillFeed.new()
	kill_feed.anchor_left = 1.0
	kill_feed.anchor_right = 1.0
	kill_feed.offset_left = -820
	kill_feed.offset_right = -24
	kill_feed.offset_top = 84
	kill_feed.offset_bottom = 84 + 5 * 40
	root.add_child(kill_feed)
	cross = Crosshair.new(self)
	root.add_child(cross)
	pause_btn = _icon_button("⏸", -120, "Pause (Esc)", "Esc")
	pause_btn.pressed.connect(flow.pause_match)
	restart_btn = _icon_button("⟲", -68, "Restart (F5)", "F5")
	restart_btn.pressed.connect(func() -> void:
		if flow.state == Enums.GameState.MATCH_ACTIVE:
			flow.restart_prompt_active = true
			flow.restart_prompt_timer = GameFlow.RESTART_PROMPT_S)
	visible = false

func _icon_button(glyph: String, right_offset: int, tip: String, key_hint: String) -> Button:
	var b := Button.new()
	b.text = glyph
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = right_offset
	b.offset_right = right_offset + 44
	b.offset_top = 24
	b.offset_bottom = 68
	# While hovered, fire is suppressed so clicking the button never shoots (§8.4)
	b.mouse_entered.connect(func() -> void: if human_input: human_input.suppress_fire = true)
	b.mouse_exited.connect(func() -> void: if human_input: human_input.suppress_fire = false)
	root.add_child(b)
	# Key hint beneath the icon (§8.4: "Esc" / "F5", 12 px)
	var hint := Label.new()
	hint.text = key_hint
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(Palette.UI_SUBTEXT, 0.8))
	hint.position = Vector2(0, 46)
	hint.size = Vector2(44, 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hint)
	return b

func _ready() -> void:
	EventBus.game_state_changed.connect(_on_state)
	EventBus.character_damaged.connect(_on_damaged)
	EventBus.character_killed.connect(_on_killed)
	EventBus.rocket_boost_spawned.connect(_on_boost_spawned)
	EventBus.match_time_warning.connect(_on_time_warning)
	EventBus.toast_requested.connect(func(text: String, _style: StringName, seconds: float) -> void: add_toast(text, seconds))
	EventBus.weapon_fired.connect(_on_weapon_fired)

func bind(p_sim: MatchSim, p_world: WorldView, p_input: HumanInput) -> void:
	sim = p_sim
	world_view = p_world
	human_input = p_input
	kill_feed.rows.clear()
	toasts.clear()
	damage_dirs.clear()
	attackers.clear()
	streak_t = 0.0
	ghost_health = 100.0
	hit_marker_t = 0.0

func unbind() -> void:
	sim = null
	world_view = null
	_stop_low_health()

func _on_state(_from: int, to: int) -> void:
	visible = sim != null and to in [Enums.GameState.SPAWNING, Enums.GameState.MATCH_ACTIVE, Enums.GameState.MATCH_ENDED, Enums.GameState.PAUSED]
	pause_btn.visible = to == Enums.GameState.MATCH_ACTIVE
	restart_btn.visible = to == Enums.GameState.MATCH_ACTIVE
	if to != Enums.GameState.MATCH_ACTIVE and human_input:
		human_input.suppress_fire = false
	if to == Enums.GameState.PRESET_MENU or to == Enums.GameState.MATCH_LOADING:
		_stop_low_health()

# ── Events ───────────────────────────────────────────────────────────────────────

func _name_color(id: int) -> Color:
	var c := sim.character(id) if sim else null
	if c == null:
		return Palette.UI_TEXT
	return Palette.SKYRA_TRIM if c.is_human else c.profile.primary

func _on_damaged(ev: DamageEvent) -> void:
	if sim == null:
		return
	if ev.target_id == 0:
		ghost_delay = 0.4
		var src := sim.character(ev.source_id)
		if src and src.id != 0:
			damage_dirs.append({"world_pos": src.centre(), "t": 1.2})
			if damage_dirs.size() > 6:
				damage_dirs.pop_front()
	elif ev.source_id == 0:
		hit_marker_t = 0.15
		hit_marker_kill = false
		Audio.play(&"ui.hitmarker")

func _on_killed(ev: KillEvent) -> void:
	if sim == null:
		return
	var victim := sim.character(ev.victim_id)
	var killer := sim.character(ev.killer_id)
	if victim == null:
		return
	var involves := ev.victim_id == 0 or ev.killer_id == 0
	var kname := "" if (killer == null or ev.suicide) else killer.name
	var kcol := _name_color(ev.killer_id)
	kill_feed.add_entry(kname, "#" + kcol.to_html(false), ev.weapon_id, victim.name, "#" + _name_color(ev.victim_id).to_html(false), ev.headshot, involves)
	if ev.killer_id == 0 and ev.victim_id != 0:
		hit_marker_t = 0.15
		hit_marker_kill = true
		Audio.play(&"ui.hitmarker.kill")
		var label := MatchRules.get_streak_label(ev.killer_streak)
		var multi := MatchRules.get_multi_kill_label(ev.multi_kill_count)
		if not label.is_empty():
			_show_streak(label)
		elif not multi.is_empty():
			_show_streak(multi)
	if ev.victim_id == 0:
		killer_name = "yourself" if ev.suicide or killer == null else killer.name
		killer_color = kcol if not ev.suicide else Palette.UI_DANGER
		killer_weapon = ev.weapon_id
		_stop_low_health()

func _show_streak(text: String) -> void:
	streak_text = text
	streak_t = 1.5

func add_toast(text: String, seconds: float = 3.0) -> void:
	toasts.append({"text": text, "t": seconds, "life": seconds})
	if toasts.size() > 3:
		toasts.pop_front()
	Audio.play(&"ui.toast")

func _on_boost_spawned(socket_id: StringName, _pos: Vector2) -> void:
	var where := "Beacon Crown" if socket_id == &"B01" else "Reactor Heart"
	add_toast("ROCKET BOOST deployed — %s" % where, 3.0)

func _on_time_warning(kind: StringName) -> void:
	if kind == &"one_minute":
		add_toast("1 MINUTE LEFT", 3.0)
		Audio.play(&"ui.match.one_minute")

func _on_weapon_fired(shooter_id: int, _weapon_id: StringName, _muzzle: Vector2, _dir: Vector2) -> void:
	if sim == null or shooter_id == 0:
		return
	var b := sim.character(shooter_id)
	if b and b.brain and (b.brain as BotBrain).has_token:
		attackers[shooter_id] = 1.0

# ── Per-frame ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if sim == null or not visible:
		return
	model = HudModel.snapshot(sim)
	var real := delta / maxf(Engine.time_scale, 0.01)
	if ghost_delay > 0.0:
		ghost_delay -= real
	elif ghost_health > model.health:
		ghost_health = maxf(model.health, ghost_health - 120.0 * real)
	if model.health > ghost_health or not model.alive:
		ghost_health = model.health
	hit_marker_t = maxf(0.0, hit_marker_t - real)
	streak_t = maxf(0.0, streak_t - real)
	for t in toasts:
		t.t -= real
	toasts = toasts.filter(func(t) -> bool: return t.t > 0.0)
	for d in damage_dirs:
		d.t -= real
	damage_dirs = damage_dirs.filter(func(d) -> bool: return d.t > 0.0)
	for id in attackers.keys():
		attackers[id] -= real
		if attackers[id] <= 0.0:
			attackers.erase(id)
	_update_low_health()
	_update_timer_ticks()
	canvas.queue_redraw()
	cross.queue_redraw()

## Heartbeat loop below 30 HP until healed to 45 (§7.10).
func _update_low_health() -> void:
	if model.alive and model.health < 30.0 and low_health_loop == 0 and flow.state == Enums.GameState.MATCH_ACTIVE:
		low_health_loop = Audio.play_loop(&"sfx.player.lowhealth_loop")
	elif low_health_loop != 0 and (not model.alive or model.health >= 45.0 or flow.state != Enums.GameState.MATCH_ACTIVE):
		_stop_low_health()

func _stop_low_health() -> void:
	if low_health_loop != 0:
		Audio.stop(low_health_loop)
		low_health_loop = 0

## ui.timer.warning_tick once per second in the last 10 s.
func _update_timer_ticks() -> void:
	if flow.state != Enums.GameState.MATCH_ACTIVE:
		return
	var s := int(ceil(model.time_left_s))
	if s <= 10 and s > 0 and s != _last_tick_second:
		_last_tick_second = s
		Audio.play(&"ui.timer.warning_tick")

func scoreboard_held() -> bool:
	return InputMap.has_action(&"scoreboard") and Input.is_action_pressed(&"scoreboard")
