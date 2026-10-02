# Implements §7.4 procedural characters: a paper-doll rig drawn in _draw() each frame,
# with the run/jet/air/crouch/landing animations, aim-rotated arm and weapon (recoil,
# reload, pump), helmet decorations, Skyra's verlet scarf, name tag and health bar,
# the §3.13 stealth / reveal / hit / burn effects (character.gdshader) and the death shatter.
class_name CharacterView
extends Node2D

const DEG := PI / 180.0
const OUTLINE_W := 2.5
const SHOULDER := Vector2(0.0, -56.0)
const REAR_SHOULDER := Vector2(-4.0, -57.0)
const HIP_FRONT := Vector2(2.0, -30.0)
const HIP_REAR := Vector2(-3.0, -30.0)
const THIGH_LEN := 14.0
const SHIN_LEN := 13.0
const BOOT_COLOR := Color("#1E2230")
const HEAD_SCALE := 0.84
const CHEST_SCALE := Vector2(1.15, 1.06)
const RIG_SHADER := preload("res://src/view/shaders/character.gdshader")

var c: CharacterState
var sim: MatchSim
var primary: Color
var secondary: Color
var visor: Color
var helmet_id: String = ""
var name_color: Color

var _t: float = 0.0
var _phase: float = 0.0
var _squash_t: float = 1.0
var _recoil: float = 0.0
var _recoil_rot: float = 0.0
var _last_shots: int = 0
var _hit_flash: float = 0.0
var _jitter_t: float = 0.0
var _health_bar_t: float = 0.0
var _reveal: float = 1.0
var _was_alive: bool = false
var _spawn_ring_t: float = 1.0
var _stealth_fx: float = 0.0
var _scarf: PackedVector2Array = PackedVector2Array()
var _scarf_prev: PackedVector2Array = PackedVector2Array()
var _shards: Array = [] # death pieces: {pos, vel, rot, spin, col, size}
var _render_pos: Vector2 = Vector2.ZERO
var _render_aim: float = 0.0
var _last_health: float = 100.0
var _mat: ShaderMaterial # §7.3.2: one material shared by every rig part of this character
var _under: Node2D # boost aura, behind the rig
var _over: Node2D # spawn ring, name tag, health bar

func setup(p_c: CharacterState, p_sim: MatchSim) -> void:
	c = p_c
	sim = p_sim
	if c.is_human:
		var hp: Dictionary = Data.human_profile
		primary = Color(hp.get("primary", "#F4F7FB"))
		secondary = Color(hp.get("secondary", "#FFC53D"))
		visor = Color(hp.get("visor", "#39E6FF"))
		helmet_id = str(hp.get("helmet", "skyra_fin"))
		name_color = Palette.SKYRA_TRIM
	else:
		primary = c.profile.primary
		secondary = c.profile.secondary
		visor = c.profile.visor
		helmet_id = str(c.profile.helmet)
		name_color = c.profile.primary
	for i in range(5):
		_scarf.append(Vector2(-3.0 - i * 9.0, -60.0))
	_scarf_prev = _scarf.duplicate()
	_was_alive = c.life_state == Enums.LifeState.ALIVE
	_mat = ShaderMaterial.new()
	_mat.shader = RIG_SHADER
	material = _mat
	_under = Node2D.new()
	_under.show_behind_parent = true
	_under.draw.connect(_draw_glow_under)
	add_child(_under)
	_over = Node2D.new()
	_over.draw.connect(_draw_overlays)
	add_child(_over)
	EventBus.character_damaged.connect(_on_damaged)
	EventBus.character_spawned.connect(_on_spawned)

func _on_damaged(ev: DamageEvent) -> void:
	if ev.target_id == c.id:
		_hit_flash = 1.0
		_jitter_t = 0.1
		_health_bar_t = 3.0

func _on_spawned(id: int, _pos: Vector2, _initial: bool) -> void:
	if id == c.id:
		_reveal = 0.0
		_spawn_ring_t = 0.0
		_shards.clear()

