# Implements §8.5.3 Score summary: header, hero stats (kills, deaths, K/D, rank badge),
# the detail grid, the bots table and PLAY AGAIN (Enter, focused) / CHANGE SETUP (Esc) /
# QUIT. Stats reveal one by one (0.08 s stagger) with ui.summary.reveal.
class_name ScoreSummary
extends Control

signal play_again_requested()
signal change_setup_requested()
signal quit_requested()

const RANK_COLORS := {"S": Color("#FFC53D"), "A": Color("#39E6FF"), "B": Color("#5EE38A"), "C": Color("#9FB0D9"), "D": Color("#FF4D6D")}

var summary: MatchSummary
var _items: Array = [] # [label, value, color, x, y, size]
var _t: float = 0.0
var _revealed: int = 0
var _play: Button
var _panel: Panel

func _init(p_summary: MatchSummary) -> void:
	summary = p_summary
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.dim_rect(0.75))
	_panel = UiKit.panel(Vector2(1200, 800), Color(Palette.UI_PANEL, 0.96))
	UiKit.place_center(_panel, Vector2(1200, 800))
	add_child(_panel)
	_panel.draw.connect(_draw_panel)
	_build_items()
	var buttons := [["PLAY AGAIN  (Enter)", play_again_requested], ["CHANGE SETUP  (Esc)", change_setup_requested], ["QUIT", quit_requested]]
	var prev: Button = null
	for i in range(3):
		var b := UiKit.gold_button(buttons[i][0], Vector2(360, 72), 26) if i == 0 else UiKit.button(buttons[i][0], Vector2(340 if i == 1 else 200, 72), 26)
		b.position = Vector2([40, 430, 800][i], 700)
		var sig: Signal = buttons[i][1]
		b.pressed.connect(func() -> void: sig.emit())
		_panel.add_child(b)
		if prev:
			prev.focus_neighbor_right = prev.get_path_to(b)
			b.focus_neighbor_left = b.get_path_to(prev)
		if i == 0:
			_play = b
		prev = b

func _ready() -> void:
	_play.grab_focus()
	Audio.play(&"ui.summary.reveal")

func _build_items() -> void:
	var h: CombatStats = summary.human if summary.human else CombatStats.new()
	var kd := float(h.kills) / float(maxi(1, h.deaths))
	_items = [
		["KILLS", str(h.kills), Palette.UI_ACCENT2, 60, 200, 64],
		["DEATHS", str(h.deaths), Palette.UI_DANGER, 250, 200, 64],
		["K/D", "%.2f" % kd, Palette.UI_TEXT, 440, 200, 64],
		["ACCURACY", "%d%%" % int(round(summary.accuracy * 100.0)), Palette.UI_TEXT, 60, 330, 34],
		["HEADSHOTS", str(h.headshots), Palette.UI_TEXT, 290, 330, 34],
		["LONGEST KILL", "%d m" % int(round(h.longest_kill_wu / 32.0)), Palette.UI_TEXT, 520, 330, 34],
		["BEST STREAK", str(h.best_streak), Palette.UI_TEXT, 60, 430, 34],
		["DAMAGE DEALT", str(int(round(h.damage_dealt))), Palette.UI_TEXT, 290, 430, 34],
		["DAMAGE TAKEN", str(int(round(h.damage_taken))), Palette.UI_TEXT, 520, 430, 34],
		["ROCKET BOOSTS", str(h.boosts_collected), Palette.UI_TEXT, 60, 530, 34],
		["FAVOURITE WEAPON", "", Palette.UI_TEXT, 290, 530, 34],
	]

func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	var target := int(_t / 0.08)
	if target > _revealed and _revealed < _items.size() + 2:
		_revealed = target
		if _revealed <= _items.size() + 1:
			Audio.play(&"ui.summary.reveal", Vector2.INF, {"volume_db": -8.0})
	_panel.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			Audio.play(&"ui.back")
			change_setup_requested.emit()
			get_viewport().set_input_as_handled()

func _draw_panel() -> void:
	var p := _panel
	var hf := ThemeFactory.heading_font()
	var bf := ThemeFactory.body_font()
	p.draw_string(hf, Vector2(60, 86), "MATCH OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Palette.UI_TEXT)
	var cfg := summary.config
	if cfg:
		var mode_name := "Mini Post" if cfg.mode == &"mini_post" else "Sniper Post"
		p.draw_string(bf, Vector2(60, 126), "%s · %d bots · %d min" % [mode_name, cfg.bot_count, cfg.duration_s / 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.UI_SUBTEXT)
	for i in range(mini(_revealed, _items.size())):
		var it: Array = _items[i]
		p.draw_string(bf, Vector2(it[3], it[4]), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.UI_SUBTEXT)
		if it[0] == "FAVOURITE WEAPON":
			var fav: StringName = summary.favourite_weapon_id
			if Data.weapons.has(fav):
				WeaponPainter.draw_icon(p, fav, Rect2(it[3], it[4] + 8, 150, 50))
				p.draw_string(bf, Vector2(it[3] + 160, it[4] + 44), (Data.weapons[fav] as WeaponDef).display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.UI_TEXT)
		else:
			p.draw_string(hf, Vector2(it[3], it[4] + 12 + it[5]), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, it[5], it[2])
	# Rank badge
	if _revealed > 3:
		var c := Vector2(700, 180)
		var col: Color = RANK_COLORS.get(summary.rank, Palette.UI_TEXT)
		p.draw_circle(c, 70.0, Color(col, 0.2))
		p.draw_arc(c, 64.0, 0.0, TAU, 48, col, 5.0)
		var rw := hf.get_string_size(summary.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
		p.draw_string(hf, c + Vector2(-rw * 0.5, 34), summary.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 96, col)
		var tw := bf.get_string_size(summary.rank_title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		p.draw_string(bf, c + Vector2(-tw * 0.5, 104), summary.rank_title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col)
	# Bots table
	if _revealed > _items.size():
		var x := 840.0
		p.draw_string(bf, Vector2(x, 180), "BOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.UI_SUBTEXT)
		p.draw_string(bf, Vector2(x + 100, 180), "KILLED YOU", HORIZONTAL_ALIGNMENT_CENTER, 130, 20, Palette.UI_SUBTEXT)
		p.draw_string(bf, Vector2(x + 250, 180), "DEATHS", HORIZONTAL_ALIGNMENT_CENTER, 90, 20, Palette.UI_SUBTEXT)
		var rows := summary.bots.duplicate()
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["kills_on_human"]) > int(b["kills_on_human"]))
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var y := 226.0 + i * 52.0
			p.draw_rect(Rect2(x - 12, y - 32, 340, 44), Color(1, 1, 1, 0.03 if i % 2 == 0 else 0.0))
			p.draw_string(hf, Vector2(x, y), str(row["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(str(row["color"])))
			p.draw_string(hf, Vector2(x + 100, y), str(row["kills_on_human"]), HORIZONTAL_ALIGNMENT_CENTER, 130, 28, Palette.UI_TEXT)
			p.draw_string(hf, Vector2(x + 250, y), str(row["deaths"]), HORIZONTAL_ALIGNMENT_CENTER, 90, 28, Palette.UI_TEXT)
