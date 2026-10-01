# Implements §7.3.1 map chunk: one 16 x 16-tile block drawn once in _draw() (Godot caches
# the commands and culls the chunk off-screen). Backdrop chunks draw interior walls;
# tile chunks draw solids, sandbags and catwalks with the per-edge treatments.
class_name MapChunk
extends Node2D

const T: float = 64.0
const CHUNK: int = 16

var grid: TileGrid
var c0: int = 0
var r0: int = 0
var backdrop: bool = false

func setup(p_grid: TileGrid, p_c0: int, p_r0: int, p_backdrop: bool) -> void:
	grid = p_grid
	c0 = p_c0
	r0 = p_r0
	backdrop = p_backdrop
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	if backdrop:
		_draw_backdrop()
	else:
		_draw_tiles()

static func is_full(t: int) -> bool:
	return t == Enums.Tile.ROCK or t == Enums.Tile.METAL or t == Enums.Tile.CRATE

static func is_interior_air(t: int) -> bool:
	return t == Enums.Tile.AIR_INTERIOR or t == Enums.Tile.UPDRAFT

func _cols() -> Array:
	return range(c0, mini(c0 + CHUNK, grid.width))

func _rows() -> Array:
	return range(r0, mini(r0 + CHUNK, grid.height))

# ── Backdrop (z −40): interior walls behind ':' '^' cells (and solids touching them) ──

func _draw_backdrop() -> void:
	for r: int in _rows():
		var run_start := -1
		for c: int in _cols() + [c0 + CHUNK]:
			var inside: bool = c < mini(c0 + CHUNK, grid.width) and _needs_backdrop(c, r)
			if inside and run_start < 0:
				run_start = c
			elif not inside and run_start >= 0:
				draw_rect(Rect2(run_start * T, r * T, (c - run_start) * T, T), Palette.INTERIOR_BG)
				run_start = -1
	# 32-wu panel grid, pipes and updraft tint
	for r: int in _rows():
		for c: int in _cols():
			var t := grid.tile_at(c, r)
			if not is_interior_air(t) and not _is_marker_interior(c, r):
				continue
			var x := c * T
			var y := r * T
			draw_line(Vector2(x, y + 32.0), Vector2(x + T, y + 32.0), Palette.INTERIOR_GRID, 2.0)
			draw_line(Vector2(x + 32.0, y), Vector2(x + 32.0, y + T), Palette.INTERIOR_GRID, 2.0)
			if t == Enums.Tile.UPDRAFT:
				draw_rect(Rect2(x, y, T, T), Color(0.25, 0.55, 0.75, 0.10))
			elif Palette.hash01(c, r, 7) < 0.25:
				var py := y + 10.0 + floorf(Palette.hash01(c, r, 8) * 40.0)
				draw_rect(Rect2(x, py, T, 7.0), Color("#2C3350"))
				draw_line(Vector2(x, py), Vector2(x + T, py), Color("#39416A"), 1.5)
				if Palette.hash01(c, r, 9) < 0.5:
					draw_rect(Rect2(x + 26.0, py - 3.0, 10.0, 13.0), Color("#3A4466"))

func _is_marker_interior(c: int, r: int) -> bool:
	return grid.tile_at(c, r) == Enums.Tile.AIR_INTERIOR

## Interior cells get a wall; solid tiles that border the interior also get one so the
## half-tile sandbags and catwalks inside rooms sit in front of a wall, not the sky.
func _needs_backdrop(c: int, r: int) -> bool:
	var t := grid.tile_at(c, r)
	if is_interior_air(t):
		return true
	if t == Enums.Tile.HALF or t == Enums.Tile.ONE_WAY or t == Enums.Tile.AIR_EXTERIOR:
		var n := 0
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			if is_interior_air(grid.tile_at(c + d.x, r + d.y)):
				n += 1
		return n >= 2 or (t != Enums.Tile.AIR_EXTERIOR and n >= 1)
	return false

# ── Tiles (z −20) ──────────────────────────────────────────────────────────────