func _process(delta: float) -> void:
	_t += delta
	var a := WorldView.alpha()
	var alive := c.life_state == Enums.LifeState.ALIVE
	if _was_alive and not alive:
		_start_death()
	_was_alive = alive
	_render_pos = c.prev_pos.lerp(c.pos, a) if alive else c.death_pos
	position = _render_pos
	_render_aim = c.aim_angle

	# Animation clocks
	var vx := c.vel.x
	if c.grounded and absf(vx) >= 60.0 and alive:
		var f := 1.4 + absf(vx) / 260.0
		var dir := 1.0 if signf(vx) == float(c.facing) else -1.0 # backpedal
		var prev_half := int(_phase / PI)
		_phase = fposmod(_phase + TAU * f * delta * dir, TAU)
		# Footstep on each run-cycle contact frame (φ = 0 and π), §9.4 footstep
		if int(_phase / PI) != prev_half:
			EventBus.footstep.emit(c.id, sim.grid.surface_at(c.pos + Vector2(0.0, 2.0)) if sim else Enums.Surface.ROCK)
	if c.landing_speed > 300.0 and c.grounded and _squash_t >= 1.0:
		_squash_t = 0.0
		c.landing_speed = 0.0
	_squash_t = minf(1.0, _squash_t + delta / 0.12)
	_hit_flash = maxf(0.0, _hit_flash - delta / 0.06)
	_jitter_t = maxf(0.0, _jitter_t - delta)
	_health_bar_t = maxf(0.0, _health_bar_t - delta)
	_reveal = minf(1.0, _reveal + delta / 0.35)
	_spawn_ring_t = minf(1.0, _spawn_ring_t + delta / 0.3)
	# 1 while stealth_t > 0, eased to 0 over 0.2 s at the end (§3.13)
	_stealth_fx = 1.0 if c.stealth_t > 0.0 else move_toward(_stealth_fx, 0.0, delta / 0.2)

	# Recoil: kick back on each shot, recover with exp_smooth λ = 40 (§7.4)
	if c.stats.shots_fired != _last_shots:
		var w := c.inventory.active_weapon()
		if w and c.stats.shots_fired > _last_shots and w.def.fire_mode != Enums.FireMode.CONTINUOUS:
			_recoil = w.def.recoil_kick_wu if w.def.recoil_kick_wu > 0.0 else 6.0
			_recoil_rot = -4.0 * DEG
		_last_shots = c.stats.shots_fired
	var k := 1.0 - exp(-40.0 * delta)
	_recoil = lerpf(_recoil, 0.0, k)
	_recoil_rot = lerpf(_recoil_rot, 0.0, k)

	if c.is_human:
		_step_scarf(delta)
	_step_shards(delta)
	# Off-screen characters are not drawn at all
	var cam := get_viewport().get_camera_2d() as GameCamera
	var on_screen := cam == null or cam.view_rect_world().grow(260.0).has_point(_render_pos)
	visible = on_screen
	if on_screen:
		_mat.set_shader_parameter(&"stealth", _stealth_fx)
		_mat.set_shader_parameter(&"stealth_time_left", c.stealth_t)
		_mat.set_shader_parameter(&"reveal", _reveal)
		_mat.set_shader_parameter(&"hit_flash", _hit_flash)
		_mat.set_shader_parameter(&"burn", 1.0 if c.burn_t > 0.0 else 0.0)
		_mat.set_shader_parameter(&"feet_y", global_position.y)
		queue_redraw()
		_under.queue_redraw()
		_over.queue_redraw()

# ── Colours (§3.13: the rig shader does stealth / hit flash / burn / reveal) ─────

## Alpha for the name tag, which is not a rig part (drawn without the shader).
func _overlay_alpha() -> float:
	var a := lerpf(1.0, 0.45, _stealth_fx)
	if c.stealth_t > 0.0 and c.stealth_t < 0.5:
		a *= 1.0 if fmod(_t * 8.0, 1.0) < 0.5 else 0.6
	return a * clampf(_reveal * 1.2, 0.0, 1.0)

# ── Pose ─────────────────────────────────────────────────────────────────────────

## Limb angles in facing space (0 = straight down, + = forward), body offsets.
func _pose() -> Dictionary:
	var p := {"thigh_f": 0.0, "thigh_r": 0.0, "knee_f": 0.0, "knee_r": 0.0,
		"bob": 0.0, "lean": 0.0, "rear_arm": 10.0 * DEG, "hip_drop": 0.0}
	var vx := c.vel.x * float(c.facing)
	if c.crouching:
		p.thigh_f = 70.0 * DEG; p.thigh_r = 55.0 * DEG
		p.knee_f = 110.0 * DEG; p.knee_r = 105.0 * DEG
		p.hip_drop = 22.0; p.lean = 8.0 * DEG
	elif not c.grounded:
		if c.jet_active:
			var flutter := 4.0 * DEG * sin(_t * TAU * 6.0)
			p.thigh_f = -10.0 * DEG + flutter; p.thigh_r = -10.0 * DEG - flutter
			p.knee_f = 35.0 * DEG; p.knee_r = 35.0 * DEG
			p.lean = clampf(vx / 460.0, -1.0, 1.0) * 10.0 * DEG
		else:
			p.thigh_f = -20.0 * DEG; p.thigh_r = 25.0 * DEG
			p.knee_f = 15.0 * DEG; p.knee_r = 15.0 * DEG
			p.rear_arm = -30.0 * DEG
	elif absf(c.vel.x) >= 60.0:
		var ph := _phase
		p.thigh_f = 32.0 * DEG * sin(ph)
		p.thigh_r = 32.0 * DEG * sin(ph + PI)
		p.knee_f = (20.0 + 25.0 * maxf(0.0, sin(ph + PI * 0.5))) * DEG
		p.knee_r = (20.0 + 25.0 * maxf(0.0, sin(ph + PI * 1.5))) * DEG
		p.bob = -2.5 * absf(sin(ph))
		p.rear_arm = -24.0 * DEG * sin(ph)
		p.lean = 4.0 * DEG * signf(vx)
	else:
		p.bob = 1.2 * sin(TAU * 0.8 * _t)
	return p

