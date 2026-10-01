# Implements §8.7 Human InputFrame construction: held states are sampled every tick,
# press/release edges are latched in _unhandled_input since the previous tick (so a
# press + release within one tick is never lost), and aim = mouse position in the world.
class_name HumanInput
extends Node

## Any CanvasItem inside the world (WorldView); used to map the mouse to world space.
var world_canvas: CanvasItem = null
## Set by the HUD while the cursor hovers its clickable buttons (§8.4).
var suppress_fire: bool = false
## Gameplay input is ignored outside SPAWNING / MATCH_ACTIVE (menus, pause).
var enabled: bool = false

var _frame: InputFrame = InputFrame.new()
var _jet_pressed: bool = false
var _fire_pressed: bool = false
var _grenade_pressed: bool = false
var _grenade_released: bool = false
var _reload_pressed: bool = false
var _switch_pressed: bool = false
var _slot_select: int = -1
var _pickup_pressed: bool = false
var _drop_pressed: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or event.is_echo():
		return
	if event.is_action_pressed(&"jetpack"):
		_jet_pressed = true
	if event.is_action_pressed(&"fire") and not suppress_fire:
		_fire_pressed = true
	if event.is_action_pressed(&"throw_grenade"):
		_grenade_pressed = true
	if event.is_action_released(&"throw_grenade"):
		_grenade_released = true
	if event.is_action_pressed(&"reload"):
		_reload_pressed = true
	if event.is_action_pressed(&"switch_weapon"):
		_switch_pressed = true
	if event.is_action_pressed(&"weapon_slot_1"):
		_slot_select = 0
	if event.is_action_pressed(&"weapon_slot_2"):
		_slot_select = 1
	if event.is_action_pressed(&"pickup_swap"):
		_pickup_pressed = true
	if event.is_action_pressed(&"drop_weapon"):
		_drop_pressed = true

func aim_world() -> Vector2:
	if world_canvas and world_canvas.is_inside_tree():
		return world_canvas.get_global_mouse_position()
	return Vector2.ZERO

## Called once per Sim tick by GameFlow.
func build_frame() -> InputFrame:
	var f := _frame
	f.clear_edges()
	if not enabled:
		f.move_x = 0
		f.jet_held = false
		f.crouch = false
		f.fire_held = false
		f.grenade_held = false
		f.aim_world = aim_world()
		_clear_latches()
		return f
	var right := Input.is_action_pressed(&"move_right")
	var left := Input.is_action_pressed(&"move_left")
	f.move_x = (1 if right else 0) - (1 if left else 0)
	f.jet_held = Input.is_action_pressed(&"jetpack")
	f.crouch = Input.is_action_pressed(&"crouch")
	f.fire_held = Input.is_action_pressed(&"fire") and not suppress_fire
	f.grenade_held = Input.is_action_pressed(&"throw_grenade")
	f.aim_world = aim_world()
	f.jet_pressed = _jet_pressed
	f.fire_pressed = _fire_pressed
	f.grenade_pressed = _grenade_pressed
	f.grenade_released = _grenade_released
	f.reload_pressed = _reload_pressed
	f.switch_pressed = _switch_pressed
	f.slot_select = _slot_select
	f.pickup_pressed = _pickup_pressed
	f.drop_pressed = _drop_pressed
	_clear_latches()
	return f

func _clear_latches() -> void:
	_jet_pressed = false
	_fire_pressed = false
	_grenade_pressed = false
	_grenade_released = false
	_reload_pressed = false
	_switch_pressed = false
	_slot_select = -1
	_pickup_pressed = false
	_drop_pressed = false
