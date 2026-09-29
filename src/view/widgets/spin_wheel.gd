# Implements §8.2.1 Duration spin wheel widget (clamped 5..10, default 7).
class_name SpinWheel
extends Control

signal value_changed(new_value: int)

const MIN_VALUE: int = 5
const MAX_VALUE: int = 10
const DEFAULT_VALUE: int = 7
const SLOT_HEIGHT: float = 56.0

var value: int = DEFAULT_VALUE
var drag_accum_y: float = 0.0

func _init(initial_value: int = DEFAULT_VALUE) -> void:
	value = clampi(initial_value, MIN_VALUE, MAX_VALUE)

func set_value(v: int) -> void:
	var clamped := clampi(v, MIN_VALUE, MAX_VALUE)
	if clamped != value:
		value = clamped
		value_changed.emit(value)

func adjust(delta: int) -> void:
	set_value(value + delta)

func on_mouse_wheel(wheel_down: bool) -> void:
	# §8.2.1: wheel down = +1, wheel up = -1
	adjust(1 if wheel_down else -1)

func on_drag(delta_y: float) -> void:
	# §8.2.1: vertical drag moves 1 value per 56 px
	drag_accum_y += delta_y
	while drag_accum_y >= SLOT_HEIGHT:
		drag_accum_y -= SLOT_HEIGHT
		adjust(-1) # dragging down scrolls up / decrements
	while drag_accum_y <= -SLOT_HEIGHT:
		drag_accum_y += SLOT_HEIGHT
		adjust(1) # dragging up scrolls down / increments

func on_key_input(keycode: Key) -> void:
	# §8.2.1: ↑/↓ and +/-
	match keycode:
		KEY_UP, KEY_EQUAL, KEY_KP_ADD:
			adjust(1)
		KEY_DOWN, KEY_MINUS, KEY_KP_SUBTRACT:
			adjust(-1)
