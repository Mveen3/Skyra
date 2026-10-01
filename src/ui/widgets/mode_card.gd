# Implements §8.2 mode cards: 380 x 120 card with the mode title, its rule line and the
# mode's signature weapon art; the selected card gets a 3-px gold border and glow.
class_name ModeCard
extends Control

signal chosen(mode: StringName)

var mode: StringName
var title: String
var subtitle: String
var weapons: Array[StringName] = []
var selected: bool = false
var _hover: bool = false

func _init(p_mode: StringName, p_title: String, p_subtitle: String, p_weapons: Array[StringName]) -> void:
	mode = p_mode
	title = p_title
	subtitle = p_subtitle
	weapons = p_weapons
	custom_minimum_size = Vector2(380.0, 120.0)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		chosen.emit(mode)
		accept_event()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if selected:
		var glow := ThemeFactory.stylebox(Color(Palette.UI_ACCENT2, 0.18), 18)
		draw_style_box(glow, r.grow(8.0))
	var border := Palette.UI_ACCENT2 if selected else (Palette.UI_ACCENT if (_hover or has_focus()) else Palette.UI_STROKE)
	draw_style_box(ThemeFactory.stylebox(Color("#1A2347") if selected else Color("#141B34"), 16, border, 3 if selected else 2), r)
	if has_focus():
		draw_style_box(ThemeFactory.stylebox(Color(0, 0, 0, 0), 18, Palette.UI_ACCENT, 2), r.grow(4.0))
	var font := ThemeFactory.heading_font()
	draw_string(font, Vector2(20.0, 46.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Palette.UI_ACCENT2 if selected else Palette.UI_TEXT)
	# Rule line, split on " · " so it never truncates beside the weapon art
	var lines := subtitle.split(" · ")
	for i in range(lines.size()):
		draw_string(ThemeFactory.body_font(), Vector2(20.0, 78.0 + i * 22.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, 200, 19, Palette.UI_SUBTEXT)
	# Weapon art on the right side
	var area := Rect2(size.x - 160.0, 14.0, 146.0, size.y - 28.0)
	if weapons.size() == 1:
		WeaponPainter.draw_icon(self, weapons[0], area.grow(-4.0))
	else:
		for i in range(weapons.size()):
			var h := area.size.y / float(weapons.size())
			WeaponPainter.draw_icon(self, weapons[i], Rect2(area.position + Vector2(0.0, h * i), Vector2(area.size.x, h)).grow(-3.0))