func _draw_tiles() -> void:
	# Base fills, merged into horizontal runs of the same tile type
	for r: int in _rows():
		var run_start := -1
		var run_type := -1
		for c: int in _cols() + [c0 + CHUNK]:
			var t: int = grid.tile_at(c, r) if c < mini(c0 + CHUNK, grid.width) else -1
			var fill := t if is_full(t) else -1
			if fill != run_type:
				if run_type >= 0:
					draw_rect(Rect2(run_start * T, r * T, (c - run_start) * T, T), _base_color(run_type))
				run_start = c
				run_type = fill
	for r: int in _rows():
		for c: int in _cols():
			match grid.tile_at(c, r):
				Enums.Tile.ROCK: _draw_rock(c, r)
				Enums.Tile.METAL: _draw_metal(c, r)
				Enums.Tile.CRATE: _draw_crate(c, r)
				Enums.Tile.HALF: _draw_sandbags(c, r)
				Enums.Tile.ONE_WAY: _draw_catwalk(c, r)
	# Outlines on every exposed edge of full solids (3 wu)
	for r: int in _rows():
		for c: int in _cols():
			if is_full(grid.tile_at(c, r)):
				_draw_outline(c, r)

func _base_color(t: int) -> Color:
	match t:
		Enums.Tile.METAL: return Palette.METAL
		Enums.Tile.CRATE: return Palette.CRATE
	return Palette.ROCK

func _exposed(c: int, r: int) -> bool:
	# Out of bounds counts as solid (world bounds behave as ROCK)
	if c < 0 or c >= grid.width or r < 0 or r >= grid.height:
		return false
	return not is_full(grid.tile_at(c, r))

func _draw_outline(c: int, r: int) -> void:
	var x := c * T
	var y := r * T
	if _exposed(c, r - 1):
		draw_line(Vector2(x - 1.5, y), Vector2(x + T + 1.5, y), Palette.OUTLINE, 3.0)
	if _exposed(c, r + 1):
		draw_line(Vector2(x - 1.5, y + T), Vector2(x + T + 1.5, y + T), Palette.OUTLINE, 3.0)
	if _exposed(c - 1, r):
		draw_line(Vector2(x, y - 1.5), Vector2(x, y + T + 1.5), Palette.OUTLINE, 3.0)
	if _exposed(c + 1, r):
		draw_line(Vector2(x + T, y - 1.5), Vector2(x + T, y + T + 1.5), Palette.OUTLINE, 3.0)

func _draw_rock(c: int, r: int) -> void:
	var x := c * T
	var y := r * T
	# 2–4 hash-placed pebbles
	var pebbles := 2 + int(Palette.hash01(c, r, 1) * 3.0)
	for k in range(pebbles):
		var px := x + 8.0 + Palette.hash01(c, r, 10 + k) * 48.0
		var py := y + 12.0 + Palette.hash01(c, r, 20 + k) * 44.0
		draw_circle(Vector2(px, py), 2.5 + Palette.hash01(c, r, 30 + k) * 3.0, Palette.ROCK_SPECK)
	if _exposed(c - 1, r):
		draw_rect(Rect2(x, y, 4.0, T), Palette.ROCK_HI)
	if _exposed(c + 1, r):
		draw_rect(Rect2(x + T - 4.0, y, 4.0, T), Palette.ROCK_SHADE)
	if _exposed(c, r + 1):
		draw_rect(Rect2(x, y + T - 5.0, T, 5.0), Palette.ROCK_SHADE)
	if _exposed(c, r - 1):
		draw_rect(Rect2(x, y, T, 6.0), Palette.MOSS)
		draw_line(Vector2(x, y + 1.5), Vector2(x + T, y + 1.5), Palette.MOSS_HI, 2.0)
		# Grass tufts: small triangles every 32 wu, hash-jittered
		for k in range(2):
			if Palette.hash01(c, r, 40 + k) < 0.7:
				var gx := x + 6.0 + k * 32.0 + Palette.hash01(c, r, 50 + k) * 18.0
				var h := 6.0 + Palette.hash01(c, r, 60 + k) * 6.0
				for j in range(3):
					var bx := gx + j * 4.0
					draw_colored_polygon(PackedVector2Array([Vector2(bx - 2.0, y), Vector2(bx + 2.0, y), Vector2(bx + (j - 1) * 1.5, y - h + absf(j - 1) * 3.0)]), Palette.MOSS_HI)

