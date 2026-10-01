# Implements §3.10.4 crosshair & per-weapon reticles at the mouse (spread ring showing the
# true cone at the cursor distance), §7.6 hit markers, and the world-anchored §8.4 widgets:
# pickup prompt, damage-direction wedges and off-screen indicators (Rocket Boost, bots
# firing at Skyra).
class_name Crosshair
extends Control

var hud: HudRoot
var _t: float = 0.0

func _init(p_hud: HudRoot) -> void:
	hud = p_hud
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta

func _xf() -> Transform2D:
	return hud.world_view.get_global_transform_with_canvas() if hud.world_view else Transform2D.IDENTITY

func _to_screen(world: Vector2) -> Vector2:
	return _xf() * world

func _draw() -> void:
	if hud.sim == null or hud.world_view == null:
		return
	var h := hud.sim.human_char
	_draw_damage_dirs(h)
	_draw_offscreen()
	if h.life_state == Enums.LifeState.ALIVE:
		_draw_pickup_prompt(h)
		if hud.flow.state == Enums.GameState.MATCH_ACTIVE or hud.flow.state == Enums.GameState.SPAWNING:
			_draw_reticle(h)
	_draw_hit_marker()

# ── Reticles ─────────────────────────────────────────────────────────────────────

func _line(a: Vector2, b: Vector2, col: Color, w: float = 2.0) -> void:
	draw_line(a, b, Color(0.04, 0.05, 0.1, 0.6 * col.a), w + 2.5)
	draw_line(a, b, col, w)

func _draw_reticle(h: CharacterState) -> void:
	var mouse := get_local_mouse_position()
	var w := h.inventory.active_weapon()
	var col := Color(1, 1, 1, 0.92)
	if w == null:
		_line(mouse + Vector2(-8, 0), mouse + Vector2(8, 0), col)
		_line(mouse + Vector2(0, -8), mouse + Vector2(0, 8), col)
		return
	var def := w.def
	var xf := _xf()
	var zoom := xf.get_scale().x
	var muzzle_s := xf * WeaponLogic.muzzle_of(h)
	var dist_px := mouse.distance_to(muzzle_s)
	var spread := SpreadModel.calc_spread_deg(def, w.bloom, h.vel.x, h.grounded, h.crouching)
	var ring := SpreadModel.crosshair_ring_radius_px(dist_px, deg_to_rad(spread))
	match str(def.id):
		"magnum":
			_line(mouse + Vector2(-9, 0), mouse + Vector2(-3, 0), col)
			_line(mouse + Vector2(3, 0), mouse + Vector2(9, 0), col)
			_line(mouse + Vector2(0, -9), mouse + Vector2(0, -3), col)
			_line(mouse + Vector2(0, 3), mouse + Vector2(0, 9), col)
			draw_arc(mouse, ring, 0.0, TAU, 32, Color(col, 0.35), 1.5)
		"mp5", "ak47":
			for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_line(mouse + d * (ring + 2.0), mouse + d * (ring + 12.0), col)
			draw_circle(mouse, 2.0, col)
		"shotgun":
			draw_arc(mouse, maxf(ring, 10.0), 0.0, TAU, 40, Color(0.04, 0.05, 0.1, 0.5), 4.5)
			draw_arc(mouse, maxf(ring, 10.0), 0.0, TAU, 40, col, 2.0)
			draw_circle(mouse, 2.0, col)
		"flamethrower":
			var reach := 360.0 * zoom
			var base := muzzle_s
			var dir := (mouse - base).normalized()
			var a0 := dir.angle() - deg_to_rad(7.0)
			draw_arc(base, reach, a0, a0 + deg_to_rad(14.0), 16, Color(1.0, 0.6, 0.2, 0.8), 3.0)
			draw_circle(mouse, 3.0, col)
		"phasr":
			var s := 9.0
			draw_polyline(PackedVector2Array([mouse + Vector2(0, -s), mouse + Vector2(s, 0), mouse + Vector2(0, s), mouse + Vector2(-s, 0), mouse + Vector2(0, -s)]), Palette.UI_ACCENT, 2.0, true)
			draw_circle(mouse, 1.5, col)
		"rocket_launcher":
			draw_arc(mouse, 10.0, 0.0, TAU, 24, col, 2.0)
			var splash := 220.0 * zoom
			for i in range(24):
				var a := TAU * float(i) / 24.0
				draw_arc(mouse, splash, a, a + TAU / 48.0, 4, Color(1.0, 0.45, 0.3, 0.55), 2.0)
		"saw_gun":
			draw_arc(mouse, 14.0, 0.0, TAU, 32, col, 2.0)
			for i in range(8):
				var a := TAU * float(i) / 8.0 + _t * 3.0
				var p := mouse + Vector2(cos(a), sin(a)) * 14.0
				draw_line(p, p + Vector2(cos(a), sin(a)) * 6.0, col, 2.0)
		"m93ba":
			_draw_scope(mouse, muzzle_s, xf, h)
		_:
			draw_arc(mouse, ring, 0.0, TAU, 32, col, 2.0)
	if h.inventory.grenade_aiming:
		draw_arc(mouse, 22.0, 0.0, TAU, 32, Color(1.0, 0.35, 0.35, 0.8), 2.0)

