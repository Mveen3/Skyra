# Implements the §8.4 HUD panels drawn from the HudModel snapshot: portrait, health bar
# (ghost damage), jetpack fuel (burnout blink, boost ∞), status badges, FPS, match timer,
# mini-scoreboard chips, weapon panel, hint bar, streak banner, toasts, respawn overlay
# and the hold-Tab scoreboard. Coordinates are 1920 x 1080 design units, 24-px margins.
class_name HudCanvas
extends Control

var hud: HudRoot
var _t: float = 0.0

func _init(p_hud: HudRoot) -> void:
	hud = p_hud
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta

func _hf() -> Font:
	return ThemeFactory.heading_font()

func _bf() -> Font:
	return ThemeFactory.body_font()

func _text(pos: Vector2, s: String, fs: int, col: Color, heading: bool = false, align_w: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := _hf() if heading else _bf()
	draw_string_outline(f, pos, s, align, align_w, fs, 6, Color(0.04, 0.05, 0.1, 0.75 * col.a))
	draw_string(f, pos, s, align, align_w, fs, col)

func _centered(y: float, s: String, fs: int, col: Color, heading: bool = true) -> void:
	_text(Vector2(0.0, y), s, fs, col, heading, size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _draw() -> void:
	if hud.sim == null:
		return
	var m := hud.model
	_draw_status(m)
	_draw_timer(m)
	if m.alive:
		_draw_weapon_panel(m)
	_text(Vector2(24.0, size.y - 24.0), "Esc Pause · F5 Restart · Tab Scores · E Pick up · Q Switch · G Frag", 16, Color(Palette.UI_TEXT, 0.55))
	if Settings.data and bool(Settings.data.display.get("show_fps", false)):
		_text(Vector2(24.0, 130.0), "%d FPS" % Engine.get_frames_per_second(), 16, Palette.UI_OK)
	_draw_streak()
	_draw_toasts()
	if not m.alive:
		_draw_respawn(m)
	if hud.scoreboard_held():
		_draw_scoreboard(m)

# ── Status panel ─────────────────────────────────────────────────────────────────

func _draw_status(m: HudModel) -> void:
	# Portrait: Skyra's helmet in a rounded frame
	var pr := Rect2(24, 24, 56, 56)
	draw_style_box(ThemeFactory.stylebox(Color(Palette.UI_PANEL, 0.85), 12, Palette.UI_ACCENT2, 2), pr)
	var hc := pr.get_center() + Vector2(0, 4)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-12, -10), hc + Vector2(3, -14), hc + Vector2(-3, -24), hc + Vector2(-16, -17)]), Palette.SKYRA_TRIM)
	draw_circle(hc, 17.0, Palette.OUTLINE)
	draw_circle(hc, 15.0, Palette.SKYRA_ARMOUR)
	draw_rect(Rect2(hc + Vector2(-2, -4), Vector2(16, 9)), Palette.SKYRA_VISOR)

	# Health bar 320 x 22 with ghost damage bar and value text
	var hb := Rect2(92, 28, 320, 22)
	draw_style_box(ThemeFactory.stylebox(Color(0.04, 0.05, 0.1, 0.8), 6, Palette.UI_STROKE, 2, 0), hb.grow(2))
	var hp := clampf(m.health / 100.0, 0.0, 1.0)
	var ghost := clampf(hud.ghost_health / 100.0, 0.0, 1.0)
	if ghost > hp:
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * ghost, hb.size.y)), Color(1, 1, 1, 0.75))
	var hcol := Palette.UI_OK if m.health > 60.0 else (Palette.UI_ACCENT2 if m.health >= 30.0 else Palette.UI_DANGER)
	if m.health < 30.0:
		hcol = hcol.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_t * TAU * 1.5)))
	draw_rect(Rect2(hb.position, Vector2(hb.size.x * hp, hb.size.y)), hcol)
	_text(Vector2(hb.position.x, hb.end.y - 3), "%d" % int(ceil(m.health)), 20, Palette.UI_TEXT, true, hb.size.x - 8, HORIZONTAL_ALIGNMENT_RIGHT)

	# Jetpack fuel 320 x 12: unlock tick at 15 %, burnout blinks red, boost shows ∞
	var fb := Rect2(92, 58, 320, 12)
	draw_rect(fb.grow(2), Color(0.04, 0.05, 0.1, 0.8))
	if m.boost_t > 0.0:
		var shimmer := 0.75 + 0.25 * sin(_t * 12.0)
		draw_rect(fb, Color(1.0, 0.55, 0.12, shimmer))
		_text(Vector2(fb.end.x + 8, fb.end.y + 4), "∞", 22, Color("#FFB703"), true)
	else:
		var fcol := Palette.UI_ACCENT
		if m.jet_locked:
			fcol = Palette.UI_DANGER if fmod(_t * 4.0, 1.0) < 0.5 else Palette.UI_DANGER.darkened(0.5)
		draw_rect(Rect2(fb.position, Vector2(fb.size.x * clampf(m.fuel / 100.0, 0.0, 1.0), fb.size.y)), fcol)
		draw_line(Vector2(fb.position.x + fb.size.x * 0.15, fb.position.y - 3), Vector2(fb.position.x + fb.size.x * 0.15, fb.end.y + 3), Palette.UI_TEXT, 2.0)

	# Status badges (28 px): CLOAKED, BOOST, BURNING
	var bx := 92.0
	if m.stealth_t > 0.0:
		bx = _badge(bx, "CLOAKED", Palette.UI_ACCENT, m.stealth_t / 2.0)
	if m.boost_t > 0.0:
		var col := Palette.UI_DANGER if m.boost_t < 2.0 else Color("#FF8A1F")
		bx = _badge(bx, "BOOST %.1f" % m.boost_t, col, m.boost_t / 10.0)
	if m.burning:
		bx = _badge(bx, "BURNING", Palette.FURNACE, -1.0)

