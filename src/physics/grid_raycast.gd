# Implements §3.1.1 Amanatides-Woo DDA Grid Raycast.
class_name GridRaycast
extends RefCounted

const MASK_SOLIDS: int = 1
const MASK_ONE_WAY: int = 2
const MASK_PROJECTILE: int = 1
const MASK_LOS: int = 1
const MASK_GRENADE: int = 3
const MASK_LASER: int = 1

enum Axis { NONE, X, Y }

static func raycast(tile_grid, a: Vector2, b: Vector2, mask: int = MASK_SOLIDS) -> Dictionary:
	var d := b - a
	var length := d.length()
	if length < 1e-4:
		return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO, "tile": Enums.Tile.AIR_EXTERIOR}

	var cell := Vector2i(int(floor(a.x / 64.0)), int(floor(a.y / 64.0)))
	var step_x := 1 if d.x > 0 else (-1 if d.x < 0 else 0)
	var step_y := 1 if d.y > 0 else (-1 if d.y < 0 else 0)

	var tMax_x: float
	if d.x != 0.0:
		var next_x := float((cell.x + (1 if step_x > 0 else 0)) * 64)
		tMax_x = (next_x - a.x) / d.x
	else:
		tMax_x = INF

	var tMax_y: float
	if d.y != 0.0:
		var next_y := float((cell.y + (1 if step_y > 0 else 0)) * 64)
		tMax_y = (next_y - a.y) / d.y
	else:
		tMax_y = INF

	var tDelta_x: float = (64.0 / absf(d.x)) if d.x != 0.0 else INF
	var tDelta_y: float = (64.0 / absf(d.y)) if d.y != 0.0 else INF

	var last_axis: int = Axis.NONE
	var mask_solids := (mask & MASK_SOLIDS) != 0
	var mask_one_way := (mask & MASK_ONE_WAY) != 0

	var max_steps: int = int(ceil(length / 32.0)) + 60
	for step_idx in range(max_steps):
		var tile: int = tile_grid.tile_at(cell.x, cell.y)

		# Full solid check (ROCK, METAL, CRATE)
		if mask_solids and (tile == Enums.Tile.ROCK or tile == Enums.Tile.METAL or tile == Enums.Tile.CRATE):
			var t_entry: float = 0.0
			var normal := Vector2.ZERO
			if last_axis == Axis.X:
				t_entry = tMax_x - tDelta_x
				normal = Vector2(-step_x, 0)
			elif last_axis == Axis.Y:
				t_entry = tMax_y - tDelta_y
				normal = Vector2(0, -step_y)
			else:
				normal = -d.normalized()
			t_entry = clampf(t_entry, 0.0, 1.0)
			return {
				"hit": true,
				"t": t_entry,
				"point": a + d * t_entry,
				"normal": normal,
				"tile": tile
			}

		# Half tile (sandbags)
		if mask_solids and tile == Enums.Tile.HALF:
			var half_rect := Rect2(cell.x * 64.0, cell.y * 64.0 + 32.0, 64.0, 32.0)
			var slab := Shapes.segment_vs_aabb(a, b, half_rect)
			if slab.hit:
				return {
					"hit": true,
					"t": slab.t,
					"point": slab.point,
					"normal": slab.normal,
					"tile": tile
				}

		# One-way platform
		if mask_one_way and tile == Enums.Tile.ONE_WAY:
			var ow_rect := Rect2(cell.x * 64.0, cell.y * 64.0, 64.0, 16.0)
			# Only lands from above: d.y > 0 and start above top of tile
			if d.y > 0 and a.y <= ow_rect.position.y:
				var slab := Shapes.segment_vs_aabb(a, b, ow_rect)
				if slab.hit and slab.normal == Vector2(0, -1):
					return {
						"hit": true,
						"t": slab.t,
						"point": slab.point,
						"normal": slab.normal,
						"tile": tile
					}

		# Advance DDA
		if tMax_x < tMax_y:
			if tMax_x > 1.0:
				break
			cell.x += step_x
			tMax_x += tDelta_x
			last_axis = Axis.X
		else:
			if tMax_y > 1.0:
				break
			cell.y += step_y
			tMax_y += tDelta_y
			last_axis = Axis.Y

	return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO, "tile": Enums.Tile.AIR_EXTERIOR}
