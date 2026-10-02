# Implements §4.11 socket visuals, §7.5 pickups/items and §3.11.3 Rocket Boost FX:
# pedestals with holo rings, floating bobbing items, respawn progress rings, loose
# weapons (pulsing glow, blink in the last 3 s) and the boost capsule.
class_name PickupView
extends Node2D

const RING_CYAN := Color("#39E6FF")
const RING_GOLD := Color("#FFC53D")
const RING_GREEN := Color("#5EE38A")
const POWER_WEAPONS := ["m93ba", "rocket_launcher", "phasr"]

var sim: MatchSim
var _t: float = 0.0
var _boost_anim_t: float = 0.0
var _last_boost_phase: int = -1

var _pedestals: Node2D

func setup(p_sim: MatchSim) -> void:
	sim = p_sim
	# Pedestals never move: draw them once into a cached child layer
	_pedestals = Node2D.new()
	_pedestals.show_behind_parent = true
	add_child(_pedestals)
	_pedestals.draw.connect(_draw_static_pedestals)
	_pedestals.queue_redraw()

func _draw_static_pedestals() -> void:
	for s in sim.sockets.sockets:
		var base: Vector2 = s.def.world
		var trap := PackedVector2Array([base + Vector2(-28, 0), base + Vector2(28, 0), base + Vector2(22, -12), base + Vector2(-22, -12)])
		_pedestals.draw_colored_polygon(trap, Color("#36414D"))
		var closed: PackedVector2Array = trap.duplicate()
		closed.append(trap[0])
		_pedestals.draw_polyline(closed, Palette.OUTLINE, 2.5, true)

func _process(delta: float) -> void:
	_t += delta
	if sim and sim.boost.phase != _last_boost_phase:
		_last_boost_phase = sim.boost.phase
		_boost_anim_t = 0.0
	_boost_anim_t += delta
	queue_redraw()

func _ring_color(item: String) -> Color:
	if item == "frag_pack":
		return RING_GREEN
	if item in POWER_WEAPONS:
		return RING_GOLD
	return RING_CYAN

func _draw() -> void:
	if sim == null:
		return
	var respawn_s: float = float(Data.modes.get(str(sim.config.mode), {}).get("socket_respawn_s", 15.0))
	for s in sim.sockets.sockets:
		var base: Vector2 = s.def.world
		var col := _ring_color(s.current_item if s.is_available else s.last_item)
		_draw_pedestal(base, col)
		if s.is_available:
			_draw_socket_item(s, base, col)
		else:
			# Empty socket: ring fills clockwise during the respawn countdown
			var k := 1.0 - clampf(s.respawn_timer / maxf(0.01, respawn_s), 0.0, 1.0)
			draw_arc(base + Vector2(0.0, -34.0), 18.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(col, 0.8), 4.0)
			draw_arc(base + Vector2(0.0, -34.0), 18.0, 0.0, TAU, 32, Color(col, 0.18), 4.0)
	for lw in sim.loose_weapons:
		_draw_loose(lw)
	_draw_features()
	_draw_boost()

func _draw_pedestal(base: Vector2, col: Color) -> void:
	draw_line(base + Vector2(-21, -11), base + Vector2(21, -11), col, 2.0)
	var pulse := 0.4 + 0.4 * (0.5 + 0.5 * sin(_t * TAU))
	var ring := PackedVector2Array()
	for i in range(25):
		var a := TAU * float(i) / 24.0
		ring.append(base + Vector2(cos(a) * 30.0, -14.0 + sin(a) * 6.0))
	draw_polyline(ring, Color(col, pulse), 2.0, true)

func _draw_socket_item(s, base: Vector2, col: Color) -> void:
	var bob := 4.0 * sin(_t * TAU * 0.6 + base.x * 0.01)
	var tilt := deg_to_rad(8.0) * sin(_t * TAU * 0.6 * 0.7 + base.x * 0.02)
	var center := base + Vector2(0.0, -12.0 - 22.0 + bob)
	Palette.draw_glow(self, center, 46.0, Color(col, 0.35))
	if s.current_item == "frag_pack":
		_draw_frag_pack(center, tilt)
	else:
		_draw_weapon_centered(StringName(s.current_item), center, tilt, 1.0)