func _badge(x: float, label: String, col: Color, frac: float) -> float:
	var y := 80.0
	var tw := _bf().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var r := Rect2(x, y, 40 + tw, 28)
	draw_style_box(ThemeFactory.stylebox(Color(col, 0.18), 14, col, 2, 0), r)
	var c := Vector2(x + 15, y + 14)
	if frac >= 0.0:
		draw_arc(c, 8.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 24, col, 4.0)
	else:
		draw_circle(c, 6.0 + sin(_t * 18.0), col)
	draw_string(_bf(), Vector2(x + 30, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.UI_TEXT)
	return r.end.x + 8.0

# ── Timer and mini-scoreboard ───────────────────────────────────────────────────

func _draw_timer(m: HudModel) -> void:
	var t := m.time_left_s
	var col := Palette.UI_TEXT
	var sc := 1.0
	if t < 10.0:
		col = Palette.UI_DANGER
		sc = 1.0 + 0.1 * maxf(0.0, 1.0 - fmod(t, 1.0) * 4.0)
	elif t < 60.0:
		col = Palette.UI_ACCENT2
	var s := UiKit.format_time(t)
	var fs := int(44.0 * sc)
	var w := _hf().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_style_box(ThemeFactory.stylebox(Color(0.04, 0.06, 0.13, 0.6), 14), Rect2(size.x * 0.5 - 90, 14, 180, 54))
	_text(Vector2(size.x * 0.5 - w * 0.5, 58), s, fs, col, true)
	# Chips: ⚔ kills · ☠ deaths · leading bot
	var chips: Array = [["⚔ %d" % m.kills, Palette.UI_ACCENT2], ["☠ %d" % m.deaths, Palette.UI_DANGER]]
	if m.top_bot_kills > 0:
		var col_b := Palette.UI_TEXT
		for b in hud.sim.bot_chars:
			if b.name == m.top_bot_name:
				col_b = b.profile.primary
		chips.append(["%s %d" % [m.top_bot_name.to_upper(), m.top_bot_kills], col_b])
	var widths: Array[float] = []
	var total := 0.0
	for c in chips:
		var w2 := _bf().get_string_size(c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 28.0
		widths.append(w2)
		total += w2 + 8.0
	var x := size.x * 0.5 - total * 0.5
	for i in range(chips.size()):
		var r := Rect2(x, 74, widths[i], 30)
		draw_style_box(ThemeFactory.stylebox(Color(0.04, 0.06, 0.13, 0.7), 15, chips[i][1], 2, 0), r)
		draw_string(_bf(), Vector2(x + 14, 96), chips[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, chips[i][1])
		x += widths[i] + 8.0

# ── Weapon panel (bottom-right, 380 x 120) ──────────────────────────────────────

func _ammo_text(id: StringName, clip: float, reserve: float) -> Array:
	var def: WeaponDef = Data.weapons.get(id)
	if def == null:
		return ["", ""]
	if def.fire_mode == Enums.FireMode.CONTINUOUS:
		var pct := int(round(clip / float(def.clip_size) * 100.0))
		return ["%d%%" % pct, "+%d%%" % int(round(reserve / float(def.clip_size) * 100.0))]
	var res := "∞" if reserve < 0.0 else str(int(reserve))
	return [str(int(clip)), res]

func _draw_weapon_panel(m: HudModel) -> void:
	var r := Rect2(size.x - 24 - 380, size.y - 24 - 120, 380, 120)
	draw_style_box(ThemeFactory.stylebox(Color(0.04, 0.06, 0.13, 0.72), 16, Palette.UI_STROKE, 2), r)
	if m.weapon_id == &"":
		_text(r.position + Vector2(0, 58), "NO AMMO", 34, Palette.UI_DANGER, true, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text(r.position + Vector2(0, 94), "find a weapon (E)", 22, Palette.UI_TEXT, false, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var def: WeaponDef = Data.weapons[m.weapon_id]
		var icon := Rect2(r.position + Vector2(14, 10), Vector2(160, 64))
		WeaponPainter.draw_icon(self, m.weapon_id, icon)
		if m.reload_progress >= 0.0:
			var c := icon.get_center()
			draw_arc(c, 40.0, -PI * 0.5, -PI * 0.5 + TAU * m.reload_progress, 40, Palette.UI_ACCENT, 4.0)
		_text(r.position + Vector2(16, 104), def.display_name.to_upper(), 22, Palette.UI_TEXT, true)
		var ammo := _ammo_text(m.weapon_id, m.clip, m.reserve)
		var clip_col := Palette.UI_TEXT
		if m.clip <= 0.0:
			_text(r.position + Vector2(196, 58), "RELOAD", 36, Palette.UI_DANGER, true)
		else:
			if m.clip <= float(m.clip_size) * 0.25:
				clip_col = Palette.UI_ACCENT2
			_text(r.position + Vector2(196, 58), ammo[0], 44, clip_col, true)
			var cw := _hf().get_string_size(ammo[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
			_text(r.position + Vector2(204 + cw, 58), "/ " + ammo[1], 24, Palette.UI_SUBTEXT, true)
	# Secondary weapon + key hint
	if m.other_weapon_id != &"":
		var sr := Rect2(r.position + Vector2(196, 70), Vector2(72, 28))
		WeaponPainter.draw_icon(self, m.other_weapon_id, sr, Color(1, 1, 1, 0.75))
		var oa := _ammo_text(m.other_weapon_id, m.other_clip, m.other_reserve)
		draw_string(_bf(), r.position + Vector2(274, 92), "%s/%s  Q" % [oa[0], oa[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.UI_SUBTEXT)
	# Grenades: icons x count + hint
	var gy := r.position.y - 40
	var gx := r.end.x - 24
	draw_string(_bf(), Vector2(gx - 90, gy + 24), "G / RMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(Palette.UI_TEXT, 0.6))
	for i in range(m.grenades):
		var gr := Rect2(gx - 120 - i * 26, gy, 22, 32)
		WeaponPainter.draw_icon(self, &"frag_grenade", gr)

# ── Banners, toasts, respawn overlay, scoreboard ────────────────────────────────

func _draw_streak() -> void:
	if hud.streak_t <= 0.0:
		return
	var k := 1.0 - hud.streak_t / 1.5
	var sc := lerpf(1.3, 1.0, minf(1.0, k * 4.0))
	var alpha := clampf(hud.streak_t / 0.3, 0.0, 1.0)
	var fs := int(56.0 * sc)
	_centered(size.y * 0.3, hud.streak_text, fs, Color(Palette.UI_ACCENT2, alpha))

func _draw_toasts() -> void:
	var y := size.y * 0.2
	for t in hud.toasts:
		var alpha := clampf(float(t.t) / 0.3, 0.0, 1.0)
		var w := _bf().get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 48.0
		var r := Rect2(size.x * 0.5 - w * 0.5, y - 30, w, 40)
		draw_style_box(ThemeFactory.stylebox(Color(Palette.UI_PANEL, 0.88 * alpha), 20, Color(Palette.UI_ACCENT, alpha), 2, 0), r)
		draw_string(_bf(), Vector2(r.position.x + 24, y - 3), t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(Palette.UI_TEXT, alpha))
		y += 48.0

func _draw_respawn(m: HudModel) -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	_centered(c.y - 70, "ELIMINATED by %s" % hud.killer_name, 44, hud.killer_color)
	if Data.weapons.has(hud.killer_weapon) or hud.killer_weapon == &"frag_grenade":
		WeaponPainter.draw_icon(self, hud.killer_weapon, Rect2(c.x - 60, c.y - 50, 120, 46))
	var k := clampf(1.0 - m.respawn_t / 2.0, 0.0, 1.0)
	draw_arc(c + Vector2(0, 50), 26.0, 0.0, TAU, 40, Color(Palette.UI_STROKE, 0.8), 5.0)
	draw_arc(c + Vector2(0, 50), 26.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, Palette.UI_ACCENT, 5.0)
	_centered(c.y + 120, "Respawning in %.1f" % maxf(0.0, m.respawn_t), 28, Palette.UI_TEXT, false)

func _draw_scoreboard(m: HudModel) -> void:
	var sim := hud.sim
	var w := 720.0
	var rows: Array = []
	for b in sim.bot_chars:
		rows.append(b)
	rows.sort_custom(func(a: CharacterState, b: CharacterState) -> bool:
		if a.stats.kills_on_human != b.stats.kills_on_human:
			return a.stats.kills_on_human > b.stats.kills_on_human
		return a.id < b.id)
	var h := 110.0 + 48.0 * (rows.size() + 1)
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y * 0.5 - h * 0.5, w, h)
	draw_style_box(ThemeFactory.stylebox(Color(Palette.UI_PANEL, 0.94), 18, Palette.UI_STROKE, 2), r)
	var cfg := sim.config
	var mode_name := "Mini Post" if cfg.mode == &"mini_post" else "Sniper Post"
	draw_string(_hf(), r.position + Vector2(30, 48), "%s · %d bots · %s left" % [mode_name, cfg.bot_count, UiKit.format_time(m.time_left_s)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.UI_TEXT)
	draw_string(_bf(), r.position + Vector2(30, 90), "NAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.UI_SUBTEXT)
	draw_string(_bf(), r.position + Vector2(440, 90), "KILLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.UI_SUBTEXT)
	draw_string(_bf(), r.position + Vector2(580, 90), "DEATHS", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.UI_SUBTEXT)
	var y := r.position.y + 136.0
	var human := sim.human_char
	draw_rect(Rect2(r.position.x + 14, y - 32, w - 28, 44), Color(Palette.UI_ACCENT2, 0.12))
	draw_string(_hf(), Vector2(r.position.x + 30, y), "SKYRA", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.UI_ACCENT2)
	draw_string(_hf(), Vector2(r.position.x + 450, y), str(human.stats.kills), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.UI_TEXT)
	draw_string(_hf(), Vector2(r.position.x + 600, y), str(human.stats.deaths), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.UI_TEXT)
	for b: CharacterState in rows:
		y += 48.0
		draw_string(_hf(), Vector2(r.position.x + 30, y), b.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, b.profile.primary)
		draw_string(_hf(), Vector2(r.position.x + 450, y), str(b.stats.kills_on_human), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.UI_TEXT)
		draw_string(_hf(), Vector2(r.position.x + 600, y), str(b.stats.deaths), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.UI_TEXT)
