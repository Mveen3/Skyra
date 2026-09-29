# Implements §9.5 MatchSummary.
class_name MatchSummary
extends RefCounted

var config: MatchConfig
var human: CombatStats
var bots: Array[Dictionary] = []
var rank: String = "D"
var rank_title: String = "Rookie"
var favourite_weapon_id: StringName = &"magnum"
var accuracy: float = 0.0