## Aim direction mapped into facing space (the rig is mirrored when facing left).
func _aim_facing() -> float:
	var d := Vector2.from_angle(_render_aim)
	return Vector2(d.x * float(c.facing), d.y).angle()

func _draw() -> void:
	if c == null:
		return
	if c.life_state != Enums.LifeState.ALIVE:
		_draw_shards()
		return
	var p := _pose()
	var sq := Vector2.ONE
	if _squash_t < 1.0:
		sq = Vector2(1.06, 0.92).lerp(Vector2.ONE, _squash_t)
	var jitter := Vector2.ZERO
	if _jitter_t > 0.0:
		jitter = Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	var body := Transform2D(0.0, Vector2(float(c.facing) * sq.x, sq.y), 0.0, jitter)
	_body_xf = body

	# Two passes each: dark outline silhouettes first, then fills (§7.2 outlines).
	# The weapon and front arm sit between body and head so the visor stays readable.
	for pass_i in range(2):
		draw_set_transform_matrix(body)
		_draw_rig(p, pass_i == 0)
	draw_set_transform_matrix(body)
	_draw_weapon(p)
	_draw_front_arm(p, false)
	for pass_i in range(2):
		_draw_head(p, pass_i == 0)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _limb(a: Vector2, b: Vector2, w: float, col: Color, outline: bool) -> void:
	if outline:
		draw_line(a, b, Palette.OUTLINE, w + OUTLINE_W * 2.0)
		draw_circle(a, w * 0.5 + OUTLINE_W, Palette.OUTLINE)
		draw_circle(b, w * 0.5 + OUTLINE_W, Palette.OUTLINE)
	else:
		draw_line(a, b, col, w)
		draw_circle(a, w * 0.5, col)
		draw_circle(b, w * 0.5, col)
		# Rounded-limb shading: dark underside, light top edge
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		if n.y < 0.0:
			n = -n
		draw_line(a + n * w * 0.28, b + n * w * 0.28, col.darkened(0.3), w * 0.32)
		draw_line(a - n * w * 0.26, b - n * w * 0.26, col.lightened(0.28), w * 0.18)

func _rrect(center: Vector2, size: Vector2, col: Color, outline: bool) -> void:
	var r := Rect2(center - size * 0.5, size)
	if outline:
		draw_rect(r.grow(OUTLINE_W), Palette.OUTLINE)
	else:
		draw_rect(r, col)

func _circle(center: Vector2, radius: float, col: Color, outline: bool) -> void:
	if outline:
		draw_circle(center, radius + OUTLINE_W, Palette.OUTLINE)
	else:
		draw_circle(center, radius, col)

func _leg(hip: Vector2, thigh: float, knee: float, col: Color, outline: bool) -> void:
	var knee_pt := hip + Vector2(sin(thigh), cos(thigh)) * THIGH_LEN
	var shin := thigh - knee
	var ankle := knee_pt + Vector2(sin(shin), cos(shin)) * SHIN_LEN
	_limb(hip, knee_pt, 10.0, col, outline)
	_limb(knee_pt, ankle, 9.0, col, outline)
	# Combat boot (toe +x): shaped upper, rubber sole, lace highlight
	var boot := _offset(PackedVector2Array([Vector2(-4.5, -6.0), Vector2(3.0, -6.0), Vector2(5.0, -3.0), Vector2(11.5, -1.5),
		Vector2(11.5, 2.5), Vector2(-4.5, 2.5)]), ankle)
	if outline:
		_poly_outline(boot)
		draw_colored_polygon(boot, Palette.OUTLINE)
	else:
		draw_colored_polygon(boot, BOOT_COLOR)
		draw_rect(Rect2(ankle + Vector2(-4.5, 0.8), Vector2(16.0, 1.9)), Color("#0C0E14"))
		draw_line(ankle + Vector2(-2.5, -4.5), ankle + Vector2(3.5, -4.0), BOOT_COLOR.lightened(0.35), 1.2)
		# Knee pad
		draw_circle(knee_pt + Vector2(1.5, 0.0), 5.2, secondary.darkened(0.35))
		draw_circle(knee_pt + Vector2(1.0, -1.2), 2.2, Color(1, 1, 1, 0.18))

