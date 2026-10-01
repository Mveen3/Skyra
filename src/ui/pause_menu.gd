# Implements §8.5.1 Pause menu: dimmed world, 520 x 540 panel with PAUSED, score and time
# left, and RESUME / RESTART MATCH / SETTINGS / QUIT TO MENU / QUIT GAME (confirm).
class_name PauseMenu
extends Control

signal resume_requested()
signal restart_requested()
signal settings_requested()
signal menu_requested()
signal quit_requested()

var _resume: Button

func _init(kills: int, deaths: int, time_left: float) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.dim_rect(0.8))
	var panel := UiKit.panel(Vector2(520, 560), Color(Palette.UI_PANEL, 0.96))
	UiKit.place_center(panel, Vector2(520, 560))
	add_child(panel)
	var title := UiKit.label("PAUSED", 56, Palette.UI_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 26)
	title.size = Vector2(520, 70)
	panel.add_child(title)
	var info := UiKit.label("⚔ %d   ☠ %d   ⏱ %s" % [kills, deaths, UiKit.format_time(time_left)], 26, Palette.UI_SUBTEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	info.position = Vector2(0, 100)
	info.size = Vector2(520, 36)
	panel.add_child(info)
	var items := [
		["RESUME  (Esc)", resume_requested],
		["RESTART MATCH  (F5)", restart_requested],
		["SETTINGS", settings_requested],
		["QUIT TO MENU", menu_requested],
		["QUIT GAME", quit_requested],
	]
	var prev: Button = null
	for i in range(items.size()):
		var b := UiKit.button(items[i][0], Vector2(400, 64), 26)
		b.position = Vector2(60, 156 + i * 76)
		var sig: Signal = items[i][1]
		b.pressed.connect(func() -> void: sig.emit())
		panel.add_child(b)
		if prev:
			prev.focus_neighbor_bottom = prev.get_path_to(b)
			b.focus_neighbor_top = b.get_path_to(prev)
		if i == 0:
			_resume = b
		prev = b

func _ready() -> void:
	_resume.grab_focus()
