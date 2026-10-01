# Implements §8.5.2 in-match restart prompt: "Restart match?  F5 / Enter = Yes · Esc = No",
# shown for 3 s after F5 without pausing the Sim (GameFlow owns the confirm keys).
class_name RestartPrompt
extends Control

var flow: GameFlow

func _init(p_flow: GameFlow) -> void:
	flow = p_flow
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	visible = flow.state == Enums.GameState.MATCH_ACTIVE and flow.restart_prompt_active
	if visible:
		queue_redraw()

func _draw() -> void:
	var w := 760.0
	var h := 110.0
	var r := Rect2((size.x - w) * 0.5, size.y * 0.42, w, h)
	draw_style_box(ThemeFactory.stylebox(Color(Palette.UI_PANEL, 0.95), 18, Palette.UI_ACCENT2, 3), r)
	var font := ThemeFactory.heading_font()
	var t1 := "RESTART MATCH?"
	var t2 := "F5 / Enter = Yes  ·  Esc = No   (%.0f)" % ceil(flow.restart_prompt_timer)
	var w1 := font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(font, Vector2(r.get_center().x - w1 * 0.5, r.position.y + 50), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Palette.UI_ACCENT2)
	var bf := ThemeFactory.body_font()
	var w2 := bf.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(bf, Vector2(r.get_center().x - w2 * 0.5, r.position.y + 90), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.UI_TEXT)