func _draw_rig(p: Dictionary, outline: bool) -> void:
	var drop := Vector2(0.0, p.hip_drop + p.bob)
	var lean: float = p.lean
	var torso_c := Vector2(0.0, -46.0) + drop
	# Legs behind
	_leg(HIP_REAR + Vector2(0.0, p.hip_drop), p.thigh_r, p.knee_r, secondary, outline)
	# Jetpack with stripe and nozzles
	var jp := Vector2(-16.0, -50.0) + drop + Vector2(-lean * 20.0, 0.0)
	_rrect(jp, Vector2(14.0, 28.0), Palette.METAL, outline)
	if not outline:
		# twin pressurised tanks with cylinder shading, a colour band and valves
		for tx in [-3.6, 3.6]:
			var tc := jp + Vector2(tx, 0.0)
			draw_rect(Rect2(tc + Vector2(-3.4, -13.0), Vector2(6.8, 26.0)), Palette.METAL.darkened(0.1))
			draw_rect(Rect2(tc + Vector2(-3.4, -13.0), Vector2(1.6, 26.0)), Palette.METAL.lightened(0.35))
			draw_rect(Rect2(tc + Vector2(1.8, -13.0), Vector2(1.6, 26.0)), Palette.METAL.darkened(0.4))
			draw_circle(tc + Vector2(0.0, -13.0), 3.4, Palette.METAL.lightened(0.15))
			draw_rect(Rect2(tc + Vector2(-3.4, -3.0), Vector2(6.8, 4.0)), primary)
		draw_rect(Rect2(jp + Vector2(-1.0, -15.5), Vector2(2.0, 3.0)), Color("#2A2F36"))
	_rrect(jp + Vector2(-3.0, 16.0), Vector2(6.0, 6.0), Color("#2A2F36"), outline)
	_rrect(jp + Vector2(3.0, 16.0), Vector2(6.0, 6.0), Color("#2A2F36"), outline)
	if not outline and (c.jet_active or c.boost_t > 0.0 and not c.grounded):
		_draw_jet_flames(jp + Vector2(0.0, 19.0))
	if c.is_human and not outline:
		_draw_scarf()
	# Rear arm (swings / raised)
	var rs := REAR_SHOULDER + drop
	var ra: float = p.rear_arm
	_limb(rs, rs + Vector2(sin(ra), cos(ra)) * 18.0, 8.0, secondary, outline)
	# Torso
	var tilt := Transform2D(lean, Vector2.ZERO)
	draw_set_transform_matrix(_current_body() * Transform2D(0.0, torso_c) * tilt * Transform2D().scaled(CHEST_SCALE) * Transform2D(0.0, -torso_c))
	var vest := _offset(PackedVector2Array([Vector2(-12.0, -15.0), Vector2(11.0, -15.0), Vector2(13.0, -8.0),
		Vector2(11.0, 15.0), Vector2(-11.0, 15.0), Vector2(-13.0, -8.0)]), torso_c)
	if outline:
		_poly_outline(vest)
		draw_colored_polygon(vest, Palette.OUTLINE)
	else:
		draw_colored_polygon(vest, primary)
		# shading bands: lit chest, shadowed flank and waist
		draw_colored_polygon(_offset(PackedVector2Array([Vector2(-12.0, -15.0), Vector2(11.0, -15.0), Vector2(12.0, -11.0), Vector2(-12.5, -11.0)]), torso_c), primary.lightened(0.3))
		draw_colored_polygon(_offset(PackedVector2Array([Vector2(-11.5, 6.0), Vector2(11.5, 6.0), Vector2(11.0, 15.0), Vector2(-11.0, 15.0)]), torso_c), primary.darkened(0.22))
		# chest plate with seam and rivets
		var plate := _offset(PackedVector2Array([Vector2(-5.0, -11.0), Vector2(10.0, -11.0), Vector2(10.5, 1.0), Vector2(2.0, 4.0), Vector2(-5.5, 1.0)]), torso_c)
		draw_colored_polygon(plate, primary.lightened(0.18))
		draw_polyline(_offset(PackedVector2Array([Vector2(-5.5, 1.0), Vector2(2.0, 4.0), Vector2(10.5, 1.0)]), torso_c), primary.darkened(0.35), 1.2)
		draw_line(torso_c + Vector2(-4.0, -10.0), torso_c + Vector2(9.0, -10.0), Color(1, 1, 1, 0.35), 1.2)
		for rv in [Vector2(-3.0, -8.5), Vector2(8.0, -8.5)]:
			draw_circle(torso_c + rv, 0.9, primary.darkened(0.45))
		# shoulder pad
		draw_circle(torso_c + Vector2(1.0, -13.0), 6.5, secondary.lightened(0.08))
		draw_arc(torso_c + Vector2(1.0, -13.0), 5.0, PI * 1.1, PI * 1.8, 6, Color(1, 1, 1, 0.25), 1.4)
		# belt with buckle and pouches
		draw_rect(Rect2(torso_c + Vector2(-12.0, 11.0), Vector2(24.0, 4.5)), secondary)
		draw_rect(Rect2(torso_c + Vector2(-2.5, 11.0), Vector2(5.0, 4.5)), Palette.SKYRA_TRIM)
		draw_rect(Rect2(torso_c + Vector2(-1.0, 12.2), Vector2(2.0, 2.1)), Palette.SKYRA_TRIM.darkened(0.45))
		for px in [-10.0, 5.0]:
			draw_rect(Rect2(torso_c + Vector2(px, 9.0), Vector2(5.0, 6.5)), secondary.darkened(0.2))
			draw_rect(Rect2(torso_c + Vector2(px, 9.0), Vector2(5.0, 1.6)), secondary.lightened(0.2))
	draw_set_transform_matrix(_current_body())
	# Front leg
	_leg(HIP_FRONT + Vector2(0.0, p.hip_drop), p.thigh_f, p.knee_f, secondary.lightened(0.12), outline)

