# Implements §8.4 Kill feed widget (top-right, max 5 rows, each lives 5 s then fades 0.4 s):
# right-aligned pills "killer · weapon icon · [headshot] · victim", gold border when
# Skyra is involved.
class_name KillFeed
extends Control

class KillRow:
	var killer_name: String = ""
	var killer_color: String = "#FFFFFF"
	var weapon_id: StringName = &""
	var victim_name: String = ""
	var victim_color: String = "#FFFFFF"
	var headshot: bool = false
	var involves_human: bool = false
	var lifetime: float = 5.0
	var alpha: float = 1.0

const MAX_ROWS: int = 5
const ROW_LIFETIME: float = 5.0
const FADE_DURATION: float = 0.4
const ROW_H: float = 34.0

var rows: Array[KillRow] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func add_entry(killer: String, k_col: String, weapon: StringName, victim: String, v_col: String, is_headshot: bool = false, is_human: bool = false) -> void:
	var row := KillRow.new()
	row.killer_name = killer
	row.killer_color = k_col
	row.weapon_id = weapon
	row.victim_name = victim
	row.victim_color = v_col
	row.headshot = is_headshot
	row.involves_human = is_human
	row.lifetime = ROW_LIFETIME

	rows.append(row)
	while rows.size() > MAX_ROWS:
		rows.pop_front()
	queue_redraw()

func step(dt: float) -> void:
	var i := rows.size() - 1
	while i >= 0:
		var r := rows[i]
		r.lifetime -= dt
		if r.lifetime <= 0.0:
			rows.remove_at(i)
		elif r.lifetime < FADE_DURATION:
			r.alpha = r.lifetime / FADE_DURATION
		i -= 1

func row_count() -> int:
	return rows.size()

func _process(delta: float) -> void:
	if rows.is_empty():
		return
	step(delta)
	queue_redraw()

func _draw() -> void:
	var font := ThemeFactory.body_font()
	var fs := 22
	var right := size.x
	for i in range(rows.size()):
		var r := rows[i]
		var y := float(i) * (ROW_H + 6.0)
		var kw := font.get_string_size(r.killer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var vw := font.get_string_size(r.victim_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon_w := 64.0
		var hs_w := 26.0 if r.headshot else 0.0
		var total := 16.0 + kw + 10.0 + icon_w + hs_w + 10.0 + vw + 16.0
		var rect := Rect2(right - total, y, total, ROW_H)
		var border := Color(Palette.UI_ACCENT2, r.alpha) if r.involves_human else Color(Palette.UI_STROKE, r.alpha)
		draw_style_box(ThemeFactory.stylebox(Color(0.04, 0.06, 0.13, 0.78 * r.alpha), 17, border, 2), rect)
		var x := rect.position.x + 16.0
		var base := y + ROW_H * 0.5 + fs * 0.36
		if not r.killer_name.is_empty():
			draw_string(font, Vector2(x, base), r.killer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Color(r.killer_color), r.alpha))
		x += kw + 10.0
		if Data.weapons.has(r.weapon_id) or r.weapon_id == &"frag_grenade":
			WeaponPainter.draw_icon(self, r.weapon_id, Rect2(x, y + 5.0, icon_w, ROW_H - 10.0), Color(1, 1, 1, r.alpha), true)
		x += icon_w
		if r.headshot:
			draw_circle(Vector2(x + 13.0, y + ROW_H * 0.5), 8.0, Color(Palette.UI_DANGER, r.alpha))
			draw_circle(Vector2(x + 13.0, y + ROW_H * 0.5), 3.0, Color(1, 1, 1, r.alpha))
		x += hs_w + 10.0
		draw_string(font, Vector2(x, base), r.victim_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Color(r.victim_color), r.alpha))
