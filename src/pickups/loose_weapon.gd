# Implements §4.10.4 Loose weapon entity: a dropped weapon lying in the world with
# its exact ammo state, simple AABB physics, updraft lift and a 20-s lifetime.
class_name LooseWeapon
extends RefCounted

var id: int = 0
var def: WeaponDef = null
var clip: float = 0.0
var reserve: float = 0.0 # -1 = infinite

var pos: Vector2 = Vector2.ZERO # bottom-centre of the 40 x 20 box
var prev_pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var height: float = 20.0
var half_w: float = 20.0 # 40 x 20 box
var grounded: bool = false
var ground_is_one_way: bool = false
var hit_wall: bool = false
var drop_through_t: float = 0.0
var facing: int = 1

var age: float = 0.0
var lifetime: float = 20.0
var active: bool = true

func aabb() -> Rect2:
	return Rect2(pos.x - half_w, pos.y - height, half_w * 2.0, height)

## Centre of the item, used for pickup reach (§4.10.3).
func centre() -> Vector2:
	return pos + Vector2(0.0, -height * 0.5)

func time_left() -> float:
	return lifetime - age

func step(dt: float, grid: TileGrid) -> void:
	if not active: return
	prev_pos = pos

	age += dt
	if age >= lifetime:
		active = false
		return

	# Updraft and gravity (§3.6: items get -1200 wu/s² in updrafts, so they still sink slowly)
	var in_updraft := grid.is_updraft(pos + Vector2(0.0, -10.0))
	vel.y += (1800.0 - 1200.0 if in_updraft else 1800.0) * dt
	vel.y = minf(vel.y, 1100.0)

	# Ground friction (§3.8)
	if grounded:
		vel.x = move_toward(vel.x, 0.0, 2400.0 * dt)
	else:
		vel.x = move_toward(vel.x, 0.0, 200.0 * dt)

	AabbMover.move(self, vel * dt, grid, dt, half_w, 0.0)
