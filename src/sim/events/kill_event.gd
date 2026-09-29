# Implements §9.5 KillEvent.
class_name KillEvent
extends RefCounted

var victim_id: int = -1
var killer_id: int = -1
var weapon_id: StringName = &""
var headshot: bool = false
var distance: float = 0.0
var time: float = 0.0
var suicide: bool = false
var killer_streak: int = 0
var multi_kill_count: int = 0