func _draw_head(p: Dictionary, outline: bool) -> void:
	var drop := Vector2(0.0, p.hip_drop + p.bob)
	var lean: float = p.lean
	# Head + helmet + visor + decoration
	var head_rot := clampf(0.3 * _aim_facing(), -15.0 * DEG, 15.0 * DEG)
	var neck := Vector2(1.0, -61.0) + drop
	var hc := Vector2(2.0, -71.0) + drop
	# Realistic proportions: the helmet is drawn at 84 % around its centre (top of the
	# helmet stays near the 84-wu collision height), the chest is widened in _draw_rig.
	var head_scale := Transform2D(0.0, hc) * Transform2D().scaled(Vector2(HEAD_SCALE, HEAD_SCALE)) * Transform2D(0.0, -hc)
	var hc_low := Vector2(0.0, 3.0)
	draw_set_transform_matrix(_current_body() * Transform2D(head_rot + lean, neck) * Transform2D(0.0, -neck) * Transform2D(0.0, hc_low) * head_scale)
	_circle(hc, 13.0, secondary, outline)
	_draw_helmet(hc, outline)
	draw_set_transform_matrix(_current_body())

var _body_xf: Transform2D = Transform2D.IDENTITY

func _current_body() -> Transform2D:
	return _body_xf

func _draw_helmet(hc: Vector2, outline: bool) -> void:
	var shell := hc + Vector2(-1.0, -1.0)
	if outline:
		draw_circle(shell, 15.0 + OUTLINE_W, Palette.OUTLINE)
		_draw_helmet_deco(hc, true)
		return
	# Shell with the lower-front quadrant cut for the visor
	var pts := PackedVector2Array()
	for i in range(19):
		var a := lerpf(PI * 0.5, PI * 2.0, float(i) / 18.0)
		pts.append(shell + Vector2(cos(a), sin(a)) * 15.0)
	pts.append(shell + Vector2(4.0, 2.0))
	draw_colored_polygon(pts, primary)
	# lower-rear shadow and a soft top sheen give the shell volume
	draw_arc(shell, 12.5, PI * 0.55, PI * 1.0, 8, primary.darkened(0.3), 4.0)
	draw_arc(shell, 11.5, PI * 1.05, PI * 1.6, 8, primary.lightened(0.35), 2.5)
	draw_circle(shell + Vector2(-5.0, -8.0), 2.0, Color(1, 1, 1, 0.35))
	# ear guard bolt and a rim line
	draw_circle(shell + Vector2(-6.0, 2.0), 3.2, secondary)
	draw_circle(shell + Vector2(-6.0, 2.0), 1.2, primary.lightened(0.3))
	draw_arc(shell, 14.0, PI * 0.55, PI * 0.95, 6, secondary, 2.0)
	_draw_helmet_deco(hc, false)
	# Wrap-around visor: dark tint, bright reflection band, glow
	var vc := hc + Vector2(6.0, 0.0)
	var vr := Rect2(vc - Vector2(8.0, 4.5), Vector2(16.0, 9.0))
	draw_rect(vr.grow(OUTLINE_W * 0.6), Palette.OUTLINE)
	draw_rect(vr, visor.darkened(0.25))
	draw_rect(Rect2(vr.position, Vector2(vr.size.x, vr.size.y * 0.55)), visor)
	draw_line(vr.position + Vector2(2.0, 2.0), vr.position + Vector2(12.0, 2.0), Color(1, 1, 1, 0.75), 1.5)
	draw_line(vr.position + Vector2(10.0, 6.5), vr.position + Vector2(14.5, 6.5), Color(1, 1, 1, 0.35), 1.0)
	Palette.draw_glow(self, vc, 18.0, Color(visor, 0.45))