func _draw_metal(c: int, r: int) -> void:
	var x := c * T
	var y := r * T
	if _exposed(c - 1, r):
		draw_rect(Rect2(x, y, 3.0, T), Palette.METAL_HI)
	if _exposed(c + 1, r):
		draw_rect(Rect2(x + T - 3.0, y, 3.0, T), Palette.METAL_SHADE)
	if _exposed(c, r + 1):
		draw_rect(Rect2(x, y + T - 3.0, T, 3.0), Palette.METAL_SHADE)
	# Panel seam + rivets r 2 at 8 wu from the corners
	draw_rect(Rect2(x + 2.0, y + 2.0, T - 4.0, T - 4.0), Color(Palette.METAL_SHADE, 0.45), false, 1.5)
	for p in [Vector2(8, 8), Vector2(T - 8, 8), Vector2(8, T - 8), Vector2(T - 8, T - 8)]:
		draw_circle(Vector2(x, y) + p, 2.4, Palette.METAL_SHADE)
		draw_circle(Vector2(x, y) + p - Vector2(0.6, 0.6), 1.0, Palette.METAL_HI)
	# Side accent stripe every 3rd tile: amber west / teal east
	if (c + r) % 3 == 0:
		var accent := Palette.METAL_WEST_ACCENT if c < 60 else Palette.METAL_EAST_ACCENT
		draw_rect(Rect2(x + 30.0, y + 6.0, 4.0, T - 12.0), accent)
	if _exposed(c, r - 1):
		draw_rect(Rect2(x, y, T, 3.0), Palette.METAL_HI)
		# Hazard stripes on the Beacon Crown and the hangar roof edges (§7.3.1)
		if r == 8 or r == 22:
			draw_rect(Rect2(x, y + 3.0, T, 10.0), Palette.HAZARD_YELLOW)
			for k in range(4):
				var sx := x + k * 16.0
				draw_colored_polygon(PackedVector2Array([Vector2(sx, y + 13.0), Vector2(sx + 7.0, y + 13.0), Vector2(sx + 17.0, y + 3.0), Vector2(sx + 10.0, y + 3.0)]), Palette.HAZARD_BLACK)

func _draw_crate(c: int, r: int) -> void:
	var x := c * T
	var y := r * T
	for k in range(1, 4):
		draw_line(Vector2(x + 3.0, y + k * 16.0), Vector2(x + T - 3.0, y + k * 16.0), Palette.CRATE_LINE, 2.0)
	draw_line(Vector2(x + 5.0, y + 5.0), Vector2(x + T - 5.0, y + T - 5.0), Palette.CRATE_LINE, 4.0)
	draw_line(Vector2(x + T - 5.0, y + 5.0), Vector2(x + 5.0, y + T - 5.0), Palette.CRATE_LINE, 4.0)
	draw_rect(Rect2(x + 1.5, y + 1.5, T - 3.0, T - 3.0), Palette.CRATE_EDGE, false, 3.0)
	draw_line(Vector2(x + 4.0, y + 4.0), Vector2(x + T - 4.0, y + 4.0), Color("#D9A05A"), 2.0)

func _ellipse(center: Vector2, rx: float, ry: float, n: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw_sandbags(c: int, r: int) -> void:
	var x := c * T
	var y := r * T + 32.0
	var bags := [Vector2(x + 17.0, y + 23.0), Vector2(x + 47.0, y + 23.0), Vector2(x + 32.0, y + 9.0)]
	for b in bags:
		var pts := _ellipse(b, 15.0, 8.5)
		draw_colored_polygon(pts, Palette.SANDBAG)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Palette.OUTLINE, 2.5, true)
		draw_line(b + Vector2(-8.0, -1.0), b + Vector2(8.0, -1.0), Palette.SANDBAG_SEAM, 1.5)
		draw_line(b + Vector2(-9.0, -5.0), b + Vector2(-2.0, -6.0), Color("#D6C79B"), 1.5)

func _draw_catwalk(c: int, r: int) -> void:
	var x := c * T
	var y := r * T
	draw_rect(Rect2(x, y, T, 12.0), Palette.GRATE)
	for k in range(8):
		var hx := x + k * 8.0
		draw_line(Vector2(hx, y + 12.0), Vector2(hx + 8.0, y), Palette.GRATE_LINE, 1.5)
	draw_line(Vector2(x, y), Vector2(x + T, y), Palette.OUTLINE, 2.5)
	draw_line(Vector2(x, y + 12.0), Vector2(x + T, y + 12.0), Palette.OUTLINE, 2.5)
	draw_line(Vector2(x, y + 2.0), Vector2(x + T, y + 2.0), Color("#C9D3DD"), 1.5)
	# Support bracket every 2 tiles, hanging 20 wu
	if c % 2 == 0:
		var bx := x + 32.0
		draw_colored_polygon(PackedVector2Array([Vector2(bx - 6.0, y + 12.0), Vector2(bx + 6.0, y + 12.0), Vector2(bx + 2.0, y + 32.0), Vector2(bx - 2.0, y + 32.0)]), Palette.GRATE_LINE)
		draw_polyline(PackedVector2Array([Vector2(bx - 6.0, y + 12.0), Vector2(bx - 2.0, y + 32.0), Vector2(bx + 2.0, y + 32.0), Vector2(bx + 6.0, y + 12.0)]), Palette.OUTLINE, 2.0, true)
