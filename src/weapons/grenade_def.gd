# Implements §9.5 GrenadeDef and §4.5.3 Grenades.
class_name GrenadeDef
extends RefCounted

var id: StringName = &"frag_grenade"
var display_name: String = "Frag"
var fuse_s: float = 3.0
var throw_speed: float = 1150.0
var inherit_velocity: float = 0.5
var gravity: float = 1800.0
var radius: float = 10.0
var restitution: float = 0.45
var friction: float = 0.8
var rest_speed: float = 40.0
var explosion: Dictionary = {}
var throw_cooldown_s: float = 0.6
var preview_time_s: float = 1.2
var bot: Dictionary = {}