func _draw_helmet_deco(hc: Vector2, outline: bool) -> void:
	var col := visor if not outline else Palette.OUTLINE
	var grow := OUTLINE_W if outline else 0.0
	match helmet_id:
		"skyra_fin":
			var fin := PackedVector2Array([Vector2(-10, -12), Vector2(4, -16), Vector2(-2, -26), Vector2(-14, -18)])
			var fp := _offset(fin, hc)
			if outline:
				_poly_outline(fp)
			else:
				draw_colored_polygon(fp, Palette.SKYRA_TRIM)
				draw_line(hc + Vector2(-10, -13), hc + Vector2(-2, -24), Color(1, 1, 1, 0.8), 1.5)
		"crest":
			var pts := _offset(PackedVector2Array([Vector2(-8, -14), Vector2(-4, -22), Vector2(0, -14), Vector2(4, -21), Vector2(8, -13)]), hc)
			if outline:
				_poly_outline(pts)
			else:
				draw_colored_polygon(pts, col)
		"twin_antenna":
			for ln in [[Vector2(-4, -14), Vector2(-8, -28)], [Vector2(4, -14), Vector2(6, -28)]]:
				draw_line(hc + ln[0], hc + ln[1], col, 2.5 + grow * 2.0)
				draw_circle(hc + ln[1], 3.0 + grow, col)
		"goggles":
			for gc in [Vector2(-2, -8), Vector2(8, -8)]:
				draw_circle(hc + gc, 5.0 + grow, col)
			draw_line(hc + Vector2(-14, -8), hc + Vector2(13, -8), col, 2.0 + grow)
		"horns":
			for poly in [[Vector2(-10, -10), Vector2(-18, -22), Vector2(-12, -24), Vector2(-6, -13)], [Vector2(10, -10), Vector2(16, -24), Vector2(10, -22), Vector2(5, -13)]]:
				var pp := _offset(PackedVector2Array(poly), hc)
				if outline:
					_poly_outline(pp)
				else:
					draw_colored_polygon(pp, col)
		"halo_dome":
			draw_circle(hc + Vector2(0, -15), 5.0 + grow, col)
			_ellipse_ring(hc + Vector2(0, -24), 14.0, 4.0, col, 2.5 + grow * 2.0)
		"cat_ears":
			for poly in [[Vector2(-11, -9), Vector2(-8, -21), Vector2(-2, -12)], [Vector2(4, -12), Vector2(10, -21), Vector2(13, -9)]]:
				var pp := _offset(PackedVector2Array(poly), hc)
				if outline:
					_poly_outline(pp)
				else:
					draw_colored_polygon(pp, col)
		"spike_crown":
			for deg: float in [-150.0, -120.0, -90.0, -60.0, -30.0]:
				var a := deg * DEG
				var base := hc + Vector2(cos(a), sin(a)) * 14.0
				var tip := hc + Vector2(cos(a), sin(a)) * 22.0
				var side := Vector2(-sin(a), cos(a)) * 3.0
				var pp := PackedVector2Array([base - side, tip, base + side])
				if outline:
					_poly_outline(pp)
				else:
					draw_colored_polygon(pp, col)

func _offset(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(q + o)
	return out

func _poly_outline(pts: PackedVector2Array) -> void:
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Palette.OUTLINE, OUTLINE_W * 2.0, true)

func _ellipse_ring(center: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in range(21):
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w, true)

# ── Arm & weapon ─────────────────────────────────────────────────────────────────

func _hand_facing() -> Vector2:
	return SHOULDER + Vector2.from_angle(_aim_facing()) * 18.0

func _weapon_anim(w: WeaponInstance) -> Dictionary:
	var anim := {"disk_angle": _t * PI, "pilot_scale": 0.7 + 0.5 * absf(sin(_t * TAU * 6.0)),
		"coils_alpha": 0.4 + 0.6 * clampf(w.clip / maxf(1.0, float(w.def.clip_size)), 0.0, 1.0) * (0.75 + 0.25 * sin(_t * 10.0))}
	if w.def.id == &"shotgun":
		var k := clampf(w.cycle_t / 0.35, 0.0, 1.0)
		anim["pump_offset"] = -10.0 * sin(k * PI) if w.cycle_t > 0.05 else 0.0
	if w.def.id == &"rocket_launcher":
		var reloading := w.state == Enums.WeaponState.RELOADING
		var progress := w.reload_elapsed_s / maxf(0.01, w.reload_total_s)
		anim["warhead_visible"] = w.clip >= 1.0 and not reloading or (reloading and progress >= 0.8)
	if w.state == Enums.WeaponState.RELOADING and w.def.reload_type == Enums.ReloadType.MAGAZINE:
		var pr := w.reload_elapsed_s / maxf(0.01, w.reload_total_s)
		anim["mag_visible"] = pr < 0.15 or pr > 0.7
		if pr > 0.7:
			anim["mag_offset"] = Vector2(0.0, 14.0 * (1.0 - (pr - 0.7) / 0.3))
	return anim

