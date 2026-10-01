# Implements §6.9 decor and landmarks (render-only, no collision): beacon mast + rotating
# light cone, neon sign, wind turbines, buoy balloons, chains, hangar signs, dropships,
# reactor core, furnace vats, boiler pipes, interior lamps and updraft streaks/fans.
# Static art is drawn once; animated pieces redraw every frame.
class_name DecorRenderer
extends Node2D

const T: float = 64.0

var grid: TileGrid
var _static: Node2D
var _anim: Node2D
var _glow: Node2D
var _fore: Node2D
var _t: float = 0.0
var _lamps: Array[Vector2] = []
var _updraft_cells: Array[Vector2i] = []
var _neon_on: bool = true
var _neon_t: float = 0.0

func setup(p_grid: TileGrid) -> void:
	grid = p_grid
	_find_lamps_and_shafts()
	_static = _layer(C.Z_MAP_BACKDROP + 1, _draw_static)
	_anim = _layer(C.Z_MAP_BACKDROP + 2, _draw_anim)
	_glow = _layer(C.Z_FX - 1, _draw_glow)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_fore = _layer(C.Z_FOREGROUND, _draw_fore)

func _layer(z: int, cb: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.z_as_relative = false
	add_child(n)
	n.draw.connect(cb.bind(n))
	n.queue_redraw()
	return n

func _find_lamps_and_shafts() -> void:
	for r in range(grid.height):
		for c in range(grid.width):
			var t := grid.tile_at(c, r)
			if t == Enums.Tile.UPDRAFT:
				_updraft_cells.append(Vector2i(c, r))
			if (t == Enums.Tile.AIR_INTERIOR) and c % 6 == 3 and MapChunk.is_full(grid.tile_at(c, r - 1)):
				_lamps.append(Vector2(c * T + 32.0, r * T + 6.0))

var _view: Rect2 = Rect2(-1e9, -1e9, 2e9, 2e9)

func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_2d() as GameCamera
	if cam:
		_view = cam.view_rect_world().grow(320.0)
	_neon_t -= delta
	if _neon_t <= 0.0:
		_neon_t = 1.0
		_neon_on = randf() > 0.01 # 1 % flicker chance per second
	_anim.queue_redraw()
	_glow.queue_redraw()
	_fore.queue_redraw()

static func _tile(c: float, r: float) -> Vector2:
	return Vector2(c * T, r * T)

# ── Static landmarks ─────────────────────────────────────────────────────────────

func _draw_static(n: Node2D) -> void:
	# Beacon mast: lattice on the Crown (cols 58–61, rows 3–7)
	var mb := _tile(58.5, 8.0)
	var mt := _tile(58.5, 3.4)
	var mb2 := _tile(61.5, 8.0)
	var mt2 := _tile(61.0, 3.4)
	for pair in [[mb, mt], [mb2, mt2]]:
		n.draw_line(pair[0], pair[1], Palette.OUTLINE, 9.0)
		n.draw_line(pair[0], pair[1], Palette.METAL_HI, 5.0)
	for k in range(6):
		var y := lerpf(mb.y, mt.y, float(k) / 6.0)
		var y2 := lerpf(mb.y, mt.y, float(k + 1) / 6.0)
		n.draw_line(Vector2(lerpf(mb.x, mt.x, float(k) / 6.0), y), Vector2(lerpf(mb2.x, mt2.x, float(k + 1) / 6.0), y2), Palette.METAL, 3.0)
		n.draw_line(Vector2(lerpf(mb2.x, mt2.x, float(k) / 6.0), y), Vector2(lerpf(mb.x, mt.x, float(k + 1) / 6.0), y2), Palette.METAL, 3.0)
	n.draw_rect(Rect2(_tile(58.6, 2.9), Vector2(2.9 * T, 0.6 * T)), Palette.OUTLINE)
	n.draw_rect(Rect2(_tile(58.7, 3.0), Vector2(2.7 * T, 0.4 * T)), Palette.METAL_SHADE)

	# Wind turbine masts on the perch shelter roofs (col 6 west / col 113 east, rows 3–6)
	for col in [6.5, 113.5]:
		n.draw_line(_tile(col, 7.0), _tile(col, 3.5), Palette.OUTLINE, 10.0)
		n.draw_line(_tile(col, 7.0), _tile(col, 3.5), Palette.METAL_HI, 6.0)

	# Buoy balloon cables (cols 44–47 / 72–75, rows 1–4)
	for bc in [45.0, 46.0, 73.0, 74.0]:
		n.draw_line(_tile(bc, 5.0), _tile(bc, 2.2), Color(Palette.OUTLINE, 0.8), 2.0)

	# Hangar signs on the roof beam (row 23) and parked dropship silhouettes (rows 23–27)
	var font := ThemeDB.fallback_font
	for sign in [[43.0, "HANGAR W-01", Palette.LAMP_WEST], [71.0, "HANGAR E-02", Palette.LAMP_EAST]]:
		n.draw_string(font, _tile(sign[0], 23.55), sign[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(sign[2], 0.85))
	for ship_x in [41.5, 69.5]:
		_draw_dropship(n, _tile(ship_x, 27.6))

	# Neon sign frame on the Spire front (cols 56–63, rows 10–11)
	n.draw_rect(Rect2(_tile(55.6, 10.1), Vector2(8.8 * T, 1.7 * T)), Color("#101426"))
	n.draw_rect(Rect2(_tile(55.6, 10.1), Vector2(8.8 * T, 1.7 * T)), Palette.OUTLINE, false, 4.0)

	# Furnace vats (cols 4–14, rows 42–44) and boiler pipes (cols 105–115, rows 42–44)
	for k in range(3):
		var vx := 4.5 + k * 3.4
		var vat := Rect2(_tile(vx, 43.2), Vector2(2.4 * T, 1.6 * T))
		n.draw_rect(vat.grow(3.0), Palette.OUTLINE)
		n.draw_rect(vat, Color("#4A3A3A"))
		n.draw_rect(Rect2(vat.position + Vector2(8.0, 6.0), Vector2(vat.size.x - 16.0, 14.0)), Palette.FURNACE)
	for k in range(4):
		var py := 42.4 + k * 0.6
		n.draw_line(_tile(105.0, py), _tile(115.5, py), Palette.OUTLINE, 22.0)
		n.draw_line(_tile(105.0, py), _tile(115.5, py), Palette.METAL_EAST_ACCENT.darkened(0.2), 16.0)
		n.draw_line(_tile(105.0, py) + Vector2(0, -4), _tile(115.5, py) + Vector2(0, -4), Palette.METAL_HI, 3.0)

	# Reactor housing ring (background, cols 57–62, rows 50–52)
	n.draw_circle(_tile(60.0, 51.4), 92.0, Palette.OUTLINE)
	n.draw_circle(_tile(60.0, 51.4), 86.0, Color("#23302A"))

	# Updraft fans at the shaft bottoms
	for fan in [[17.0, 48.6], [99.0, 48.6], [58.0, 44.4]]:
		n.draw_rect(Rect2(_tile(fan[0], fan[1]), Vector2(4.0 * T, 0.35 * T)), Palette.OUTLINE)
		n.draw_rect(Rect2(_tile(fan[0], fan[1]) + Vector2(4, 3), Vector2(4.0 * T - 8.0, 0.35 * T - 6.0)), Palette.METAL_SHADE)

	# Interior lamp fixtures
	for lp in _lamps:
		n.draw_rect(Rect2(lp + Vector2(-10.0, -6.0), Vector2(20.0, 8.0)), Palette.OUTLINE)
		var warm := lp.x < 3840.0
		n.draw_rect(Rect2(lp + Vector2(-7.0, -4.0), Vector2(14.0, 5.0)), Palette.LAMP_WEST if warm else Palette.LAMP_EAST)

func _draw_dropship(n: Node2D, base: Vector2) -> void:
	var col := Color("#2B3352")
	var hull := PackedVector2Array([base + Vector2(0, -60), base + Vector2(90, -110), base + Vector2(420, -110),
		base + Vector2(560, -70), base + Vector2(600, -40), base + Vector2(540, -10), base + Vector2(40, -10)])
	n.draw_colored_polygon(hull, col)
	var closed: PackedVector2Array = hull.duplicate()
	closed.append(hull[0])
	n.draw_polyline(closed, Palette.OUTLINE, 4.0, true)
	n.draw_colored_polygon(PackedVector2Array([base + Vector2(430, -100), base + Vector2(530, -70), base + Vector2(430, -70)]), Color("#3D4E7A"))
	n.draw_rect(Rect2(base + Vector2(120, -10), Vector2(18, 10)), Palette.OUTLINE)
	n.draw_rect(Rect2(base + Vector2(440, -10), Vector2(18, 10)), Palette.OUTLINE)

# ── Animated landmarks ───────────────────────────────────────────────────────────

func _draw_anim(n: Node2D) -> void:
	# Turbine blades (3, radius 90, 40°/s)
	for col in [6.5, 113.5]:
		var hub := _tile(col, 3.5)
		if not _view.has_point(hub):
			continue
		for b in range(3):
			var a := deg_to_rad(40.0) * _t + TAU * float(b) / 3.0
			var tip := hub + Vector2(cos(a), sin(a)) * 90.0
			n.draw_line(hub, tip, Palette.OUTLINE, 11.0)
			n.draw_line(hub, tip, Color("#E8EEF5"), 6.0)
		n.draw_circle(hub, 9.0, Palette.OUTLINE)
		n.draw_circle(hub, 6.0, Palette.METAL_HI)
	# Buoy balloons, bobbing ±4 wu
	for bal in [[45.5, Palette.UI_DANGER], [73.5, Palette.LAMP_EAST]]:
		var bob := 4.0 * sin(_t * 1.7 + bal[0])
		var c := _tile(bal[0], 1.8) + Vector2(0.0, bob)
		n.draw_circle(c, 46.0, Palette.OUTLINE)
		n.draw_circle(c, 42.0, bal[1])
		for s in [-1.0, 1.0]:
			n.draw_line(c + Vector2(14.0 * s, -38.0), c + Vector2(14.0 * s, 38.0), Color.WHITE, 6.0)
		n.draw_circle(c + Vector2(-14.0, -14.0), 9.0, Color(1, 1, 1, 0.4))
	# Hanging chains under the drift rocks (sine ±6°)
	for cx in [31.5, 33.5, 85.5, 87.5]:
		var top := _tile(cx, 12.0)
		var sway := deg_to_rad(6.0) * sin(_t * 1.3 + cx)
		var prev := top
		for k in range(1, 9):
			var p := top + Vector2(sin(sway) * k * 18.0, cos(sway) * k * 18.0)
			n.draw_line(prev, p, Palette.OUTLINE, 6.0)
			n.draw_line(prev, p, Palette.GRATE_LINE, 3.0)
			prev = p
	if _view.intersects(Rect2(_tile(55.0, 9.0), Vector2(10.0 * T, 4.0 * T))):
		_draw_neon(n)
	if _view.intersects(Rect2(_tile(50.0, 44.0), Vector2(20.0 * T, 12.0 * T))):
		_draw_reactor(n)
	if _view.intersects(Rect2(_tile(0.0, 40.0), Vector2(20.0 * T, 10.0 * T))):
		_draw_furnace(n)
	_draw_fans(n)

func _draw_neon(n: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var neon_a := 1.0 if _neon_on else 0.25
	var sp := _tile(56.2, 11.35)
	n.draw_string_outline(font, sp, "OUTPOST SKYRA", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, 10, Color(Palette.SKYRA_VISOR, 0.35 * neon_a))
	n.draw_string(font, sp, "OUTPOST SKYRA", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, Color(Color("#FF3FA4").lerp(Palette.SKYRA_VISOR, 0.5 + 0.5 * sin(_t)), neon_a))

func _draw_reactor(n: Node2D) -> void:
	# Reactor core: pulsing green sphere (r 70, 1.2 Hz) + electric arcs every 0.4 s
	var core := _tile(60.0, 51.4)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 1.2)
	n.draw_circle(core, 70.0 + 6.0 * pulse, Color(Palette.REACTOR, 0.85))
	n.draw_circle(core, 44.0, Color("#D9FFD2"))
	var arc_seed := int(_t / 0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = arc_seed
	for k in range(3):
		var a := rng.randf_range(0.0, TAU)
		var prev := core + Vector2(cos(a), sin(a)) * 40.0
		for j in range(4):
			var p := core + Vector2(cos(a), sin(a)) * (60.0 + j * 18.0) + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14))
			n.draw_line(prev, p, Color("#E6FFDA"), 3.0)
			prev = p

func _draw_furnace(n: Node2D) -> void:
	# Furnace molten glow pulse
	for k in range(3):
		var vx := 4.5 + k * 3.4
		var g := 0.6 + 0.4 * sin(_t * 3.0 + k)
		n.draw_rect(Rect2(_tile(vx, 43.2) + Vector2(8.0, 6.0), Vector2(2.4 * T - 16.0, 14.0)), Color(1.0, 0.75, 0.3, g))

func _draw_fans(n: Node2D) -> void:
	# Spinning fan blades (360°/s)
	for fan in [[19.0, 48.75], [101.0, 48.75], [60.0, 44.55]]:
		var hub := _tile(fan[0], fan[1])
		if not _view.has_point(hub):
			continue
		for b in range(4):
			var a := TAU * _t + TAU * float(b) / 4.0
			n.draw_line(hub, hub + Vector2(cos(a) * 110.0, sin(a) * 9.0), Palette.GRATE, 5.0)

## Additive glows: beacon light cone, lamps, reactor and furnace.
func _draw_glow(n: Node2D) -> void:
	# Beacon light cone: length 900 wu, 18°, period 6 s, #E6FFFF α 0.25
	var head := _tile(60.0, 3.1)
	var a := TAU * _t / 6.0
	var dir := Vector2(cos(a), sin(a) * 0.35 - 0.15).normalized()
	var half := deg_to_rad(9.0)
	n.draw_colored_polygon(PackedVector2Array([head, head + dir.rotated(-half) * 900.0, head + dir.rotated(half) * 900.0]),
		Color(0.9, 1.0, 1.0, 0.25))
	Palette.draw_glow(n, head, 60.0, Color(0.9, 1.0, 1.0, 0.8))
	for lp in _lamps:
		if not _view.has_point(lp):
			continue
		var col := Palette.LAMP_WEST if lp.x < 3840.0 else Palette.LAMP_EAST
		Palette.draw_glow(n, lp + Vector2(0.0, 24.0), 130.0, Color(col, 0.22))
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 1.2)
	Palette.draw_glow(n, _tile(60.0, 51.4), 230.0, Color(Palette.REACTOR, 0.35 + 0.15 * pulse))
	Palette.draw_glow(n, _tile(9.5, 43.8), 360.0, Color(Palette.FURNACE, 0.25))

## Foreground: rising updraft streaks (α 0.25).
func _draw_fore(n: Node2D) -> void:
	for cell in _updraft_cells:
		if not _view.has_point(Vector2(cell.x * T, cell.y * T)):
			continue
		var h := Palette.hash01(cell.x, 0, 3)
		var speed := 380.0 + h * 200.0
		var x := cell.x * T + 8.0 + Palette.hash01(cell.x, cell.y, 4) * 48.0
		var y0 := cell.y * T + fposmod(-_t * speed + Palette.hash01(cell.x, cell.y, 5) * 64.0, T)
		n.draw_line(Vector2(x, y0), Vector2(x, y0 + 22.0), Palette.UPDRAFT_STREAK, 2.5)
