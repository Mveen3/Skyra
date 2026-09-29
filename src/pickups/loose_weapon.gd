# Implements §4.10.4 Loose weapon entity.
class_name LooseWeapon
extends RefCounted

var id: int = 0
var def: WeaponDef = null
var clip: int = 0
var reserve: int = 0

var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var height: float = 20.0
var half_w: float = 20.0 # 40 x 20 box
var grounded: bool = false
var ground_is_one_way: bool = false
var drop_through_t: float = 0.0

var age: float = 0.0
var lifetime: float = 20.0
var active: bool = true

func aabb() -> Rect2:
	return Rect2(pos.x - half_w, pos.y - height, half_w * 2.0, height)

func step(dt: float, grid: TileGrid) -> void:
	if not active: return

	age += dt
	if age >= lifetime:
		active = false
		return

	# Updraft and gravity
	var in_updraft := grid.is_updraft(pos + Vector2(0.0, -10.0))
	var ay := -1200.0 if in_updraft else 1800.0
	vel.y += ay * dt
	vel.y = minf(vel.y, 1100.0)

	# Ground friction
	if grounded:
		vel.x = move_toward(vel.x, 0.0, 2400.0 * dt)
	else:
		vel.x = move_toward(vel.x, 0.0, 200.0 * dt)

	# Move via AabbMover
	AabbMover.move(self, vel * dt, grid, dt, half_w, 0.0)
