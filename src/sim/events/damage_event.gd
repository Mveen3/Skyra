# Implements §9.5 DamageEvent.
class_name DamageEvent
extends RefCounted

var target_id: int = -1
var source_id: int = -1
var weapon_id: StringName = &""
var amount: float = 0.0
var point: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.ZERO
var headshot: bool = false
var explosive: bool = false
var self_mult: float = 1.0
var is_burn: bool = false
var time: float = 0.0