## Black Arrow: full scope reticle with mil-dots and the range read-out in metres (1 m = 32 wu).
func _draw_scope(mouse: Vector2, _muzzle_s: Vector2, xf: Transform2D, h: CharacterState) -> void:
	var r := 46.0
	var red := Color("#FF3355")
	draw_arc(mouse, r, 0.0, TAU, 48, Color(0.04, 0.05, 0.1, 0.55), 6.0)
	draw_arc(mouse, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 2.0)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_line(mouse + d * 6.0, mouse + d * (r + 14.0), Color(1, 1, 1, 0.9), 1.5)
		for k in range(1, 4):
			draw_circle(mouse + d * (k * 12.0), 2.0, red)
	draw_circle(mouse, 2.0, red)
	var world_mouse := xf.affine_inverse() * mouse
	var metres := int(round(h.shoulder().distance_to(world_mouse) / 32.0))
	var label := "%d m" % metres
	draw_string(ThemeFactory.heading_font(), mouse + Vector2(r + 10.0, r + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))

func _draw_hit_marker() -> void:
	if hud.hit_marker_t <= 0.0:
		return
	var mouse := get_local_mouse_position()
	var k := hud.hit_marker_t / 0.15
	var s := 12.0 if hud.hit_marker_kill else 9.0
	var col := Color(Palette.UI_DANGER, k) if hud.hit_marker_kill else Color(1, 1, 1, k)
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_line(mouse + d * 5.0, mouse + d * (5.0 + s), col, 3.0 if hud.hit_marker_kill else 2.0)

# ── World-anchored widgets ──────────────────────────────────────────────────────

func _draw_pickup_prompt(h: CharacterState) -> void:
	var target := hud.sim.find_pickup_target(h)
	if target.is_empty():
		return
	var def: WeaponDef = target["def"]
	var action := PickupResolver.pickup_action(h, def)
	var key := InputBindings.label(Settings.binding(&"pickup_swap")[0])
	var text := ""
	match action:
		&"take": text = "%s  Take %s" % [key, def.display_name]
		&"merge": text = "%s  +Ammo %s" % [key, def.display_name]
		_:
			var cur := h.inventory.active_weapon()
			text = "%s  Swap %s ⇄ %s" % [key, cur.def.display_name if cur else "?", def.display_name]
	var p := _to_screen((target["pos"] as Vector2) + Vector2(0.0, -46.0))
	var f := ThemeFactory.body_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28.0
	var r := Rect2(p.x - w * 0.5, p.y - 30.0, w, 30.0)
	draw_style_box(ThemeFactory.stylebox(Color(Palette.UI_PANEL, 0.9), 15, Palette.UI_ACCENT, 2, 0), r)
	draw_string(f, Vector2(r.position.x + 14.0, r.position.y + 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.UI_TEXT)

## 60° red wedges on a 180-px ring pointing to the damage source, fading over 1.2 s.
func _draw_damage_dirs(h: CharacterState) -> void:
	var c := size * 0.5
	var me := h.centre() if h.life_state == Enums.LifeState.ALIVE else h.death_pos
	for d in hud.damage_dirs:
		var dir: Vector2 = (d.world_pos as Vector2) - me
		if dir.length_squared() < 1.0:
			continue
		var a := dir.angle()
		var alpha := clampf(float(d.t) / 1.2, 0.0, 1.0) * 0.8
		draw_arc(c, 180.0, a - deg_to_rad(30.0), a + deg_to_rad(30.0), 16, Color(Palette.UI_DANGER, alpha), 14.0)

## Edge-of-screen arrows (48-px margin): Rocket Boost with distance in m, bots firing at Skyra.
func _draw_offscreen() -> void:
	var sim := hud.sim
	var h := sim.human_char
	var me := h.centre() if h.life_state == Enums.LifeState.ALIVE else h.death_pos
	var b := sim.boost
	if b.phase == RocketBoostManager.BoostPhase.SPAWNING_IN or b.phase == RocketBoostManager.BoostPhase.AVAILABLE:
		var metres := int(round(me.distance_to(b.current_pickup_pos) / 32.0))
		_edge_marker(b.current_pickup_pos, Color("#FF8A1F"), "ROCKET  %d m" % metres)
	for id in hud.attackers:
		var bot := sim.character(id)
		if bot and bot.life_state == Enums.LifeState.ALIVE:
			_edge_marker(bot.centre(), bot.profile.primary, "")

func _edge_marker(world: Vector2, col: Color, label: String) -> void:
	var p := _to_screen(world)
	var rect := Rect2(Vector2.ZERO, size).grow(-48.0)
	if rect.has_point(p):
		return
	var c := size * 0.5
	var dir := (p - c).normalized()
	# Clamp the arrow onto the margin rectangle
	var tx := (rect.size.x * 0.5) / maxf(absf(dir.x), 1e-4)
	var ty := (rect.size.y * 0.5) / maxf(absf(dir.y), 1e-4)
	var e := c + dir * minf(tx, ty)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([e + dir * 18.0, e - dir * 6.0 + side * 12.0, e - dir * 6.0 - side * 12.0]), col)
	draw_polyline(PackedVector2Array([e + dir * 18.0, e - dir * 6.0 + side * 12.0, e - dir * 6.0 - side * 12.0, e + dir * 18.0]), Palette.OUTLINE, 2.0, true)
	if not label.is_empty():
		var f := ThemeFactory.body_font()
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var lp := e - dir * 34.0 - Vector2(w * 0.5, -6.0)
		lp.x = clampf(lp.x, 8.0, size.x - w - 8.0)
		draw_string_outline(f, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.04, 0.05, 0.1, 0.8))
		draw_string(f, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
