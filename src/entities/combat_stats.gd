# Implements §9.5 CombatStats.
class_name CombatStats
extends RefCounted

var kills: int = 0
var deaths: int = 0
var kills_on_human: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var headshots: int = 0
var longest_kill_wu: float = 0.0
var best_streak: int = 0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var boosts_collected: int = 0
var kills_by_weapon: Dictionary = {}
var last_hit_shot_id: int = -1 # accuracy bookkeeping: last shot already counted as a hit
