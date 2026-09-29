# Implements §8.4 and §9.5 HudModel continuous snapshot.
class_name HudModel
extends RefCounted

var alive: bool = true
var health: float = 100.0
var fuel: float = 100.0
var jet_locked: bool = false
var boost_t: float = 0.0
var stealth_t: float = 0.0
var burning: bool = false
var weapon_id: StringName = &""
var clip: float = 0.0
var reserve: float = 0.0 # -1 = ∞
var clip_size: int = 0
var reload_progress: float = -1.0 # -1 = not reloading
var other_weapon_id: StringName = &""
var other_clip: float = 0.0
var other_reserve: float = 0.0
var grenades: int = 0
var scope: float = 1.0
var time_left_s: float = 420.0
var kills: int = 0
var deaths: int = 0
var top_bot_name: String = ""
var top_bot_kills: int = 0
var respawn_t: float = 0.0
var killer_name: String = ""
var killer_weapon_id: StringName = &""

static func snapshot(sim: MatchSim) -> HudModel:
	var m := HudModel.new()
	if not sim:
		return m

	var h: CharacterState = sim.human_char
	if h:
		m.alive = (h.life_state == Enums.LifeState.ALIVE)
		m.health = h.health
		m.fuel = h.fuel
		m.jet_locked = h.jet_locked
		m.boost_t = h.boost_t
		m.stealth_t = h.stealth_t
		m.burning = (h.burn_t > 0.0)
		m.respawn_t = h.respawn_t

		if h.inventory:
			var w: WeaponInstance = h.inventory.active_weapon()
			if w and w.def:
				m.weapon_id = StringName(w.def.id)
				m.clip = w.clip
				m.reserve = w.reserve
				m.clip_size = w.def.clip_size
				m.scope = w.def.scope
				if w.state == Enums.WeaponState.RELOADING and w.def.reload_s > 0.0:
					m.reload_progress = clampf(1.0 - (w.state_t / w.def.reload_s), 0.0, 1.0)
				else:
					m.reload_progress = -1.0

			var ow: WeaponInstance = h.inventory.other_weapon()
			if ow and ow.def:
				m.other_weapon_id = StringName(ow.def.id)
				m.other_clip = ow.clip
				m.other_reserve = ow.reserve

			m.grenades = h.inventory.grenades

		if h.stats:
			m.kills = h.stats.kills
			m.deaths = h.stats.deaths

	if sim.rules:
		m.time_left_s = sim.rules.time_left_s

	# Top bot by kills on human
	var best_kills := -1
	var best_name := ""
	for b in sim.bot_chars:
		var k := b.stats.kills_on_human if b.stats else 0
		if k > best_kills:
			best_kills = k
			best_name = b.name
	m.top_bot_name = best_name
	m.top_bot_kills = maxi(0, best_kills)

	return m
