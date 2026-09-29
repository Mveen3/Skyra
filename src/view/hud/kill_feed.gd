# Implements §8.4 Kill feed widget (max 5 rows, 5 s lifetime).
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

var rows: Array[KillRow] = []

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
