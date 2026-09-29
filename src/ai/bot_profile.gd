# Implements §9.5 BotProfile and Appendix D.
class_name BotProfile
extends RefCounted

var id: StringName = &""
var name: String = ""
var archetype: String = ""
var primary: Color = Color.WHITE
var color: String:
	get: return "#" + primary.to_html(false)
var secondary: Color = Color.BLACK
var visor: Color = Color.CYAN
var helmet: StringName = &""
var aggression: float = 0.5
var accuracy_mult: float = 1.0
var reaction_mult: float = 1.0
var range_mult: float = 1.0
var jet_hop_per_min: float = 10.0
var grenade_affinity: float = 0.5
var weapon_pref: Dictionary = {}