func _draw_weapon_centered(id: StringName, center: Vector2, rot: float, alpha: float, flip: bool = false) -> void:
	var b := WeaponPainter.bounds(id)
	var sx := -1.0 if flip else 1.0
	var xf := Transform2D(rot, center) * Transform2D(Vector2(sx, 0.0), Vector2(0.0, 1.0), Vector2.ZERO) * Transform2D(0.0, -b.get_center())
	WeaponPainter.draw(self, id, xf, {}, Color(1, 1, 1, alpha))

func _draw_frag_pack(center: Vector2, tilt: float) -> void:
	draw_set_transform(center, tilt, Vector2.ONE)
	# Military ammo crate: olive body with lid shading, steel edges, latches, handle, stencil
	var r := Rect2(-20.0, -14.0, 40.0, 28.0)
	var olive := Color("#556B2F")
	draw_rect(r.grow(2.5), Palette.OUTLINE)
	draw_rect(r, olive)
	draw_rect(Rect2(-20.0, -14.0, 40.0, 7.0), olive.lightened(0.22))
	draw_rect(Rect2(-20.0, 8.0, 40.0, 6.0), olive.darkened(0.25))
	draw_line(Vector2(-20.0, -7.0), Vector2(20.0, -7.0), olive.darkened(0.45), 1.2)
	for ex in [-20.0, 17.0]:
		draw_rect(Rect2(ex, -14.0, 3.0, 28.0), Color("#7D8792"))
		draw_rect(Rect2(ex, -14.0, 1.0, 28.0), Color("#B9C2CB"))
	for lx in [-11.0, 7.0]:
		draw_rect(Rect2(lx, -9.0, 4.0, 5.0), Color("#3A4048"))
		draw_rect(Rect2(lx + 1.0, -8.0, 2.0, 1.5), Color("#9AA4AE"))
	draw_arc(Vector2(0.0, -14.0), 5.0, PI, TAU, 8, Color("#2A2F36"), 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-14.0, 7.5), "FRAG ×2", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#E8E3C8"))
	draw_line(Vector2(-18.0, -12.5), Vector2(15.0, -12.5), Color(1, 1, 1, 0.25), 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for gx in [-9.0, 9.0]:
		WeaponPainter.draw(self, &"frag_grenade", Transform2D(tilt, center).translated_local(Vector2(gx, -24.0)).scaled_local(Vector2(0.75, 0.75)))

func _draw_loose(lw: LooseWeapon) -> void:
	var a := WorldView.alpha()
	var p := lw.prev_pos.lerp(lw.pos, a) + Vector2(0.0, -10.0)
	var left := lw.time_left()
	var alpha := 1.0
	if left < 3.0:
		alpha = 1.0 if fmod(_t * 6.0, 1.0) < 0.6 else 0.25
	var glow := 0.35 * (0.5 + 0.5 * sin(_t * TAU * 2.0))
	Palette.draw_glow(self, p, 42.0, Color(1, 1, 1, glow * alpha))
	_draw_weapon_centered(lw.def.id, p, 0.0, alpha, lw.facing < 0)

func _draw_boost() -> void:
	var b := sim.boost
	if b.phase == RocketBoostManager.BoostPhase.WAITING:
		return
	var base := b.current_pickup_pos
	var scale_k := 1.0
	var alpha := 1.0
	if b.phase == RocketBoostManager.BoostPhase.SPAWNING_IN:
		# Vertical cyan beam from the top of the screen, then a landing shockwave
		var k := clampf(_boost_anim_t / 0.6, 0.0, 1.0)
		draw_rect(Rect2(base.x - 14.0, base.y - 2400.0, 28.0, 2400.0 * k + 40.0), Color(0.22, 0.9, 1.0, 0.35))
		draw_rect(Rect2(base.x - 5.0, base.y - 2400.0, 10.0, 2400.0 * k + 40.0), Color(0.9, 1.0, 1.0, 0.7))
		alpha = k
	elif b.phase == RocketBoostManager.BoostPhase.DESPAWNING:
		var k := clampf(_boost_anim_t / 0.4, 0.0, 1.0)
		alpha = 1.0 - k
		scale_k = 1.0 - 0.6 * k
	elif _boost_anim_t < 0.35:
		draw_arc(base, 90.0 * _boost_anim_t / 0.35, 0.0, TAU, 40, Color(0.22, 0.9, 1.0, 1.0 - _boost_anim_t / 0.35), 6.0)
	var bob := 6.0 * sin(_t * TAU * 0.8)
	var c := base + Vector2(0.0, bob)
	# Pulsing additive-style glow (radius 60)
	Palette.draw_glow(self, c, 70.0 * scale_k, Color(1.0, 0.5, 0.15, (0.55 + 0.2 * sin(_t * 6.0)) * alpha))
	# Rotating hexagon ring (r 34, 90°/s)
	var hex := PackedVector2Array()
	for i in range(7):
		var a := deg_to_rad(90.0) * _t + TAU * float(i) / 6.0
		hex.append(c + Vector2(cos(a), sin(a)) * 34.0 * scale_k)
	draw_polyline(hex, Color(Palette.SKYRA_VISOR, alpha), 3.0, true)
	draw_set_transform(c, 0.0, Vector2(scale_k, scale_k))
	var oc := Color(Palette.OUTLINE, alpha)
	# Exhaust flame
	var fl := 14.0 + 6.0 * sin(_t * 40.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-7, 22), Vector2(7, 22), Vector2(0, 22 + fl)]), Color(0.5, 0.95, 1.0, alpha))
	# Fins
	for s in [-1.0, 1.0]:
		var fin := PackedVector2Array([Vector2(8 * s, 6), Vector2(17 * s, 20), Vector2(17 * s, 26), Vector2(8 * s, 20)])
		draw_colored_polygon(fin, Color("#FFB703", alpha))
	# Body + nose + band + window
	draw_rect(Rect2(-12.5, -24.5, 25.0, 49.0), oc)
	draw_rect(Rect2(-10.0, -22.0, 20.0, 44.0), Color("#E63946", alpha))
	draw_rect(Rect2(-10.0, 4.0, 20.0, 6.0), Color(1, 1, 1, alpha))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -22), Vector2(10, -22), Vector2(0, -40)]), Color("#F4F7FB", alpha))
	draw_circle(Vector2(0, -9), 6.5, oc)
	draw_circle(Vector2(0, -9), 5.0, Color(Palette.SKYRA_VISOR, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)

# ── Map features: launch pads and med stations ──────────────────────────────────

func _draw_features() -> void:
	if sim.features == null:
		return
	for p in sim.features.pads:
		_draw_launch_pad(p)
	for m in sim.features.meds:
		_draw_med_station(m)

func _draw_launch_pad(p: MapFeatures.Pad) -> void:
	var b := p.pos
	var hw := sim.features.pad_half_width + 6.0
	var squash := 1.0 - 0.5 * clampf(p.cool_t / 0.35, 0.0, 1.0)
	# steel base plate with hazard stripes
	var base := Rect2(b + Vector2(-hw, -9.0), Vector2(hw * 2.0, 9.0))
	draw_rect(base.grow(2.0), Palette.OUTLINE)
	draw_rect(base, Color("#3A434E"))
	var i := 0
	var x := base.position.x
	while x < base.end.x - 4.0:
		draw_colored_polygon(PackedVector2Array([Vector2(x, base.end.y), Vector2(x + 6.0, base.position.y), Vector2(x + 11.0, base.position.y), Vector2(x + 5.0, base.end.y)]), Color("#FFC53D") if i % 2 == 0 else Color("#1B1E22"))
		x += 11.0
		i += 1
	# spring coils and the launch plate (compressed right after use)
	var plate_y := b.y - 9.0 - 10.0 * squash
	for k in range(3):
		var yk := lerpf(b.y - 9.0, plate_y, (float(k) + 0.5) / 3.0)
		draw_line(Vector2(b.x - hw * 0.6, yk), Vector2(b.x + hw * 0.6, yk), Color("#9AA6B2"), 2.0)
	var plate := Rect2(Vector2(b.x - hw + 4.0, plate_y - 5.0), Vector2(hw * 2.0 - 8.0, 5.0))
	draw_rect(plate.grow(1.5), Palette.OUTLINE)
	draw_rect(plate, Color("#C9D1D9"))
	draw_line(plate.position + Vector2(2.0, 1.0), Vector2(plate.end.x - 2.0, plate.position.y + 1.0), Color(1, 1, 1, 0.8), 1.0)
	# glowing up-chevrons that pulse upward
	for k in range(3):
		var phase := fmod(_t * 1.6 + float(k) / 3.0, 1.0)
		var cy := plate_y - 14.0 - phase * 46.0
		var a := (1.0 - phase) * 0.85
		var col := Color(0.25, 0.95, 1.0, a)
		draw_polyline(PackedVector2Array([Vector2(b.x - 12.0, cy + 8.0), Vector2(b.x, cy), Vector2(b.x + 12.0, cy + 8.0)]), col, 3.0, true)
	Palette.draw_glow(self, b + Vector2(0.0, -16.0), 46.0, Color(0.2, 0.9, 1.0, 0.25 + 0.25 * (1.0 - squash)))

func _draw_med_station(m: MapFeatures.Med) -> void:
	var b := m.pos
	# wall-mounted style pedestal
	var ped := PackedVector2Array([b + Vector2(-24, 0), b + Vector2(24, 0), b + Vector2(18, -10), b + Vector2(-18, -10)])
	draw_colored_polygon(ped, Color("#36414D"))
	var closed: PackedVector2Array = ped.duplicate()
	closed.append(ped[0])
	draw_polyline(closed, Palette.OUTLINE, 2.5, true)
	var c := b + Vector2(0.0, -34.0 + 3.0 * sin(_t * 2.4))
	if m.active:
		Palette.draw_glow(self, c, 44.0, Color(0.35, 1.0, 0.45, 0.35))
		# first-aid case: white shell, red cross, handle, latch and highlight
		var r := Rect2(c - Vector2(17.0, 12.0), Vector2(34.0, 24.0))
		draw_rect(r.grow(2.5), Palette.OUTLINE)
		draw_rect(r, Color("#F2F5F8"))
		draw_rect(Rect2(r.position + Vector2(0.0, 16.0), Vector2(34.0, 8.0)), Color("#D3DAE1"))
		draw_rect(Rect2(c - Vector2(3.5, 9.0), Vector2(7.0, 18.0)), Color("#E63946"))
		draw_rect(Rect2(c - Vector2(9.0, 3.5), Vector2(18.0, 7.0)), Color("#E63946"))
		draw_arc(c + Vector2(0.0, -12.0), 6.0, PI, TAU, 8, Color("#2A2F36"), 2.0)
		draw_line(r.position + Vector2(3.0, 2.5), r.position + Vector2(30.0, 2.5), Color(1, 1, 1, 0.9), 1.2)
		draw_string(ThemeDB.fallback_font, c + Vector2(-14.0, 30.0), "+%d HP" % int(sim.features.med_heal), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1.0, 0.65, 0.8))
	else:
		# recharge ring
		var k := 1.0 - clampf(m.timer / maxf(0.01, sim.features.med_respawn_s), 0.0, 1.0)
		var g := Color(0.35, 1.0, 0.45)
		draw_arc(c, 18.0, 0.0, TAU, 32, Color(g, 0.18), 4.0)
		draw_arc(c, 18.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(g, 0.8), 4.0)
		draw_rect(Rect2(c - Vector2(2.0, 6.0), Vector2(4.0, 12.0)), Color(g, 0.5))
		draw_rect(Rect2(c - Vector2(6.0, 2.0), Vector2(12.0, 4.0)), Color(g, 0.5))
