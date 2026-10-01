# Small helpers for building the code-first UI (§2.3): labels, buttons and panels in
# 1920 x 1080 design units, plus the shared UI click/hover sounds (§7.10 Menus).
class_name UiKit
extends RefCounted

static func label(text: String, size: int = 24, color: Color = Palette.UI_TEXT, heading: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if heading:
		l.add_theme_font_override("font", ThemeFactory.heading_font())
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A themed button that plays ui.hover / ui.click (§8.1 feedback).
static func button(text: String, size: Vector2 = Vector2(400, 64), font_size: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", ThemeFactory.heading_font())
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void: Audio.play(&"ui.hover"))
	b.focus_entered.connect(func() -> void: b.pivot_offset = b.size * 0.5; b.scale = Vector2(1.03, 1.03))
	b.focus_exited.connect(func() -> void: b.scale = Vector2.ONE)
	b.pressed.connect(func() -> void: Audio.play(&"ui.click"))
	return b

static func gold_button(text: String, size: Vector2, font_size: int = 40) -> Button:
	var b := button(text, size, font_size)
	var dark := Color("#0B1020")
	for st in ["normal", "hover", "pressed", "focus"]:
		var bg := Palette.UI_ACCENT2 if st != "pressed" else Palette.UI_ACCENT2.darkened(0.15)
		if st == "hover":
			bg = Palette.UI_ACCENT2.lightened(0.15)
		var border := Color.WHITE if st == "focus" or st == "hover" else Palette.UI_ACCENT2.darkened(0.3)
		var sb := ThemeFactory.stylebox(bg, 16, border, 3)
		if st == "focus":
			sb.shadow_color = Color(Palette.UI_ACCENT2, 0.55)
			sb.shadow_size = 18
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(c, dark)
	return b

static func panel(size: Vector2, bg: Color = Color(Palette.UI_PANEL, 0.85)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	p.size = size
	p.add_theme_stylebox_override("panel", ThemeFactory.stylebox(bg, 20, Palette.UI_STROKE, 2))
	return p

static func dim_rect(alpha: float = 0.8) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.UI_BG, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r

## Centres `c` horizontally at design y `y` (anchors keep it centred on wide screens).
static func place_center_x(c: Control, y: float, size: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -size.x * 0.5
	c.offset_right = size.x * 0.5
	c.offset_top = y
	c.offset_bottom = y + size.y

## Centres `c` on screen.
static func place_center(c: Control, size: Vector2) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -size.x * 0.5
	c.offset_right = size.x * 0.5
	c.offset_top = -size.y * 0.5
	c.offset_bottom = size.y * 0.5

static func format_time(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]
