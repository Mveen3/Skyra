# Implements §8.1 (5) code-built Theme: §7.2 UI palette, rounded panels/buttons, a
# visible 2-px cyan keyboard focus ring, and heading / body font variations built from
# the engine font (the optional Russo One / Rajdhani files are used when present, §7.8).
class_name ThemeFactory
extends RefCounted

static var _theme: Theme = null
static var _heading: Font = null
static var _body: Font = null

static func heading_font() -> Font:
	if _heading == null:
		_heading = _load_font("res://assets/fonts/RussoOne-Regular.ttf", 0.9, 2)
	return _heading

static func body_font() -> Font:
	if _body == null:
		_body = _load_font("res://assets/fonts/Rajdhani-Bold.ttf", 0.45, 1)
	return _body

static func _load_font(path: String, embolden: float, spacing: int) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			return f
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = embolden
	fv.spacing_glyph = spacing
	return fv

static func stylebox(bg: Color, radius: int = 12, border: Color = Color.TRANSPARENT, border_w: int = 0, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.5
	sb.content_margin_bottom = pad * 0.5
	sb.anti_aliasing = true
	return sb

static func _track(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := stylebox(bg, 6, border, 1 if border.a > 0.0 else 0, 0)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 24
	t.set_color("font_color", "Label", Palette.UI_TEXT)
	t.set_color("font_color", "Button", Palette.UI_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Palette.UI_ACCENT)
	t.set_stylebox("normal", "Button", stylebox(Color("#1E2744"), 12, Palette.UI_STROKE, 2))
	t.set_stylebox("hover", "Button", stylebox(Color("#26325A"), 12, Palette.UI_ACCENT, 2))
	t.set_stylebox("pressed", "Button", stylebox(Color("#16203F"), 12, Palette.UI_ACCENT, 2))
	t.set_stylebox("focus", "Button", stylebox(Color(0, 0, 0, 0), 12, Palette.UI_ACCENT, 2))
	t.set_stylebox("disabled", "Button", stylebox(Color("#141B34"), 12, Palette.UI_STROKE, 1))
	t.set_stylebox("panel", "Panel", stylebox(Color(Palette.UI_PANEL, 0.92), 20, Palette.UI_STROKE, 2))
	t.set_stylebox("panel", "PanelContainer", stylebox(Color(Palette.UI_PANEL, 0.92), 20, Palette.UI_STROKE, 2, 24))
	t.set_stylebox("panel", "TooltipPanel", stylebox(Palette.UI_PANEL, 8, Palette.UI_STROKE, 2))
	t.set_color("font_color", "TooltipLabel", Palette.UI_TEXT)
	# Sliders (audio settings): the track thickness comes from the content margins
	t.set_stylebox("slider", "HSlider", _track(Color("#1E2744"), Palette.UI_STROKE))
	t.set_stylebox("grabber_area", "HSlider", _track(Palette.UI_ACCENT, Color.TRANSPARENT))
	t.set_stylebox("grabber_area_highlight", "HSlider", _track(Palette.UI_ACCENT.lightened(0.2), Color.TRANSPARENT))
	# Tabs and scroll areas (settings overlay)
	t.set_stylebox("panel", "TabContainer", stylebox(Color(0, 0, 0, 0), 0))
	t.set_stylebox("tab_selected", "TabContainer", stylebox(Palette.UI_ACCENT, 10, Color.TRANSPARENT, 0, 18))
	t.set_stylebox("tab_unselected", "TabContainer", stylebox(Color("#1E2744"), 10, Color.TRANSPARENT, 0, 18))
	t.set_stylebox("tab_hovered", "TabContainer", stylebox(Color("#26325A"), 10, Color.TRANSPARENT, 0, 18))
	t.set_color("font_selected_color", "TabContainer", Color("#0B1020"))
	t.set_color("font_unselected_color", "TabContainer", Palette.UI_TEXT)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_font_size("font_size", "TabContainer", 24)
	t.set_stylebox("panel", "ScrollContainer", stylebox(Color(0, 0, 0, 0), 0))
	t.set_color("font_color", "CheckButton", Palette.UI_TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_focus_color", "CheckButton", Color.WHITE)
	t.set_stylebox("focus", "CheckButton", stylebox(Color(0, 0, 0, 0), 10, Palette.UI_ACCENT, 2))
	_theme = t
	return t
