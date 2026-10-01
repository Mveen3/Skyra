# Implements §7.6 projectile visuals: tracers (Skyra's rounds gold with a white core,
# bot rounds tinted with their lightened primary), rockets, spinning saw blades with
# ghost copies (orange glow when armed), frag grenades with the shrinking LED blink, and
# flame puffs with the §4.7 colour ramp (additive glow for the first 60 % of life).
class_name ProjectileView
extends Node2D

const TRACER_WIDTH := {"magnum": 3.0, "mp5": 2.0, "ak47": 2.5, "shotgun": 1.8, "m93ba": 4.0}
const FLAME_RAMP := [
	[0.0, Color("#FFFFFF")], [0.15, Color("#FFE066")], [0.45, Color("#FF8A1F")],
	[0.75, Color("#D62828")], [1.0, Color(0.17, 0.17, 0.17, 0.0)],
]

var sim: MatchSim
var _t: float = 0.0
var _flames: Node2D

func setup(p_sim: MatchSim) -> void:
	sim = p_sim
	_flames = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flames.material = add
	add_child(_flames)
	_flames.draw.connect(_draw_flame_glows)

func _process(delta: float) -> void:
	_t += delta
	if sim == null:
		return
	queue_redraw()
	_flames.queue_redraw()

func _tint(owner_id: int) -> Color:
	var c := sim.character(owner_id)
	if c == null or c.is_human:
		return Color("#FFE08A")
	return c.profile.primary.lightened(0.5)

static func flame_color(k: float) -> Color:
	for i in range(FLAME_RAMP.size() - 1):
		var a: Array = FLAME_RAMP[i]
		var b: Array = FLAME_RAMP[i + 1]
		if k <= b[0]:
			return (a[1] as Color).lerp(b[1], (k - a[0]) / (b[0] - a[0]))
	return FLAME_RAMP.back()[1]

func _draw() -> void:
	if sim == null:
		return
	var al := WorldView.alpha()
	for p in sim.projectiles.active_projectiles:
		var pos := p.prev_pos.lerp(p.pos, al)
		match p.kind:
			Projectile.Kind.BULLET, Projectile.Kind.PELLET, Projectile.Kind.SLUG:
				var length := minf(p.travelled + p.speed * (1.0 / 60.0) * al, p.speed * 0.02)
				var w: float = TRACER_WIDTH.get(p.weapon_id, 2.0)
				var col := _tint(p.owner_id)
				var tail := pos - p.dir * length
				draw_line(tail, pos, Color(col, 0.85), w)
				draw_line(tail.lerp(pos, 0.4), pos, Color(1, 1, 1, 0.95), maxf(1.0, w * 0.45))
			Projectile.Kind.ROCKET:
				_draw_rocket(pos, p.dir)
			Projectile.Kind.SAW_BLADE:
				_draw_saw(p, pos)
			Projectile.Kind.GRENADE:
				_draw_grenade(p, pos)
			Projectile.Kind.FLAME_PUFF:
				var k := clampf(p.age / maxf(0.01, p.lifetime), 0.0, 1.0)
				var col := flame_color(k)
				draw_circle(pos, p.radius, col)

func _draw_flame_glows() -> void:
	if sim == null:
		return
	var al := WorldView.alpha()
	for p in sim.projectiles.active_projectiles:
		if p.kind != Projectile.Kind.FLAME_PUFF:
			continue
		var k := clampf(p.age / maxf(0.01, p.lifetime), 0.0, 1.0)
		if k > 0.6:
			continue
		var pos := p.prev_pos.lerp(p.pos, al)
		var col := flame_color(k)
		Palette.draw_glow(_flames, pos, p.radius * 1.8, Color(col, 0.6 * (1.0 - k / 0.6)))

func _draw_rocket(pos: Vector2, dir: Vector2) -> void:
	draw_set_transform(pos, dir.angle(), Vector2.ONE)
	var fl := 16.0 + 8.0 * sin(_t * 50.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -4), Vector2(-10, 4), Vector2(-10 - fl, 0)]), Color("#FF9F1C"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -2), Vector2(-10, 2), Vector2(-10 - fl * 0.5, 0)]), Color("#FFF3B0"))
	draw_rect(Rect2(-12.5, -6.5, 25.0, 13.0), Palette.OUTLINE)
	draw_rect(Rect2(-10, -4, 16, 8), Color("#56633E"))
	draw_colored_polygon(PackedVector2Array([Vector2(6, -4), Vector2(14, 0), Vector2(6, 4)]), Color("#D62828"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -4), Vector2(-14, -8), Vector2(-6, -4)]), Color("#3E4A2C"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, 4), Vector2(-14, 8), Vector2(-6, 4)]), Color("#3E4A2C"))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_saw(p: Projectile, pos: Vector2) -> void:
	var r := p.radius
	if p.armed:
		Palette.draw_glow(self, pos, r * 2.6, Color(1.0, 0.55, 0.1, 0.6))
	# Two ghost copies, 1/60 s behind
	var v := p.vel / 60.0
	for g in [[2.0, 0.15], [1.0, 0.3]]:
		draw_circle(pos - v * g[0], r, Color(0.8, 0.83, 0.86, g[1]))
	draw_circle(pos, r + 2.5, Palette.OUTLINE)
	draw_set_transform_matrix(Transform2D(p.spin, pos))
	draw_circle(Vector2.ZERO, r, Color("#C9D1D9") if not p.armed else Color("#FFD9A8"))
	for i in range(10):
		var a := TAU * float(i) / 10.0
		draw_colored_polygon(PackedVector2Array([Vector2(cos(a), sin(a)) * (r - 1.0), Vector2(cos(a + 0.31), sin(a + 0.31)) * (r + 4.0),
			Vector2(cos(a + 0.63), sin(a + 0.63)) * (r - 1.0)]), Color("#C9D1D9"))
	draw_arc(Vector2.ZERO, r * 0.5, 0.0, TAU, 16, Color("#9AA7B4"), 1.5)
	draw_circle(Vector2.ZERO, r * 0.25, Color("#6B7682"))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_grenade(p: Projectile, pos: Vector2) -> void:
	var fuse_total := Data.grenade.fuse_s if Data.grenade else 3.0
	var k := clampf(1.0 - p.fuse / fuse_total, 0.0, 1.0)
	var period := lerpf(0.5, 0.08, k)
	var led_on := fmod(_t, period) < period * 0.5
	var xf := Transform2D(p.spin, pos)
	WeaponPainter.draw(self, &"frag_grenade", xf, {"pin_visible": false, "led_on": led_on})
	if led_on:
		Palette.draw_glow(self, xf * Vector2(0.0, -3.0), 10.0, Color(1.0, 0.2, 0.33, 0.7))
