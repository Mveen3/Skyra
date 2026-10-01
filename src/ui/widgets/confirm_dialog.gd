# Implements the shared confirm dialog ("Quit Skyra? [Yes] [No]", §8.2 / §8.5.1): a dimmed
# modal with two buttons; Enter activates the focused one, Esc answers No.
class_name ConfirmDialog
extends Control

signal answered(yes: bool)

var _yes: Button
var _no: Button

func _init(question: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UiKit.dim_rect(0.7))
	var panel := UiKit.panel(Vector2(560, 260), Color(Palette.UI_PANEL, 0.97))
	UiKit.place_center(panel, Vector2(560, 260))
	add_child(panel)
	var q := UiKit.label(question, 40, Palette.UI_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	q.position = Vector2(0, 46)
	q.size = Vector2(560, 60)
	panel.add_child(q)
	_yes = UiKit.button("YES", Vector2(200, 64))
	_yes.position = Vector2(60, 150)
	_yes.pressed.connect(func() -> void: _answer(true))
	panel.add_child(_yes)
	_no = UiKit.button("NO", Vector2(200, 64))
	_no.position = Vector2(300, 150)
	_no.pressed.connect(func() -> void: _answer(false))
	panel.add_child(_no)
	_yes.focus_neighbor_right = _yes.get_path_to(_no)
	_no.focus_neighbor_left = _no.get_path_to(_yes)

func _ready() -> void:
	_no.grab_focus()

func _answer(yes: bool) -> void:
	answered.emit(yes)
	queue_free()

func _input(event: InputEvent) -> void:
	# Modal: swallow gameplay shortcuts while the dialog is open
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		Audio.play(&"ui.back")
		_answer(false)
		get_viewport().set_input_as_handled()
