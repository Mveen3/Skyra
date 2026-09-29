# Implements §9.5 ExplosionEvent.
class_name ExplosionEvent
extends RefCounted

var pos: Vector2 = Vector2.ZERO
var radius: float = 0.0
var max_damage: float = 0.0
var min_damage: float = 0.0
var knockback: float = 0.0
var self_mult: float = 1.0
var owner_id: int = -1
var weapon_id: StringName = &""
