# Implements §9.5 InputFrame.
class_name InputFrame
extends RefCounted

var move_x: int = 0
var jet_held: bool = false
var jetpack_held: bool:
	get: return jet_held
	set(v): jet_held = v
var jet_pressed: bool = false
var jump_pressed: bool:
	get: return jet_pressed
	set(v): jet_pressed = v
var crouch: bool = false
var crouch_held: bool:
	get: return crouch
	set(v): crouch = v
var fire_held: bool = false
var fire_pressed: bool = false
var aim_world: Vector2 = Vector2.ZERO
var grenade_pressed: bool = false
var grenade_held: bool = false
var grenade_released: bool = false
var grenade_angle: float = 0.0
var reload_pressed: bool = false
var switch_pressed: bool = false
var slot_select: int = -1
var pickup_pressed: bool = false
var drop_pressed: bool = false

func clear_edges() -> void:
	jet_pressed = false
	fire_pressed = false
	grenade_pressed = false
	grenade_released = false
	reload_pressed = false
	switch_pressed = false
	slot_select = -1
	pickup_pressed = false
	drop_pressed = false

func copy_from(other: InputFrame) -> void:
	move_x = other.move_x
	jet_held = other.jet_held
	jet_pressed = other.jet_pressed
	crouch = other.crouch
	fire_held = other.fire_held
	fire_pressed = other.fire_pressed
	aim_world = other.aim_world
	grenade_pressed = other.grenade_pressed
	grenade_held = other.grenade_held
	grenade_released = other.grenade_released
	reload_pressed = other.reload_pressed
	switch_pressed = other.switch_pressed
	slot_select = other.slot_select
	pickup_pressed = other.pickup_pressed
	drop_pressed = other.drop_pressed
