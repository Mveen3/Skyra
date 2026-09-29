# Implements §3.1 TileGrid collision queries.
class_name TileGrid
extends RefCounted

var width: int = 120
var height: int = 60
var cols: int:
	get: return width
var rows: int:
	get: return height
var tile_size: int = 64
var tiles: PackedByteArray = PackedByteArray()

func load_from(map_data: MapData) -> void:
	width = map_data.width
	height = map_data.height
	tile_size = map_data.tile_size
	tiles = map_data.tiles.duplicate()

func load_from_ascii(ascii_rows: Array[String]) -> void:
	height = ascii_rows.size()
	width = ascii_rows[0].length() if height > 0 else 0
	tile_size = 64
	tiles.resize(width * height)
	for r in range(height):
		var line := ascii_rows[r]
		for c in range(width):
			var ch := line[c]
			var t := Enums.Tile.AIR_EXTERIOR
			match ch:
				".": t = Enums.Tile.AIR_EXTERIOR
				":": t = Enums.Tile.AIR_INTERIOR
				"^": t = Enums.Tile.UPDRAFT
				"#": t = Enums.Tile.ROCK
				"M": t = Enums.Tile.METAL
				"C": t = Enums.Tile.CRATE
				"h": t = Enums.Tile.HALF
				"=": t = Enums.Tile.ONE_WAY
				_: t = Enums.Tile.AIR_EXTERIOR
			tiles[r * width + c] = t

func tile_at(col: int, row: int) -> int:
	if col < 0 or col >= width or row < 0 or row >= height:
		return Enums.Tile.ROCK
	var idx := row * width + col
	if idx < 0 or idx >= tiles.size():
		return Enums.Tile.ROCK
	return tiles[idx]

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 64.0)), int(floor(p.y / 64.0)))

func solid_rects_in(aabb: Rect2, include_one_way: bool = false) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var c0 := int(floor(aabb.position.x / 64.0))
	var c1 := int(floor(aabb.end.x / 64.0))
	var r0 := int(floor(aabb.position.y / 64.0))
	var r1 := int(floor(aabb.end.y / 64.0))
	
	# Clamp search bounds or include outside bounds as rock rects
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var t := tile_at(c, r)
			var world_x := float(c * 64)
			var world_y := float(r * 64)
			
			if t == Enums.Tile.ROCK or t == Enums.Tile.METAL or t == Enums.Tile.CRATE:
				var r_rect := Rect2(world_x, world_y, 64.0, 64.0)
				if aabb.intersects(r_rect):
					result.append(r_rect)
			elif t == Enums.Tile.HALF:
				var h_rect := Rect2(world_x, world_y + 32.0, 64.0, 32.0)
				if aabb.intersects(h_rect):
					result.append(h_rect)
			elif include_one_way and t == Enums.Tile.ONE_WAY:
				var ow_rect := Rect2(world_x, world_y, 64.0, 16.0)
				if aabb.intersects(ow_rect):
					result.append(ow_rect)
					
	return result

func one_way_rects_in(aabb: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var c0 := int(floor(aabb.position.x / 64.0))
	var c1 := int(floor(aabb.end.x / 64.0))
	var r0 := int(floor(aabb.position.y / 64.0))
	var r1 := int(floor(aabb.end.y / 64.0))
	
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if tile_at(c, r) == Enums.Tile.ONE_WAY:
				var ow := Rect2(c * 64.0, r * 64.0, 64.0, 16.0)
				if aabb.intersects(ow):
					result.append(ow)
	return result

func one_way_rects_in_x_range(x0: float, x1: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var c0 := int(floor(x0 / 64.0))
	var c1 := int(floor(x1 / 64.0))
	for r in range(height):
		for c in range(c0, c1 + 1):
			if tile_at(c, r) == Enums.Tile.ONE_WAY:
				result.append(Rect2(c * 64.0, r * 64.0, 64.0, 16.0))
	return result

func is_updraft(p: Vector2) -> bool:
	var c := cell_of(p)
	return tile_at(c.x, c.y) == Enums.Tile.UPDRAFT

func is_interior(p: Vector2) -> bool:
	var c := cell_of(p)
	var t := tile_at(c.x, c.y)
	return t == Enums.Tile.AIR_INTERIOR or t == Enums.Tile.UPDRAFT

func surface_at(p: Vector2) -> int:
	var c := cell_of(p)
	var t := tile_at(c.x, c.y)
	match t:
		Enums.Tile.ROCK: return Enums.Surface.ROCK
		Enums.Tile.METAL, Enums.Tile.ONE_WAY: return Enums.Surface.METAL
		Enums.Tile.CRATE: return Enums.Surface.WOOD
		Enums.Tile.HALF: return Enums.Surface.SAND
		_: return Enums.Surface.NONE

func raycast(a: Vector2, b: Vector2, mask: int = GridRaycast.MASK_SOLIDS) -> Dictionary:
	return GridRaycast.raycast(self, a, b, mask)
