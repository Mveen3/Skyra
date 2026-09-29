# Implements §9.5 MapData.
class_name MapData
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var tile_size: int = 64
var width: int = 120
var height: int = 60
var tiles: PackedByteArray = PackedByteArray()
var sockets: Array[SocketDef] = []
var zones: Array[ZoneDef] = []

func tile(col: int, row: int) -> int:
	if col < 0 or col >= width or row < 0 or row >= height:
		return Enums.Tile.ROCK
	var idx := row * width + col
	if idx < 0 or idx >= tiles.size():
		return Enums.Tile.ROCK
	return tiles[idx]

func zone_at(cell: Vector2i) -> ZoneDef:
	for z in zones:
		for r in z.rects:
			if r.has_point(cell):
				return z
	return null