func _weapon_dip(w: WeaponInstance) -> float:
	if w.state != Enums.WeaponState.RELOADING:
		return 0.0
	var e := w.reload_elapsed_s
	var tot := maxf(0.01, w.reload_total_s)
	var into := clampf(e / 0.15, 0.0, 1.0)
	var out := clampf((tot - e) / 0.15, 0.0, 1.0)
	return 25.0 * DEG * minf(into, out)

func _draw_weapon(_p: Dictionary) -> void:
	var w: WeaponInstance = c.inventory.active_weapon()
	if w == null:
		return
	var ang := _aim_facing() + _recoil_rot + _weapon_dip(w)
	var xf := Transform2D(ang, _hand_facing()) * Transform2D(0.0, Vector2(-_recoil, 0.0))
	WeaponPainter.draw(self, w.def.id, _current_body() * xf, _weapon_anim(w), Color.WHITE)

func _draw_front_arm(_p: Dictionary, outline: bool) -> void:
	var hand := _hand_facing() - Vector2.from_angle(_aim_facing()) * _recoil * 0.5
	draw_set_transform_matrix(_current_body())
	_limb(SHOULDER + Vector2(2.0, 0.0), hand, 9.0, primary, true)
	_limb(SHOULDER + Vector2(2.0, 0.0), hand, 9.0, primary, outline)
	var elbow := (SHOULDER + Vector2(2.0, 0.0)).lerp(hand, 0.5)
	if not outline:
		draw_circle(elbow, 4.6, secondary.darkened(0.25))
		draw_circle(elbow + Vector2(-0.8, -1.2), 1.8, Color(1, 1, 1, 0.2))
	_circle(hand, 5.0, secondary, true)
	_circle(hand, 5.0, secondary, false)
	if not outline:
		draw_circle(hand + Vector2(-1.0, -1.5), 2.0, secondary.lightened(0.3))

# ── Effects ──────────────────────────────────────────────────────────────────────

func _draw_jet_flames(at: Vector2) -> void:
	var boosted := c.boost_t > 0.0
	var core := Color("#7FDBFF") if boosted else (Color("#CFFBFF") if c.is_human else Color.WHITE)
	var outer := Color("#FF8A1F") if boosted else (Palette.SKYRA_VISOR if c.is_human else primary)
	var flick := 0.8 + 0.2 * sin(_t * 47.0)
	for nx in [-3.0, 3.0]:
		var base := at + Vector2(nx, 0.0)
		var length := (30.0 if boosted else 20.0) * flick
		draw_colored_polygon(PackedVector2Array([base + Vector2(-3.5, 0.0), base + Vector2(3.5, 0.0), base + Vector2(0.0, length)]), Color(outer, 0.85))
		draw_colored_polygon(PackedVector2Array([base + Vector2(-1.8, 0.0), base + Vector2(1.8, 0.0), base + Vector2(0.0, length * 0.55)]), core)

## Rocket Boost aura on a child drawn behind the rig (not a rig part, no shader).
func _draw_glow_under() -> void:
	if c.life_state != Enums.LifeState.ALIVE or c.boost_t <= 0.0:
		return
	var flick := 1.0
	if c.boost_t < 2.0:
		flick = 0.5 + 0.5 * signf(sin(_t * TAU * 8.0))
	Palette.draw_glow(_under, Vector2(0.0, -44.0), 64.0, Color(1.0, 0.55, 0.1, 0.55 * flick))

func _step_scarf(delta: float) -> void:
	# 5-point verlet chain anchored at the neck (−3, −60); segment 9; gravity 400; damping 0.92
	var anchor := Vector2(-3.0, -60.0)
	# Spec wind (−vel·0.08 + vertical flutter) plus a light backward breeze so it trails
	var wind := -Vector2(c.vel.x * float(c.facing), c.vel.y) * 0.08 + Vector2(-25.0, 20.0 * sin(5.0 * _t))
	for i in range(_scarf.size()):
		if i == 0:
			_scarf[i] = anchor
			_scarf_prev[i] = anchor
			continue
		var cur := _scarf[i]
		var vel := (cur - _scarf_prev[i]) * 0.92
		_scarf_prev[i] = cur
		_scarf[i] = cur + vel + (Vector2(0.0, 400.0) + wind * 10.0) * delta * delta
	for _iter in range(3):
		for i in range(1, _scarf.size()):
			var d := _scarf[i] - _scarf[i - 1]
			var l := d.length()
			if l > 0.001:
				_scarf[i] = _scarf[i - 1] + d / l * 9.0

func _draw_scarf() -> void:
	var col := Palette.SKYRA_SCARF
	for i in range(_scarf.size() - 1):
		var w := lerpf(7.0, 3.0, float(i) / float(_scarf.size() - 1))
		draw_line(_scarf[i], _scarf[i + 1], Palette.OUTLINE, w + 3.0)
	for i in range(_scarf.size() - 1):
		var w := lerpf(7.0, 3.0, float(i) / float(_scarf.size() - 1))
		draw_line(_scarf[i], _scarf[i + 1], col, w)
		draw_circle(_scarf[i + 1], w * 0.5, col)

## Spawn ring, name tag and bot health bar on a child node without the rig shader.
func _draw_overlays() -> void:
	if c.life_state != Enums.LifeState.ALIVE:
		return
	var ci := _over
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam else 1.0
	# Spawn ring (0 → 80 wu over 0.3 s)
	if _spawn_ring_t < 1.0:
		var ring_col := Palette.SKYRA_VISOR if c.is_human else primary
		ci.draw_arc(Vector2(0.0, -42.0), 80.0 * _spawn_ring_t, 0.0, TAU, 40, Color(ring_col, 1.0 - _spawn_ring_t), 4.0)
	# Name tag at (0, −106), 18 screen px; colour = primary (Skyra gold)
	var a := _overlay_alpha()
	var font := ThemeDB.fallback_font
	var fs := int(round(18.0 * 0.9 / zoom))
	var label := c.name
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var tp := Vector2(-tw * 0.5, -106.0)
	ci.draw_string_outline(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(3.0 / zoom)), Color(Palette.OUTLINE, a))
	ci.draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(name_color, a))
	# Bot health bar 48 x 5 for 3 s after taking damage
	if not c.is_human and _health_bar_t > 0.0:
		var bw := 48.0 / zoom * 0.9
		var bh := 5.0 / zoom * 0.9
		var bp := Vector2(-bw * 0.5, -100.0)
		ci.draw_rect(Rect2(bp - Vector2(1, 1), Vector2(bw + 2.0, bh + 2.0)), Palette.OUTLINE)
		ci.draw_rect(Rect2(bp, Vector2(bw * clampf(c.health / 100.0, 0.0, 1.0), bh)), primary.lightened(0.2))

# ── Death shatter (§7.4) ─────────────────────────────────────────────────────────

func _start_death() -> void:
	_shards.clear()
	var parts := [[Vector2(2, -71), primary, 15.0], [Vector2(0, -46), primary, 13.0], [Vector2(-16, -50), Palette.METAL, 9.0],
		[Vector2(2, -24), secondary, 7.0], [Vector2(-3, -24), secondary, 7.0], [Vector2(10, -56), primary, 6.0],
		[Vector2(-6, -54), secondary, 6.0], [Vector2(4, -8), BOOT_COLOR, 6.0], [Vector2(-4, -8), BOOT_COLOR, 6.0]]
	var base_vel := c.vel * 0.5
	for p in parts:
		var dir := (p[0] as Vector2 - Vector2(0.0, -42.0)).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		dir = dir.rotated(randf_range(-0.6, 0.6))
		_shards.append({"pos": Vector2(p[0].x * float(c.facing), p[0].y), "vel": base_vel + dir * randf_range(150.0, 450.0) + Vector2(0.0, -200.0),
			"rot": 0.0, "spin": randf_range(-12.6, 12.6), "col": p[1], "size": p[2], "age": 0.0})

func _step_shards(delta: float) -> void:
	for s in _shards:
		s.vel += Vector2(0.0, 1800.0) * delta
		s.pos += s.vel * delta
		s.rot += s.spin * delta
		s.age += delta
	_shards = _shards.filter(func(s): return s.age < 1.0)

func _draw_shards() -> void:
	for s in _shards:
		var a := 1.0 - float(s.age)
		var sz: float = s.size
		draw_set_transform(s.pos, s.rot, Vector2.ONE)
		draw_rect(Rect2(-sz * 0.5 - 2.0, -sz * 0.5 - 2.0, sz + 4.0, sz + 4.0), Color(Palette.OUTLINE, a))
		draw_rect(Rect2(-sz * 0.5, -sz * 0.5, sz, sz), Color(s.col, a))
	draw_set_transform_matrix(Transform2D.IDENTITY)
